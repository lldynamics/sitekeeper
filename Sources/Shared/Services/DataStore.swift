import Foundation
import Observation

@MainActor
@Observable
final class DataStore {
    @ObservationIgnored let projectStore = ProjectStore()
    @ObservationIgnored let financeStore = FinanceStore()
    @ObservationIgnored let materialLibraryStore = MaterialLibraryStore()
    @ObservationIgnored let userPreferenceStore = UserPreferenceStore()

    enum LoadState { case loading, ready, failed }

    var persistenceErrorMessage: String?
    private(set) var loadState: LoadState = .loading
    var isApplyingBackup = false

    func setLoadState(_ state: LoadState) { loadState = state }

    /// 版本签名：任何数据变化时刷新，观察者可据此判定索引是否已过期
    /// 仅用于“是否变更”判定，主线程自增即可。
    var searchIndexVersion = 0
    var dataVersion = UUID()
    var latestDataHealthScan: DataHealthScanSummary?
    var latestDataHealthSnapshot: DataHealthScanSnapshot?

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
    @ObservationIgnored var dataHealthScanTask: Task<Void, Never>?
    let dataHealthScanDebounceInterval: Duration = .milliseconds(900)
    let dataHealthScheduledScanMaxAge: TimeInterval = 6 * 60 * 60

    init(storageDirectory: URL? = nil) {
        let documentsDirectory = storageDirectory ?? Self.defaultDocumentsDirectory
        storeURL = documentsDirectory.appendingPathComponent("sitekeeper.json")
        persistenceActor = DataStorePersistenceActor(storeURL: storeURL)
        loadAsync()
        publishWidgetData()
    }
}
