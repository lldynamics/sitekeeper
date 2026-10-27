import Foundation

/// Only inputs used by the dashboard summary participate in invalidation. Collection
/// revisions are maintained at the write boundary, so cache hits never hash records.
struct DashboardSummaryRevision: Equatable {
    let projectSource: ObjectIdentifier
    let financeSource: ObjectIdentifier
    let projectVersions: [UInt64]
    let financeVersions: [UInt64]
    let dayContext: ProjectDayContext
    let priceSpikeThreshold: Double
    let ignoredPriceSpikeKeys: Set<String>

    @MainActor
    init(projectStore: ProjectStore, financeStore: FinanceStore) {
        projectSource = ObjectIdentifier(projectStore)
        financeSource = ObjectIdentifier(financeStore)
        let project = projectStore.dashboardCollectionVersions
        projectVersions = [
            "projects", "dailyLogs", "siteTodos", "progressTasks",
            "projectFinancialRecords", "projectDocuments", "projectWarehouseMovements"
        ].map { project[$0, default: 0] }
        let finance = financeStore.dashboardCollectionVersions
        financeVersions = ["materialItems", "quoteItems", "laborRecords"].map { finance[$0, default: 0] }
        dayContext = projectStore.dayContext
        priceSpikeThreshold = financeStore.materialPriceSpikeThreshold
        ignoredPriceSpikeKeys = financeStore.ignoredMaterialPriceSpikeKeys
    }
}

/// Copy-on-write input values isolate calculation from stores and make the cold path
/// directly benchmarkable. Per-project finance and warehouse indexes are reused.
struct DashboardSummaryInput {
    let dayContext: ProjectDayContext
    var projects: [Project] = []
    var dailyLogs: [DailyLog] = []
    var siteTodos: [SiteTodo] = []
    var progressTasks: [ProgressTask] = []
    var financialRecords: [ProjectFinancialRecord] = []
    var documents: [ProjectDocument] = []
    var warehouseMovements: [ProjectWarehouseMovement] = []
    var materialsByProjectID: [UUID: [MaterialItem]] = [:]
    var quotesByProjectID: [UUID: [QuoteItem]] = [:]
    var laborByProjectID: [UUID: [LaborRecord]] = [:]
    var financialRecordsByProjectID: [UUID: [ProjectFinancialRecord]] = [:]
    var warehouseMovementsByProjectID: [UUID: [ProjectWarehouseMovement]] = [:]
    var materialPriceSpikeCountByProjectID: [UUID: Int] = [:]

    init(dayContext: ProjectDayContext) {
        self.dayContext = dayContext
    }

    @MainActor
    init(projectStore: ProjectStore, financeStore: FinanceStore) {
        dayContext = projectStore.dayContext
        projects = projectStore.projects
        dailyLogs = projectStore.dailyLogs
        siteTodos = projectStore.siteTodos
        progressTasks = projectStore.progressTasks
        financialRecords = projectStore.projectFinancialRecords
        documents = projectStore.projectDocuments
        warehouseMovements = projectStore.projectWarehouseMovements
        materialsByProjectID = financeStore.materialItemsByProjectID
        quotesByProjectID = financeStore.quoteItemsByProjectID
        laborByProjectID = financeStore.laborRecordsByProjectID
        financialRecordsByProjectID = projectStore.projectFinancialRecordsByProjectID
        warehouseMovementsByProjectID = projectStore.projectWarehouseMovementsByProjectID
        materialPriceSpikeCountByProjectID = financeStore.materialPriceSpikeCountByProjectID
    }
}

struct DashboardSummaryModel {
    let activeProjects: [Project]
    let activeProjectIDs: Set<UUID>
    let projectNameByID: [UUID: String]
    let todayLogs: [DailyLog]
    let openTodos: [SiteTodo]
    let todayTodos: [SiteTodo]
    let overdueTasks: [ProgressTask]
    let overdueTodos: [SiteTodo]
    let activeFinancialRecords: [ProjectFinancialRecord]
    let businessSummary: ProjectBusinessSummary
    let warehouseMovements: [ProjectWarehouseMovement]
    let warehouseStockLines: [WarehouseStockLine]
    let warehouseTodayMovementCount: Int
    let warehouseNegativeCount: Int
    let recentWarehouseMovements: [ProjectWarehouseMovement]
    let projectsWithoutTodayLogCount: Int
    let unattachedReceiptCount: Int
    let unsettledFinancialCount: Int
    let materialPriceSpikeCount: Int
}

/// View-owned, bounded to one revision. The synchronous main-actor refresh has no
/// suspended work that could publish an old result after a newer revision.
@MainActor
final class DashboardSummaryCache {
    private var revision: DashboardSummaryRevision?
    private var summary: DashboardSummaryModel?
    private(set) var buildCount = 0

    func value(
        revision: DashboardSummaryRevision,
        input: () -> DashboardSummaryInput
    ) -> DashboardSummaryModel {
        if self.revision == revision, let summary { return summary }
        let next = DashboardSummaryBuilder.build(input())
        self.revision = revision
        summary = next
        buildCount += 1
        return next
    }
}
