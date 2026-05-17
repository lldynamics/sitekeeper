import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

struct DataStoreProjectFileCleanupResult: Equatable {
    var photoFileNames: Set<String> = []
    var quickNoteAttachmentFileNames: Set<String> = []
    var projectDocumentFileNames: Set<String> = []
    var drawingFileNames: Set<String> = []

    var totalFileCount: Int {
        photoFileNames.count
            + quickNoteAttachmentFileNames.count
            + projectDocumentFileNames.count
            + drawingFileNames.count
    }
}

@MainActor
@Observable
final class DataStore {
    @ObservationIgnored let projectStore = ProjectStore()
    @ObservationIgnored let financeStore = FinanceStore()
    @ObservationIgnored let materialLibraryStore = MaterialLibraryStore()
    @ObservationIgnored let userPreferenceStore = UserPreferenceStore()

    private func proxiedRead<Value>(
        _ keyPath: KeyPath<DataStore, Value>,
        _ value: @autoclosure () -> Value
    ) -> Value {
        access(keyPath: keyPath)
        return value()
    }

    private func proxiedWrite<Value>(
        _ keyPath: WritableKeyPath<DataStore, Value>,
        _ mutation: () -> Void
    ) {
        withMutation(keyPath: keyPath, mutation)
    }

    // 清单
    private(set) var materialItems: [MaterialItem] {
        get { proxiedRead(\.materialItems, financeStore.materialItems) }
        set { proxiedWrite(\.materialItems) { financeStore.setMaterialItems(newValue) } }
    }
    private(set) var quoteItems: [QuoteItem] {
        get { proxiedRead(\.quoteItems, financeStore.quoteItems) }
        set { proxiedWrite(\.quoteItems) { financeStore.setQuoteItems(newValue) } }
    }
    private(set) var laborRecords: [LaborRecord] {
        get { proxiedRead(\.laborRecords, financeStore.laborRecords) }
        set { proxiedWrite(\.laborRecords) { financeStore.setLaborRecords(newValue) } }
    }
    // 项目
    private(set) var projects: [Project] {
        get { proxiedRead(\.projects, projectStore.projects) }
        set { proxiedWrite(\.projects) { projectStore.setProjects(newValue) } }
    }
    private(set) var dailyLogs: [DailyLog] {
        get { proxiedRead(\.dailyLogs, projectStore.dailyLogs) }
        set { proxiedWrite(\.dailyLogs) { projectStore.setDailyLogs(newValue) } }
    }
    private(set) var historyRecords: [HistoryRecord] {
        get { proxiedRead(\.historyRecords, projectStore.historyRecords) }
        set {
            proxiedWrite(\.historyRecords) {
                projectStore.setHistoryRecords(applyingHistoryRetention(to: newValue))
            }
        }
    }
    private(set) var progressTasks: [ProgressTask] {
        get { proxiedRead(\.progressTasks, projectStore.progressTasks) }
        set { proxiedWrite(\.progressTasks) { projectStore.setProgressTasks(newValue) } }
    }
    private(set) var lightingCircuitPlans: [LightingCircuitPlan] {
        get { proxiedRead(\.lightingCircuitPlans, projectStore.lightingCircuitPlans) }
        set { proxiedWrite(\.lightingCircuitPlans) { projectStore.setLightingCircuitPlans(newValue) } }
    }
    private(set) var siteTodos: [SiteTodo] {
        get { proxiedRead(\.siteTodos, projectStore.siteTodos) }
        set { proxiedWrite(\.siteTodos) { projectStore.setSiteTodos(newValue) } }
    }
    private(set) var projectDrawings: [ProjectDrawing] {
        get { proxiedRead(\.projectDrawings, projectStore.projectDrawings) }
        set { proxiedWrite(\.projectDrawings) { projectStore.setProjectDrawings(newValue) } }
    }
    private(set) var projectContacts: [ProjectContact] {
        get { proxiedRead(\.projectContacts, projectStore.projectContacts) }
        set { proxiedWrite(\.projectContacts) { projectStore.setProjectContacts(newValue) } }
    }
    private(set) var projectFinancialRecords: [ProjectFinancialRecord] {
        get { proxiedRead(\.projectFinancialRecords, projectStore.projectFinancialRecords) }
        set { proxiedWrite(\.projectFinancialRecords) { projectStore.setProjectFinancialRecords(newValue) } }
    }
    private(set) var projectDocuments: [ProjectDocument] {
        get { proxiedRead(\.projectDocuments, projectStore.projectDocuments) }
        set { proxiedWrite(\.projectDocuments) { projectStore.setProjectDocuments(newValue) } }
    }
    private(set) var quickNotes: [QuickNote] {
        get { proxiedRead(\.quickNotes, projectStore.quickNotes) }
        set { proxiedWrite(\.quickNotes) { projectStore.setQuickNotes(newValue) } }
    }
    private(set) var projectWarehouseMovements: [ProjectWarehouseMovement] {
        get { proxiedRead(\.projectWarehouseMovements, projectStore.projectWarehouseMovements) }
        set { proxiedWrite(\.projectWarehouseMovements) { projectStore.setProjectWarehouseMovements(newValue) } }
    }

    // 模板 / 材料库
    private(set) var templates: [ProjectTemplate] {
        get { proxiedRead(\.templates, materialLibraryStore.templates) }
        set { proxiedWrite(\.templates) { materialLibraryStore.setTemplates(newValue) } }
    }
    private(set) var materialPriceEntries: [MaterialPriceEntry] {
        get { proxiedRead(\.materialPriceEntries, materialLibraryStore.materialPriceEntries) }
        set { proxiedWrite(\.materialPriceEntries) { materialLibraryStore.setMaterialPriceEntries(newValue) } }
    }
    private(set) var materialSheetDrafts: [MaterialSheetDraft] {
        get { proxiedRead(\.materialSheetDrafts, materialLibraryStore.materialSheetDrafts) }
        set { proxiedWrite(\.materialSheetDrafts) { materialLibraryStore.setMaterialSheetDrafts(newValue) } }
    }
    private(set) var supplierProfiles: [SupplierProfile] {
        get { proxiedRead(\.supplierProfiles, materialLibraryStore.supplierProfiles) }
        set { proxiedWrite(\.supplierProfiles) { materialLibraryStore.setSupplierProfiles(newValue) } }
    }
    private(set) var constructionMethods: [ConstructionMethod] {
        get { proxiedRead(\.constructionMethods, materialLibraryStore.constructionMethods) }
        set { proxiedWrite(\.constructionMethods) { materialLibraryStore.setConstructionMethods(newValue) } }
    }
    private(set) var userMaterials: [UserMaterial] {
        get { proxiedRead(\.userMaterials, materialLibraryStore.userMaterials) }
        set { proxiedWrite(\.userMaterials) { materialLibraryStore.setUserMaterials(newValue) } }
    }
    private(set) var deletedUserMaterials: [UserMaterial] {
        get { proxiedRead(\.deletedUserMaterials, materialLibraryStore.deletedUserMaterials) }
        set { proxiedWrite(\.deletedUserMaterials) { materialLibraryStore.setDeletedUserMaterials(newValue) } }
    }

    // 用户偏好
    var favoriteMaterialKeys: [String] {
        get { proxiedRead(\.favoriteMaterialKeys, userPreferenceStore.favoriteMaterialKeys) }
        set { proxiedWrite(\.favoriteMaterialKeys) { userPreferenceStore.setFavoriteMaterialKeys(newValue) } }
    }
    var recentMaterialKeys: [String] {
        get { proxiedRead(\.recentMaterialKeys, userPreferenceStore.recentMaterialKeys) }
        set { proxiedWrite(\.recentMaterialKeys) { userPreferenceStore.setRecentMaterialKeys(newValue) } }
    }
    var hiddenPresetKeys: Set<String> {
        get { proxiedRead(\.hiddenPresetKeys, userPreferenceStore.hiddenPresetKeys) }
        set { proxiedWrite(\.hiddenPresetKeys) { userPreferenceStore.setHiddenPresetKeys(newValue) } }
    }
    var persistenceErrorMessage: String?

    /// 版本签名：任何数据变化时刷新，观察者可据此判定索引是否已过期
    /// 仅用于“是否变更”判定，主线程自增即可。
    var searchIndexVersion = 0
    var dataVersion = UUID()

    private let primaryStoreURL: URL
    private let legacyStoreURL: URL
    private let storeURL: URL
    private let persistenceActor: DataStorePersistenceActor
    private var latestPersistToken = 0
    private var persistTask: Task<Void, Never>?
    private var initialLoadTask: Task<Void, Never>?
    private var needsSaveAfterInitialLoad = false
    private var scheduledSaveTask: Task<Void, Never>?
    private let autosaveClock = ContinuousClock()
    private var autosaveFirstMutationAt: ContinuousClock.Instant?
    private var autosaveLastMutationAt: ContinuousClock.Instant?
    private let autosaveDebounceInterval: Duration = .milliseconds(500)
    private let autosaveMaxLatency: Duration = .seconds(3)
    private let historyRecordMaxTotalCount = 200
    private let historyRecordMaxCountPerTool = 50

    private static func recordIssue(
        _ event: String,
        details: [String: String] = [:],
        error: Error? = nil
    ) {
        StorageIssueLog.recordEvent(
            event,
            category: .dataStore,
            details: details,
            error: error
        )
    }

