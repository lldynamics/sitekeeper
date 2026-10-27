import Foundation
import Observation

struct ProjectActivitySummary: Equatable {
    var dailyLogCount = 0
    var progressTaskCount = 0
    var todoCount = 0
    var openTodoCount = 0
    var overdueProgressCount = 0
    var overdueTodoCount = 0
    var documentCount = 0
    var latestDailyLogDate: Date?
    var latestProgressDate: Date?
    var latestTodoDate: Date?
    var latestDocumentDate: Date?
    var latestDrawingDate: Date?
    var latestFinancialDate: Date?
    var latestWarehouseDate: Date?
    var latestQuickNoteDate: Date?
    var collectedIncomeAmount = MoneyValue.zero
    var unattachedReceiptCount = 0
    var unsettledFinancialCount = 0
    var linkedFinancialRecordIDs: Set<UUID> = []

    var latestActivityDate: Date? {
        [
            latestDailyLogDate,
            latestProgressDate,
            latestTodoDate,
            latestDocumentDate,
            latestDrawingDate,
            latestFinancialDate,
            latestWarehouseDate,
            latestQuickNoteDate
        ]
            .compactMap { $0 }
            .max()
    }

    var overdueItemCount: Int {
        overdueProgressCount + overdueTodoCount
    }

    var hasUnsettledFinancial: Bool {
        unsettledFinancialCount > 0
    }
}

@MainActor
@Observable
final class ProjectStore {
    @ObservationIgnored private var batchDepth = 0
    @ObservationIgnored private var activityRebuildPending = false
    @ObservationIgnored private var affectedActivityProjectIDs: Set<UUID> = []
    @ObservationIgnored private var needsFullActivityRebuild = true
    /// Counts actual builder input, including full refreshes after a day/time-zone change.
    @ObservationIgnored private(set) var activityIndexProcessedRecordCount = 0
    @ObservationIgnored private(set) var activityIndexRebuiltProjectCount = 0
    @ObservationIgnored private(set) var lastActivityIndexProcessedRecordCount = 0
    @ObservationIgnored private(set) var lastActivityIndexRebuiltProjectCount = 0
    @ObservationIgnored private(set) var activityIndexBuildCount = 0

