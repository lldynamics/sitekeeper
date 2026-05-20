import Foundation
import Observation

@MainActor
@Observable
final class DataStore {
    @ObservationIgnored let projectStore = ProjectStore()
    @ObservationIgnored let financeStore = FinanceStore()
    @ObservationIgnored let materialLibraryStore = MaterialLibraryStore()
    @ObservationIgnored let userPreferenceStore = UserPreferenceStore()

    var persistenceErrorMessage: String?

    /// 版本签名：任何数据变化时刷新，观察者可据此判定索引是否已过期
    /// 仅用于“是否变更”判定，主线程自增即可。
    var searchIndexVersion = 0
    var dataVersion = UUID()

    let storeURL: URL
    let persistenceActor: DataStorePersistenceActor
    var latestPersistToken = 0
    var persistTask: Task<Void, Never>?
    var initialLoadTask: Task<Void, Never>?
    var needsSaveAfterInitialLoad = false
    var scheduledSaveTask: Task<Void, Never>?
    let autosaveClock = ContinuousClock()
    var autosaveFirstMutationAt: ContinuousClock.Instant?
    var autosaveLastMutationAt: ContinuousClock.Instant?
    let autosaveDebounceInterval: Duration = .milliseconds(500)
    let autosaveMaxLatency: Duration = .seconds(3)

    init(storageDirectory: URL? = nil) {
        let documentsDirectory = storageDirectory ?? Self.defaultDocumentsDirectory
        storeURL = documentsDirectory.appendingPathComponent("sitekeeper.json")
        persistenceActor = DataStorePersistenceActor(storeURL: storeURL)
        loadAsync()
        publishWidgetData()
    }
}