    private static var defaultDocumentsDirectory: URL {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return dir
        }
        recordIssue(
            "datastore.documents_directory_unavailable",
            details: ["fallback": "temporary-directory"]
        )
        return FileManager.default.temporaryDirectory
    }

    private static func resolveLoadURL(primaryStoreURL: URL, legacyStoreURL: URL) -> URL? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: primaryStoreURL.path) {
            return primaryStoreURL
        }
        if fileManager.fileExists(atPath: legacyStoreURL.path) {
            return legacyStoreURL
        }
        return nil
    }

    init(storageDirectory: URL? = nil) {
        let documentsDirectory = storageDirectory ?? Self.defaultDocumentsDirectory
        primaryStoreURL = documentsDirectory.appendingPathComponent("sitekeeper.json")
        legacyStoreURL = documentsDirectory.appendingPathComponent("construction_toolbox.json")
        storeURL = primaryStoreURL
        persistenceActor = DataStorePersistenceActor(storeURL: storeURL)
        loadAsync()
        publishWidgetData()
    }

    private func loadAsync() {
        initialLoadTask?.cancel()
        let primaryStoreURL = self.primaryStoreURL
        let legacyStoreURL = self.legacyStoreURL
        let storeURL = self.storeURL
        let persistenceActor = self.persistenceActor
        initialLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard let snapshot = try await persistenceActor.loadSnapshot(primaryStoreURL: primaryStoreURL, legacyStoreURL: legacyStoreURL) else {
                    initialLoadTask = nil
                    flushDeferredSaveIfNeededAfterInitialLoad()
                    return
                }
                guard !Task.isCancelled else { return }
                applyLoadedSnapshot(snapshot)
                initialLoadTask = nil
                flushDeferredSaveIfNeededAfterInitialLoad()
            } catch let decodeError as DataStorePersistenceActor.LoadDecodeError {
                guard !Task.isCancelled else { return }
                let backupName = "sitekeeper_corrupt_\(Formatters.now().replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: " ", with: "_")).json"
                let backupURL = storeURL.deletingLastPathComponent().appendingPathComponent(backupName)
                do {
                    try decodeError.rawData.write(to: backupURL, options: .atomic)
                } catch {
                    Self.recordIssue(
                        "datastore.corrupt_backup_write_failed",
                        details: ["file": backupName],
                        error: error
                    )
                }
                persistenceErrorMessage = String(
                    format: String(localized: "本地数据解析失败，已保留异常文件：%@。可从备份页重新导入最近备份。"),
                    backupName
                )
                initialLoadTask = nil
                flushDeferredSaveIfNeededAfterInitialLoad()
            } catch {
                guard !Task.isCancelled else { return }
                persistenceErrorMessage = String(
                    format: String(localized: "读取本地数据失败：%@"),
                    error.localizedDescription
                )
                initialLoadTask = nil
                flushDeferredSaveIfNeededAfterInitialLoad()
            }
        }
    }

    private func applyLoadedSnapshot(_ snapshot: BackupSnapshot) {
        let migratedLegacyRecords = Self.migrateLegacyPaymentRecords(
            snapshot.legacyPaymentRecords,
            projects: snapshot.projects
        )
        materialItems = snapshot.materialItems
        quoteItems = snapshot.quoteItems
        laborRecords = snapshot.laborRecords
        projects = snapshot.projects
        dailyLogs = snapshot.dailyLogs
        historyRecords = snapshot.historyRecords
        progressTasks = snapshot.progressTasks
        lightingCircuitPlans = snapshot.lightingCircuitPlans
        siteTodos = snapshot.siteTodos
        projectDrawings = snapshot.projectDrawings
        projectContacts = snapshot.projectContacts
        projectFinancialRecords = Self.mergeFinancialRecords(
            existing: snapshot.projectFinancialRecords,
            incoming: migratedLegacyRecords
        )
        projectDocuments = snapshot.projectDocuments
        quickNotes = snapshot.quickNotes
        projectWarehouseMovements = snapshot.projectWarehouseMovements
        templates = snapshot.templates
        materialPriceEntries = snapshot.materialPriceEntries
        materialSheetDrafts = snapshot.materialSheetDrafts
        supplierProfiles = snapshot.supplierProfiles
        constructionMethods = snapshot.constructionMethods
        favoriteMaterialKeys = snapshot.favoriteMaterialKeys
        recentMaterialKeys = snapshot.recentMaterialKeys
        userMaterials = snapshot.userMaterials
        deletedUserMaterials = snapshot.deletedUserMaterials
        hiddenPresetKeys = snapshot.hiddenPresetKeys
        if !snapshot.legacyPaymentRecords.isEmpty {
            Self.recordIssue(
                "datastore.legacy_payment_records_migrated",
                details: [
                    "recordCount": String(snapshot.legacyPaymentRecords.count),
                    "target": "project_financial_records"
                ]
            )
            needsSaveAfterInitialLoad = true
        }
        refreshSearchIndexVersion()
        dataVersion = UUID()
        publishWidgetData()
    }

    func makeSnapshot(includePhotoFiles: Bool) -> BackupSnapshot {
        BackupSnapshot(
            materialItems: materialItems,
            quoteItems: quoteItems,
            laborRecords: laborRecords,
            projects: projects,
            dailyLogs: dailyLogs,
            historyRecords: historyRecords,
            progressTasks: progressTasks,
            lightingCircuitPlans: lightingCircuitPlans,
            siteTodos: siteTodos,
            projectDrawings: projectDrawings,
            projectContacts: projectContacts,
            projectFinancialRecords: projectFinancialRecords,
            projectDocuments: projectDocuments,
            quickNotes: quickNotes,
            projectWarehouseMovements: projectWarehouseMovements,
            templates: templates,
            materialPriceEntries: materialPriceEntries,
            materialSheetDrafts: materialSheetDrafts,
            supplierProfiles: supplierProfiles,
            constructionMethods: constructionMethods,
            favoriteMaterialKeys: favoriteMaterialKeys,
            recentMaterialKeys: recentMaterialKeys,
            userMaterials: userMaterials,
            deletedUserMaterials: deletedUserMaterials,
            hiddenPresetKeys: hiddenPresetKeys,
            photoFiles: includePhotoFiles ? (PhotoStorage.backupFiles(for: dailyLogs) + PhotoStorage.backupFiles(for: siteTodos)) : [],
            drawingFiles: includePhotoFiles ? DrawingStorage.backupFiles(for: projectDrawings) : [],
            documentFiles: includePhotoFiles ? ProjectDocumentStorage.backupFiles(for: projectDocuments) : [],
            quickNoteAttachmentFiles: includePhotoFiles
                ? QuickNoteAttachmentStorage.backupFiles(
                    for: quickNotes,
                    extraAttachments: constructionMethods.flatMap(\.attachments) + constructionMethods.flatMap(\.tutorialAttachments)
                )
                : []
        )
    }

    func flushSave() async {
        cancelScheduledSave()
        persistTask?.cancel()
        await awaitInitialLoad()
        let snapshot = makeSnapshot(includePhotoFiles: false)
        do {
            try await persistenceActor.persist(snapshot: snapshot)
        } catch {
            persistenceErrorMessage = String(
                format: String(localized: "保存本地数据失败：%@"),
                error.localizedDescription
            )
        }
        publishWidgetData()
    }

    func save(includePhotoFiles: Bool = false) {
        if let initialLoadTask, !initialLoadTask.isCancelled {
            needsSaveAfterInitialLoad = true
            return
        }
        let snapshot = makeSnapshot(includePhotoFiles: includePhotoFiles)
        latestPersistToken += 1
        let persistToken = latestPersistToken
        let persistenceActor = self.persistenceActor

        persistTask?.cancel()
        persistTask = Task(priority: .utility) {
            do {
                try await persistenceActor.persist(snapshot: snapshot)
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self,
                          persistToken == self.latestPersistToken else { return }
                    self.persistenceErrorMessage = String(
                        format: String(localized: "保存本地数据失败：%@"),
                        error.localizedDescription
                    )
                }
            }
        }
        publishWidgetData()
    }

    func scheduleSave() {
        refreshSearchIndexVersion()
        dataVersion = UUID()
        guard UserPreferences.bool(UserPreferenceKeys.autoSave, default: true) else { return }
        let now = autosaveClock.now
        autosaveLastMutationAt = now
        if autosaveFirstMutationAt == nil {
            autosaveFirstMutationAt = now
        }
        guard scheduledSaveTask == nil else { return }
        scheduledSaveTask = Task { [weak self] in
            await self?.runScheduledSaveLoop()
        }
    }

    func awaitInitialLoad() async {
        await initialLoadTask?.value
    }

    private func flushDeferredSaveIfNeededAfterInitialLoad() {
        guard needsSaveAfterInitialLoad else { return }
        needsSaveAfterInitialLoad = false
        save(includePhotoFiles: false)
    }

    private func runScheduledSaveLoop() async {
        defer { scheduledSaveTask = nil }
        let minimumPollInterval: Duration = .milliseconds(120)
        while !Task.isCancelled {
            guard let firstMutationAt = autosaveFirstMutationAt,
                  let lastMutationAt = autosaveLastMutationAt else {
                return
            }
            let now = autosaveClock.now
            let idleElapsed = now - lastMutationAt
            let totalElapsed = now - firstMutationAt
            if idleElapsed >= autosaveDebounceInterval || totalElapsed >= autosaveMaxLatency {
                break
            }

            let idleRemaining = autosaveDebounceInterval - idleElapsed
            let maxRemaining = autosaveMaxLatency - totalElapsed
            var sleepDuration = idleRemaining < maxRemaining ? idleRemaining : maxRemaining
            if sleepDuration < minimumPollInterval {
                sleepDuration = minimumPollInterval
            }
            do {
                try await Task.sleep(for: sleepDuration)
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }
        let hadPendingChanges = autosaveLastMutationAt != nil
        autosaveFirstMutationAt = nil
        autosaveLastMutationAt = nil
        guard hadPendingChanges else { return }
        save(includePhotoFiles: false)
    }

    private func cancelScheduledSave() {
        scheduledSaveTask?.cancel()
        scheduledSaveTask = nil
        autosaveFirstMutationAt = nil
        autosaveLastMutationAt = nil
    }

    var hasAnyBusinessData: Bool {
        !materialItems.isEmpty ||
        !quoteItems.isEmpty ||
        !laborRecords.isEmpty ||
        !projects.isEmpty ||
        !dailyLogs.isEmpty ||
        !historyRecords.isEmpty ||
        !progressTasks.isEmpty ||
        !lightingCircuitPlans.isEmpty ||
        !siteTodos.isEmpty ||
        !projectDrawings.isEmpty ||
        !projectContacts.isEmpty ||
        !projectFinancialRecords.isEmpty ||
        !projectDocuments.isEmpty ||
        !quickNotes.isEmpty ||
        !projectWarehouseMovements.isEmpty ||
        !templates.isEmpty ||
        !materialPriceEntries.isEmpty ||
        !materialSheetDrafts.isEmpty ||
        !supplierProfiles.isEmpty ||
        !constructionMethods.isEmpty ||
        !userMaterials.isEmpty ||
        !deletedUserMaterials.isEmpty
    }

    var historyRetentionTotalLimit: Int {
        historyRecordMaxTotalCount
    }

    var historyRetentionPerToolLimit: Int {
        historyRecordMaxCountPerTool
    }

    // MARK: - Explicit write APIs

    private func appendElement<Element>(
        _ element: Element,
        to keyPath: ReferenceWritableKeyPath<DataStore, [Element]>
    ) {
        var values = self[keyPath: keyPath]
        values.append(element)
        self[keyPath: keyPath] = values
    }

    private func appendElements<Element>(
        _ elements: [Element],
        to keyPath: ReferenceWritableKeyPath<DataStore, [Element]>
    ) {
        guard !elements.isEmpty else { return }
        var values = self[keyPath: keyPath]
        values.append(contentsOf: elements)
        self[keyPath: keyPath] = values
    }

    private func insertElement<Element>(
        _ element: Element,
        at index: Int,
        to keyPath: ReferenceWritableKeyPath<DataStore, [Element]>
    ) {
        var values = self[keyPath: keyPath]
        let boundedIndex = min(max(index, 0), values.count)
        values.insert(element, at: boundedIndex)
        self[keyPath: keyPath] = values
    }

    private func mergeUniqueElementsByID<Element: Identifiable>(
        _ incoming: [Element],
        into keyPath: ReferenceWritableKeyPath<DataStore, [Element]>
    ) where Element.ID: Hashable {
        guard !incoming.isEmpty else { return }
        var current = self[keyPath: keyPath]
        var existingIDs = Set(current.map(\.id))
        for item in incoming where existingIDs.insert(item.id).inserted {
            current.append(item)
        }
        self[keyPath: keyPath] = current
    }

    @discardableResult
    private func removeElements<Element>(
        from keyPath: ReferenceWritableKeyPath<DataStore, [Element]>,
        where shouldRemove: (Element) -> Bool,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<Element> {
        let snapshot = self[keyPath: keyPath]
        let removed = snapshot.filter(shouldRemove)
        guard !removed.isEmpty else {
            return DataStoreRemovalResult(
                snapshot: snapshot,
                removed: [],
                audit: audit,
                deferredFileCleanup: deferredFileCleanup
            )
        }

        var values = snapshot
        values.removeAll(where: shouldRemove)
        self[keyPath: keyPath] = values

        let result = DataStoreRemovalResult(
            snapshot: snapshot,
            removed: removed,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup
        )
        if recordsAuditImmediately {
            result.recordAuditStarted()
            result.performDeferredFileCleanup()
            result.recordAuditSucceeded()
        }
        return result
    }

    @discardableResult
    private func removeElements<Element, ID: Hashable>(
        from keyPath: ReferenceWritableKeyPath<DataStore, [Element]>,
        ids: Set<ID>,
        id: (Element) -> ID,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<Element> {
        guard !ids.isEmpty else {
            return DataStoreRemovalResult(
                snapshot: self[keyPath: keyPath],
                removed: [],
                audit: audit,
                deferredFileCleanup: deferredFileCleanup
            )
        }
        return removeElements(
            from: keyPath,
            where: { ids.contains(id($0)) },
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendMaterialItem(_ item: MaterialItem) {
        appendElement(item, to: \.materialItems)
    }

    @discardableResult
    func updateMaterialItem(_ item: MaterialItem) -> Bool {
        var current = materialItems
        guard let index = current.firstIndex(where: { $0.id == item.id }) else { return false }
        current[index] = item
        materialItems = current
        return true
    }

    func replaceMaterialItems(_ items: [MaterialItem]) {
        materialItems = items
    }

    func mergeMaterialItemsByID(_ items: [MaterialItem]) {
        mergeUniqueElementsByID(items, into: \.materialItems)
    }

    func restoreMaterialItems(from deletion: DataStoreRemovalResult<MaterialItem>) {
        materialItems = deletion.restoredItems(current: materialItems, id: \.id)
    }

    @discardableResult
    func removeMaterialItems(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<MaterialItem> {
        removeElements(
            from: \.materialItems,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendQuoteItem(_ item: QuoteItem) {
        appendElement(item, to: \.quoteItems)
    }

    @discardableResult
    func updateQuoteItem(_ item: QuoteItem) -> Bool {
        var current = quoteItems
        guard let index = current.firstIndex(where: { $0.id == item.id }) else { return false }
        current[index] = item
        quoteItems = current
        return true
    }

    func replaceQuoteItems(_ items: [QuoteItem]) {
        quoteItems = items
    }

    func mergeQuoteItemsByID(_ items: [QuoteItem]) {
        mergeUniqueElementsByID(items, into: \.quoteItems)
    }

    func restoreQuoteItems(from deletion: DataStoreRemovalResult<QuoteItem>) {
        quoteItems = deletion.restoredItems(current: quoteItems, id: \.id)
    }

    @discardableResult
    func removeQuoteItems(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<QuoteItem> {
        removeElements(
            from: \.quoteItems,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendLaborRecord(_ record: LaborRecord) {
        appendElement(record, to: \.laborRecords)
    }

    @discardableResult
    func updateLaborRecord(_ record: LaborRecord) -> Bool {
        var current = laborRecords
        guard let index = current.firstIndex(where: { $0.id == record.id }) else { return false }
        current[index] = record
        laborRecords = current
        return true
    }

    func replaceLaborRecords(_ records: [LaborRecord]) {
        laborRecords = records
    }

    func mergeLaborRecordsByID(_ records: [LaborRecord]) {
        mergeUniqueElementsByID(records, into: \.laborRecords)
    }

    func restoreLaborRecords(from deletion: DataStoreRemovalResult<LaborRecord>) {
        laborRecords = deletion.restoredItems(current: laborRecords, id: \.id)
    }

    @discardableResult
    func removeLaborRecords(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<LaborRecord> {
        removeElements(
            from: \.laborRecords,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendProject(_ project: Project) {
        appendElement(project, to: \.projects)
    }

    @discardableResult
    func updateProject(_ project: Project) -> Bool {
        var current = projects
        guard let index = current.firstIndex(where: { $0.id == project.id }) else { return false }
        current[index] = project
        projects = current
        return true
    }

    func replaceProjects(_ values: [Project]) {
        projects = values
    }

    func mergeProjectsByID(_ values: [Project]) {
        mergeUniqueElementsByID(values, into: \.projects)
    }

    func appendDailyLog(_ log: DailyLog) {
        appendElement(log, to: \.dailyLogs)
    }

    func insertDailyLogAtTop(_ log: DailyLog) {
        insertElement(log, at: 0, to: \.dailyLogs)
    }

    @discardableResult
    func updateDailyLog(_ log: DailyLog) -> Bool {
        var current = dailyLogs
        guard let index = current.firstIndex(where: { $0.id == log.id }) else { return false }
        current[index] = log
        dailyLogs = current
        return true
    }

    func replaceDailyLogs(_ logs: [DailyLog]) {
        dailyLogs = logs
    }

    func mergeDailyLogsByID(_ logs: [DailyLog]) {
        mergeUniqueElementsByID(logs, into: \.dailyLogs)
    }

    func restoreDailyLogs(from deletion: DataStoreRemovalResult<DailyLog>) {
        dailyLogs = deletion.restoredItems(current: dailyLogs, id: \.id)
    }

    @discardableResult
    func removeDailyLogs(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<DailyLog> {
        removeElements(
            from: \.dailyLogs,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendProgressTask(_ task: ProgressTask) {
        appendElement(task, to: \.progressTasks)
    }

    @discardableResult
    func updateProgressTask(_ task: ProgressTask) -> Bool {
        var current = progressTasks
        guard let index = current.firstIndex(where: { $0.id == task.id }) else { return false }
        current[index] = task
        progressTasks = current
        return true
    }

    func replaceProgressTasks(_ tasks: [ProgressTask]) {
        progressTasks = tasks
    }

    func mergeProgressTasksByID(_ tasks: [ProgressTask]) {
        mergeUniqueElementsByID(tasks, into: \.progressTasks)
    }

    func restoreProgressTasks(from deletion: DataStoreRemovalResult<ProgressTask>) {
        progressTasks = deletion.restoredItems(current: progressTasks, id: \.id)
    }

    @discardableResult
    func removeProgressTasks(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProgressTask> {
        removeElements(
            from: \.progressTasks,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func insertLightingCircuitPlanAtTop(_ plan: LightingCircuitPlan) {
        insertElement(plan, at: 0, to: \.lightingCircuitPlans)
    }

    @discardableResult
    func updateLightingCircuitPlan(_ plan: LightingCircuitPlan) -> Bool {
        var current = lightingCircuitPlans
        guard let index = current.firstIndex(where: { $0.id == plan.id }) else { return false }
        current[index] = plan
        lightingCircuitPlans = current
        return true
    }

    func replaceLightingCircuitPlans(_ plans: [LightingCircuitPlan]) {
        lightingCircuitPlans = plans
    }

    func mergeLightingCircuitPlansByID(_ plans: [LightingCircuitPlan]) {
        mergeUniqueElementsByID(plans, into: \.lightingCircuitPlans)
    }

    func restoreLightingCircuitPlans(from deletion: DataStoreRemovalResult<LightingCircuitPlan>) {
        lightingCircuitPlans = deletion.restoredItems(current: lightingCircuitPlans, id: \.id)
    }

    @discardableResult
    func removeLightingCircuitPlans(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<LightingCircuitPlan> {
        removeElements(
            from: \.lightingCircuitPlans,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendSiteTodo(_ todo: SiteTodo) {
        appendElement(todo, to: \.siteTodos)
    }

    func insertSiteTodoAtTop(_ todo: SiteTodo) {
        insertElement(todo, at: 0, to: \.siteTodos)
    }

    @discardableResult
    func updateSiteTodo(_ todo: SiteTodo) -> Bool {
        var current = siteTodos
        guard let index = current.firstIndex(where: { $0.id == todo.id }) else { return false }
        current[index] = todo
        siteTodos = current
        return true
    }

    func replaceSiteTodos(_ todos: [SiteTodo]) {
        siteTodos = todos
    }

    func mergeSiteTodosByID(_ todos: [SiteTodo]) {
        mergeUniqueElementsByID(todos, into: \.siteTodos)
    }

    func restoreSiteTodos(from deletion: DataStoreRemovalResult<SiteTodo>) {
        siteTodos = deletion.restoredItems(current: siteTodos, id: \.id)
    }

    @discardableResult
    func removeSiteTodos(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<SiteTodo> {
        removeElements(
            from: \.siteTodos,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendProjectDrawing(_ drawing: ProjectDrawing) {
        appendElement(drawing, to: \.projectDrawings)
    }

    func appendProjectDrawings(_ drawings: [ProjectDrawing]) {
        appendElements(drawings, to: \.projectDrawings)
    }

    @discardableResult
    func updateProjectDrawing(_ drawing: ProjectDrawing) -> Bool {
        var current = projectDrawings
        guard let index = current.firstIndex(where: { $0.id == drawing.id }) else { return false }
        current[index] = drawing
        projectDrawings = current
        return true
    }

    @discardableResult
    func mutateProjectDrawing(
        id: UUID,
        _ mutation: (inout ProjectDrawing) -> Void
    ) -> Bool {
        var current = projectDrawings
        guard let index = current.firstIndex(where: { $0.id == id }) else { return false }
        mutation(&current[index])
        projectDrawings = current
        return true
    }

    func replaceProjectDrawings(_ drawings: [ProjectDrawing]) {
        projectDrawings = drawings
    }

    func mergeProjectDrawingsByID(_ drawings: [ProjectDrawing]) {
        mergeUniqueElementsByID(drawings, into: \.projectDrawings)
    }

    func restoreProjectDrawings(from deletion: DataStoreRemovalResult<ProjectDrawing>) {
        projectDrawings = deletion.restoredItems(current: projectDrawings, id: \.id)
    }

    @discardableResult
    func removeProjectDrawings(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectDrawing> {
        removeElements(
            from: \.projectDrawings,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    func removeProjectDrawings(
        where shouldRemove: (ProjectDrawing) -> Bool,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectDrawing> {
        removeElements(
            from: \.projectDrawings,
            where: shouldRemove,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendProjectContact(_ contact: ProjectContact) {
        appendElement(contact, to: \.projectContacts)
    }

    func insertProjectContactAtTop(_ contact: ProjectContact) {
        insertElement(contact, at: 0, to: \.projectContacts)
    }

    func mergeProjectContactsByID(_ contacts: [ProjectContact]) {
        mergeUniqueElementsByID(contacts, into: \.projectContacts)
    }

    func replaceProjectContacts(_ contacts: [ProjectContact]) {
        projectContacts = contacts
    }

    func upsertProjectContact(
        _ contact: ProjectContact,
        insertAtTopWhenNew: Bool = false
    ) {
        var currentContacts = projectContacts
        if let index = currentContacts.firstIndex(where: { $0.id == contact.id }) {
            currentContacts[index] = contact
            projectContacts = currentContacts
            return
        }
        if insertAtTopWhenNew {
            currentContacts.insert(contact, at: 0)
        } else {
            currentContacts.append(contact)
        }
        projectContacts = currentContacts
    }

    func restoreProjectContacts(from deletion: DataStoreRemovalResult<ProjectContact>) {
        projectContacts = deletion.restoredItems(current: projectContacts, id: \.id)
    }

    @discardableResult
    func removeProjectContact(
        id: UUID,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectContact> {
        removeElements(
            from: \.projectContacts,
            ids: Set([id]),
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    func removeProjectContacts(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectContact> {
        removeElements(
            from: \.projectContacts,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendProjectFinancialRecord(_ record: ProjectFinancialRecord) {
        appendElement(record, to: \.projectFinancialRecords)
    }

    func appendProjectFinancialRecords(_ records: [ProjectFinancialRecord]) {
        appendElements(records, to: \.projectFinancialRecords)
    }

    @discardableResult
    func updateProjectFinancialRecord(_ record: ProjectFinancialRecord) -> Bool {
        var current = projectFinancialRecords
        guard let index = current.firstIndex(where: { $0.id == record.id }) else { return false }
        current[index] = record
        projectFinancialRecords = current
        return true
    }

    @discardableResult
    func mutateProjectFinancialRecord(
        id: UUID,
        _ mutation: (inout ProjectFinancialRecord) -> Void
    ) -> Bool {
        var current = projectFinancialRecords
        guard let index = current.firstIndex(where: { $0.id == id }) else { return false }
        mutation(&current[index])
        projectFinancialRecords = current
        return true
    }

    func replaceProjectFinancialRecords(_ records: [ProjectFinancialRecord]) {
        projectFinancialRecords = records
    }

    func mergeProjectFinancialRecordsByID(_ records: [ProjectFinancialRecord]) {
        mergeUniqueElementsByID(records, into: \.projectFinancialRecords)
    }

    func restoreProjectFinancialRecords(from deletion: DataStoreRemovalResult<ProjectFinancialRecord>) {
        projectFinancialRecords = deletion.restoredItems(current: projectFinancialRecords, id: \.id)
    }

    @discardableResult
    func removeProjectFinancialRecords(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectFinancialRecord> {
        removeElements(
            from: \.projectFinancialRecords,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendProjectDocument(_ document: ProjectDocument) {
        appendElement(document, to: \.projectDocuments)
    }

    func appendProjectDocuments(_ documents: [ProjectDocument]) {
        appendElements(documents, to: \.projectDocuments)
    }

    @discardableResult
    func updateProjectDocument(_ document: ProjectDocument) -> Bool {
        var current = projectDocuments
        guard let index = current.firstIndex(where: { $0.id == document.id }) else { return false }
        current[index] = document
        projectDocuments = current
        return true
    }

    @discardableResult
    func mutateProjectDocument(
        id: UUID,
        _ mutation: (inout ProjectDocument) -> Void
    ) -> Bool {
        var current = projectDocuments
        guard let index = current.firstIndex(where: { $0.id == id }) else { return false }
        mutation(&current[index])
        projectDocuments = current
        return true
    }

    func replaceProjectDocuments(_ documents: [ProjectDocument]) {
        projectDocuments = documents
    }

    func mergeProjectDocumentsByID(_ documents: [ProjectDocument]) {
        mergeUniqueElementsByID(documents, into: \.projectDocuments)
    }

    func restoreProjectDocuments(from deletion: DataStoreRemovalResult<ProjectDocument>) {
        projectDocuments = deletion.restoredItems(current: projectDocuments, id: \.id)
    }

    @discardableResult
    func removeProjectDocuments(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectDocument> {
        removeElements(
            from: \.projectDocuments,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendQuickNote(_ note: QuickNote) {
        appendElement(note, to: \.quickNotes)
    }

    func insertQuickNoteAtTop(_ note: QuickNote) {
        insertElement(note, at: 0, to: \.quickNotes)
    }

    @discardableResult
    func updateQuickNote(_ note: QuickNote) -> Bool {
        var current = quickNotes
        guard let index = current.firstIndex(where: { $0.id == note.id }) else { return false }
        current[index] = note
        quickNotes = current
        return true
    }

    @discardableResult
    func mutateQuickNote(
        id: UUID,
        _ mutation: (inout QuickNote) -> Void
    ) -> Bool {
        var current = quickNotes
        guard let index = current.firstIndex(where: { $0.id == id }) else { return false }
        mutation(&current[index])
        quickNotes = current
        return true
    }

    func replaceQuickNotes(_ notes: [QuickNote]) {
        quickNotes = notes
    }

    func mergeQuickNotesByID(_ notes: [QuickNote]) {
        mergeUniqueElementsByID(notes, into: \.quickNotes)
    }

    func restoreQuickNotes(from deletion: DataStoreRemovalResult<QuickNote>) {
        quickNotes = deletion.restoredItems(current: quickNotes, id: \.id)
    }

    @discardableResult
    func removeQuickNotes(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<QuickNote> {
        removeElements(
            from: \.quickNotes,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendProjectWarehouseMovement(_ movement: ProjectWarehouseMovement) {
        appendElement(movement, to: \.projectWarehouseMovements)
    }

    func insertProjectWarehouseMovementAtTop(_ movement: ProjectWarehouseMovement) {
        insertElement(movement, at: 0, to: \.projectWarehouseMovements)
    }

    @discardableResult
    func updateProjectWarehouseMovement(_ movement: ProjectWarehouseMovement) -> Bool {
        var current = projectWarehouseMovements
        guard let index = current.firstIndex(where: { $0.id == movement.id }) else { return false }
        current[index] = movement
        projectWarehouseMovements = current
        return true
    }

    @discardableResult
    func mutateProjectWarehouseMovement(
        id: UUID,
        _ mutation: (inout ProjectWarehouseMovement) -> Void
    ) -> Bool {
        var current = projectWarehouseMovements
        guard let index = current.firstIndex(where: { $0.id == id }) else { return false }
        mutation(&current[index])
        projectWarehouseMovements = current
        return true
    }

    func replaceProjectWarehouseMovements(_ movements: [ProjectWarehouseMovement]) {
        projectWarehouseMovements = movements
    }

    func mergeProjectWarehouseMovementsByID(_ movements: [ProjectWarehouseMovement]) {
        mergeUniqueElementsByID(movements, into: \.projectWarehouseMovements)
    }

    func restoreProjectWarehouseMovements(from deletion: DataStoreRemovalResult<ProjectWarehouseMovement>) {
        projectWarehouseMovements = deletion.restoredItems(current: projectWarehouseMovements, id: \.id)
    }

    @discardableResult
    func removeProjectWarehouseMovements(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectWarehouseMovement> {
        removeElements(
            from: \.projectWarehouseMovements,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    func clearProjectPhotoReferences(projectId: UUID) -> DataStoreProjectFileCleanupResult {
        var logs = dailyLogs
        var todos = siteTodos
        var selectedPhotoNames = Set<String>()

        for index in logs.indices where logs[index].projectId == projectId {
            selectedPhotoNames.formUnion(logs[index].allPhotoFileNames)
            logs[index].photoFileName = nil
            logs[index].photos = []
        }
        for index in todos.indices where todos[index].projectId == projectId {
            if let before = todos[index].rectificationBeforePhotoFileName {
                selectedPhotoNames.insert(before)
            }
            if let after = todos[index].rectificationAfterPhotoFileName {
                selectedPhotoNames.insert(after)
            }
            todos[index].rectificationBeforePhotoFileName = nil
            todos[index].rectificationAfterPhotoFileName = nil
        }

        dailyLogs = logs
        siteTodos = todos

        let remainingPhotoNames = PhotoStorage.referencedFileNames(logs: dailyLogs, todos: siteTodos)
        return DataStoreProjectFileCleanupResult(
            photoFileNames: selectedPhotoNames.filter { !remainingPhotoNames.contains($0) }
        )
    }

    @discardableResult
    func clearProjectVideoReferences(
        projectId: UUID,
        videoFileExtensions: Set<String>
    ) -> DataStoreProjectFileCleanupResult {
        var notes = quickNotes
        var selectedAttachmentNames = Set<String>()

        for index in notes.indices where notes[index].projectId == projectId {
            let videos = notes[index].attachments.filter { $0.attachmentKind == .video }
            selectedAttachmentNames.formUnion(videos.map(\.fileName))
            notes[index].attachments.removeAll { $0.attachmentKind == .video }
        }
        quickNotes = notes

        let videoDocumentIDs = Set(
            projectDocuments
                .filter { $0.projectId == projectId }
                .filter { document in
                    let ext = document.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return videoFileExtensions.contains(ext) && !Self.isStorageCleanupTicketCategory(document.category)
                }
                .map(\.id)
        )
        let videoDocumentFileNames = Set(
            projectDocuments
                .filter { videoDocumentIDs.contains($0.id) }
                .map(\.fileName)
        )
        removeProjectDocuments(ids: videoDocumentIDs)
        unlinkProjectDocumentReferences(ids: videoDocumentIDs)

        let extraMethodAttachments = constructionMethods.flatMap(\.attachments)
            + constructionMethods.flatMap(\.tutorialAttachments)
        let remainingAttachmentNames = QuickNoteAttachmentStorage.referencedFileNames(
            for: quickNotes,
            extraAttachments: extraMethodAttachments
        )
        let remainingDocumentNames = Set(projectDocuments.map(\.fileName))

        return DataStoreProjectFileCleanupResult(
            quickNoteAttachmentFileNames: selectedAttachmentNames.filter { !remainingAttachmentNames.contains($0) },
            projectDocumentFileNames: videoDocumentFileNames.filter { !remainingDocumentNames.contains($0) }
        )
    }

    @discardableResult
    func clearProjectCADReferences(
        projectId: UUID,
        cadFileExtensions: Set<String>
    ) -> DataStoreProjectFileCleanupResult {
        let drawingIDs = Set(
            projectDrawings
                .filter { drawing in
                    let ext = drawing.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    return drawing.projectId == projectId && cadFileExtensions.contains(ext)
                }
                .map(\.id)
        )
        let drawingFileNames = Set(
            projectDrawings
                .filter { drawingIDs.contains($0.id) }
                .map(\.fileName)
        )

        removeProjectDrawings(ids: drawingIDs)

        let remainingDrawingNames = Set(projectDrawings.map(\.fileName))
        return DataStoreProjectFileCleanupResult(
            drawingFileNames: drawingFileNames.filter { !remainingDrawingNames.contains($0) }
        )
    }

    @discardableResult
    func clearProjectTicketDocumentReferences(projectId: UUID) -> DataStoreProjectFileCleanupResult {
        let documentIDs = Set(
            projectDocuments
                .filter { $0.projectId == projectId && Self.isStorageCleanupTicketCategory($0.category) }
                .map(\.id)
        )
        let documentFileNames = Set(
            projectDocuments
                .filter { documentIDs.contains($0.id) }
                .map(\.fileName)
        )

        removeProjectDocuments(ids: documentIDs)
        unlinkProjectDocumentReferences(ids: documentIDs)

        let remainingDocumentNames = Set(projectDocuments.map(\.fileName))
        return DataStoreProjectFileCleanupResult(
            projectDocumentFileNames: documentFileNames.filter { !remainingDocumentNames.contains($0) }
        )
    }

    func unlinkProjectDocumentReferences(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }

        var records = projectFinancialRecords
        for index in records.indices {
            records[index].linkedDocumentIds.removeAll { ids.contains($0) }
        }
        projectFinancialRecords = records

        var movements = projectWarehouseMovements
        for index in movements.indices {
            movements[index].linkedDocumentIds.removeAll { ids.contains($0) }
        }
        projectWarehouseMovements = movements
    }

    private static func isStorageCleanupTicketCategory(_ category: ProjectDocumentCategory) -> Bool {
        switch category {
        case .invoice, .receipt, .paymentRequest:
            return true
        default:
            return false
        }
    }

    func appendMaterialPriceEntry(_ entry: MaterialPriceEntry) {
        appendElement(entry, to: \.materialPriceEntries)
    }

    func appendMaterialPriceEntries(_ entries: [MaterialPriceEntry]) {
        appendElements(entries, to: \.materialPriceEntries)
    }

    func mergeMaterialPriceEntriesByID(_ entries: [MaterialPriceEntry]) {
        mergeUniqueElementsByID(entries, into: \.materialPriceEntries)
    }

    func replaceMaterialPriceEntries(_ entries: [MaterialPriceEntry]) {
        materialPriceEntries = entries
    }

    func insertMaterialPriceEntryAtTop(_ entry: MaterialPriceEntry) {
        insertElement(entry, at: 0, to: \.materialPriceEntries)
    }

    func upsertMaterialPriceEntry(_ entry: MaterialPriceEntry) {
        var entries = materialPriceEntries
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
            materialPriceEntries = entries
            return
        }

        let entryKey = MaterialIdentity.key(
            name: entry.name,
            specification: entry.specification,
            unit: entry.unit
        )
        if let duplicateIndex = entries.firstIndex(where: {
            MaterialIdentity.key(name: $0.name, specification: $0.specification, unit: $0.unit) == entryKey
        }) {
            var merged = entry
            merged.id = entries[duplicateIndex].id
            entries[duplicateIndex] = merged
            materialPriceEntries = entries
            return
        }

        entries.insert(entry, at: 0)
        materialPriceEntries = entries
    }

    func restoreMaterialPriceEntries(from deletion: DataStoreRemovalResult<MaterialPriceEntry>) {
        materialPriceEntries = deletion.restoredItems(current: materialPriceEntries, id: \.id)
    }

    func replaceMaterialSheetDrafts(_ drafts: [MaterialSheetDraft]) {
        materialSheetDrafts = drafts
    }

    func insertMaterialSheetDraftAtTop(_ draft: MaterialSheetDraft) {
        insertElement(draft, at: 0, to: \.materialSheetDrafts)
    }

    func mergeMaterialSheetDraftsByID(_ drafts: [MaterialSheetDraft]) {
        mergeUniqueElementsByID(drafts, into: \.materialSheetDrafts)
    }

    func replaceSupplierProfiles(_ profiles: [SupplierProfile]) {
        supplierProfiles = profiles
    }

    func mergeSupplierProfilesByID(_ profiles: [SupplierProfile]) {
        mergeUniqueElementsByID(profiles, into: \.supplierProfiles)
    }

    func appendUserMaterial(_ material: UserMaterial) {
        appendElement(material, to: \.userMaterials)
    }

    func replaceUserMaterials(_ materials: [UserMaterial]) {
        userMaterials = materials
    }

    func mergeUserMaterialsByID(_ materials: [UserMaterial]) {
        mergeUniqueElementsByID(materials, into: \.userMaterials)
    }

    func restoreUserMaterials(from deletion: DataStoreRemovalResult<UserMaterial>) {
        userMaterials = deletion.restoredItems(current: userMaterials, id: \.id)
    }

    func replaceDeletedUserMaterials(_ materials: [UserMaterial]) {
        deletedUserMaterials = materials
    }

    func mergeDeletedUserMaterialsByID(_ materials: [UserMaterial]) {
        mergeUniqueElementsByID(materials, into: \.deletedUserMaterials)
    }

    func removeDeletedUserMaterials(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        var current = deletedUserMaterials
        current.removeAll { ids.contains($0.id) }
        deletedUserMaterials = current
    }

    func prependDeletedUserMaterials(_ materials: [UserMaterial], maxCount: Int? = nil) {
        guard !materials.isEmpty else { return }
        var current = deletedUserMaterials
        let incomingIDs = Set(materials.map(\.id))
        current.removeAll { incomingIDs.contains($0.id) }
        current.insert(contentsOf: materials, at: 0)
        if let maxCount, maxCount > 0, current.count > maxCount {
            current = Array(current.prefix(maxCount))
        }
        deletedUserMaterials = current
    }

    @discardableResult
    func removeUserMaterials(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<UserMaterial> {
        removeElements(
            from: \.userMaterials,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    func removeMaterialPriceEntries(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<MaterialPriceEntry> {
        removeElements(
            from: \.materialPriceEntries,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    func removeMaterialSheetDrafts(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<MaterialSheetDraft> {
        removeElements(
            from: \.materialSheetDrafts,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func appendTemplate(_ template: ProjectTemplate) {
        appendElement(template, to: \.templates)
    }

    func mergeTemplatesByID(_ templates: [ProjectTemplate]) {
        mergeUniqueElementsByID(templates, into: \.templates)
    }

    func replaceTemplates(_ templates: [ProjectTemplate]) {
        self.templates = templates
    }

    func insertTemplateAtTop(_ template: ProjectTemplate) {
        insertElement(template, at: 0, to: \.templates)
    }

    func upsertTemplate(
        _ template: ProjectTemplate,
        insertAtTopWhenNew: Bool = false
    ) {
        var currentTemplates = templates
        if let index = currentTemplates.firstIndex(where: { $0.id == template.id }) {
            currentTemplates[index] = template
            templates = currentTemplates
            return
        }
        if insertAtTopWhenNew {
            currentTemplates.insert(template, at: 0)
        } else {
            currentTemplates.append(template)
        }
        templates = currentTemplates
    }

    func restoreTemplates(from deletion: DataStoreRemovalResult<ProjectTemplate>) {
        templates = deletion.restoredItems(current: templates, id: \.id)
    }

    @discardableResult
    func removeTemplates(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectTemplate> {
        removeElements(
            from: \.templates,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    func removeConstructionMethods(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ConstructionMethod> {
        removeElements(
            from: \.constructionMethods,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    func mergeConstructionMethodsByID(_ methods: [ConstructionMethod]) {
        mergeUniqueElementsByID(methods, into: \.constructionMethods)
    }

    func replaceConstructionMethods(_ methods: [ConstructionMethod]) {
        constructionMethods = methods
    }

    func upsertConstructionMethod(
        _ method: ConstructionMethod,
        insertAtTopWhenNew: Bool = false
    ) {
        var currentMethods = constructionMethods
        if let index = currentMethods.firstIndex(where: { $0.id == method.id }) {
            currentMethods[index] = method
            constructionMethods = currentMethods
            return
        }
        if insertAtTopWhenNew {
            currentMethods.insert(method, at: 0)
        } else {
            currentMethods.append(method)
        }
        constructionMethods = currentMethods
    }

    func restoreConstructionMethods(from deletion: DataStoreRemovalResult<ConstructionMethod>) {
        constructionMethods = deletion.restoredItems(current: constructionMethods, id: \.id)
    }

    func importSampleData(replacingExisting: Bool) {
#if DEBUG
        guard AppFeatureFlags.allowsSampleDataImport else {
            persistenceErrorMessage = String(localized: "当前发布环境已关闭示例数据导入。")
            return
        }
        if replacingExisting {
            clearAllBusinessData(deleteStoredFiles: true)
        }
        seedDefaults()
        save(includePhotoFiles: false)
#else
        persistenceErrorMessage = String(localized: "当前发布环境已关闭示例数据导入。")
#endif
    }

    func appendCalculationHistory(tool: String, input: String, result: String, date: String = Formatters.now()) {
        let record = HistoryRecord(tool: tool, input: input, result: result, date: date)
        historyRecords = [record] + historyRecords
        scheduleSave()
    }

    func replaceHistoryRecords(_ records: [HistoryRecord]) {
        historyRecords = records
    }

    func mergeHistoryRecordsByID(_ records: [HistoryRecord]) {
        mergeUniqueElementsByID(records, into: \.historyRecords)
    }

    func restoreHistoryRecords(from deletion: DataStoreRemovalResult<HistoryRecord>) {
        historyRecords = deletion.restoredItems(current: historyRecords, id: \.id)
    }

    @discardableResult
    func removeCalculationHistory(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<HistoryRecord> {
        removeElements(
            from: \.historyRecords,
            ids: ids,
            id: \.id,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    func clearCalculationHistory(
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<HistoryRecord> {
        removeElements(
            from: \.historyRecords,
            where: { _ in true },
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    @discardableResult
    func enforceCalculationHistoryRetention(
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<HistoryRecord> {
        let trimmed = applyingHistoryRetention(to: historyRecords)
        let keptIDs = Set(trimmed.map(\.id))
        return removeElements(
            from: \.historyRecords,
            where: { !keptIDs.contains($0.id) },
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

    private func projectDeletionSnapshot() -> DataStoreProjectDeletionSnapshot {
        DataStoreProjectDeletionSnapshot(
            projects: projects,
            materialItems: materialItems,
            quoteItems: quoteItems,
            laborRecords: laborRecords,
            dailyLogs: dailyLogs,
            progressTasks: progressTasks,
            lightingCircuitPlans: lightingCircuitPlans,
            siteTodos: siteTodos,
            projectDrawings: projectDrawings,
            projectContacts: projectContacts,
            projectFinancialRecords: projectFinancialRecords,
            projectDocuments: projectDocuments,
            quickNotes: quickNotes,
            projectWarehouseMovements: projectWarehouseMovements,
            materialSheetDrafts: materialSheetDrafts
        )
    }

    private func projectDeletionFileCleanup(
        logs: [DailyLog],
        todos: [SiteTodo],
        drawings: [ProjectDrawing],
        documents: [ProjectDocument],
        quickNotes: [QuickNote]
    ) -> DataStoreDeferredFileCleanup {
        DataStoreDeferredFileCleanup.combined(
            summary: String(localized: "删除项目关联文件"),
            cleanups: [
                DataStoreDeferredFileCleanup.photoFiles(
                    logs.flatMap(\.allPhotoFileNames)
                        + todos.compactMap(\.rectificationBeforePhotoFileName)
                        + todos.compactMap(\.rectificationAfterPhotoFileName),
                    summary: "project.photoFiles"
                ),
                DataStoreDeferredFileCleanup.drawingFiles(
                    drawings.map(\.fileName),
                    summary: "project.drawingFiles"
                ),
                DataStoreDeferredFileCleanup.projectDocumentFiles(
                    documents.map(\.fileName),
                    summary: "project.documentFiles"
                ),
                DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                    quickNotes.flatMap { note in
                        note.attachments.map(\.fileName)
                    },
                    summary: "project.quickNoteAttachmentFiles"
                )
            ]
        )
    }

    private func restoredSnapshotItems<Item: Identifiable>(
        snapshot: [Item],
        current: [Item]
    ) -> [Item] where Item.ID: Hashable {
        let snapshotIDs = Set(snapshot.map(\.id))
        let newItems = current.filter { !snapshotIDs.contains($0.id) }
        return newItems + snapshot
    }

    func relatedDataCount(for projectId: UUID) -> Int {
        let summary = projectStore.projectActivitySummary(for: projectId)
        return financeStore.materialItems(for: projectId).count
            + financeStore.quoteItems(for: projectId).count
            + financeStore.laborRecords(for: projectId).count
            + summary.dailyLogCount
            + summary.progressTaskCount
            + projectStore.lightingCircuitPlans(for: projectId).count
            + summary.todoCount
            + projectStore.projectDrawings(for: projectId).count
            + projectStore.projectContacts(for: projectId).count
            + projectStore.projectFinancialRecords(for: projectId).count
            + summary.documentCount
            + projectStore.quickNotes(for: projectId).count
            + projectStore.projectWarehouseMovements(for: projectId).count
            + materialLibraryStore.materialSheetDraftCount(for: projectId)
    }

    @discardableResult
    func removeProjectCascade(
        _ projectId: UUID,
        audit: DataStoreDeletionAuditContext? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreProjectDeletionResult {
        let snapshot = projectDeletionSnapshot()
        let removedProject = snapshot.projects.first { $0.id == projectId }
        let projectLogs = snapshot.dailyLogs.filter { $0.projectId == projectId }
        let projectTodos = snapshot.siteTodos.filter { $0.projectId == projectId }
        let projectDrawingItems = snapshot.projectDrawings.filter { $0.projectId == projectId }
        let projectDocumentItems = snapshot.projectDocuments.filter { $0.projectId == projectId }
        let projectQuickNotes = snapshot.quickNotes.filter { $0.projectId == projectId }
        let fileCleanup = projectDeletionFileCleanup(
            logs: projectLogs,
            todos: projectTodos,
            drawings: projectDrawingItems,
            documents: projectDocumentItems,
            quickNotes: projectQuickNotes
        )

        guard removedProject != nil else {
            return DataStoreProjectDeletionResult(
                projectId: projectId,
                snapshot: snapshot,
                removedProject: nil,
                deletedRecordCount: 0,
                audit: audit,
                deferredFileCleanup: fileCleanup
            )
        }

        let deletedRecordCount = 1
            + snapshot.materialItems.filter { $0.projectId == projectId }.count
            + snapshot.quoteItems.filter { $0.projectId == projectId }.count
            + snapshot.laborRecords.filter { $0.projectId == projectId }.count
            + projectLogs.count
            + snapshot.progressTasks.filter { $0.projectId == projectId }.count
            + snapshot.lightingCircuitPlans.filter { $0.projectId == projectId }.count
            + projectTodos.count
            + projectDrawingItems.count
            + snapshot.projectContacts.filter { $0.projectId == projectId }.count
            + snapshot.projectFinancialRecords.filter { $0.projectId == projectId }.count
            + projectDocumentItems.count
            + projectQuickNotes.count
            + snapshot.projectWarehouseMovements.filter { $0.projectId == projectId }.count
            + snapshot.materialSheetDrafts.filter { $0.projectId == projectId }.count

        materialItems = snapshot.materialItems.filter { $0.projectId != projectId }
        quoteItems = snapshot.quoteItems.filter { $0.projectId != projectId }
        laborRecords = snapshot.laborRecords.filter { $0.projectId != projectId }
        dailyLogs = snapshot.dailyLogs.filter { $0.projectId != projectId }
        progressTasks = snapshot.progressTasks.filter { $0.projectId != projectId }
        lightingCircuitPlans = snapshot.lightingCircuitPlans.filter { $0.projectId != projectId }
        siteTodos = snapshot.siteTodos.filter { $0.projectId != projectId }
        projectDrawings = snapshot.projectDrawings.filter { $0.projectId != projectId }
        projectContacts = snapshot.projectContacts.compactMap { contact in
            if contact.projectId == projectId {
                return nil
            }
            var cleaned = contact
            cleaned.relatedProjectIds.removeAll { $0 == projectId }
            return cleaned
        }
        projectFinancialRecords = snapshot.projectFinancialRecords.filter { $0.projectId != projectId }
        projectDocuments = snapshot.projectDocuments.filter { $0.projectId != projectId }
        quickNotes = snapshot.quickNotes.filter { $0.projectId != projectId }
        projectWarehouseMovements = snapshot.projectWarehouseMovements.filter { $0.projectId != projectId }
        materialSheetDrafts = snapshot.materialSheetDrafts.filter { $0.projectId != projectId }
        projects = snapshot.projects.filter { $0.id != projectId }

        let result = DataStoreProjectDeletionResult(
            projectId: projectId,
            snapshot: snapshot,
            removedProject: removedProject,
            deletedRecordCount: deletedRecordCount,
            audit: audit,
            deferredFileCleanup: fileCleanup
        )
        if recordsAuditImmediately {
            result.recordAuditStarted()
            result.performDeferredFileCleanup()
            result.recordAuditSucceeded()
        }
        return result
    }

    func restoreProjectCascade(_ deletion: DataStoreProjectDeletionResult) {
        guard !deletion.isEmpty else { return }
        projects = restoredSnapshotItems(snapshot: deletion.snapshot.projects, current: projects)
        materialItems = restoredSnapshotItems(snapshot: deletion.snapshot.materialItems, current: materialItems)
        quoteItems = restoredSnapshotItems(snapshot: deletion.snapshot.quoteItems, current: quoteItems)
        laborRecords = restoredSnapshotItems(snapshot: deletion.snapshot.laborRecords, current: laborRecords)
        dailyLogs = restoredSnapshotItems(snapshot: deletion.snapshot.dailyLogs, current: dailyLogs)
        progressTasks = restoredSnapshotItems(snapshot: deletion.snapshot.progressTasks, current: progressTasks)
        lightingCircuitPlans = restoredSnapshotItems(snapshot: deletion.snapshot.lightingCircuitPlans, current: lightingCircuitPlans)
        siteTodos = restoredSnapshotItems(snapshot: deletion.snapshot.siteTodos, current: siteTodos)
        projectDrawings = restoredSnapshotItems(snapshot: deletion.snapshot.projectDrawings, current: projectDrawings)
        projectContacts = restoredSnapshotItems(snapshot: deletion.snapshot.projectContacts, current: projectContacts)
        projectFinancialRecords = restoredSnapshotItems(
            snapshot: deletion.snapshot.projectFinancialRecords,
            current: projectFinancialRecords
        )
        projectDocuments = restoredSnapshotItems(snapshot: deletion.snapshot.projectDocuments, current: projectDocuments)
        quickNotes = restoredSnapshotItems(snapshot: deletion.snapshot.quickNotes, current: quickNotes)
        projectWarehouseMovements = restoredSnapshotItems(
            snapshot: deletion.snapshot.projectWarehouseMovements,
            current: projectWarehouseMovements
        )
        materialSheetDrafts = restoredSnapshotItems(snapshot: deletion.snapshot.materialSheetDrafts, current: materialSheetDrafts)
    }

    func deleteProject(_ projectId: UUID) {
        let deletion = removeProjectCascade(projectId)
        deletion.performDeferredFileCleanup()
        scheduleSave()
    }

    func clearAllBusinessData(deleteStoredFiles: Bool = true) {
        cancelScheduledSave()
        if deleteStoredFiles {
            DataStoreDeferredFileCleanup.combined(
                summary: "dataStore.clearAllBusinessData",
                cleanups: [
                    DataStoreDeferredFileCleanup.photoFiles(
                        PhotoStorage.allStoredFileNames(),
                        summary: "dataStore.clearAll.photos"
                    ),
                    DataStoreDeferredFileCleanup.drawingFiles(
                        DrawingStorage.allStoredFileNames(),
                        summary: "dataStore.clearAll.drawings"
                    ),
                    DataStoreDeferredFileCleanup.projectDocumentFiles(
                        ProjectDocumentStorage.allStoredFileNames(),
                        summary: "dataStore.clearAll.projectDocuments"
                    ),
                    DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                        QuickNoteAttachmentStorage.allStoredFileNames(),
                        summary: "dataStore.clearAll.quickNoteAttachments"
                    )
                ]
            )
            .perform()
            StorageIssueLog.clear()
        }
        clearAllData()
        save(includePhotoFiles: false)
    }

    func clearAllBusinessDataAsync(
        deleteStoredFiles: Bool = true,
        onProgress: (@MainActor (String) -> Void)? = nil
    ) async {
        cancelScheduledSave()
        if deleteStoredFiles {
            let photoNames = PhotoStorage.allStoredFileNames()
            let drawingNames = DrawingStorage.allStoredFileNames()
            let documentNames = ProjectDocumentStorage.allStoredFileNames()
            let attachmentNames = QuickNoteAttachmentStorage.allStoredFileNames()

            onProgress?(String(localized: "正在并行删除照片/图纸/资料/附件"))
            async let deletePhotos: Void = Task.detached(priority: .userInitiated) {
                DataStoreDeferredFileCleanup.photoFiles(
                    photoNames,
                    summary: "dataStore.clearAllAsync.photos"
                )?.perform()
            }.value
            async let deleteDrawings: Void = Task.detached(priority: .userInitiated) {
                DataStoreDeferredFileCleanup.drawingFiles(
                    drawingNames,
                    summary: "dataStore.clearAllAsync.drawings"
                )?.perform()
            }.value
            async let deleteDocuments: Void = Task.detached(priority: .userInitiated) {
                DataStoreDeferredFileCleanup.projectDocumentFiles(
                    documentNames,
                    summary: "dataStore.clearAllAsync.projectDocuments"
                )?.perform()
            }.value
            async let deleteAttachments: Void = Task.detached(priority: .userInitiated) {
                DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
                    attachmentNames,
                    summary: "dataStore.clearAllAsync.quickNoteAttachments"
                )?.perform()
            }.value
            _ = await (deletePhotos, deleteDrawings, deleteDocuments, deleteAttachments)

            onProgress?(String(localized: "正在清理日志"))
            await Task.detached(priority: .utility) {
                StorageIssueLog.clear()
            }.value
        }

        onProgress?(String(localized: "正在写入空数据"))
        clearAllData()
        save(includePhotoFiles: false)
        onProgress?(String(localized: "清空完成"))
    }

    private func clearAllData() {
        materialItems = []
        quoteItems = []
        laborRecords = []
        projects = []
        dailyLogs = []
        historyRecords = []
        progressTasks = []
        lightingCircuitPlans = []
        siteTodos = []
        projectDrawings = []
        projectContacts = []
        projectFinancialRecords = []
        projectDocuments = []
        quickNotes = []
        projectWarehouseMovements = []
        templates = []
        materialPriceEntries = []
        materialSheetDrafts = []
        supplierProfiles = []
        constructionMethods = []
        favoriteMaterialKeys = []
        recentMaterialKeys = []
        userMaterials = []
        deletedUserMaterials = []
        hiddenPresetKeys = []
        refreshSearchIndexVersion()
        dataVersion = UUID()
        publishWidgetData()
    }

    private func refreshSearchIndexVersion() {
        searchIndexVersion &+= 1
    }

    private static func migrateLegacyPaymentRecords(
        _ legacyRecords: [LegacyPaymentRecord],
        projects: [Project]
    ) -> [ProjectFinancialRecord] {
        guard !legacyRecords.isEmpty else { return [] }
        let counterpartyByProjectID = Dictionary(
            uniqueKeysWithValues: projects.map { ($0.id, $0.customerName) }
        )
        return legacyRecords.map { legacy in
            legacy.migratedFinancialRecord(
                counterparty: counterpartyByProjectID[legacy.projectId] ?? ""
            )
        }
    }

    private static func mergeFinancialRecords(
        existing: [ProjectFinancialRecord],
        incoming: [ProjectFinancialRecord]
    ) -> [ProjectFinancialRecord] {
        guard !incoming.isEmpty else { return existing }
        var merged = existing
        var knownIDs = Set(existing.map(\.id))
        for record in incoming where knownIDs.insert(record.id).inserted {
            merged.append(record)
        }
        return merged
    }

    func publishWidgetData() {
        guard let defaults = UserDefaults(suiteName: WidgetSharedDefaults.suiteName) else { return }
        let activeProjects = projects.filter {
            $0.status == .active || $0.status == .paused
        }
        let activeProjectIDs = Set(activeProjects.map(\.id))
        let stockLines = activeProjects.flatMap {
            WarehouseStockCalculator.stockLines(for: $0.id, movements: projectWarehouseMovements)
        }
        let activeFinancialRecords = projectFinancialRecords.filter {
            activeProjectIDs.contains($0.projectId) && $0.normalizedStatus == .active
        }
        let missingReceiptCount = activeFinancialRecords.filter { record in
            guard record.requiresAttachment else { return false }
            let linkedByRecord = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = projectDocuments.contains { $0.linkedFinancialRecordId == record.id }
            return !(linkedByRecord || linkedByDocument)
        }.count
        let priceSpikeCount = activeProjects.reduce(0) { count, project in
            count + financeStore.materialPriceSpikeCount(for: project.id)
        }
        let reminderDaysRaw = UserDefaults.standard.integer(forKey: UserPreferenceKeys.backupHealthReminderDays)
        let reminderDays = max(1, reminderDaysRaw == 0 ? 7 : reminderDaysRaw)
        let localBackupRaw = UserDefaults.standard.double(forKey: UserPreferenceKeys.localBackupLastSuccessAt)
        let cloudBackupRaw = UserDefaults.standard.double(forKey: UserPreferenceKeys.cloudBackupLastSuccessAt)
        let localBackupDate = localBackupRaw > 0 ? Date(timeIntervalSince1970: localBackupRaw) : nil
        let cloudBackupDate = cloudBackupRaw > 0 ? Date(timeIntervalSince1970: cloudBackupRaw) : nil
        let latestBackupDate: Date? = {
            switch (localBackupDate, cloudBackupDate) {
            case let (lhs?, rhs?):
                return max(lhs, rhs)
            case let (lhs?, nil):
                return lhs
            case let (nil, rhs?):
                return rhs
            case (nil, nil):
                return nil
            }
        }()
        let backupOverdueCount: Int = {
            guard let latestBackupDate else { return 1 }
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: latestBackupDate)
            let today = calendar.startOfDay(for: Date())
            let days = max(calendar.dateComponents([.day], from: start, to: today).day ?? 0, 0)
            return days >= reminderDays ? 1 : 0
        }()
        let widgetData = WidgetDataBuilder.build(
            projects: activeProjects.map {
                WidgetBuilderProjectInput(
                    id: $0.id,
                    name: $0.name,
                    status: $0.status.rawValue,
                    isActive: true
                )
            },
            todos: siteTodos.map { WidgetBuilderTodoInput(projectId: $0.projectId, isDone: $0.isDone, dueDate: $0.dueDate) },
            tasks: progressTasks.map { WidgetBuilderTaskInput(projectId: $0.projectId, completion: $0.completion) },
            stockLines: stockLines.map { WidgetBuilderStockInput(quantity: $0.quantity) },
            missingReceiptCount: missingReceiptCount,
            priceSpikeCount: priceSpikeCount,
            backupOverdueCount: backupOverdueCount
        )
        let data: Data
        do {
            data = try JSONEncoder().encode(widgetData)
        } catch {
            Self.recordIssue(
                "datastore.widget_payload_encode_failed",
                details: ["target": WidgetSharedDefaults.dataKey],
                error: error
            )
            return
        }
        defaults.set(data, forKey: WidgetSharedDefaults.dataKey)
        defaults.set(widgetData.lastUpdatedAt, forKey: WidgetSharedDefaults.updatedAtKey)
        reloadWidgetTimelines()
    }

    private func reloadWidgetTimelines() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedDefaults.widgetKind)
#endif
    }

    /// 根据仓库流水自动更新 MaterialItem.quantity。
    /// 匹配规则：同一项目下（name + specification + unit）一致的材料。
    /// 入库为正，出库为负；对已有材料更新 quantity，不存在则自动创建。
    func syncWarehouseToMaterialQuantity(for projectIDs: Set<UUID>? = nil) {
        let targetProjectIDs = projectIDs ?? Set(projectWarehouseMovements.map(\.projectId))
        for pid in targetProjectIDs {
            var materialIndexByIdentity: [String: Int] = [:]
            var existingMaterialNames = Set<String>()
            for index in materialItems.indices where materialItems[index].projectId == pid {
                materialIndexByIdentity[warehouseMaterialIdentity(
                    name: materialItems[index].name,
                    specification: materialItems[index].specification,
                    unit: materialItems[index].unit
                )] = index
                existingMaterialNames.insert(materialItems[index].name)
            }

            let lines = WarehouseStockCalculator.stockLines(for: pid, movements: projectWarehouseMovements)
            for line in lines {
                if line.quantity == 0 && !existingMaterialNames.contains(line.materialName) {
                    continue
                }
                let qtyStr = WarehouseStockCalculator.quantityText(line.quantity)
                let identity = warehouseMaterialIdentity(
                    name: line.materialName,
                    specification: line.specification,
                    unit: line.unit
                )
                if let idx = materialIndexByIdentity[identity] {
                    materialItems[idx].quantity = qtyStr
                } else if line.quantity > 0 {
                    let newItem = MaterialItem(
                        name: line.materialName,
                        quantity: qtyStr,
                        unit: line.unit,
                        specification: line.specification,
                        projectId: pid
                    )
                    materialItems.append(newItem)
                    materialIndexByIdentity[identity] = materialItems.count - 1
                    existingMaterialNames.insert(newItem.name)
                }
            }
        }
    }

    private func warehouseMaterialIdentity(name: String, specification: String, unit: String) -> String {
        [name, specification, unit].joined(separator: "\u{1f}")
    }

    private func applyingHistoryRetention(to records: [HistoryRecord]) -> [HistoryRecord] {
        guard !records.isEmpty else { return [] }
        var kept: [HistoryRecord] = []
        kept.reserveCapacity(min(records.count, historyRecordMaxTotalCount))
        var toolCounts: [String: Int] = [:]

        for record in records {
            if kept.count >= historyRecordMaxTotalCount {
                break
            }
            let count = toolCounts[record.tool, default: 0]
            if count >= historyRecordMaxCountPerTool {
                continue
            }
            kept.append(record)
            toolCounts[record.tool] = count + 1
        }
        return kept
    }
}

actor DataStorePersistenceActor {
    private let storeURL: URL

    private static func recordIssue(
        _ event: String,
        details: [String: String] = [:],
        error: Error? = nil
    ) {
        StorageIssueLog.recordEvent(
            event,
            category: .dataStore,
            details: details,
            error: error
        )
    }

    struct LoadDecodeError: Error {
        let rawData: Data
    }

    init(storeURL: URL) {
        self.storeURL = storeURL
    }

    func loadSnapshot(primaryStoreURL: URL, legacyStoreURL: URL) throws -> BackupSnapshot? {
        let fileManager = FileManager.default
        let sourceURL: URL
        if fileManager.fileExists(atPath: primaryStoreURL.path) {
            sourceURL = primaryStoreURL
        } else if fileManager.fileExists(atPath: legacyStoreURL.path) {
            sourceURL = legacyStoreURL
        } else {
            return nil
        }

        let data = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
        let snapshot: BackupSnapshot
        do {
            snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: data)
        } catch {
            throw LoadDecodeError(rawData: data)
        }

        if sourceURL == legacyStoreURL {
            do {
                try data.write(to: primaryStoreURL, options: .atomic)
                do {
                    _ = try FileOps.removeIfExists(
                        at: legacyStoreURL,
                        context: .init(
                            event: "datastore.legacy_store_cleanup",
                            category: .dataStore,
                            source: "DataStore.loadSnapshotFromDisk"
                        )
                    )
                } catch {
                    Self.recordIssue(
                        "datastore.legacy_store_cleanup_failed",
                        details: [
                            "file": legacyStoreURL.lastPathComponent,
                            "target": primaryStoreURL.lastPathComponent
                        ],
                        error: error
                    )
                }
            } catch {
                Self.recordIssue(
                    "datastore.legacy_store_migration_failed",
                    details: [
                        "source": legacyStoreURL.lastPathComponent,
                        "target": primaryStoreURL.lastPathComponent
                    ],
                    error: error
                )
            }
        }
        return snapshot
    }

    func persist(snapshot: BackupSnapshot) throws {
        guard !Task.isCancelled else { return }
        let encoder = JSONEncoder()
        let data = try encoder.encode(snapshot)
        guard !Task.isCancelled else { return }
        try data.write(to: storeURL, options: .atomic)
    }
}