    func withBatchUpdates(_ operation: () -> Void) {
        batchDepth += 1
        defer {
            batchDepth -= 1
            if batchDepth == 0, activityRebuildPending { rebuildProjectActivityIndex() }
        }
        operation()
    }
    @ObservationIgnored private let mutationSink: DomainStoreMutationSink
    private(set) var projects: [Project] = [] {
        didSet {
            mutationSink.didMutate("projects")
            refreshProjectStatusIndex()
            refreshDueReminderVersion()
            refreshFileSearchVersion()
        }
    }
    private(set) var dailyLogs: [DailyLog] = [] {
        didSet {
            mutationSink.didMutate("dailyLogs")
            dailyLogsByProjectID = regroupActivity(
                dailyLogs, previous: dailyLogsByProjectID,
                projectID: { $0.projectId }, activityEqual: ProjectActivityIndexBuilder.hasSameActivity
            )
            rebuildProjectActivityIndex()
            refreshFileSearchVersion()
        }
    }
    private(set) var historyRecords: [HistoryRecord] = [] {
        didSet { mutationSink.didMutate("historyRecords") }
    }
    private(set) var progressTasks: [ProgressTask] = [] {
        didSet {
            mutationSink.didMutate("progressTasks")
            progressTasksByProjectID = regroupActivity(
                progressTasks, previous: progressTasksByProjectID,
                projectID: { $0.projectId }, activityEqual: ProjectActivityIndexBuilder.hasSameActivity
            )
            rebuildProjectActivityIndex()
        }
    }
    private(set) var siteTodos: [SiteTodo] = [] {
        didSet {
            mutationSink.didMutate("siteTodos")
            siteTodosByProjectID = regroupActivity(
                siteTodos, previous: siteTodosByProjectID,
                projectID: { $0.projectId }, activityEqual: ProjectActivityIndexBuilder.hasSameActivity
            )
            rebuildProjectActivityIndex()
            refreshFileSearchVersion()
            refreshDueReminderVersion()
        }
    }
    private(set) var projectDrawings: [ProjectDrawing] = [] {
        didSet {
            mutationSink.didMutate("projectDrawings")
            projectDrawingsByProjectID = regroupActivity(
                projectDrawings, previous: projectDrawingsByProjectID,
                projectID: { $0.projectId }, activityEqual: ProjectActivityIndexBuilder.hasSameActivity
            )
            rebuildProjectActivityIndex()
            refreshFileSearchVersion()
        }
    }
    private(set) var projectContacts: [ProjectContact] = [] {
        didSet {
            mutationSink.didMutate("projectContacts")
            projectContactsByProjectID = Self.groupedContactsByLinkedProjectID(projectContacts)
        }
    }
    private(set) var projectFinancialRecords: [ProjectFinancialRecord] = [] {
        didSet {
            mutationSink.didMutate("projectFinancialRecords")
            projectFinancialRecordsByProjectID = regroupActivity(
                projectFinancialRecords, previous: projectFinancialRecordsByProjectID,
                projectID: { $0.projectId }, activityEqual: ProjectActivityIndexBuilder.hasSameActivity
            )
            rebuildProjectActivityIndex()
            refreshDueReminderVersion()
        }
    }
    private(set) var projectDocuments: [ProjectDocument] = [] {
        didSet {
            mutationSink.didMutate("projectDocuments")
            projectDocumentsByProjectID = regroupActivity(
                projectDocuments, previous: projectDocumentsByProjectID,
                projectID: { $0.projectId }, activityEqual: ProjectActivityIndexBuilder.hasSameActivity
            )
            rebuildProjectActivityIndex()
            refreshFileSearchVersion()
        }
    }
    private(set) var quickNotes: [QuickNote] = [] {
        didSet {
            mutationSink.didMutate("quickNotes")
            quickNotesByProjectID = regroupActivity(
                quickNotes, previous: quickNotesByProjectID,
                projectID: { $0.projectId }, activityEqual: ProjectActivityIndexBuilder.hasSameActivity
            )
            rebuildProjectActivityIndex()
            refreshFileSearchVersion()
        }
    }
    private(set) var projectWarehouseMovements: [ProjectWarehouseMovement] = [] {
        didSet {
            mutationSink.didMutate("projectWarehouseMovements")
            projectWarehouseMovementsByProjectID = regroupActivity(
                projectWarehouseMovements, previous: projectWarehouseMovementsByProjectID,
                projectID: { $0.projectId }, activityEqual: ProjectActivityIndexBuilder.hasSameActivity
            )
            rebuildProjectActivityIndex()
        }
    }

    private(set) var dailyLogsByProjectID: [UUID: [DailyLog]] = [:]
    private(set) var progressTasksByProjectID: [UUID: [ProgressTask]] = [:]
    private(set) var siteTodosByProjectID: [UUID: [SiteTodo]] = [:]
    private(set) var projectDrawingsByProjectID: [UUID: [ProjectDrawing]] = [:]
    private(set) var projectContactsByProjectID: [UUID: [ProjectContact]] = [:]
    private(set) var projectFinancialRecordsByProjectID: [UUID: [ProjectFinancialRecord]] = [:]
    private(set) var projectDocumentsByProjectID: [UUID: [ProjectDocument]] = [:]
    private(set) var quickNotesByProjectID: [UUID: [QuickNote]] = [:]
    private(set) var projectWarehouseMovementsByProjectID: [UUID: [ProjectWarehouseMovement]] = [:]
    private(set) var activeOrPausedProjectIDs: Set<UUID> = []
    private(set) var activeOrPausedProjectCount = 0
    private(set) var missingTodayLogActiveProjectCount = 0
    private(set) var fileSearchVersion = 0
    private(set) var dueReminderVersion = 0

    private(set) var projectActivityIndexByID: [UUID: ProjectActivitySummary] = [:]
    private(set) var todayLogProjectIDs: Set<UUID> = []
    private(set) var dayContext: ProjectDayContext
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: () -> Calendar

    private static func groupedContactsByLinkedProjectID(_ contacts: [ProjectContact]) -> [UUID: [ProjectContact]] {
        var grouped: [UUID: [ProjectContact]] = [:]
        for contact in contacts {
            for projectID in contact.allProjectIDs {
                grouped[projectID, default: []].append(contact)
            }
        }
        return grouped
    }

