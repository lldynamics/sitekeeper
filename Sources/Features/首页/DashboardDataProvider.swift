import SwiftUI

extension DashboardView {
    static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var todayStr: String { Self.localDateFormatter.string(from: Date()) }

    var activeProjects: [Project] {
        projectStore.projects.filter { $0.status == .active || $0.status == .paused }
    }

    var activeProjectIDs: Set<UUID> {
        Set(activeProjects.map(\.id))
    }

    var projectNameByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: projectStore.projects.map { ($0.id, $0.name) })
    }

    var todayLogs: [DailyLog] {
        projectStore.dailyLogs.filter { log in
            log.date == todayStr && (log.projectId.map(activeProjectIDs.contains) ?? true)
        }
    }

    var openTodos: [SiteTodo] {
        projectStore.siteTodos.filter { todo in
            guard !todo.isDone else { return false }
            guard let projectId = todo.projectId else { return false }
            return activeProjectIDs.contains(projectId)
        }
    }

    var todayTodos: [SiteTodo] {
        openTodos.filter { $0.dueDate == todayStr }
    }

    var overdueTasks: [ProgressTask] {
        projectStore.progressTasks.filter { task in
            guard activeProjectIDs.contains(task.projectId),
                  task.clampedCompletion < 1,
                  let due = parseLocalDate(task.dueDate) else { return false }
            return due < Calendar.current.startOfDay(for: Date())
        }
    }

    var overdueTodos: [SiteTodo] {
        openTodos.filter(\.isOverdue)
    }

    var activeFinancialRecords: [ProjectFinancialRecord] {
        projectStore.projectFinancialRecords.filter { activeProjectIDs.contains($0.projectId) }
    }

    var dashboardBusinessSummary: ProjectBusinessSummary {
        guard !activeProjects.isEmpty else {
            return ProjectBusinessSummary(
                quoteTotal: 0,
                contractAmount: 0,
                paidAmount: 0,
                receivableAmount: 0,
                receivableAgeDays: nil,
                recentCollection: nil,
                materialCost: 0,
                laborCostAmount: 0,
                pendingMaterialCount: 0,
                unpricedQuoteCount: 0
            )
        }

        let projectIDs = activeProjectIDs
        let quotes = financeStore.quoteItems.filter { item in
            guard let projectId = item.projectId else { return false }
            return projectIDs.contains(projectId)
        }
        let materials = financeStore.materialItems.filter { item in
            guard let projectId = item.projectId else { return false }
            return projectIDs.contains(projectId)
        }
        let laborRecords = financeStore.laborRecords.filter { item in
            guard let projectId = item.projectId else { return false }
            return projectIDs.contains(projectId)
        }

        let quoteTotal = quotes.reduce(0) { $0 + ReportBuilder.quoteGrandTotal($1) }
        let contractAmount = activeProjects.reduce(0) { $0 + $1.contractAmountValue.doubleValue }
        let paidByRecords = activeProjects.reduce(0) { $0 + dashboardCollectedAmount(for: $1.id) }
        let paidAmountFallback = activeProjects.reduce(0) { $0 + $1.paidAmountValue.doubleValue }
        let paidAmount = paidByRecords > 0 ? paidByRecords : paidAmountFallback

        let materialAutoCost = materials.reduce(0) { $0 + ReportBuilder.materialLineTotal($1) }
        let laborAutoCost = laborRecords.reduce(0) { $0 + ReportBuilder.laborLineTotal($1) }
        let materialFallback = activeProjects.reduce(0) { $0 + $1.materialCostValue.doubleValue }
        let laborFallback = activeProjects.reduce(0) { $0 + $1.laborCostValue.doubleValue }
        let materialCost = materialAutoCost > 0 ? materialAutoCost : materialFallback
        let laborCostAmount = laborAutoCost > 0 ? laborAutoCost : laborFallback

        let receivableAmount = max(contractAmount - paidAmount, 0)
        let receivableAgeDays = activeProjects.compactMap { project -> Int? in
            let projectPaid = dashboardCollectedAmount(for: project.id)
            let paid = projectPaid > 0 ? projectPaid : project.paidAmountValue.doubleValue
            let receivable = max(project.contractAmountValue.doubleValue - paid, 0)
            return dashboardReceivableAgeDays(for: project, receivableAmount: receivable)
        }.max()

        return ProjectBusinessSummary(
            quoteTotal: quoteTotal,
            contractAmount: contractAmount,
            paidAmount: paidAmount,
            receivableAmount: receivableAmount,
            receivableAgeDays: receivableAgeDays,
            recentCollection: dashboardLatestCollection(),
            materialCost: materialCost,
            laborCostAmount: laborCostAmount,
            pendingMaterialCount: materials.filter { $0.quantityValue.doubleValue == 0 }.count,
            unpricedQuoteCount: quotes.filter { $0.unitPriceValue.doubleValue == 0 }.count
        )
    }

    var warehouseMovementsForActiveProjects: [ProjectWarehouseMovement] {
        projectStore.projectWarehouseMovements.filter { activeProjectIDs.contains($0.projectId) }
    }

    var warehouseStockLines: [WarehouseStockLine] {
        activeProjects.flatMap { project in
            WarehouseStockCalculator.stockLines(for: project.id, movements: warehouseMovementsForActiveProjects)
        }
    }

    var warehouseTodayMovementCount: Int {
        warehouseMovementsForActiveProjects.filter { $0.date == todayStr }.count
    }

    var warehouseNegativeCount: Int {
        warehouseStockLines.filter { $0.quantity < 0 }.count
    }

    var recentWarehouseMovements: [ProjectWarehouseMovement] {
        Array(warehouseMovementsForActiveProjects.sorted { $0.createdAt > $1.createdAt }.prefix(3))
    }

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

    var projectsWithoutTodayLogCount: Int {
        activeProjects.filter { project in
            !projectStore.dailyLogs.contains { $0.projectId == project.id && $0.date == todayStr }
        }.count
    }

    var unattachedReceiptCount: Int {
        activeFinancialRecords.filter { record in
            guard record.requiresAttachment else { return false }
            let linkedByRecord = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = projectStore.projectDocuments.contains { $0.linkedFinancialRecordId == record.id }
            return !(linkedByRecord || linkedByDocument)
        }.count
    }

    var unsettledFinancialCount: Int {
        activeFinancialRecords.filter { record in
            record.normalizedStatus == .active && !record.dueDate.isEmpty
        }.count
    }

    var materialPriceSpikeCount: Int {
        activeProjects.reduce(0) { total, project in
            total + financeStore.materialPriceSpikeCount(for: project.id)
        }
    }

    var materialPriceSpikeProjectCount: Int {
        activeProjects.filter { financeStore.materialPriceSpikeCount(for: $0.id) > 0 }.count
    }

    var usesWideDashboardLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
}
