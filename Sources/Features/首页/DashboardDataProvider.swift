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
        let projectIDs = activeProjectIDs
        let today = todayStr
        return projectStore.dailyLogs.filter { log in
            log.date == today && (log.projectId.map(projectIDs.contains) ?? true)
        }
    }

    var openTodos: [SiteTodo] {
        let projectIDs = activeProjectIDs
        return projectStore.siteTodos.filter { todo in
            guard !todo.isDone else { return false }
            guard let projectId = todo.projectId else { return false }
            return projectIDs.contains(projectId)
        }
    }

    var todayTodos: [SiteTodo] {
        let today = todayStr
        return openTodos.filter { $0.dueDate == today }
    }

    var overdueTasks: [ProgressTask] {
        let projectIDs = activeProjectIDs
        let today = Calendar.current.startOfDay(for: Date())
        return projectStore.progressTasks.filter { task in
            guard projectIDs.contains(task.projectId),
                  task.clampedCompletion < 1,
                  let due = parseLocalDate(task.dueDate) else { return false }
            return due < today
        }
    }

    var overdueTodos: [SiteTodo] {
        openTodos.filter(\.isOverdue)
    }

    var activeFinancialRecords: [ProjectFinancialRecord] {
        let projectIDs = activeProjectIDs
        return projectStore.projectFinancialRecords.filter { projectIDs.contains($0.projectId) }
    }

    var dashboardBusinessSummary: ProjectBusinessSummary {
        let projects = activeProjects
        guard !projects.isEmpty else {
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

        // FinanceStore and ProjectStore maintain per-project indexes.  The dashboard
        // renders this summary several times while its panels are composed, so avoid
        // repeatedly filtering every record collection once per active project.
        let quotes = projects.flatMap { financeStore.quoteItems(for: $0.id) }
        let materials = projects.flatMap { financeStore.materialItems(for: $0.id) }
        let laborRecords = projects.flatMap { financeStore.laborRecords(for: $0.id) }
        let financialRecords = projects.flatMap { projectStore.projectFinancialRecords(for: $0.id) }

        var materialCostByProjectID: [UUID: Double] = [:]
        for item in materials {
            guard let projectId = item.projectId else { continue }
            materialCostByProjectID[projectId, default: 0] += ReportBuilder.materialLineTotal(item)
        }
        var laborCostByProjectID: [UUID: Double] = [:]
        for item in laborRecords {
            guard let projectId = item.projectId else { continue }
            laborCostByProjectID[projectId, default: 0] += ReportBuilder.laborLineTotal(item)
        }
        var collectionByProjectID: [UUID: MoneyValue] = [:]
        for record in financialRecords where record.countsInBusinessMetrics && record.isCollectionIncome {
            collectionByProjectID[record.projectId] =
                (collectionByProjectID[record.projectId] ?? MoneyValue.zero) + record.amountValue
        }

        let quoteTotal = quotes.reduce(0) { $0 + ReportBuilder.quoteGrandTotal($1) }
        let contractAmount = projects.reduce(0) { $0 + $1.contractAmountValue.doubleValue }
        let paidAmount = projects.reduce(0) { total, project in
            let recorded = (collectionByProjectID[project.id] ?? MoneyValue.zero).doubleValue
            return total + ProjectFinancialMetrics.effectivePaidAmount(
                recordedCollectionAmount: recorded,
                manualPaidAmount: project.paidAmountValue.doubleValue
            )
        }
        let materialCost = projects.reduce(0) { total, project in
            let recorded = materialCostByProjectID[project.id] ?? 0
            return total + (recorded > 0 ? recorded : project.materialCostValue.doubleValue)
        }
        let laborCostAmount = projects.reduce(0) { total, project in
            let recorded = laborCostByProjectID[project.id] ?? 0
            return total + (recorded > 0 ? recorded : project.laborCostValue.doubleValue)
        }

        let receivableAmount = max(contractAmount - paidAmount, 0)
        let receivableAgeDays = projects.compactMap { project -> Int? in
            let projectPaid = (collectionByProjectID[project.id] ?? MoneyValue.zero).doubleValue
            let paid = ProjectFinancialMetrics.effectivePaidAmount(
                recordedCollectionAmount: projectPaid,
                manualPaidAmount: project.paidAmountValue.doubleValue
            )
            let receivable = max(project.contractAmountValue.doubleValue - paid, 0)
            return dashboardReceivableAgeDays(for: project, receivableAmount: receivable)
        }.max()

        return ProjectBusinessSummary(
            quoteTotal: quoteTotal,
            contractAmount: contractAmount,
            paidAmount: paidAmount,
            receivableAmount: receivableAmount,
            receivableAgeDays: receivableAgeDays,
            recentCollection: ProjectFinancialMetrics.latestCollection(
                records: financialRecords,
                projectName: { projectName($0) }
            ),
            materialCost: materialCost,
            laborCostAmount: laborCostAmount,
            pendingMaterialCount: materials.filter { $0.quantityValue.doubleValue == 0 }.count,
            unpricedQuoteCount: quotes.filter { $0.unitPriceValue.doubleValue == 0 }.count
        )
    }

    var warehouseMovementsForActiveProjects: [ProjectWarehouseMovement] {
        let projectIDs = activeProjectIDs
        return projectStore.projectWarehouseMovements.filter { projectIDs.contains($0.projectId) }
    }

    var warehouseStockLines: [WarehouseStockLine] {
        activeProjects.flatMap { project in
            WarehouseStockCalculator.stockLines(
                for: project.id,
                movements: projectStore.projectWarehouseMovements(for: project.id)
            )
        }
    }

    var warehouseTodayMovementCount: Int {
        let today = todayStr
        return warehouseMovementsForActiveProjects.filter { $0.date == today }.count
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
        let today = todayStr
        let loggedProjects = Set(projectStore.dailyLogs.lazy
            .filter { $0.date == today }
            .compactMap(\.projectId))
        return activeProjects.filter { !loggedProjects.contains($0.id) }.count
    }

    var unattachedReceiptCount: Int {
        let linkedRecordIDs = Set(projectStore.projectDocuments.compactMap(\.linkedFinancialRecordId))
        return activeFinancialRecords.filter { record in
            guard record.requiresAttachment else { return false }
            let linkedByRecord = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = linkedRecordIDs.contains(record.id)
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