    init(
        now: @escaping () -> Date = Date.init,
        calendar: @escaping () -> Calendar = { .current },
        mutationSink: DomainStoreMutationSink? = nil
    ) {
        self.mutationSink = mutationSink ?? DomainStoreMutationSink()
        self.now = now
        self.calendar = calendar
        dayContext = ProjectDayContext(now: now(), calendar: calendar())
        rebuildProjectActivityIndex()
    }

    var totalOverdueItemCount: Int {
        projectActivityIndexByID.values.reduce(0) { $0 + $1.overdueItemCount }
    }

    func projectActivitySummary(for projectId: UUID) -> ProjectActivitySummary {
        projectActivityIndexByID[projectId] ?? ProjectActivitySummary()
    }

    func dailyLogs(for projectId: UUID) -> [DailyLog] {
        dailyLogsByProjectID[projectId] ?? []
    }

    func progressTasks(for projectId: UUID) -> [ProgressTask] {
        progressTasksByProjectID[projectId] ?? []
    }

    func siteTodos(for projectId: UUID) -> [SiteTodo] {
        siteTodosByProjectID[projectId] ?? []
    }

    func projectDrawings(for projectId: UUID) -> [ProjectDrawing] {
        projectDrawingsByProjectID[projectId] ?? []
    }

    func projectContacts(for projectId: UUID) -> [ProjectContact] {
        projectContactsByProjectID[projectId] ?? []
    }

    func projectFinancialRecords(for projectId: UUID) -> [ProjectFinancialRecord] {
        projectFinancialRecordsByProjectID[projectId] ?? []
    }

    func projectDocuments(for projectId: UUID) -> [ProjectDocument] {
        projectDocumentsByProjectID[projectId] ?? []
    }

    func quickNotes(for projectId: UUID) -> [QuickNote] {
        quickNotesByProjectID[projectId] ?? []
    }

    func projectWarehouseMovements(for projectId: UUID) -> [ProjectWarehouseMovement] {
        projectWarehouseMovementsByProjectID[projectId] ?? []
    }

    /// Only the assigned collection is grouped. Compare the exact inputs consumed by the
    /// activity builder; unrelated edits still update full record queries and persistence.
    private func regroupActivity<Value>(
        _ values: [Value], previous: [UUID: [Value]],
        projectID: (Value) -> UUID?, activityEqual: (Value, Value) -> Bool
    ) -> [UUID: [Value]] {
        let grouped = Self.groupedByProjectID(values, projectID: projectID)
        for id in Set(previous.keys).union(grouped.keys) {
            if !(previous[id] ?? []).elementsEqual(grouped[id] ?? [], by: activityEqual) {
                affectedActivityProjectIDs.insert(id)
            }
        }
        return grouped
    }

    private func rebuildProjectActivityIndex(dayContext context: ProjectDayContext? = nil) {
        guard batchDepth == 0 else {
            activityRebuildPending = true
            return
        }
        activityRebuildPending = false
        activityIndexBuildCount &+= 1
        let nextContext = context ?? ProjectDayContext(now: now(), calendar: calendar())
        let rebuildAll = needsFullActivityRebuild || nextContext != dayContext
        var builder = ProjectActivityIndexBuilder(context: applyDayContext(nextContext))
        let affectedIDs = affectedActivityProjectIDs
        if rebuildAll {
            builder.add(dailyLogs)
            builder.add(progressTasks)
            builder.add(siteTodos)
            // Documents must precede finance: reverse receipt links belong to the project.
            builder.add(projectDocuments)
            builder.add(projectDrawings)
            builder.add(projectFinancialRecords)
            builder.add(projectWarehouseMovements)
            builder.add(quickNotes)
            lastActivityIndexRebuiltProjectCount = Set(projectActivityIndexByID.keys).union(builder.summaries.keys).count
            projectActivityIndexByID = builder.summaries
            todayLogProjectIDs = builder.todayProjectIDs
        } else {
            for id in affectedIDs {
                builder.add(dailyLogsByProjectID[id] ?? [])
                builder.add(progressTasksByProjectID[id] ?? [])
                builder.add(siteTodosByProjectID[id] ?? [])
                builder.add(projectDocumentsByProjectID[id] ?? [])
                builder.add(projectDrawingsByProjectID[id] ?? [])
                builder.add(projectFinancialRecordsByProjectID[id] ?? [])
                builder.add(projectWarehouseMovementsByProjectID[id] ?? [])
                builder.add(quickNotesByProjectID[id] ?? [])
            }
            // Assigning nil removes the summary when a project's final record is removed.
            for id in affectedIDs {
                projectActivityIndexByID[id] = builder.summaries[id]
                if builder.todayProjectIDs.contains(id) {
                    todayLogProjectIDs.insert(id)
                } else {
                    todayLogProjectIDs.remove(id)
                }
            }
            lastActivityIndexRebuiltProjectCount = affectedIDs.count
        }
        needsFullActivityRebuild = false
        affectedActivityProjectIDs.removeAll(keepingCapacity: true)
        lastActivityIndexProcessedRecordCount = builder.processedRecordCount
        activityIndexProcessedRecordCount &+= builder.processedRecordCount
        activityIndexRebuiltProjectCount &+= lastActivityIndexRebuiltProjectCount
        refreshMissingTodayLogCount()
    }

