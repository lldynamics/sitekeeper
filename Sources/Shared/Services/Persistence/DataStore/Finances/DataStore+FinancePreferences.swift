import Foundation

@MainActor
extension DataStore {
    /// Feature code writes finance preferences through the DataStore façade so
    /// persistence, observation, and future audit behavior stay behind one port.
    func setMaterialPriceSpikeThreshold(_ value: Double) {
        financeStore.setMaterialPriceSpikeThreshold(value)
    }

    func setMaterialPriceSpikeIgnored(_ ignored: Bool, for detailKey: String) {
        financeStore.setMaterialPriceSpikeIgnored(ignored, for: detailKey)
    }
}
