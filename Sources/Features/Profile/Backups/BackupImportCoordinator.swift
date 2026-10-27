import Foundation

enum BackupImportCoordinator {
    static func copySelectedBackupToSandbox(_ selectedURL: URL) throws -> URL {
        let hasAccess = selectedURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                selectedURL.stopAccessingSecurityScopedResource()
            }
        }

        let ext = selectedURL.pathExtension.isEmpty ? "zip" : selectedURL.pathExtension
        let copiedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-import-\(UUID().uuidString).\(ext)")
        _ = try FileOps.removeIfExists(
            at: copiedURL,
            context: .init(
                event: "backup_import.prepare_temp_file",
                category: .fileStorage,
                source: "BackupImportCoordinator.copySelectedBackupToSandbox"
            )
        )
        try FileManager.default.copyItem(at: selectedURL, to: copiedURL)
        return copiedURL
    }

    @MainActor
    static func applyImportMetadata(snapshot: BackupSnapshot, mode: ImportMode, store: DataStore) {
        switch mode {
        case .merge: mergeMetadata(snapshot, into: store)
        case .overwrite: overwriteMetadata(snapshot, in: store)
        }
        store.enforceCalculationHistoryRetention()
        sanitizeMaterialProjectReferences(in: store)
    }

    @MainActor
    private static func mergeMetadata(_ snapshot: BackupSnapshot, into store: DataStore) {
        var seen = Set(store.legacyDateProvenance)
        store.legacyDateProvenance += snapshot.legacyDateProvenance.filter { seen.insert($0).inserted }
        store.mergeMaterialItemsByID(snapshot.materialItems)
        store.mergeQuoteItemsByID(snapshot.quoteItems)
        store.mergeLaborRecordsByID(snapshot.laborRecords)
        store.mergeProjectsByID(snapshot.projects)
        store.mergeDailyLogsByID(snapshot.dailyLogs)
        store.mergeHistoryRecordsByID(snapshot.historyRecords)
        store.mergeProgressTasksByID(snapshot.progressTasks)
        store.mergeSiteTodosByID(snapshot.siteTodos)
        store.mergeProjectDrawingsByID(snapshot.projectDrawings)
        store.mergeProjectContactsByID(snapshot.projectContacts)
        store.mergeProjectFinancialRecordsByID(snapshot.projectFinancialRecords)
        store.mergeProjectDocumentsByID(snapshot.projectDocuments)
        store.mergeQuickNotesByID(snapshot.quickNotes)
        store.mergeProjectWarehouseMovementsByID(snapshot.projectWarehouseMovements)
        store.mergeTemplatesByID(snapshot.templates)
        store.mergeMaterialPriceEntriesByID(snapshot.materialPriceEntries)
        store.mergeMaterialSheetDraftsByID(snapshot.materialSheetDrafts)
        store.mergeSupplierProfilesByID(snapshot.supplierProfiles)
        store.mergeConstructionMethodsByID(snapshot.constructionMethods)
        store.favoriteMaterialKeys = mergeUniqueStrings(existing: store.favoriteMaterialKeys, incoming: snapshot.favoriteMaterialKeys)
        store.recentMaterialKeys = mergeUniqueStrings(existing: store.recentMaterialKeys, incoming: snapshot.recentMaterialKeys)
        store.mergeUserMaterialsByID(snapshot.userMaterials)
        store.mergeDeletedUserMaterialsByID(snapshot.deletedUserMaterials)
        store.hiddenPresetKeys.formUnion(snapshot.hiddenPresetKeys)
    }

    @MainActor
    private static func overwriteMetadata(_ snapshot: BackupSnapshot, in store: DataStore) {
        store.legacyDateProvenance = snapshot.legacyDateProvenance
        store.replaceMaterialItems(snapshot.materialItems)
        store.replaceQuoteItems(snapshot.quoteItems)
        store.replaceLaborRecords(snapshot.laborRecords)
        store.replaceProjects(snapshot.projects)
        store.replaceDailyLogs(snapshot.dailyLogs)
        store.replaceHistoryRecords(snapshot.historyRecords)
        store.replaceProgressTasks(snapshot.progressTasks)
        store.replaceSiteTodos(snapshot.siteTodos)
        store.replaceProjectDrawings(snapshot.projectDrawings)
        store.replaceProjectContacts(snapshot.projectContacts)
        store.replaceProjectFinancialRecords(snapshot.projectFinancialRecords)
        store.replaceProjectDocuments(snapshot.projectDocuments)
        store.replaceQuickNotes(snapshot.quickNotes)
        store.replaceProjectWarehouseMovements(snapshot.projectWarehouseMovements)
        store.replaceTemplates(snapshot.templates)
        store.replaceMaterialPriceEntries(snapshot.materialPriceEntries)
        store.replaceMaterialSheetDrafts(snapshot.materialSheetDrafts)
        store.replaceSupplierProfiles(snapshot.supplierProfiles)
        store.replaceConstructionMethods(snapshot.constructionMethods)
        store.favoriteMaterialKeys = snapshot.favoriteMaterialKeys
        store.recentMaterialKeys = snapshot.recentMaterialKeys
        store.replaceUserMaterials(snapshot.userMaterials)
        store.replaceDeletedUserMaterials(snapshot.deletedUserMaterials)
        store.hiddenPresetKeys = snapshot.hiddenPresetKeys
    }

    @MainActor
    static func commitAndPersistImport(
        restoreTransaction: BackupArchiveService.EmbeddedFileRestoreTransaction,
        importedSnapshot: BackupSnapshot,
        previousSnapshot: BackupSnapshot,
        importMode: ImportMode,
        store: DataStore,
        sourceFileName: String,
        onPersistingMetadata: @MainActor () -> Void = {}
    ) async throws -> BackupEmbeddedRestoreCounts {
        await store.awaitInitialLoad()
        try store.requireNoBackupExport()
        guard !store.isApplyingBackup else {
            throw DataStore.PersistenceBlockedError(message: nil)
        }
        store.isApplyingBackup = true
        store.cancelScheduledSave()
        store.persistTask?.cancel()
        await store.persistTask?.value
        defer {
            store.isApplyingBackup = false
            store.cancelScheduledSave()
        }
        let snapshotToApply: BackupSnapshot
        let restorePolicy: BackupEmbeddedFileRestorePolicy
        switch importMode {
        case .merge:
            let preparation = prepareMergeImport(
                importedSnapshot: importedSnapshot,
                previousSnapshot: previousSnapshot
            )
            snapshotToApply = preparation.snapshot
            restorePolicy = preparation.restorePolicy
        case .overwrite:
            snapshotToApply = importedSnapshot
            restorePolicy = .referencedBy(importedSnapshot, overwritesExistingFiles: true)
        }
        applyImportMetadata(snapshot: snapshotToApply, mode: importMode, store: store)

        return try await commitAppliedImport(
            restoreTransaction: restoreTransaction, restorePolicy: restorePolicy,
            previousSnapshot: previousSnapshot, importMode: importMode, store: store,
            sourceFileName: sourceFileName, onPersistingMetadata: onPersistingMetadata
        )
    }
}