    var dashboardCollectionVersions: [String: UInt64] { mutationSink.versions }

    private func refreshProjectStatusIndex() {
        activeOrPausedProjectIDs = Set(
            projects.lazy
                .filter { $0.status == .active || $0.status == .paused }
                .map(\.id)
        )
        activeOrPausedProjectCount = activeOrPausedProjectIDs.count
        refreshMissingTodayLogCount()
    }

    private func refreshFileSearchVersion() {
        fileSearchVersion &+= 1
    }

    private static func groupedByProjectID<Value>(
        _ values: [Value],
        projectID: (Value) -> UUID?
    ) -> [UUID: [Value]] {
        var grouped: [UUID: [Value]] = [:]
        grouped.reserveCapacity(32)
        for value in values {
            guard let id = projectID(value) else { continue }
            grouped[id, default: []].append(value)
        }
        return grouped
    }

    func setProjects(_ value: [Project]) { projects = value }
    func setDailyLogs(_ value: [DailyLog]) { dailyLogs = value }
    func setHistoryRecords(_ value: [HistoryRecord]) { historyRecords = value }
    func setProgressTasks(_ value: [ProgressTask]) { progressTasks = value }
    func setSiteTodos(_ value: [SiteTodo]) { siteTodos = value }
    func setProjectDrawings(_ value: [ProjectDrawing]) { projectDrawings = value }
    func setProjectContacts(_ value: [ProjectContact]) { projectContacts = value }
    func setProjectFinancialRecords(_ value: [ProjectFinancialRecord]) { projectFinancialRecords = value }
    func setProjectDocuments(_ value: [ProjectDocument]) { projectDocuments = value }
    func setQuickNotes(_ value: [QuickNote]) { quickNotes = value }
    func setProjectWarehouseMovements(_ value: [ProjectWarehouseMovement]) { projectWarehouseMovements = value }
}

// Calendar transitions only invalidate derived indexes and notification snapshots.
extension ProjectStore {
    /// Refresh derived UI state only. Advancing the day never edits or saves business records.
    @discardableResult
    func refreshDateSensitiveStateIfNeeded() -> Bool {
        let nextContext = ProjectDayContext(now: now(), calendar: calendar())
        guard nextContext != dayContext else { return false }
        rebuildProjectActivityIndex(dayContext: nextContext)
        return true
    }

    var secondsUntilNextDay: TimeInterval {
        let instant = now()
        let context = ProjectDayContext(now: instant, calendar: calendar())
        return max(context.nextDayStart.timeIntervalSince(instant), 1)
    }

    private func refreshDueReminderVersion() {
        dueReminderVersion &+= 1
    }

    func hasTodayLog(for projectId: UUID) -> Bool {
        refreshDateSensitiveStateIfNeeded()
        return todayLogProjectIDs.contains(projectId)
    }

    private func refreshMissingTodayLogCount() {
        missingTodayLogActiveProjectCount = activeOrPausedProjectIDs.subtracting(todayLogProjectIDs).count
    }

    private func applyDayContext(_ suppliedContext: ProjectDayContext?) -> ProjectDayContext {
        let context = suppliedContext ?? ProjectDayContext(now: now(), calendar: calendar())
        if dayContext != context {
            dayContext = context
            refreshDueReminderVersion()
        }
        return context
    }
}

@MainActor
@Observable
final class MaterialLibraryStore {
    @ObservationIgnored private let mutationSink: DomainStoreMutationSink

