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
        if FileManager.default.fileExists(atPath: copiedURL.path) {
            try FileManager.default.removeItem(at: copiedURL)
        }
        try FileManager.default.copyItem(at: selectedURL, to: copiedURL)
        return copiedURL
    }

    @MainActor
    static func applyImportMetadata(snapshot: BackupSnapshot, mode: ImportMode, store: DataStore) {
        switch mode {
        case .merge:
            appendUniqueByID(snapshot.materialItems, to: &store.materialItems)
            appendUniqueByID(snapshot.quoteItems, to: &store.quoteItems)
            appendUniqueByID(snapshot.laborRecords, to: &store.laborRecords)
            appendUniqueByID(snapshot.projects, to: &store.projects)
            appendUniqueByID(snapshot.dailyLogs, to: &store.dailyLogs)
            appendUniqueByID(snapshot.historyRecords, to: &store.historyRecords)
            appendUniqueByID(snapshot.progressTasks, to: &store.progressTasks)
            appendUniqueByID(snapshot.lightingCircuitPlans, to: &store.lightingCircuitPlans)
            appendUniqueByID(snapshot.siteTodos, to: &store.siteTodos)
            appendUniqueByID(snapshot.projectDrawings, to: &store.projectDrawings)
            appendUniqueByID(snapshot.projectContacts, to: &store.projectContacts)
            appendUniqueByID(snapshot.projectFinancialRecords, to: &store.projectFinancialRecords)
            let migratedLegacyRecords = migratedLegacyPaymentRecords(snapshot.legacyPaymentRecords, projects: store.projects)
            appendUniqueByID(migratedLegacyRecords, to: &store.projectFinancialRecords)
            appendUniqueByID(snapshot.projectDocuments, to: &store.projectDocuments)
            appendUniqueByID(snapshot.quickNotes, to: &store.quickNotes)
            appendUniqueByID(snapshot.projectWarehouseMovements, to: &store.projectWarehouseMovements)
            appendUniqueByID(snapshot.templates, to: &store.templates)
            appendUniqueByID(snapshot.materialPriceEntries, to: &store.materialPriceEntries)
            appendUniqueByID(snapshot.supplierProfiles, to: &store.supplierProfiles)
            appendUniqueByID(snapshot.constructionMethods, to: &store.constructionMethods)
            store.favoriteMaterialKeys = mergeUniqueStrings(existing: store.favoriteMaterialKeys, incoming: snapshot.favoriteMaterialKeys)
            store.recentMaterialKeys = mergeUniqueStrings(existing: store.recentMaterialKeys, incoming: snapshot.recentMaterialKeys)
            appendUniqueByID(snapshot.userMaterials, to: &store.userMaterials)
            appendUniqueByID(snapshot.deletedUserMaterials, to: &store.deletedUserMaterials)
            store.hiddenPresetKeys.formUnion(snapshot.hiddenPresetKeys)
        case .overwrite:
            store.materialItems = snapshot.materialItems
            store.quoteItems = snapshot.quoteItems
            store.laborRecords = snapshot.laborRecords
            store.projects = snapshot.projects
            store.dailyLogs = snapshot.dailyLogs
            store.historyRecords = snapshot.historyRecords
            store.progressTasks = snapshot.progressTasks
            store.lightingCircuitPlans = snapshot.lightingCircuitPlans
            store.siteTodos = snapshot.siteTodos
            store.projectDrawings = snapshot.projectDrawings
            store.projectContacts = snapshot.projectContacts
            store.projectFinancialRecords = mergeUniqueByID(
                snapshot.projectFinancialRecords,
                migratedLegacyPaymentRecords(snapshot.legacyPaymentRecords, projects: snapshot.projects)
            )
            store.projectDocuments = snapshot.projectDocuments
            store.quickNotes = snapshot.quickNotes
            store.projectWarehouseMovements = snapshot.projectWarehouseMovements
            store.templates = snapshot.templates
            store.materialPriceEntries = snapshot.materialPriceEntries
            store.supplierProfiles = snapshot.supplierProfiles
            store.constructionMethods = snapshot.constructionMethods
            store.favoriteMaterialKeys = snapshot.favoriteMaterialKeys
            store.recentMaterialKeys = snapshot.recentMaterialKeys
            store.userMaterials = snapshot.userMaterials
            store.deletedUserMaterials = snapshot.deletedUserMaterials
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
        for index in store.materialItems.indices {
            guard let projectId = store.materialItems[index].projectId,
                  !validProjectIds.contains(projectId) else { continue }
            store.materialItems[index].projectId = nil
        }
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
