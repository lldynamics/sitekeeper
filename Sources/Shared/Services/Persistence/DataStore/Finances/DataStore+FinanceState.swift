import Foundation

@MainActor
extension DataStore {
    private(set) var materialItems: [MaterialItem] {
        get {
            return financeStore.materialItems
        }
        set {
            financeStore.setMaterialItems(newValue)
        }
    }

    private(set) var quoteItems: [QuoteItem] {
        get {
            return financeStore.quoteItems
        }
        set {
            financeStore.setQuoteItems(newValue)
        }
    }

    private(set) var laborRecords: [LaborRecord] {
        get {
            return financeStore.laborRecords
        }
        set {
            financeStore.setLaborRecords(newValue)
        }
    }
}
