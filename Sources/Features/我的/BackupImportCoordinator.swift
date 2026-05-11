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
            appendUniqueByID(snapshot.paymentRecords, to: &store.paymentRecords)
            appendUniqueByID(snapshot.projectDrawings, to: &store.projectDrawings)
            appendUniqueByID(snapshot.projectContacts, to: &store.projectContacts)
            appendUniqueByID(snapshot.projectFinancialRecords, to: &store.projectFinancialRecords)
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
            store.paymentRecords = snapshot.paymentRecords
            store.projectDrawings = snapshot.projectDrawings
            store.projectContacts = snapshot.projectContacts
            store.projectFinancialRecords = snapshot.projectFinancialRecords
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
        store.enforceCalculationHistoryRetention()
        sanitizeMaterialProjectReferences(in: store)
    }

    static func cleanupOverwrittenFiles(previous: BackupSnapshot, imported: BackupSnapshot) {
        let oldPhotoNames = photoFileNames(in: previous)
        let newPhotoNames = photoFileNames(in: imported)
        let oldDrawingNames = Set(previous.projectDrawings.map(\.fileName).filter { !$0.isEmpty })
        let newDrawingNames = Set(imported.projectDrawings.map(\.fileName).filter { !$0.isEmpty })
        let oldDocumentNames = Set(previous.projectDocuments.map(\.fileName).filter { !$0.isEmpty })
        let newDocumentNames = Set(imported.projectDocuments.map(\.fileName).filter { !$0.isEmpty })
        let oldQuickNoteAttachmentNames = quickNoteAttachmentFileNames(in: previous)
        let newQuickNoteAttachmentNames = quickNoteAttachmentFileNames(in: imported)

        PhotoStorage.delete(fileNames: Array(oldPhotoNames.subtracting(newPhotoNames)))
        DrawingStorage.delete(fileNames: Array(oldDrawingNames.subtracting(newDrawingNames)))
        ProjectDocumentStorage.delete(fileNames: Array(oldDocumentNames.subtracting(newDocumentNames)))
        QuickNoteAttachmentStorage.delete(fileNames: Array(oldQuickNoteAttachmentNames.subtracting(newQuickNoteAttachmentNames)))
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
