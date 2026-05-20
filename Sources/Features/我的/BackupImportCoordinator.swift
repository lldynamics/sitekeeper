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
        case .merge:
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
            let migratedLegacyRecords = migratedLegacyPaymentRecords(snapshot.legacyPaymentRecords, projects: store.projects)
            store.mergeProjectFinancialRecordsByID(migratedLegacyRecords)
            store.mergeProjectDocumentsByID(snapshot.projectDocuments)
            store.mergeQuickNotesByID(snapshot.quickNotes)
            store.mergeProjectWarehouseMovementsByID(snapshot.projectWarehouseMovements)
            store.mergeTemplatesByID(snapshot.templates)
            store.mergeMaterialPriceEntriesByID(snapshot.materialPriceEntries)
            store.mergeSupplierProfilesByID(snapshot.supplierProfiles)
            store.mergeConstructionMethodsByID(snapshot.constructionMethods)
            store.favoriteMaterialKeys = mergeUniqueStrings(existing: store.favoriteMaterialKeys, incoming: snapshot.favoriteMaterialKeys)
            store.recentMaterialKeys = mergeUniqueStrings(existing: store.recentMaterialKeys, incoming: snapshot.recentMaterialKeys)
            store.mergeUserMaterialsByID(snapshot.userMaterials)
            store.mergeDeletedUserMaterialsByID(snapshot.deletedUserMaterials)
            store.hiddenPresetKeys.formUnion(snapshot.hiddenPresetKeys)
        case .overwrite:
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
            store.replaceProjectFinancialRecords(mergeUniqueByID(
                snapshot.projectFinancialRecords,
                migratedLegacyPaymentRecords(snapshot.legacyPaymentRecords, projects: snapshot.projects)
            ))
            store.replaceProjectDocuments(snapshot.projectDocuments)
            store.replaceQuickNotes(snapshot.quickNotes)
            store.replaceProjectWarehouseMovements(snapshot.projectWarehouseMovements)
            store.replaceTemplates(snapshot.templates)
            store.replaceMaterialPriceEntries(snapshot.materialPriceEntries)
            store.replaceSupplierProfiles(snapshot.supplierProfiles)
            store.replaceConstructionMethods(snapshot.constructionMethods)
            store.favoriteMaterialKeys = snapshot.favoriteMaterialKeys
            store.recentMaterialKeys = snapshot.recentMaterialKeys
            store.replaceUserMaterials(snapshot.userMaterials)
            store.replaceDeletedUserMaterials(snapshot.deletedUserMaterials)
            store.hiddenPresetKeys = snapshot.hiddenPresetKeys
        }
        if !snapshot.legacyPaymentRecords.isEmpty {
            StorageIssueLog.record("导入备份时已迁移旧收款记录 \(snapshot.legacyPaymentRecords.count) 条到财务流水")
        }
        store.enforceCalculationHistoryRetention()
        sanitizeMaterialProjectReferences(in: store)
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
            StorageIssueLog.record(
                "覆盖导入清理旧文件失败：\(cleanupErrors.joined(separator: "；"))"
            )
        }
        return impact
    }

    private static func appendUniqueByID<T: Identifiable>(_ incoming: [T], to current: inout [T]) where T.ID: Hashable {
        var existing = Set(current.map(\.id))
        for item in incoming where !existing.contains(item.id) {
            current.append(item)
            existing.insert(item.id)
        }
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

    private static func mergeUniqueByID<T: Identifiable>(_ primary: [T], _ secondary: [T]) -> [T] where T.ID: Hashable {
        var merged = primary
        var knownIDs = Set(primary.map(\.id))
        for item in secondary where knownIDs.insert(item.id).inserted {
            merged.append(item)
        }
        return merged
    }

    private static func migratedLegacyPaymentRecords(
        _ records: [LegacyPaymentRecord],
        projects: [Project]
    ) -> [ProjectFinancialRecord] {
        guard !records.isEmpty else { return [] }
        let counterpartyByProjectID = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.id, $0.customerName) }
        )
        return records.map { record in
            record.migratedFinancialRecord(
                counterparty: counterpartyByProjectID[record.projectId] ?? ""
            )
        }
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
