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

    func appendTemplate(_ template: ProjectTemplate) {
        replaceTemplates(templates + [template])
    }

    func mergeTemplatesByID(_ templates: [ProjectTemplate]) {
        replaceTemplates(mergedUniqueByID(self.templates, with: templates))
    }

    func insertTemplateAtTop(_ template: ProjectTemplate) {
        var currentTemplates = templates
        currentTemplates.insert(template, at: 0)
        replaceTemplates(currentTemplates)
    }

    func upsertTemplate(
        _ template: ProjectTemplate,
        insertAtTopWhenNew: Bool = false
    ) {
        var currentTemplates = templates
        if let index = currentTemplates.firstIndex(where: { $0.id == template.id }) {
            currentTemplates[index] = template
            replaceTemplates(currentTemplates)
            return
        }
        if insertAtTopWhenNew {
            currentTemplates.insert(template, at: 0)
        } else {
            currentTemplates.append(template)
        }
        replaceTemplates(currentTemplates)
    }

    func restoreTemplates(from deletion: DataStoreRemovalResult<ProjectTemplate>) {
        replaceTemplates(deletion.restoredItems(current: templates, id: \.id))
    }

    func mergeConstructionMethodsByID(_ methods: [ConstructionMethod]) {
        replaceConstructionMethods(mergedUniqueByID(constructionMethods, with: methods))
    }

    func upsertConstructionMethod(
        _ method: ConstructionMethod,
        insertAtTopWhenNew: Bool = false
    ) {
        var currentMethods = constructionMethods
        if let index = currentMethods.firstIndex(where: { $0.id == method.id }) {
            currentMethods[index] = method
            replaceConstructionMethods(currentMethods)
            return
        }
        if insertAtTopWhenNew {
            currentMethods.insert(method, at: 0)
        } else {
            currentMethods.append(method)
        }
        replaceConstructionMethods(currentMethods)
    }

    func restoreConstructionMethods(from deletion: DataStoreRemovalResult<ConstructionMethod>) {
        replaceConstructionMethods(deletion.restoredItems(current: constructionMethods, id: \.id))
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

    @discardableResult
    func removeTemplates(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectTemplate> {
        removeLibraryElements(
            from: templates,
            ids: ids,
            id: \.id,
            replace: replaceTemplates,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    func removeConstructionMethods(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ConstructionMethod> {
        removeLibraryElements(
            from: constructionMethods,
            ids: ids,
            id: \.id,
            replace: replaceConstructionMethods,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    private func mergedUniqueByID<Element: Identifiable>(
        _ current: [Element],
        with incoming: [Element]
    ) -> [Element] where Element.ID: Hashable {
        guard !incoming.isEmpty else { return current }
        var merged = current
        var existingIDs = Set(current.map(\.id))
        for item in incoming where existingIDs.insert(item.id).inserted {
            merged.append(item)
        }
        return merged
    }

    @discardableResult
    private func removeLibraryElements<Element, ID: Hashable>(
        from current: [Element],
        ids: Set<ID>,
        id: (Element) -> ID,
        replace: ([Element]) -> Void,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<Element> {
        guard !ids.isEmpty else {
            return DataStoreRemovalResult(
                snapshot: current,
                removed: [],
                audit: audit,
                deferredFileCleanup: deferredFileCleanup
            )
        }

        let removed = current.filter { ids.contains(id($0)) }
        guard !removed.isEmpty else {
            return DataStoreRemovalResult(
                snapshot: current,
                removed: [],
                audit: audit,
                deferredFileCleanup: deferredFileCleanup
            )
        }

        replace(current.filter { !ids.contains(id($0)) })

        let result = DataStoreRemovalResult(
            snapshot: current,
            removed: removed,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup
        )
        if recordsAuditImmediately {
            result.recordAuditStarted()
            result.performDeferredFileCleanup()
            result.recordAuditSucceeded()
        }
        return result
    }
}
