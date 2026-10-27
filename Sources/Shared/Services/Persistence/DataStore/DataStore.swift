import Foundation
import Observation

@MainActor
@Observable
final class DataStore {
    @ObservationIgnored let projectStore: ProjectStore
    @ObservationIgnored let financeStore: FinanceStore
    @ObservationIgnored let materialLibraryStore: MaterialLibraryStore
    @ObservationIgnored let materialLibraryPreferencesStore: MaterialLibraryPreferencesStore
    @ObservationIgnored private let mutationSink = DomainStoreMutationSink()
    @ObservationIgnored var isApplyingSnapshot = false
    @ObservationIgnored var savingPaymentProjects: Set<UUID> = []

    enum LoadState { case loading, ready, failed }

    var persistenceVersions: [String: UInt64] { mutationSink.versions }

    var legacyDateProvenance: [LegacyDateProvenance] = []
    var persistenceErrorMessage: String?
    private(set) var loadState: LoadState = .loading
    var isApplyingBackup = false {
        didSet { if isApplyingBackup { invalidateDataHealthScan() } }
    }
    var activeBackupExportCount = 0

    func setLoadState(_ state: LoadState) {
        loadState = state
        if state != .ready { invalidateDataHealthScan() }
    }

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
    @ObservationIgnored let dataHealthWorker: DataHealthScanWorker
    @ObservationIgnored var dataHealthLastCompletedAt: Date?
    @ObservationIgnored var dataHealthScanGeneration = UUID()
    @ObservationIgnored var dataHealthSupplementalScanPending = false
    @ObservationIgnored var dataHealthScanTask: Task<DataHealthScanSummary?, Never>?
    let dataHealthScanDebounceInterval: Duration = .milliseconds(900)
    let dataHealthScheduledScanMaxAge: TimeInterval = 6 * 60 * 60

    init(storageDirectory: URL? = nil, dataHealthWorker: DataHealthScanWorker = DataHealthScanWorker()) {
        self.dataHealthWorker = dataHealthWorker
        projectStore = ProjectStore(mutationSink: mutationSink)
        financeStore = FinanceStore(mutationSink: mutationSink)
        materialLibraryStore = MaterialLibraryStore(mutationSink: mutationSink)
        materialLibraryPreferencesStore = MaterialLibraryPreferencesStore(mutationSink: mutationSink)
        let documentsDirectory = storageDirectory ?? Self.defaultDocumentsDirectory
        storeURL = documentsDirectory.appendingPathComponent("sitekeeper.json")
        persistenceActor = DataStorePersistenceActor(storeURL: storeURL)
        mutationSink.owner = self
        loadAsync()
        publishWidgetData()
    }
}

/// All domain data changes enter the same persistence coordinator, including direct
/// child-store writes. The sink is immutable in each store and does not retain its owner.
@MainActor
final class DomainStoreMutationSink {
    weak var owner: DataStore?

    private(set) var versions: [String: UInt64] = [:]

    func didMutate(_ collection: String) {
        versions[collection, default: 0] &+= 1
        guard let owner else { return }
        owner.invalidateDataHealthScan()
        guard owner.loadState == .ready, !owner.isApplyingBackup, !owner.isApplyingSnapshot else { return }
        owner.scheduleSave()
    }
}