extension BackupImportCoordinator {
    static func overwrittenLocalFiles(previous: BackupSnapshot, imported: BackupSnapshot) -> BackupFileImpactSummary {
        let oldPhotoNames = photoFileNames(in: previous)
        let newPhotoNames = photoFileNames(in: imported)
        let oldDrawingNames = Set(previous.projectDrawings.map(\.fileName).filter { !$0.isEmpty })
        let newDrawingNames = Set(imported.projectDrawings.map(\.fileName).filter { !$0.isEmpty })
        let oldDocumentNames = Set(previous.projectDocuments.map(\.fileName).filter { !$0.isEmpty })
        let newDocumentNames = Set(imported.projectDocuments.map(\.fileName).filter { !$0.isEmpty })
        let oldQuickNoteAttachmentNames = quickNoteAttachmentFileNames(in: previous)
        let newQuickNoteAttachmentNames = quickNoteAttachmentFileNames(in: imported)

        return BackupFileImpactSummary(
            photoFileNames: oldPhotoNames.subtracting(newPhotoNames).filter { PhotoStorage.exists(fileName: $0) },
            drawingFileNames: oldDrawingNames.subtracting(newDrawingNames).filter { DrawingStorage.exists(fileName: $0) },
            documentFileNames: oldDocumentNames.subtracting(newDocumentNames).filter { ProjectDocumentStorage.exists(fileName: $0) },
            quickNoteAttachmentFileNames: oldQuickNoteAttachmentNames.subtracting(newQuickNoteAttachmentNames).filter {
                QuickNoteAttachmentStorage.exists(fileName: $0)
            }
        )
    }

