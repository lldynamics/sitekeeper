import SwiftUI

extension DashboardView {
    var todayDay: CalendarDay { projectStore.dayContext.day }

    var dashboardSummaryRevision: DashboardSummaryRevision {
        DashboardSummaryRevision(projectStore: projectStore, financeStore: financeStore)
    }

    var dashboardSummary: DashboardSummaryModel {
        dashboardSummaryCache.value(revision: dashboardSummaryRevision) {
            DashboardSummaryInput(projectStore: projectStore, financeStore: financeStore)
        }
    }

    var activeProjects: [Project] { dashboardSummary.activeProjects }
    var activeProjectIDs: Set<UUID> { dashboardSummary.activeProjectIDs }
    var projectNameByID: [UUID: String] { dashboardSummary.projectNameByID }
    var todayLogs: [DailyLog] { dashboardSummary.todayLogs }
    var openTodos: [SiteTodo] { dashboardSummary.openTodos }
    var todayTodos: [SiteTodo] { dashboardSummary.todayTodos }
    var overdueTasks: [ProgressTask] { dashboardSummary.overdueTasks }
    var overdueTodos: [SiteTodo] { dashboardSummary.overdueTodos }
    var activeFinancialRecords: [ProjectFinancialRecord] { dashboardSummary.activeFinancialRecords }
    var dashboardBusinessSummary: ProjectBusinessSummary { dashboardSummary.businessSummary }
    var warehouseMovementsForActiveProjects: [ProjectWarehouseMovement] { dashboardSummary.warehouseMovements }
    var warehouseStockLines: [WarehouseStockLine] { dashboardSummary.warehouseStockLines }
    var warehouseTodayMovementCount: Int { dashboardSummary.warehouseTodayMovementCount }
    var warehouseNegativeCount: Int { dashboardSummary.warehouseNegativeCount }
    var recentWarehouseMovements: [ProjectWarehouseMovement] { dashboardSummary.recentWarehouseMovements }

    var currentProject: Project? {
        if let selectedProjectId = UUID(uuidString: selectedProjectIdRaw),
           let selected = activeProjects.first(where: { $0.id == selectedProjectId }) {
            return selected
        }
        return activeProjects.count == 1 ? activeProjects.first : nil
    }

    var rankedDashboardProjectRows: [DashboardProjectRow] {
        activeProjects
            .map(dashboardProjectRow(for:))
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.activityDate != rhs.activityDate { return lhs.activityDate > rhs.activityDate }
                return lhs.project.name.localizedStandardCompare(rhs.project.name) == .orderedAscending
            }
    }

    var dashboardVisibleProjectRows: [DashboardProjectRow] {
        let ranked = rankedDashboardProjectRows
        var visible = Array(ranked.prefix(dashboardProjectDisplayLimit))
        if let currentProject,
           !visible.contains(where: { $0.project.id == currentProject.id }),
           let currentRow = ranked.first(where: { $0.project.id == currentProject.id }) {
            visible = [currentRow] + Array(ranked.filter { $0.project.id != currentProject.id }.prefix(max(dashboardProjectDisplayLimit - 1, 0)))
        }
        return visible
    }

    var hiddenDashboardProjectCount: Int {
        max(activeProjects.count - dashboardVisibleProjectRows.count, 0)
    }

    var logEntryDestination: DashboardDestination {
        .dailyLog(initialProjectId: currentProject?.id, autoOpenComposer: true)
    }

    var todoEntryDestination: DashboardDestination {
        .siteTodo(initialProjectId: currentProject?.id, autoOpenComposer: true)
    }

    var photoEntryDestination: DashboardDestination {
        .watermarkCamera(initialProjectId: currentProject?.id, autoOpenCameraOnAppear: true)
    }

    var bookkeepingEntryDestination: DashboardDestination {
        if let project = currentProject {
            return .projectDetail(projectId: project.id, autoOpenFinancialAdd: true)
        }
        if activeProjects.count > 1 {
            return .bookkeepingProjectPicker(projects: activeProjects)
        }
        return .projectList()
    }

    var warehouseOverviewDestination: DashboardDestination {
        .warehouseOverview
    }

    var warehouseMovementDestination: DashboardDestination {
        if let project = currentProject {
            return .warehouse(project: project)
        }
        return .warehouseOverview
    }

    var overdueCount: Int {
        overdueTasks.count + overdueTodos.count
    }

    var projectsWithoutTodayLogCount: Int { dashboardSummary.projectsWithoutTodayLogCount }
    var unattachedReceiptCount: Int { dashboardSummary.unattachedReceiptCount }
    var unsettledFinancialCount: Int { dashboardSummary.unsettledFinancialCount }
    var materialPriceSpikeCount: Int { dashboardSummary.materialPriceSpikeCount }

    var usesWideDashboardLayout: Bool {
        horizontalSizeClass == .regular
    }
}
