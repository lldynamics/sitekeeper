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
        try importedSnapshot.validateRecordIdentifiers()
        try importedSnapshot.validateAttachmentReferences()
        await store.awaitInitialLoad()
        try store.requireNoBackupExport()
        guard !store.isApplyingBackup else {
            throw DataStore.PersistenceBlockedError(message: nil)
        }
        if importMode == .merge {
            try store.makeSnapshot(includePhotoFiles: false).validateRecordIdentifiers()
        }
        store.isApplyingBackup = true
        store.cancelScheduledSave()
        store.persistTask?.cancel()
        await store.persistTask?.value
        defer {
            store.isApplyingBackup = false
            store.cancelScheduledSave()
        }
        let preparation = try prepareImport(
            importedSnapshot: importedSnapshot,
            previousSnapshot: previousSnapshot,
            overwritesExistingFiles: importMode == .overwrite
        )
        applyImportMetadata(snapshot: preparation.snapshot, mode: importMode, store: store)

        return try await commitAppliedImport(
            restoreTransaction: restoreTransaction, restorePolicy: preparation.restorePolicy,
            previousSnapshot: previousSnapshot, importMode: importMode, store: store,
            sourceFileName: sourceFileName, onPersistingMetadata: onPersistingMetadata
        )
    }
}

extension BackupImportCoordinator {
    static func previewWithLocalImpact(_ preview: BackupImportPreview, previous: BackupSnapshot) -> BackupImportPreview {
        BackupImportPreview(
            snapshot: preview.snapshot,
            manifest: preview.manifest,
            incomingFiles: preview.incomingFiles,
            overwrittenLocalFiles: overwrittenLocalFiles(previous: previous, imported: preview.snapshot),
            mergeFilePlan: Result { try plannedRestoreFiles(from: preview, previous: previous, mode: .merge) },
            overwriteFilePlan: Result { try plannedRestoreFiles(from: preview, previous: previous, mode: .overwrite) }
        )
    }