    @discardableResult
    static func cleanupOverwrittenFiles(previous: BackupSnapshot, imported: BackupSnapshot) -> BackupFileImpactSummary {
        let impact = overwrittenLocalFiles(previous: previous, imported: imported)
        var cleanupErrors: [String] = []

        func runCleanup(_ label: String, _ cleanup: () throws -> Void) {
            do {
                try cleanup()
            } catch {
                cleanupErrors.append("\(label): \(error.localizedDescription)")
            }
        }

        runCleanup("photo") {
            try DataStoreDeferredFileCleanup.deletePhotoFilesOrThrow(
                impact.photoFileNames,
                summary: "backupImport.photos"
            )
        }
        runCleanup("drawing") {
            try DataStoreDeferredFileCleanup.deleteDrawingFilesOrThrow(
                impact.drawingFileNames,
                summary: "backupImport.drawings"
            )
        }
        runCleanup("document") {
            try DataStoreDeferredFileCleanup.deleteProjectDocumentFilesOrThrow(
                impact.documentFileNames,
                summary: "backupImport.projectDocuments"
            )
        }
        runCleanup("quickNoteAttachment") {
            try DataStoreDeferredFileCleanup.deleteQuickNoteAttachmentFilesOrThrow(
                impact.quickNoteAttachmentFileNames,
                summary: "backupImport.quickNoteAttachments"
            )
        }

        if !cleanupErrors.isEmpty {
            StorageIssueLog.recordEvent(
                "backup.import.cleanup_overwritten_files_failed",
                category: .fileStorage,
                details: [
                    "source": "BackupImportCoordinator.cleanupOverwrittenFiles",
                    "photo_count": "\(impact.photoFileNames.count)",
                    "drawing_count": "\(impact.drawingFileNames.count)",
                    "document_count": "\(impact.documentFileNames.count)",
                    "quick_note_attachment_count": "\(impact.quickNoteAttachmentFileNames.count)",
                    "errors": cleanupErrors.joined(separator: " | ")
                ]
            )
        }
        return impact
    }

    private static func mergeUniqueStrings(existing: [String], incoming: [String]) -> [String] {
        var seen = Set(existing)
        var merged = existing
        for key in incoming where !key.isEmpty && !seen.contains(key) {
            merged.append(key)
            seen.insert(key)
        }
        return merged
    }

    @MainActor
    private static func sanitizeMaterialProjectReferences(in store: DataStore) {
        let validProjectIds = Set(store.projects.map(\.id))
        var materialItems = store.materialItems
        for index in materialItems.indices {
            guard let projectId = materialItems[index].projectId,
                  !validProjectIds.contains(projectId) else { continue }
            materialItems[index].projectId = nil
        }
        store.replaceMaterialItems(materialItems)
    }

    private static func photoFileNames(in snapshot: BackupSnapshot) -> Set<String> {
        var names = Set(snapshot.dailyLogs.flatMap(\.allPhotoFileNames).filter { !$0.isEmpty })
        names.formUnion(snapshot.siteTodos.compactMap(\.rectificationBeforePhotoFileName).filter { !$0.isEmpty })
        names.formUnion(snapshot.siteTodos.compactMap(\.rectificationAfterPhotoFileName).filter { !$0.isEmpty })
        return names
    }

    private static func quickNoteAttachmentFileNames(in snapshot: BackupSnapshot) -> Set<String> {
        Set(
            (
                snapshot.quickNotes.flatMap { $0.attachments.map(\.fileName) }
                    + snapshot.constructionMethods.flatMap(\.attachments).map(\.fileName)
                    + snapshot.constructionMethods.flatMap(\.tutorialAttachments).map(\.fileName)
            ).filter { !$0.isEmpty }
        )
    }
}

extension BackupImportCoordinator {
    private struct MergeImportPreparation {
        var snapshot: BackupSnapshot
        var restorePolicy: BackupEmbeddedFileRestorePolicy
    }

    private struct MergeFileNameResolver {
        private(set) var destinations: [String: String] = [:]
        private var reservedDestinations = Set<String>()
        let exists: (String) -> Bool

        init(exists: @escaping (String) -> Bool) {
            self.exists = exists
        }

        mutating func resolve(_ sourceFileName: String) -> String {
            guard !sourceFileName.isEmpty else { return sourceFileName }
            if let destination = destinations[sourceFileName] {
                return destination
            }

            let destination: String
            if !exists(sourceFileName), !reservedDestinations.contains(sourceFileName) {
                destination = sourceFileName
            } else {
                destination = makeAvailableFileName(basedOn: sourceFileName)
            }
            destinations[sourceFileName] = destination
            reservedDestinations.insert(destination)
            return destination
        }

        private mutating func makeAvailableFileName(basedOn sourceFileName: String) -> String {
            let fileExtension = URL(fileURLWithPath: sourceFileName).pathExtension
            while true {
                var candidate = "backup-merge-\(UUID().uuidString)"
                if !fileExtension.isEmpty {
                    candidate += ".\(fileExtension)"
                }
                if !exists(candidate), !reservedDestinations.contains(candidate) {
                    return candidate
                }
            }
        }
    }

