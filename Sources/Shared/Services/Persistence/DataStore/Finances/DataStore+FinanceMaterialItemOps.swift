import Foundation

@MainActor
extension DataStore {
    func appendMaterialItem(_ item: MaterialItem) {
        replaceMaterialItems(materialItems + [item])
    }

    @discardableResult
    func updateMaterialItem(_ item: MaterialItem) -> Bool {
        var current = materialItems
        guard let index = current.firstIndex(where: { $0.id == item.id }) else { return false }
        current[index] = item
        replaceMaterialItems(current)
        return true
    }

    func mergeMaterialItemsByID(_ items: [MaterialItem]) {
        replaceMaterialItems(mergedFinanceElementsByID(materialItems, with: items))
    }

    func restoreMaterialItems(from deletion: DataStoreRemovalResult<MaterialItem>) {
        replaceMaterialItems(deletion.restoredItems(current: materialItems, id: \.id))
    }

    @discardableResult
    func removeMaterialItems(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<MaterialItem> {
        removeFinanceElements(
            from: materialItems,
            ids: ids,
            id: \.id,
            replace: replaceMaterialItems,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }
}