    init(mutationSink: DomainStoreMutationSink? = nil) {
        self.mutationSink = mutationSink ?? DomainStoreMutationSink()
    }
    private(set) var templates: [ProjectTemplate] = [] {
        didSet { mutationSink.didMutate("templates") }
    }
    private(set) var materialPriceEntries: [MaterialPriceEntry] = [] {
        didSet { mutationSink.didMutate("materialPriceEntries") }
    }
    private(set) var materialSheetDrafts: [MaterialSheetDraft] = [] {
        didSet {
            mutationSink.didMutate("materialSheetDrafts")
            materialSheetDraftsByProjectID = Self.groupedByProjectID(materialSheetDrafts) { $0.projectId }
            materialSheetDraftCountByProjectID = Self.buildCountMap(materialSheetDraftsByProjectID)
        }
    }
    private(set) var supplierProfiles: [SupplierProfile] = [] {
        didSet { mutationSink.didMutate("supplierProfiles") }
    }
    private(set) var constructionMethods: [ConstructionMethod] = [] {
        didSet { mutationSink.didMutate("constructionMethods") }
    }
    private(set) var userMaterials: [UserMaterial] = [] {
        didSet { mutationSink.didMutate("userMaterials") }
    }
    private(set) var deletedUserMaterials: [UserMaterial] = [] {
        didSet { mutationSink.didMutate("deletedUserMaterials") }
    }
    private(set) var materialSheetDraftsByProjectID: [UUID: [MaterialSheetDraft]] = [:]
    private(set) var materialSheetDraftCountByProjectID: [UUID: Int] = [:]

    func materialSheetDrafts(for projectId: UUID) -> [MaterialSheetDraft] {
        materialSheetDraftsByProjectID[projectId] ?? []
    }

    func materialSheetDraftCount(for projectId: UUID) -> Int {
        materialSheetDraftCountByProjectID[projectId] ?? 0
    }

    private static func groupedByProjectID<Value>(
        _ values: [Value],
        projectID: (Value) -> UUID?
    ) -> [UUID: [Value]] {
        var grouped: [UUID: [Value]] = [:]
        grouped.reserveCapacity(32)
        for value in values {
            guard let id = projectID(value) else { continue }
            grouped[id, default: []].append(value)
        }
        return grouped
    }

    private static func buildCountMap<Value>(
        _ groupedValues: [UUID: [Value]]
    ) -> [UUID: Int] {
        var countMap: [UUID: Int] = [:]
        countMap.reserveCapacity(groupedValues.count)
        for (projectId, values) in groupedValues {
            countMap[projectId] = values.count
        }
        return countMap
    }

    func setTemplates(_ value: [ProjectTemplate]) { templates = value }
    func setMaterialPriceEntries(_ value: [MaterialPriceEntry]) { materialPriceEntries = value }
    func setMaterialSheetDrafts(_ value: [MaterialSheetDraft]) { materialSheetDrafts = value }
    func setSupplierProfiles(_ value: [SupplierProfile]) { supplierProfiles = value }
    func setConstructionMethods(_ value: [ConstructionMethod]) { constructionMethods = value }
    func setUserMaterials(_ value: [UserMaterial]) { userMaterials = value }
    func setDeletedUserMaterials(_ value: [UserMaterial]) { deletedUserMaterials = value }
}

@MainActor
@Observable
final class MaterialLibraryPreferencesStore {
    @ObservationIgnored private let mutationSink: DomainStoreMutationSink

    init(mutationSink: DomainStoreMutationSink? = nil) {
        self.mutationSink = mutationSink ?? DomainStoreMutationSink()
    }
    private(set) var favoriteMaterialKeys: [String] = [] {
        didSet { mutationSink.didMutate("favoriteMaterialKeys") }
    }
    private(set) var recentMaterialKeys: [String] = [] {
        didSet { mutationSink.didMutate("recentMaterialKeys") }
    }
    private(set) var hiddenPresetKeys: Set<String> = [] {
        didSet { mutationSink.didMutate("hiddenPresetKeys") }
    }

    func setFavoriteMaterialKeys(_ value: [String]) { favoriteMaterialKeys = value }
    func setRecentMaterialKeys(_ value: [String]) { recentMaterialKeys = value }
    func setHiddenPresetKeys(_ value: Set<String>) { hiddenPresetKeys = value }
}
