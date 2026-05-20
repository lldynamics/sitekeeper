import Foundation

@MainActor
extension DataStore {
    private(set) var materialItems: [MaterialItem] {
        get {
            access(keyPath: \.materialItems)
            return financeStore.materialItems
        }
        set {
            withMutation(keyPath: \.materialItems) {
                financeStore.setMaterialItems(newValue)
            }
        }
    }

    private(set) var quoteItems: [QuoteItem] {
        get {
            access(keyPath: \.quoteItems)
            return financeStore.quoteItems
        }
        set {
            withMutation(keyPath: \.quoteItems) {
                financeStore.setQuoteItems(newValue)
            }
        }
    }

    private(set) var laborRecords: [LaborRecord] {
        get {
            access(keyPath: \.laborRecords)
            return financeStore.laborRecords
        }
        set {
            withMutation(keyPath: \.laborRecords) {
                financeStore.setLaborRecords(newValue)
            }
        }
    }
}
