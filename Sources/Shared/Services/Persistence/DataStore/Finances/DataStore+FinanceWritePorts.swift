import Foundation

@MainActor
extension DataStore {
    func replaceMaterialItems(_ items: [MaterialItem]) {
        financeStore.setMaterialItems(items)
    }

    func replaceQuoteItems(_ items: [QuoteItem]) {
        financeStore.setQuoteItems(items)
    }

    func replaceLaborRecords(_ records: [LaborRecord]) {
        financeStore.setLaborRecords(records)
    }
}
