import Foundation

@MainActor
extension DataStore {
    func replaceMaterialItems(_ items: [MaterialItem]) {
        withMutation(keyPath: \.materialItems) {
            financeStore.setMaterialItems(items)
        }
    }

    func replaceQuoteItems(_ items: [QuoteItem]) {
        withMutation(keyPath: \.quoteItems) {
            financeStore.setQuoteItems(items)
        }
    }

    func replaceLaborRecords(_ records: [LaborRecord]) {
        withMutation(keyPath: \.laborRecords) {
            financeStore.setLaborRecords(records)
        }
    }
}