    static func overwrittenLocalFiles(previous: BackupSnapshot, imported: BackupSnapshot) -> BackupFileImpactSummary {
        let oldPhotoNames = photoFileNames(in: previous)
        let newPhotoNames = photoFileNames(in: imported)
        let oldDrawingNames = Set(previous.projectDrawings.map(\.fileName).filter { !$0.isEmpty })
        let newDrawingNames = Set(imported.projectDrawings.map(\.fileName).filter { !$0.isEmpty })
        let oldDocumentNames = Set(previous.projectDocuments.map(\.fileName).filter { !$0.isEmpty })
        let newDocumentNames = Set(imported.projectDocuments.map(\.fileName).filter { !$0.isEmpty })
        let oldQuickNoteAttachmentNames = quickNoteAttachmentFileNames(in: previous)
        let newQuickNoteAttachmentNames = quickNoteAttachmentFileNames(in: imported)

        func removed(_ old: Set<String>, _ new: Set<String>, exists: (String) -> Bool) -> [String] {
            let retained = Set(new.map(AttachmentStoragePath.comparisonKey))
            return old.filter { !retained.contains(AttachmentStoragePath.comparisonKey($0)) && exists($0) }
        }
        return BackupFileImpactSummary(
            photoFileNames: removed(oldPhotoNames, newPhotoNames, exists: PhotoStorage.exists(fileName:)),
            drawingFileNames: removed(oldDrawingNames, newDrawingNames, exists: DrawingStorage.exists(fileName:)),
            documentFileNames: removed(oldDocumentNames, newDocumentNames, exists: ProjectDocumentStorage.exists(fileName:)),
            quickNoteAttachmentFileNames: removed(oldQuickNoteAttachmentNames, newQuickNoteAttachmentNames, exists: QuickNoteAttachmentStorage.exists(fileName:))
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
    static func plannedRestoreFiles(
        from preview: BackupImportPreview,
        previous: BackupSnapshot,
        mode: ImportMode
    ) throws -> BackupFileImpactSummary {
        let preparation = try prepareImport(
            importedSnapshot: preview.snapshot,
            previousSnapshot: previous,
            overwritesExistingFiles: mode == .overwrite
        )
        return preparation.restorePolicy.plannedFiles(from: preview.incomingFiles)
    }

    private struct MergeImportPreparation {
        var snapshot: BackupSnapshot
        var restorePolicy: BackupEmbeddedFileRestorePolicy
    }

    private struct MergeFileNameResolver {
        private(set) var destinations: [String: String] = [:]
        private var sourceDestinations: [String: String] = [:]
        private var reservedDestinations = Set<String>()
        let existingNames: [String: [String]]
        let referencedNames: [String: [String]]
        let overwritesExistingFiles: Bool
        let exists: (String) -> Bool

        init(
            existingNames: [String],
            referencedNames: Set<String>,
            overwritesExistingFiles: Bool,
            exists: @escaping (String) -> Bool
        ) {
            self.existingNames = Dictionary(grouping: existingNames, by: AttachmentStoragePath.comparisonKey)
            self.referencedNames = Dictionary(grouping: referencedNames, by: AttachmentStoragePath.comparisonKey)
            self.overwritesExistingFiles = overwritesExistingFiles
            self.exists = exists
        }

        mutating func restoreMissingReference(_ source: String, key: String) {
            guard sourceDestinations[key] == nil,
                  existingNames[key] == nil,
                  let references = referencedNames[key], references.count == 1,
                  let destination = references.first, !exists(destination) else { return }
            recordDestination(destination, for: source, key: key)
        }

        mutating func resolve(_ sourceFileName: String) throws -> String {
            guard !sourceFileName.isEmpty else { return sourceFileName }
            let key = AttachmentStoragePath.comparisonKey(sourceFileName)
            if let destination = sourceDestinations[key] {
                destinations[sourceFileName] = destination
                return destination
            }

            let matches = existingNames[key] ?? []
            let destination: String
            if overwritesExistingFiles {
                // An ambiguous existing family cannot safely choose an overwrite target.
                guard matches.count <= 1 else { throw FileStorageError.unsafeAttachmentPath(sourceFileName) }
                destination = matches.first ?? sourceFileName
            } else if matches.isEmpty, referencedNames[key] == nil,
                      !exists(sourceFileName), !reservedDestinations.contains(key) {
                destination = sourceFileName
            } else {
                destination = makeAvailableFileName(basedOn: sourceFileName)
            }
            recordDestination(destination, for: sourceFileName, key: key)
            return destination
        }

        private mutating func recordDestination(_ destination: String, for source: String, key: String) {
            destinations[source] = destination
            sourceDestinations[key] = destination
            reservedDestinations.insert(AttachmentStoragePath.comparisonKey(destination))
        }

        private mutating func makeAvailableFileName(basedOn sourceFileName: String) -> String {
            let fileExtension = URL(fileURLWithPath: sourceFileName).pathExtension
            while true {
                var candidate = "backup-merge-\(UUID().uuidString)"
                if !fileExtension.isEmpty {
                    candidate += ".\(fileExtension)"
                }
                let key = AttachmentStoragePath.comparisonKey(candidate)
                if existingNames[key] == nil, referencedNames[key] == nil,
                   !exists(candidate), !reservedDestinations.contains(key) {
                    return candidate
                }
            }
        }
    }

    private static func prepareImport(
        importedSnapshot: BackupSnapshot,
        previousSnapshot: BackupSnapshot,
        overwritesExistingFiles: Bool
    ) throws -> MergeImportPreparation {
        var snapshot = importedSnapshot
        var photoResolver = MergeFileNameResolver(
            existingNames: try storedNames(PhotoStorage.fileURL(for:)),
            referencedNames: photoFileNames(in: previousSnapshot),
            overwritesExistingFiles: overwritesExistingFiles, exists: PhotoStorage.exists(fileName:)
        )
        var drawingResolver = MergeFileNameResolver(
            existingNames: try storedNames(DrawingStorage.fileURL(for:)),
            referencedNames: Set(previousSnapshot.projectDrawings.map(\.fileName).filter { !$0.isEmpty }),
            overwritesExistingFiles: overwritesExistingFiles, exists: DrawingStorage.exists(fileName:)
        )
        var documentResolver = MergeFileNameResolver(
            existingNames: try storedNames(ProjectDocumentStorage.fileURL(for:)),
            referencedNames: Set(previousSnapshot.projectDocuments.map(\.fileName).filter { !$0.isEmpty }),
            overwritesExistingFiles: overwritesExistingFiles, exists: ProjectDocumentStorage.exists(fileName:)
        )
        var attachmentResolver = MergeFileNameResolver(
            existingNames: try storedNames(QuickNoteAttachmentStorage.fileURL(for:)),
            referencedNames: quickNoteAttachmentFileNames(in: previousSnapshot),
            overwritesExistingFiles: overwritesExistingFiles, exists: QuickNoteAttachmentStorage.exists(fileName:)
        )

        if !overwritesExistingFiles {
            // Match within the same record before reserving paths for newly imported records.
            // A name referenced by an unrelated local record must not silently acquire new bytes.
            restoreSharedReferences(snapshot.dailyLogs, previous: previousSnapshot.dailyLogs, names: \.allPhotoFileNames, resolver: &photoResolver)
            restoreSharedReferences(snapshot.siteTodos, previous: previousSnapshot.siteTodos, names: todoPhotoNames, resolver: &photoResolver)
            restoreSharedReferences(snapshot.projectDrawings, previous: previousSnapshot.projectDrawings, names: { [$0.fileName] }, resolver: &drawingResolver)
            restoreSharedReferences(snapshot.projectDocuments, previous: previousSnapshot.projectDocuments, names: { [$0.fileName] }, resolver: &documentResolver)
            restoreSharedReferences(snapshot.quickNotes, previous: previousSnapshot.quickNotes, names: { $0.attachments.map(\.fileName) }, resolver: &attachmentResolver)
            restoreSharedReferences(snapshot.constructionMethods, previous: previousSnapshot.constructionMethods, names: { ($0.attachments + $0.tutorialAttachments).map(\.fileName) }, resolver: &attachmentResolver)
        }

        try resolvePhotoReferences(in: &snapshot, previous: previousSnapshot, overwritesExistingFiles: overwritesExistingFiles, resolver: &photoResolver)

        let existingDrawingIDs = Set(previousSnapshot.projectDrawings.map(\.id))
        for index in snapshot.projectDrawings.indices where overwritesExistingFiles || !existingDrawingIDs.contains(snapshot.projectDrawings[index].id) {
            snapshot.projectDrawings[index].fileName = try drawingResolver.resolve(snapshot.projectDrawings[index].fileName)
        }

        let existingDocumentIDs = Set(previousSnapshot.projectDocuments.map(\.id))
        for index in snapshot.projectDocuments.indices where overwritesExistingFiles || !existingDocumentIDs.contains(snapshot.projectDocuments[index].id) {
            snapshot.projectDocuments[index].fileName = try documentResolver.resolve(snapshot.projectDocuments[index].fileName)
        }

        let existingQuickNoteIDs = Set(previousSnapshot.quickNotes.map(\.id))
        for index in snapshot.quickNotes.indices where overwritesExistingFiles || !existingQuickNoteIDs.contains(snapshot.quickNotes[index].id) {
            for attachmentIndex in snapshot.quickNotes[index].attachments.indices {
                snapshot.quickNotes[index].attachments[attachmentIndex].fileName = try attachmentResolver.resolve(
                    snapshot.quickNotes[index].attachments[attachmentIndex].fileName
                )
            }
        }

        let existingMethodIDs = Set(previousSnapshot.constructionMethods.map(\.id))
        for index in snapshot.constructionMethods.indices where overwritesExistingFiles || !existingMethodIDs.contains(snapshot.constructionMethods[index].id) {
            for attachmentIndex in snapshot.constructionMethods[index].attachments.indices {
                snapshot.constructionMethods[index].attachments[attachmentIndex].fileName = try attachmentResolver.resolve(
                    snapshot.constructionMethods[index].attachments[attachmentIndex].fileName
                )
            }
            for attachmentIndex in snapshot.constructionMethods[index].tutorialAttachments.indices {
                snapshot.constructionMethods[index].tutorialAttachments[attachmentIndex].fileName = try attachmentResolver.resolve(
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
                quickNoteAttachmentFileDestinations: attachmentResolver.destinations,
                overwritesExistingFiles: overwritesExistingFiles
            )
        )
    }

    private static func restoreSharedReferences<Record: Identifiable>(
        _ imported: [Record],
        previous: [Record],
        names: (Record) -> [String],
        resolver: inout MergeFileNameResolver
    ) {
        let previousByID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for record in imported {
            guard let local = previousByID[record.id] else { continue }
            let localKeys = Set(names(local).filter { !$0.isEmpty }.map(AttachmentStoragePath.comparisonKey))
            for source in names(record) where !source.isEmpty {
                let key = AttachmentStoragePath.comparisonKey(source)
                if localKeys.contains(key) {
                    resolver.restoreMissingReference(source, key: key)
                }
            }
        }
    }

    private static func todoPhotoNames(_ todo: SiteTodo) -> [String] {
        [todo.rectificationBeforePhotoFileName, todo.rectificationAfterPhotoFileName].compactMap { $0 }
    }

    private static func storedNames(_ fileURL: (String) -> URL) throws -> [String] {
        let probe = fileURL(".backup-name-probe-\(UUID().uuidString)")
        guard probe.isFileURL else { throw FileStorageError.unsafeAttachmentPath(probe.lastPathComponent) }
        let directory = probe.deletingLastPathComponent()
        try AttachmentStoragePath.validateDirectory(directory)
        do {
            return try FileManager.default.contentsOfDirectory(atPath: directory.path)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return []
        }
    }

    private static func resolvePhotoReferences(in snapshot: inout BackupSnapshot, previous previousSnapshot: BackupSnapshot, overwritesExistingFiles: Bool, resolver: inout MergeFileNameResolver) throws {
        let existingDailyLogIDs = Set(previousSnapshot.dailyLogs.map(\.id))
        for index in snapshot.dailyLogs.indices where overwritesExistingFiles || !existingDailyLogIDs.contains(snapshot.dailyLogs[index].id) {
            if let fileName = snapshot.dailyLogs[index].photoFileName {
                snapshot.dailyLogs[index].photoFileName = try resolver.resolve(fileName)
            }
            for photoIndex in snapshot.dailyLogs[index].photos.indices {
                snapshot.dailyLogs[index].photos[photoIndex].fileName = try resolver.resolve(
                    snapshot.dailyLogs[index].photos[photoIndex].fileName
                )
            }
        }

        let existingTodoIDs = Set(previousSnapshot.siteTodos.map(\.id))
        for index in snapshot.siteTodos.indices where overwritesExistingFiles || !existingTodoIDs.contains(snapshot.siteTodos[index].id) {
            if let fileName = snapshot.siteTodos[index].rectificationBeforePhotoFileName {
                snapshot.siteTodos[index].rectificationBeforePhotoFileName = try resolver.resolve(fileName)
            }
            if let fileName = snapshot.siteTodos[index].rectificationAfterPhotoFileName {
                snapshot.siteTodos[index].rectificationAfterPhotoFileName = try resolver.resolve(fileName)
            }
        }
    }
}
