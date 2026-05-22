import Foundation

@MainActor
extension DataStore {
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
}
