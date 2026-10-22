import Foundation

@MainActor
enum ProjectWarehouseDeletionActions {
    @MainActor
    struct Deletion {
        let movements: DataStoreRemovalResult<ProjectWarehouseMovement>
        let documents: DataStoreRemovalResult<ProjectDocument>?

        func restore(in store: DataStore) {
            store.replaceProjectWarehouseMovements(Self.restoringMissing(movements, current: store.projectWarehouseMovements))
            if let documents {
                store.replaceProjectDocuments(Self.restoringMissing(documents, current: store.projectDocuments))
            }
            store.scheduleSave()
        }

        func commit(in store: DataStore) {
            documents?.performDeferredFileCleanup()
            store.scheduleSave()
        }

        private static func restoringMissing<Element: Identifiable>(
            _ deletion: DataStoreRemovalResult<Element>,
            current: [Element]
        ) -> [Element] {
            let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            return deletion.restoredItems(current: current, id: \.id).map { currentByID[$0.id] ?? $0 }
        }
    }

    static func execute(ids: Set<UUID>, deleteAttachments: Bool, store: DataStore) -> Deletion? {
        let targets = store.projectWarehouseMovements.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return nil }
        let documentIDs = deleteAttachments ? removableDocumentIDs(for: targets, store: store) : []
        let fileNames = store.projectDocuments.filter { documentIDs.contains($0.id) }.map(\.fileName)
        let summary = deleteAttachments
            ? String(format: String(localized: "删除 %lld 条出入库流水（含附件）"), Int64(targets.count))
            : String(format: String(localized: "删除 %lld 条出入库流水"), Int64(targets.count))
        let movements = store.removeProjectWarehouseMovements(
            ids: ids,
            audit: DataStoreDeletionAuditContext(
                summary: summary,
                detail: String(format: String(localized: "关联附件文件 %lld 个"), Int64(fileNames.count)),
                source: "ProjectWarehouseView"
            )
        )
        // Only unreferenced attachments are removed, so surviving records need no link changes.
        let documents = documentIDs.isEmpty ? nil : store.removeProjectDocuments(
            ids: documentIDs,
            deferredFileCleanup: .projectDocumentFiles(fileNames, summary: "projectWarehouse.documentFiles")
        )
        return Deletion(movements: movements, documents: documents)
    }

    private static func removableDocumentIDs(
        for targets: [ProjectWarehouseMovement],
        store: DataStore
    ) -> Set<UUID> {
        let targetIDs = Set(targets.map(\.id))
        let survivingLinks = Set(store.projectWarehouseMovements
            .filter { !targetIDs.contains($0.id) }
            .flatMap(\.linkedDocumentIds))
        let financialLinks = Set(store.projectFinancialRecords.flatMap(\.linkedDocumentIds))
        return Set(targets.flatMap(\.linkedDocumentIds))
            .subtracting(survivingLinks)
            .subtracting(financialLinks)
    }
}
