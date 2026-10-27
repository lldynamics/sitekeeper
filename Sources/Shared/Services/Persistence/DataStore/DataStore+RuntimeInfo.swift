import Foundation

@MainActor
extension DataStore {
    var canEditBusinessData: Bool { loadState == .ready && !isApplyingBackup }

    func requireBusinessWritesAllowed() throws {
        guard canEditBusinessData else { throw PersistenceBlockedError(message: persistenceErrorMessage) }
    }

    static func recordIssue(
        _ event: String,
        details: [String: String] = [:],
        error: Error? = nil
    ) {
        StorageIssueLog.recordEvent(
            event,
            category: .dataStore,
            details: details,
            error: error
        )
    }

    var hasAnyBusinessData: Bool {
        !materialItems.isEmpty ||
        !quoteItems.isEmpty ||
        !laborRecords.isEmpty ||
        !projects.isEmpty ||
        !dailyLogs.isEmpty ||
        !historyRecords.isEmpty ||
        !progressTasks.isEmpty ||
        !siteTodos.isEmpty ||
        !projectDrawings.isEmpty ||
        !projectContacts.isEmpty ||
        !projectFinancialRecords.isEmpty ||
        !projectDocuments.isEmpty ||
        !quickNotes.isEmpty ||
        !projectWarehouseMovements.isEmpty ||
        !templates.isEmpty ||
        !materialPriceEntries.isEmpty ||
        !materialSheetDrafts.isEmpty ||
        !supplierProfiles.isEmpty ||
        !constructionMethods.isEmpty ||
        !userMaterials.isEmpty ||
        !deletedUserMaterials.isEmpty
    }

    static var defaultDocumentsDirectory: URL {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return dir
        }
        recordIssue(
            "datastore.documents_directory_unavailable",
            details: ["fallback": "temporary-directory"]
        )
        return FileManager.default.temporaryDirectory
    }
}
