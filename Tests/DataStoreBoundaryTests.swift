import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct DataStoreBoundaryTests {
    @Test func financePreferenceWritesUseDataStoreFacade() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("datastore-boundary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DataStore(storageDirectory: directory)
        let previous = store.financeStore.materialPriceSpikeThreshold
        defer { store.setMaterialPriceSpikeThreshold(previous) }

        store.setMaterialPriceSpikeThreshold(0.23)

        #expect(abs(store.financeStore.materialPriceSpikeThreshold - 0.23) < 0.0001)
    }
}
