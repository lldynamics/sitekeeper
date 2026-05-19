import Foundation
import Observation

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

    let primaryStoreURL: URL
    let legacyStoreURL: URL
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

    static func recordIssue(
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

    init(storageDirectory: URL? = nil) {
        let documentsDirectory = storageDirectory ?? Self.defaultDocumentsDirectory
        primaryStoreURL = documentsDirectory.appendingPathComponent("sitekeeper.json")
        legacyStoreURL = documentsDirectory.appendingPathComponent("construction_toolbox.json")
        storeURL = primaryStoreURL
        persistenceActor = DataStorePersistenceActor(storeURL: storeURL)
        loadAsync()
        publishWidgetData()
    }

    var hasAnyBusinessData: Bool {
        !materialItems.isEmpty ||
        !quoteItems.isEmpty ||
        !laborRecords.isEmpty ||
        !projects.isEmpty ||
        !dailyLogs.isEmpty ||
        !historyRecords.isEmpty ||
        !progressTasks.isEmpty ||
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

    func replaceMaterialItems(_ items: [MaterialItem]) {
        materialItems = items
    }

    func replaceQuoteItems(_ items: [QuoteItem]) {
        quoteItems = items
    }

    func replaceLaborRecords(_ records: [LaborRecord]) {
        laborRecords = records
    }

    func replaceProgressTasks(_ tasks: [ProgressTask]) {
        progressTasks = tasks
    }

    func replaceProjects(_ values: [Project]) {
        projects = values
    }

    func replaceDailyLogs(_ logs: [DailyLog]) {
        dailyLogs = logs
    }

    func replaceSiteTodos(_ todos: [SiteTodo]) {
        siteTodos = todos
    }

    func replaceProjectContacts(_ contacts: [ProjectContact]) {
        proxiedWrite(\.projectContacts) { projectStore.setProjectContacts(contacts) }
    }

    func replaceProjectFinancialRecords(_ records: [ProjectFinancialRecord]) {
        proxiedWrite(\.projectFinancialRecords) { projectStore.setProjectFinancialRecords(records) }
    }

    func replaceProjectDocuments(_ documents: [ProjectDocument]) {
        proxiedWrite(\.projectDocuments) { projectStore.setProjectDocuments(documents) }
    }

    func replaceQuickNotes(_ notes: [QuickNote]) {
        proxiedWrite(\.quickNotes) { projectStore.setQuickNotes(notes) }
    }

    func replaceProjectWarehouseMovements(_ movements: [ProjectWarehouseMovement]) {
        proxiedWrite(\.projectWarehouseMovements) { projectStore.setProjectWarehouseMovements(movements) }
    }

    func replaceMaterialPriceEntries(_ entries: [MaterialPriceEntry]) {
        materialPriceEntries = entries
    }

    func replaceMaterialSheetDrafts(_ drafts: [MaterialSheetDraft]) {
        materialSheetDrafts = drafts
    }

    func replaceSupplierProfiles(_ profiles: [SupplierProfile]) {
        supplierProfiles = profiles
    }

    func replaceUserMaterials(_ materials: [UserMaterial]) {
        userMaterials = materials
    }

    func replaceDeletedUserMaterials(_ materials: [UserMaterial]) {
        deletedUserMaterials = materials
    }

    func replaceTemplates(_ templates: [ProjectTemplate]) {
        self.templates = templates
    }

    func replaceConstructionMethods(_ methods: [ConstructionMethod]) {
        constructionMethods = methods
    }

    func replaceHistoryRecords(_ records: [HistoryRecord]) {
        historyRecords = records
    }

}
