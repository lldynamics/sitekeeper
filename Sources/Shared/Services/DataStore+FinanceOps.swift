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

    func appendQuoteItem(_ item: QuoteItem) {
        replaceQuoteItems(quoteItems + [item])
    }

    @discardableResult
    func updateQuoteItem(_ item: QuoteItem) -> Bool {
        var current = quoteItems
        guard let index = current.firstIndex(where: { $0.id == item.id }) else { return false }
        current[index] = item
        replaceQuoteItems(current)
        return true
    }

    func mergeQuoteItemsByID(_ items: [QuoteItem]) {
        replaceQuoteItems(mergedFinanceElementsByID(quoteItems, with: items))
    }

    func restoreQuoteItems(from deletion: DataStoreRemovalResult<QuoteItem>) {
        replaceQuoteItems(deletion.restoredItems(current: quoteItems, id: \.id))
    }

    @discardableResult
    func removeQuoteItems(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<QuoteItem> {
        removeFinanceElements(
            from: quoteItems,
            ids: ids,
            id: \.id,
            replace: replaceQuoteItems,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendLaborRecord(_ record: LaborRecord) {
        replaceLaborRecords(laborRecords + [record])
    }

    @discardableResult
    func updateLaborRecord(_ record: LaborRecord) -> Bool {
        var current = laborRecords
        guard let index = current.firstIndex(where: { $0.id == record.id }) else { return false }
        current[index] = record
        replaceLaborRecords(current)
        return true
    }

    func mergeLaborRecordsByID(_ records: [LaborRecord]) {
        replaceLaborRecords(mergedFinanceElementsByID(laborRecords, with: records))
    }

    func restoreLaborRecords(from deletion: DataStoreRemovalResult<LaborRecord>) {
        replaceLaborRecords(deletion.restoredItems(current: laborRecords, id: \.id))
    }

    @discardableResult
    func removeLaborRecords(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<LaborRecord> {
        removeFinanceElements(
            from: laborRecords,
            ids: ids,
            id: \.id,
            replace: replaceLaborRecords,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendProgressTask(_ task: ProgressTask) {
        replaceProgressTasks(progressTasks + [task])
    }

    @discardableResult
    func updateProgressTask(_ task: ProgressTask) -> Bool {
        var current = progressTasks
        guard let index = current.firstIndex(where: { $0.id == task.id }) else { return false }
        current[index] = task
        replaceProgressTasks(current)
        return true
    }

    func mergeProgressTasksByID(_ tasks: [ProgressTask]) {
        replaceProgressTasks(mergedFinanceElementsByID(progressTasks, with: tasks))
    }

    func restoreProgressTasks(from deletion: DataStoreRemovalResult<ProgressTask>) {
        replaceProgressTasks(deletion.restoredItems(current: progressTasks, id: \.id))
    }

    @discardableResult
    func removeProgressTasks(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProgressTask> {
        removeFinanceElements(
            from: progressTasks,
            ids: ids,
            id: \.id,
            replace: replaceProgressTasks,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    private func mergedFinanceElementsByID<Element: Identifiable>(
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
    private func removeFinanceElements<Element, ID: Hashable>(
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
