import Foundation

@MainActor
extension DataStore {
    func appendMaterialPriceEntry(_ entry: MaterialPriceEntry) {
        replaceMaterialPriceEntries(materialPriceEntries + [entry])
    }

    func appendMaterialPriceEntries(_ entries: [MaterialPriceEntry]) {
        guard !entries.isEmpty else { return }
        replaceMaterialPriceEntries(materialPriceEntries + entries)
    }

    func mergeMaterialPriceEntriesByID(_ entries: [MaterialPriceEntry]) {
        replaceMaterialPriceEntries(mergedUniqueByID(materialPriceEntries, with: entries))
    }

    func insertMaterialPriceEntryAtTop(_ entry: MaterialPriceEntry) {
        var entries = materialPriceEntries
        entries.insert(entry, at: 0)
        replaceMaterialPriceEntries(entries)
    }

    func upsertMaterialPriceEntry(_ entry: MaterialPriceEntry) {
        var entries = materialPriceEntries
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            replaceMaterialPriceEntries(entries)
            return
        }

        let entryKey = MaterialIdentity.key(
            name: entry.name,
            specification: entry.specification,
            unit: entry.unit
        )
        if let duplicateIndex = entries.firstIndex(where: {
            MaterialIdentity.key(name: $0.name, specification: $0.specification, unit: $0.unit) == entryKey
        }) {
            var merged = entry
            merged.id = entries[duplicateIndex].id
            entries[duplicateIndex] = merged
            replaceMaterialPriceEntries(entries)
            return
        }

        entries.insert(entry, at: 0)
        replaceMaterialPriceEntries(entries)
    }

    func restoreMaterialPriceEntries(from deletion: DataStoreRemovalResult<MaterialPriceEntry>) {
        replaceMaterialPriceEntries(deletion.restoredItems(current: materialPriceEntries, id: \.id))
    }

    func insertMaterialSheetDraftAtTop(_ draft: MaterialSheetDraft) {
        var drafts = materialSheetDrafts
        drafts.insert(draft, at: 0)
        replaceMaterialSheetDrafts(drafts)
    }

    func mergeMaterialSheetDraftsByID(_ drafts: [MaterialSheetDraft]) {
        replaceMaterialSheetDrafts(mergedUniqueByID(materialSheetDrafts, with: drafts))
    }

    func mergeSupplierProfilesByID(_ profiles: [SupplierProfile]) {
        replaceSupplierProfiles(mergedUniqueByID(supplierProfiles, with: profiles))
    }

    func appendUserMaterial(_ material: UserMaterial) {
        replaceUserMaterials(userMaterials + [material])
    }

    func mergeUserMaterialsByID(_ materials: [UserMaterial]) {
        replaceUserMaterials(mergedUniqueByID(userMaterials, with: materials))
    }

    func restoreUserMaterials(from deletion: DataStoreRemovalResult<UserMaterial>) {
        replaceUserMaterials(deletion.restoredItems(current: userMaterials, id: \.id))
    }

    func mergeDeletedUserMaterialsByID(_ materials: [UserMaterial]) {
        replaceDeletedUserMaterials(mergedUniqueByID(deletedUserMaterials, with: materials))
    }

    func removeDeletedUserMaterials(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        replaceDeletedUserMaterials(deletedUserMaterials.filter { !ids.contains($0.id) })
    }

    func prependDeletedUserMaterials(_ materials: [UserMaterial], maxCount: Int? = nil) {
        guard !materials.isEmpty else { return }
        var current = deletedUserMaterials
        let incomingIDs = Set(materials.map(\.id))
        current.removeAll { incomingIDs.contains($0.id) }
        current.insert(contentsOf: materials, at: 0)
        if let maxCount, maxCount > 0, current.count > maxCount {
            current = Array(current.prefix(maxCount))
        }
        replaceDeletedUserMaterials(current)
    }

    @discardableResult
    func removeUserMaterials(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<UserMaterial> {
        removeLibraryElements(
            from: userMaterials,
            ids: ids,
            id: \.id,
            replace: replaceUserMaterials,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    func removeMaterialPriceEntries(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<MaterialPriceEntry> {
        removeLibraryElements(
            from: materialPriceEntries,
            ids: ids,
            id: \.id,
            replace: replaceMaterialPriceEntries,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    func removeMaterialSheetDrafts(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<MaterialSheetDraft> {
        removeLibraryElements(
            from: materialSheetDrafts,
            ids: ids,
            id: \.id,
            replace: replaceMaterialSheetDrafts,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }
}