    private static func prepareMergeImport(
        importedSnapshot: BackupSnapshot,
        previousSnapshot: BackupSnapshot
    ) -> MergeImportPreparation {
        var snapshot = importedSnapshot
        var photoResolver = MergeFileNameResolver(exists: PhotoStorage.exists(fileName:))
        var drawingResolver = MergeFileNameResolver(exists: DrawingStorage.exists(fileName:))
        var documentResolver = MergeFileNameResolver(exists: ProjectDocumentStorage.exists(fileName:))
        var attachmentResolver = MergeFileNameResolver(exists: QuickNoteAttachmentStorage.exists(fileName:))

        resolvePhotoReferences(in: &snapshot, previous: previousSnapshot, resolver: &photoResolver)

        let existingDrawingIDs = Set(previousSnapshot.projectDrawings.map(\.id))
        for index in snapshot.projectDrawings.indices where !existingDrawingIDs.contains(snapshot.projectDrawings[index].id) {
            snapshot.projectDrawings[index].fileName = drawingResolver.resolve(snapshot.projectDrawings[index].fileName)
        }

        let existingDocumentIDs = Set(previousSnapshot.projectDocuments.map(\.id))
        for index in snapshot.projectDocuments.indices where !existingDocumentIDs.contains(snapshot.projectDocuments[index].id) {
            snapshot.projectDocuments[index].fileName = documentResolver.resolve(snapshot.projectDocuments[index].fileName)
        }

        let existingQuickNoteIDs = Set(previousSnapshot.quickNotes.map(\.id))
        for index in snapshot.quickNotes.indices where !existingQuickNoteIDs.contains(snapshot.quickNotes[index].id) {
            for attachmentIndex in snapshot.quickNotes[index].attachments.indices {
                snapshot.quickNotes[index].attachments[attachmentIndex].fileName = attachmentResolver.resolve(
                    snapshot.quickNotes[index].attachments[attachmentIndex].fileName
                )
            }
        }

        let existingMethodIDs = Set(previousSnapshot.constructionMethods.map(\.id))
        for index in snapshot.constructionMethods.indices where !existingMethodIDs.contains(snapshot.constructionMethods[index].id) {
            for attachmentIndex in snapshot.constructionMethods[index].attachments.indices {
                snapshot.constructionMethods[index].attachments[attachmentIndex].fileName = attachmentResolver.resolve(
                    snapshot.constructionMethods[index].attachments[attachmentIndex].fileName
                )
            }
            for attachmentIndex in snapshot.constructionMethods[index].tutorialAttachments.indices {
                snapshot.constructionMethods[index].tutorialAttachments[attachmentIndex].fileName = attachmentResolver.resolve(
                    snapshot.constructionMethods[index].tutorialAttachments[attachmentIndex].fileName
                )
            }
        }

        return MergeImportPreparation(
            snapshot: snapshot,
            restorePolicy: .mapped(
                photoFileDestinations: photoResolver.destinations,
                drawingFileDestinations: drawingResolver.destinations,
                documentFileDestinations: documentResolver.destinations,
                quickNoteAttachmentFileDestinations: attachmentResolver.destinations
            )
        )
    }

    private static func resolvePhotoReferences(in snapshot: inout BackupSnapshot, previous previousSnapshot: BackupSnapshot, resolver: inout MergeFileNameResolver) {
        let existingDailyLogIDs = Set(previousSnapshot.dailyLogs.map(\.id))
        for index in snapshot.dailyLogs.indices where !existingDailyLogIDs.contains(snapshot.dailyLogs[index].id) {
            if let fileName = snapshot.dailyLogs[index].photoFileName {
                snapshot.dailyLogs[index].photoFileName = resolver.resolve(fileName)
            }
            for photoIndex in snapshot.dailyLogs[index].photos.indices {
                snapshot.dailyLogs[index].photos[photoIndex].fileName = resolver.resolve(
                    snapshot.dailyLogs[index].photos[photoIndex].fileName
                )
            }
        }

        let existingTodoIDs = Set(previousSnapshot.siteTodos.map(\.id))
        for index in snapshot.siteTodos.indices where !existingTodoIDs.contains(snapshot.siteTodos[index].id) {
            if let fileName = snapshot.siteTodos[index].rectificationBeforePhotoFileName {
                snapshot.siteTodos[index].rectificationBeforePhotoFileName = resolver.resolve(fileName)
            }
            if let fileName = snapshot.siteTodos[index].rectificationAfterPhotoFileName {
                snapshot.siteTodos[index].rectificationAfterPhotoFileName = resolver.resolve(fileName)
            }
        }
    }
}
