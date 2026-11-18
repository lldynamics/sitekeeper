import Foundation

extension ProjectDetailFinanceDocumentActions {
    @MainActor
    static func executeDocumentDeletion(
        ids: Set<UUID>,
        store: DataStore,
        documentCleanupMode: LinkedDocumentCleanupMode,
        audit: DataStoreDeletionAuditContext? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DocumentDeletionExecution? {
        guard !ids.isEmpty else { return nil }
        let targets = store.projectDocuments.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return nil }

        let removableFileNames = targets.map(\.fileName)
        let deferredFileCleanup: DataStoreDeferredFileCleanup?
        switch documentCleanupMode {
        case .deferred:
            deferredFileCleanup = nil
        case .immediate:
            deferredFileCleanup = DataStoreDeferredFileCleanup.projectDocumentFiles(
                removableFileNames,
                summary: "projectDetail.documentFile"
            )
        }

        let documentDeletion = store.removeProjectDocuments(
            ids: ids,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
        guard !documentDeletion.isEmpty else { return nil }

        var financialRecords = store.projectFinancialRecords
        for index in financialRecords.indices {
            financialRecords[index].linkedDocumentIds.removeAll { ids.contains($0) }
        }
        store.replaceProjectFinancialRecords(financialRecords)

        var warehouseMovements = store.projectWarehouseMovements
        for index in warehouseMovements.indices {
            warehouseMovements[index].linkedDocumentIds.removeAll { ids.contains($0) }
        }
        store.replaceProjectWarehouseMovements(warehouseMovements)
        return DocumentDeletionExecution(
            documentDeletion: documentDeletion,
            removableDocumentFileNames: removableFileNames
        )
    }

    @MainActor
    static func executeFinancialRecordDeletion(
        ids: Set<UUID>,
        deleteLinkedDocuments: Bool,
        store: DataStore,
        documentCleanupMode: LinkedDocumentCleanupMode,
        financialAudit: DataStoreDeletionAuditContext? = nil,
        recordsAuditImmediately: Bool = false
    ) -> FinancialRecordDeletionExecution? {
        guard !ids.isEmpty else { return nil }

        let recordsToDelete = store.projectFinancialRecords.filter { ids.contains($0.id) }
        guard !recordsToDelete.isEmpty else { return nil }
        let documentProjectIDs = Dictionary(uniqueKeysWithValues: store.projectDocuments.map { ($0.id, $0.projectId) })
        let recordProjectIDs = Dictionary(uniqueKeysWithValues: recordsToDelete.map { ($0.id, $0.projectId) })
        let linkedDocumentIds = Set(recordsToDelete.flatMap { record in
            record.linkedDocumentIds.filter { documentProjectIDs[$0] == record.projectId }
        })
        let linkedByRecordFieldIds: Set<UUID> = Set(
            store.projectDocuments.compactMap { document in
                guard let linkedId = document.linkedFinancialRecordId,
                      recordProjectIDs[linkedId] == document.projectId else { return nil }
                return document.id
            }
        )
        let targetDocumentIds = linkedDocumentIds.union(linkedByRecordFieldIds)

        let removableFileNames = removeOrUnlinkFinancialDocuments(
            targetDocumentIds: targetDocumentIds, deleteLinkedDocuments: deleteLinkedDocuments,
            store: store, documentCleanupMode: documentCleanupMode,
            recordsAuditImmediately: recordsAuditImmediately
        )

        let financialDeletion = store.removeProjectFinancialRecords(
            ids: ids,
            audit: financialAudit,
            recordsAuditImmediately: recordsAuditImmediately
        )
        guard !financialDeletion.isEmpty else { return nil }
        return FinancialRecordDeletionExecution(
            financialDeletion: financialDeletion,
            removableDocumentFileNames: removableFileNames,
            linkedDocumentCount: targetDocumentIds.count
        )
    }

    @MainActor
    private static func removeOrUnlinkFinancialDocuments(
        targetDocumentIds: Set<UUID>,
        deleteLinkedDocuments: Bool,
        store: DataStore,
        documentCleanupMode: LinkedDocumentCleanupMode,
        recordsAuditImmediately: Bool
    ) -> [String] {
        var removableFileNames: [String] = []
        if deleteLinkedDocuments {
            if !targetDocumentIds.isEmpty {
                removableFileNames = store.projectDocuments
                    .filter { targetDocumentIds.contains($0.id) }
                    .map(\.fileName)

                let deferredFileCleanup: DataStoreDeferredFileCleanup?
                switch documentCleanupMode {
                case .deferred:
                    deferredFileCleanup = nil
                case .immediate:
                    deferredFileCleanup = DataStoreDeferredFileCleanup.projectDocumentFiles(
                        removableFileNames,
                        summary: "projectDetail.financialLinkedDocumentFiles"
                    )
                }
                store.removeProjectDocuments(
                    ids: targetDocumentIds,
                    deferredFileCleanup: deferredFileCleanup,
                    recordsAuditImmediately: recordsAuditImmediately
                )
                var financialRecords = store.projectFinancialRecords
                for index in financialRecords.indices {
                    financialRecords[index].linkedDocumentIds.removeAll { targetDocumentIds.contains($0) }
                }
                store.replaceProjectFinancialRecords(financialRecords)

                var warehouseMovements = store.projectWarehouseMovements
                for index in warehouseMovements.indices {
                    warehouseMovements[index].linkedDocumentIds.removeAll { targetDocumentIds.contains($0) }
                }
                store.replaceProjectWarehouseMovements(warehouseMovements)
            }
        } else if !targetDocumentIds.isEmpty {
            var projectDocuments = store.projectDocuments
            for index in projectDocuments.indices {
                guard targetDocumentIds.contains(projectDocuments[index].id) else { continue }
                projectDocuments[index].linkedFinancialRecordId = nil
            }
            store.replaceProjectDocuments(projectDocuments)
        }

        return removableFileNames
    }

    static func linkedDocuments(for record: ProjectFinancialRecord, documents: [ProjectDocument]) -> [ProjectDocument] {
        guard !record.linkedDocumentIds.isEmpty else { return [] }
        let idSet = Set(record.linkedDocumentIds)
        return documents.filter { idSet.contains($0.id) }
    }
}
