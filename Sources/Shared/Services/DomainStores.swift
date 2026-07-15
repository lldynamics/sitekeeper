import Foundation
import Observation

struct ProjectActivitySummary {
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
    var collectedIncomeAmount = 0.0
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
    private(set) var projects: [Project] = [] {
        didSet {
            refreshProjectStatusIndex()
            refreshFileSearchVersion()
        }
    }
    private(set) var dailyLogs: [DailyLog] = [] {
        didSet {
            dailyLogsByProjectID = Self.groupedByProjectID(dailyLogs) { $0.projectId }
            rebuildProjectActivityIndex()
            refreshFileSearchVersion()
        }
    }
    private(set) var historyRecords: [HistoryRecord] = []
    private(set) var progressTasks: [ProgressTask] = [] {
        didSet {
            progressTasksByProjectID = Self.groupedByProjectID(progressTasks) { $0.projectId }
            rebuildProjectActivityIndex()
        }
    }
    private(set) var siteTodos: [SiteTodo] = [] {
        didSet {
            siteTodosByProjectID = Self.groupedByProjectID(siteTodos) { $0.projectId }
            rebuildProjectActivityIndex()
            refreshFileSearchVersion()
            refreshDueReminderVersion()
        }
    }
    private(set) var projectDrawings: [ProjectDrawing] = [] {
        didSet {
            projectDrawingsByProjectID = Self.groupedByProjectID(projectDrawings) { $0.projectId }
            rebuildProjectActivityIndex()
            refreshFileSearchVersion()
        }
    }
    private(set) var projectContacts: [ProjectContact] = [] {
        didSet {
            projectContactsByProjectID = Self.groupedContactsByLinkedProjectID(projectContacts)
        }
    }
    private(set) var projectFinancialRecords: [ProjectFinancialRecord] = [] {
        didSet {
            projectFinancialRecordsByProjectID = Self.groupedByProjectID(projectFinancialRecords) { $0.projectId }
            rebuildProjectActivityIndex()
            refreshDueReminderVersion()
        }
    }
    private(set) var projectDocuments: [ProjectDocument] = [] {
        didSet {
            projectDocumentsByProjectID = Self.groupedByProjectID(projectDocuments) { $0.projectId }
            rebuildProjectActivityIndex()
            refreshFileSearchVersion()
        }
    }
    private(set) var quickNotes: [QuickNote] = [] {
        didSet {
            quickNotesByProjectID = Self.groupedByProjectID(quickNotes) { $0.projectId }
            rebuildProjectActivityIndex()
            refreshFileSearchVersion()
        }
    }
    private(set) var projectWarehouseMovements: [ProjectWarehouseMovement] = [] {
        didSet {
            projectWarehouseMovementsByProjectID = Self.groupedByProjectID(projectWarehouseMovements) { $0.projectId }
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
    private var todayLogCacheDateKey = ""

    private static func groupedContactsByLinkedProjectID(_ contacts: [ProjectContact]) -> [UUID: [ProjectContact]] {
        var grouped: [UUID: [ProjectContact]] = [:]
        for contact in contacts {
            for projectID in contact.allProjectIDs {
                grouped[projectID, default: []].append(contact)
            }
        }
        return grouped
    }

    init() {
        rebuildProjectActivityIndex()
    }

    private func refreshDueReminderVersion() {
        dueReminderVersion &+= 1
    }

    var totalOpenTodoCount: Int {
        projectActivityIndexByID.values.reduce(0) { $0 + $1.openTodoCount }
    }

    var totalOverdueItemCount: Int {
        projectActivityIndexByID.values.reduce(0) { $0 + $1.overdueItemCount }
    }

    var totalUnattachedReceiptCount: Int {
        projectActivityIndexByID.values.reduce(0) { $0 + $1.unattachedReceiptCount }
    }

    var totalUnsettledFinancialCount: Int {
        projectActivityIndexByID.values.reduce(0) { $0 + $1.unsettledFinancialCount }
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

    func hasTodayLog(for projectId: UUID) -> Bool {
        refreshTodayLogCacheIfNeeded()
        return todayLogProjectIDs.contains(projectId)
    }

    func hasLinkedFinancialDocument(for recordId: UUID, in projectId: UUID) -> Bool {
        projectActivityIndexByID[projectId]?.linkedFinancialRecordIDs.contains(recordId) == true
    }

    private func rebuildProjectActivityIndex() {
        let today = Formatters.date.string(from: Date())
        let todayStart = Calendar.current.startOfDay(for: Date())
        var nextIndex: [UUID: ProjectActivitySummary] = [:]
        var nextTodayProjectIDs: Set<UUID> = []

        for log in dailyLogs {
            guard let projectId = log.projectId else { continue }
            var summary = nextIndex[projectId] ?? ProjectActivitySummary()
            summary.dailyLogCount += 1
            if log.date == today {
                nextTodayProjectIDs.insert(projectId)
            }
            if let logDate = Formatters.date.date(from: log.date) {
                summary.latestDailyLogDate = Self.maxDate(summary.latestDailyLogDate, logDate)
            }
            nextIndex[projectId] = summary
        }

        for task in progressTasks {
            var summary = nextIndex[task.projectId] ?? ProjectActivitySummary()
            summary.progressTaskCount += 1
            if let startDate = Formatters.date.date(from: task.startDate) {
                summary.latestProgressDate = Self.maxDate(summary.latestProgressDate, startDate)
            }
            if let dueDate = Formatters.date.date(from: task.dueDate) {
                summary.latestProgressDate = Self.maxDate(summary.latestProgressDate, dueDate)
                if task.clampedCompletion < 1, dueDate < todayStart {
                    summary.overdueProgressCount += 1
                }
            }
            nextIndex[task.projectId] = summary
        }

        for todo in siteTodos {
            guard let projectId = todo.projectId else { continue }
            var summary = nextIndex[projectId] ?? ProjectActivitySummary()
            summary.todoCount += 1
            if !todo.isDone {
                summary.openTodoCount += 1
            }
            if todo.isOverdue {
                summary.overdueTodoCount += 1
            }
            if let dueDate = Formatters.date.date(from: todo.dueDate) {
                summary.latestTodoDate = Self.maxDate(summary.latestTodoDate, dueDate)
            }
            nextIndex[projectId] = summary
        }

        for document in projectDocuments {
            var summary = nextIndex[document.projectId] ?? ProjectActivitySummary()
            summary.documentCount += 1
            if let createdAt = Formatters.dateTime.date(from: document.createdAt) ?? Formatters.date.date(from: document.createdAt) {
                summary.latestDocumentDate = Self.maxDate(summary.latestDocumentDate, createdAt)
            }
            if let linkedFinancialRecordId = document.linkedFinancialRecordId {
                summary.linkedFinancialRecordIDs.insert(linkedFinancialRecordId)
            }
            nextIndex[document.projectId] = summary
        }

        for drawing in projectDrawings {
            var summary = nextIndex[drawing.projectId] ?? ProjectActivitySummary()
            if let importedAt = Formatters.parseDateOrDateTime(drawing.importedAt) {
                summary.latestDrawingDate = Self.maxDate(summary.latestDrawingDate, importedAt)
            }
            nextIndex[drawing.projectId] = summary
        }

        for record in projectFinancialRecords {
            var summary = nextIndex[record.projectId] ?? ProjectActivitySummary()
            if let financialAt = Formatters.parseDateOrDateTime(record.date) {
                summary.latestFinancialDate = Self.maxDate(summary.latestFinancialDate, financialAt)
            }
            if record.countsInBusinessMetrics, record.isCollectionIncome {
                summary.collectedIncomeAmount += record.amountValue.doubleValue
            }
            if record.requiresAttachment {
                let linkedByList = !record.linkedDocumentIds.isEmpty
                let linkedByDocument = summary.linkedFinancialRecordIDs.contains(record.id)
                if !(linkedByList || linkedByDocument) {
                    summary.unattachedReceiptCount += 1
                }
            }
            if record.normalizedStatus == .active,
               !record.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                summary.unsettledFinancialCount += 1
            }
            nextIndex[record.projectId] = summary
        }

        for movement in projectWarehouseMovements {
            var summary = nextIndex[movement.projectId] ?? ProjectActivitySummary()
            if let movementAt = Formatters.parseDateOrDateTime(movement.date) {
                summary.latestWarehouseDate = Self.maxDate(summary.latestWarehouseDate, movementAt)
            }
            nextIndex[movement.projectId] = summary
        }

        for note in quickNotes {
            guard let projectId = note.projectId else { continue }
            var summary = nextIndex[projectId] ?? ProjectActivitySummary()
            if let noteAt = Formatters.parseDateOrDateTime(note.createdAt) {
                summary.latestQuickNoteDate = Self.maxDate(summary.latestQuickNoteDate, noteAt)
            }
            nextIndex[projectId] = summary
        }

        projectActivityIndexByID = nextIndex
        todayLogProjectIDs = nextTodayProjectIDs
        todayLogCacheDateKey = today
        refreshMissingTodayLogCount()
    }

    private func refreshTodayLogCacheIfNeeded() {
        let today = Formatters.date.string(from: Date())
        guard todayLogCacheDateKey != today else { return }
        var nextTodayProjectIDs: Set<UUID> = []
        for log in dailyLogs where log.date == today {
            if let projectId = log.projectId {
                nextTodayProjectIDs.insert(projectId)
            }
        }
        todayLogProjectIDs = nextTodayProjectIDs
        todayLogCacheDateKey = today
        refreshMissingTodayLogCount()
    }

    private func refreshProjectStatusIndex() {
        activeOrPausedProjectIDs = Set(
            projects.lazy
                .filter { $0.status == .active || $0.status == .paused }
                .map(\.id)
        )
        activeOrPausedProjectCount = activeOrPausedProjectIDs.count
        refreshMissingTodayLogCount()
    }

    private func refreshMissingTodayLogCount() {
        missingTodayLogActiveProjectCount = activeOrPausedProjectIDs.subtracting(todayLogProjectIDs).count
    }

    private func refreshFileSearchVersion() {
        fileSearchVersion &+= 1
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs else { return rhs }
        return max(lhs, rhs)
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

@MainActor
@Observable
final class MaterialLibraryStore {
    private(set) var templates: [ProjectTemplate] = []
    private(set) var materialPriceEntries: [MaterialPriceEntry] = []
    private(set) var materialSheetDrafts: [MaterialSheetDraft] = [] {
        didSet {
            materialSheetDraftsByProjectID = Self.groupedByProjectID(materialSheetDrafts) { $0.projectId }
            materialSheetDraftCountByProjectID = Self.buildCountMap(materialSheetDraftsByProjectID)
        }
    }
    private(set) var supplierProfiles: [SupplierProfile] = []
    private(set) var constructionMethods: [ConstructionMethod] = []
    private(set) var userMaterials: [UserMaterial] = []
    private(set) var deletedUserMaterials: [UserMaterial] = []
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
final class UserPreferenceStore {
    private(set) var favoriteMaterialKeys: [String] = []
    private(set) var recentMaterialKeys: [String] = []
    private(set) var hiddenPresetKeys: Set<String> = []

    func setFavoriteMaterialKeys(_ value: [String]) { favoriteMaterialKeys = value }
    func setRecentMaterialKeys(_ value: [String]) { recentMaterialKeys = value }
    func setHiddenPresetKeys(_ value: Set<String>) { hiddenPresetKeys = value }
}
