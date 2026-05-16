import Foundation
import Observation
#if canImport(WidgetKit)
import WidgetKit
#endif

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
    var materialItems: [MaterialItem] {
        get { proxiedRead(\.materialItems, financeStore.materialItems) }
        set { proxiedWrite(\.materialItems) { financeStore.setMaterialItems(newValue) } }
    }
    var quoteItems: [QuoteItem] {
        get { proxiedRead(\.quoteItems, financeStore.quoteItems) }
        set { proxiedWrite(\.quoteItems) { financeStore.setQuoteItems(newValue) } }
    }
    var laborRecords: [LaborRecord] {
        get { proxiedRead(\.laborRecords, financeStore.laborRecords) }
        set { proxiedWrite(\.laborRecords) { financeStore.setLaborRecords(newValue) } }
    }
    // 项目
    var projects: [Project] {
        get { proxiedRead(\.projects, projectStore.projects) }
        set { proxiedWrite(\.projects) { projectStore.setProjects(newValue) } }
    }
    var dailyLogs: [DailyLog] {
        get { proxiedRead(\.dailyLogs, projectStore.dailyLogs) }
        set { proxiedWrite(\.dailyLogs) { projectStore.setDailyLogs(newValue) } }
    }
    var historyRecords: [HistoryRecord] {
        get { proxiedRead(\.historyRecords, projectStore.historyRecords) }
        set {
            proxiedWrite(\.historyRecords) {
                projectStore.setHistoryRecords(applyingHistoryRetention(to: newValue))
            }
        }
    }
    var progressTasks: [ProgressTask] {
        get { proxiedRead(\.progressTasks, projectStore.progressTasks) }
        set { proxiedWrite(\.progressTasks) { projectStore.setProgressTasks(newValue) } }
    }
    var lightingCircuitPlans: [LightingCircuitPlan] {
        get { proxiedRead(\.lightingCircuitPlans, projectStore.lightingCircuitPlans) }
        set { proxiedWrite(\.lightingCircuitPlans) { projectStore.setLightingCircuitPlans(newValue) } }
    }
    var siteTodos: [SiteTodo] {
        get { proxiedRead(\.siteTodos, projectStore.siteTodos) }
        set { proxiedWrite(\.siteTodos) { projectStore.setSiteTodos(newValue) } }
    }
    var projectDrawings: [ProjectDrawing] {
        get { proxiedRead(\.projectDrawings, projectStore.projectDrawings) }
        set { proxiedWrite(\.projectDrawings) { projectStore.setProjectDrawings(newValue) } }
    }
    var projectContacts: [ProjectContact] {
        get { proxiedRead(\.projectContacts, projectStore.projectContacts) }
        set { proxiedWrite(\.projectContacts) { projectStore.setProjectContacts(newValue) } }
    }
    var projectFinancialRecords: [ProjectFinancialRecord] {
        get { proxiedRead(\.projectFinancialRecords, projectStore.projectFinancialRecords) }
        set { proxiedWrite(\.projectFinancialRecords) { projectStore.setProjectFinancialRecords(newValue) } }
    }
    var projectDocuments: [ProjectDocument] {
        get { proxiedRead(\.projectDocuments, projectStore.projectDocuments) }
        set { proxiedWrite(\.projectDocuments) { projectStore.setProjectDocuments(newValue) } }
    }
    var quickNotes: [QuickNote] {
        get { proxiedRead(\.quickNotes, projectStore.quickNotes) }
        set { proxiedWrite(\.quickNotes) { projectStore.setQuickNotes(newValue) } }
    }
    var projectWarehouseMovements: [ProjectWarehouseMovement] {
        get { proxiedRead(\.projectWarehouseMovements, projectStore.projectWarehouseMovements) }
        set { proxiedWrite(\.projectWarehouseMovements) { projectStore.setProjectWarehouseMovements(newValue) } }
    }

    // 模板 / 材料库
    var templates: [ProjectTemplate] {
        get { proxiedRead(\.templates, materialLibraryStore.templates) }
        set { proxiedWrite(\.templates) { materialLibraryStore.setTemplates(newValue) } }
    }
    var materialPriceEntries: [MaterialPriceEntry] {
        get { proxiedRead(\.materialPriceEntries, materialLibraryStore.materialPriceEntries) }
        set { proxiedWrite(\.materialPriceEntries) { materialLibraryStore.setMaterialPriceEntries(newValue) } }
    }
    var materialSheetDrafts: [MaterialSheetDraft] {
        get { proxiedRead(\.materialSheetDrafts, materialLibraryStore.materialSheetDrafts) }
        set { proxiedWrite(\.materialSheetDrafts) { materialLibraryStore.setMaterialSheetDrafts(newValue) } }
    }
    var supplierProfiles: [SupplierProfile] {
        get { proxiedRead(\.supplierProfiles, materialLibraryStore.supplierProfiles) }
        set { proxiedWrite(\.supplierProfiles) { materialLibraryStore.setSupplierProfiles(newValue) } }
    }
    var constructionMethods: [ConstructionMethod] {
        get { proxiedRead(\.constructionMethods, materialLibraryStore.constructionMethods) }
        set { proxiedWrite(\.constructionMethods) { materialLibraryStore.setConstructionMethods(newValue) } }
    }
    var userMaterials: [UserMaterial] {
        get { proxiedRead(\.userMaterials, materialLibraryStore.userMaterials) }
        set { proxiedWrite(\.userMaterials) { materialLibraryStore.setUserMaterials(newValue) } }
    }
    var deletedUserMaterials: [UserMaterial] {
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

    private static var defaultDocumentsDirectory: URL {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return dir
        }
        StorageIssueLog.record("无法访问应用文档目录，已回退到临时目录", category: .dataStore)
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
                    StorageIssueLog.record(
                        "损坏数据备份写入失败：\(backupName)，\(error.localizedDescription)",
                        category: .dataStore
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
            StorageIssueLog.record(
                "检测到旧收款记录 \(snapshot.legacyPaymentRecords.count) 条，已自动迁移为财务流水",
                category: .dataStore
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

    func appendDailyLog(_ log: DailyLog) {
        appendElement(log, to: \.dailyLogs)
    }

    func insertDailyLogAtTop(_ log: DailyLog) {
        insertElement(log, at: 0, to: \.dailyLogs)
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

    func appendSiteTodo(_ todo: SiteTodo) {
        appendElement(todo, to: \.siteTodos)
    }

    func insertSiteTodoAtTop(_ todo: SiteTodo) {
        insertElement(todo, at: 0, to: \.siteTodos)
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

    func appendProjectWarehouseMovement(_ movement: ProjectWarehouseMovement) {
        appendElement(movement, to: \.projectWarehouseMovements)
    }

    func insertProjectWarehouseMovementAtTop(_ movement: ProjectWarehouseMovement) {
        insertElement(movement, at: 0, to: \.projectWarehouseMovements)
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

    func appendMaterialPriceEntry(_ entry: MaterialPriceEntry) {
        appendElement(entry, to: \.materialPriceEntries)
    }

    func appendMaterialPriceEntries(_ entries: [MaterialPriceEntry]) {
        appendElements(entries, to: \.materialPriceEntries)
    }

    func insertMaterialPriceEntryAtTop(_ entry: MaterialPriceEntry) {
        insertElement(entry, at: 0, to: \.materialPriceEntries)
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

    func appendTemplate(_ template: ProjectTemplate) {
        appendElement(template, to: \.templates)
    }

    func insertTemplateAtTop(_ template: ProjectTemplate) {
        insertElement(template, at: 0, to: \.templates)
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

    func removeCalculationHistory(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        historyRecords.removeAll { ids.contains($0.id) }
        scheduleSave()
    }

    func clearCalculationHistory() {
        guard !historyRecords.isEmpty else { return }
        historyRecords.removeAll()
        scheduleSave()
    }

    func enforceCalculationHistoryRetention() {
        let trimmed = applyingHistoryRetention(to: historyRecords)
        guard trimmed.count != historyRecords.count else { return }
        historyRecords = trimmed
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

    func deleteProject(_ projectId: UUID) {
        let projectLogs = projectStore.dailyLogs(for: projectId)
        let projectTodos = projectStore.siteTodos(for: projectId)
        let projectDrawingItems = projectStore.projectDrawings(for: projectId)
        let projectDocumentItems = projectStore.projectDocuments(for: projectId)
        let projectQuickNotes = projectStore.quickNotes(for: projectId)

        // 照片（日志 + 待办整改前后）
        let logPhotos = projectLogs.flatMap(\.allPhotoFileNames)
        let todoPhotos = projectTodos.compactMap(\.rectificationBeforePhotoFileName) +
            projectTodos.compactMap(\.rectificationAfterPhotoFileName)
        PhotoStorage.delete(fileNames: logPhotos + todoPhotos)

        // 图纸文件
        for drawing in projectDrawingItems {
            DrawingStorage.delete(fileName: drawing.fileName)
        }

        // 文档文件
        for document in projectDocumentItems {
            ProjectDocumentStorage.delete(fileName: document.fileName)
        }

        // 随手记附件
        let quickNoteAttachments = projectQuickNotes.flatMap(\.attachments)
        QuickNoteAttachmentStorage.delete(attachments: quickNoteAttachments)

        // 数据记录
        materialItems.removeAll { $0.projectId == projectId }
        quoteItems.removeAll { $0.projectId == projectId }
        laborRecords.removeAll { $0.projectId == projectId }
        dailyLogs.removeAll { $0.projectId == projectId }
        progressTasks.removeAll { $0.projectId == projectId }
        lightingCircuitPlans.removeAll { $0.projectId == projectId }
        siteTodos.removeAll { $0.projectId == projectId }
        projectDrawings.removeAll { $0.projectId == projectId }
        projectContacts = projectContacts.compactMap { contact in
            if contact.projectId == projectId {
                return nil
            }
            var cleaned = contact
            cleaned.relatedProjectIds.removeAll { $0 == projectId }
            return cleaned
        }
        projectFinancialRecords.removeAll { $0.projectId == projectId }
        projectDocuments.removeAll { $0.projectId == projectId }
        quickNotes.removeAll { $0.projectId == projectId }
        projectWarehouseMovements.removeAll { $0.projectId == projectId }
        materialSheetDrafts.removeAll { $0.projectId == projectId }
        projects.removeAll { $0.id == projectId }
        scheduleSave()
    }

    func clearAllBusinessData(deleteStoredFiles: Bool = true) {
        cancelScheduledSave()
        if deleteStoredFiles {
            PhotoStorage.delete(fileNames: PhotoStorage.allStoredFileNames())
            DrawingStorage.delete(fileNames: DrawingStorage.allStoredFileNames())
            ProjectDocumentStorage.delete(fileNames: ProjectDocumentStorage.allStoredFileNames())
            QuickNoteAttachmentStorage.delete(fileNames: QuickNoteAttachmentStorage.allStoredFileNames())
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
                PhotoStorage.delete(fileNames: photoNames)
            }.value
            async let deleteDrawings: Void = Task.detached(priority: .userInitiated) {
                DrawingStorage.delete(fileNames: drawingNames)
            }.value
            async let deleteDocuments: Void = Task.detached(priority: .userInitiated) {
                ProjectDocumentStorage.delete(fileNames: documentNames)
            }.value
            async let deleteAttachments: Void = Task.detached(priority: .userInitiated) {
                QuickNoteAttachmentStorage.delete(fileNames: attachmentNames)
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
        guard let defaults = UserDefaults(suiteName: "group.com.chengjinfang.sitekeeper") else { return }
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
            StorageIssueLog.record("Widget 数据编码失败：\(error.localizedDescription)", category: .dataStore)
            return
        }
        defaults.set(data, forKey: "widget_data")
        defaults.set(widgetData.lastUpdatedAt, forKey: "widget_data_updated_at")
        reloadWidgetTimelines()
    }

    private func reloadWidgetTimelines() {
#if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: "SitekeeperWidget")
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
                    try FileManager.default.removeItem(at: legacyStoreURL)
                } catch let cocoaError as CocoaError where cocoaError.code == .fileNoSuchFile {
                    // ignore missing legacy file
                } catch {
                    StorageIssueLog.record(
                        "旧数据文件迁移后清理失败：\(legacyStoreURL.lastPathComponent)，\(error.localizedDescription)",
                        category: .dataStore
                    )
                }
            } catch {
                StorageIssueLog.record("旧数据文件迁移失败：\(error.localizedDescription)", category: .dataStore)
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
