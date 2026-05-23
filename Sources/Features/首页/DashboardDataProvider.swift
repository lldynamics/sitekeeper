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

    var logQuickActions: [TodayPrimaryQuickAction] {
        var actions: [TodayPrimaryQuickAction] = []
        if let project = currentProject {
            actions.append(
                TodayPrimaryQuickAction(
                    title: String(localized: "当前项目写日志"),
                    systemImage: "building.2.fill",
                    destination: .dailyLog(initialProjectId: project.id, autoOpenComposer: true)
                )
            )
        }
        actions.append(
            TodayPrimaryQuickAction(
                title: String(localized: "直接新建日志"),
                systemImage: "square.and.pencil",
                destination: .dailyLog(autoOpenComposer: true)
            )
        )
        return actions
    }

    var todoQuickActions: [TodayPrimaryQuickAction] {
        var actions: [TodayPrimaryQuickAction] = []
        if let project = currentProject {
            actions.append(
                TodayPrimaryQuickAction(
                    title: String(localized: "当前项目加待办"),
                    systemImage: "building.2.fill",
                    destination: .siteTodo(initialProjectId: project.id, autoOpenComposer: true)
                )
            )
        }
        actions.append(
            TodayPrimaryQuickAction(
                title: String(localized: "直接新建待办"),
                systemImage: "plus.circle",
                destination: .siteTodo(autoOpenComposer: true)
            )
        )
        return actions
    }

    var photoQuickActions: [TodayPrimaryQuickAction] {
        var actions: [TodayPrimaryQuickAction] = []
        if let project = currentProject {
            actions.append(
                TodayPrimaryQuickAction(
                    title: String(localized: "当前项目拍照片"),
                    systemImage: "camera.fill",
                    destination: .watermarkCamera(initialProjectId: project.id, autoOpenCameraOnAppear: true)
                )
            )
        }
        actions.append(
            TodayPrimaryQuickAction(
                title: String(localized: "打开水印相机"),
                systemImage: "camera.badge.ellipsis",
                destination: .watermarkCamera(initialProjectId: currentProject?.id)
            )
        )
        return actions
    }

    var bookkeepingQuickActions: [TodayPrimaryQuickAction] {
        var actions: [TodayPrimaryQuickAction] = []
        if activeProjects.count == 1, let project = activeProjects.first {
            actions.append(
                TodayPrimaryQuickAction(
                    title: String(localized: "当前项目记账"),
                    systemImage: "receipt.fill",
                    destination: .projectDetail(projectId: project.id, autoOpenFinancialAdd: true)
                )
            )
        } else if activeProjects.count > 1 {
            actions.append(
                TodayPrimaryQuickAction(
                    title: String(localized: "选择工程记账"),
                    systemImage: "building.2.fill",
                    destination: .bookkeepingProjectPicker(projects: activeProjects)
                )
            )
        } else {
            actions.append(
                TodayPrimaryQuickAction(
                    title: String(localized: "新建项目"),
                    systemImage: "plus.circle",
                    destination: .projectList()
                )
            )
        }
        return actions
    }

    var dashboardSearchSuggestions: [RealtimeSearchSuggestion] {
        RealtimeSearchSuggestionBuilder.suggestions(
            keyword: dashboardSearchText,
            categories: [.command, .project, .contact, .supplier, .material],
            projects: projectStore.projects,
            contacts: projectStore.projectContacts,
            suppliers: store.supplierProfiles,
            materials: store.materialPriceEntries,
            limit: 10
        )
    }

    @MainActor
    func showQuickActionFeedback(title: String) {
        quickActionToastMessage = String(format: String(localized: "已打开%@"), title)
    }

    @MainActor
    func showDashboardActionFeedback(_ message: String) {
        quickActionToastMessage = message
    }

    @MainActor
    func dismissQuickActionToastAfterDelay() async {
        guard quickActionToastMessage != nil else { return }
        guard await DebouncedTask.wait(for: .milliseconds(900)) else { return }
        withAnimation(.easeOut(duration: 0.2)) {
            quickActionToastMessage = nil
        }
    }

    func cleanupSelectedProject() {
        guard !selectedProjectIdRaw.isEmpty else { return }
        if !activeProjects.contains(where: { $0.id.uuidString == selectedProjectIdRaw }) {
            selectedProjectIdRaw = ""
        }
    }

    func dashboardProjectRow(for project: Project) -> DashboardProjectRow {
        let signal = dashboardProjectSignal(for: project)
        return DashboardProjectRow(
            project: project,
            subtitle: signal.subtitle,
            color: signal.color,
            score: signal.score,
            activityDate: recentActivityDate(for: project)
        )
    }

    func dashboardProjectSignal(for project: Project) -> DashboardProjectSignal {
        let overdue = overdueCount(for: project)
        let todayTodo = todayTodoCount(for: project)
        let missingReceipt = unattachedReceiptCount(for: project)
        let priceSpike = materialPriceSpikeCount(for: project)
        let missingLog = !hasTodayLog(for: project)
        let openTodos = openTodoCount(for: project)
        let score = overdue * 1000
            + todayTodo * 420
            + missingReceipt * 240
            + priceSpike * 200
            + (missingLog ? 120 : 0)
            + openTodos * 20

        if overdue > 0 {
            return DashboardProjectSignal(
                subtitle: DashboardSubtitleBuilder.overdue(overdue),
                color: .appRisk,
                score: score
            )
        }
        if todayTodo > 0 {
            return DashboardProjectSignal(
                subtitle: DashboardSubtitleBuilder.today(todayTodo),
                color: .appPrimaryAction,
                score: score
            )
        }
        if missingReceipt > 0 {
            return DashboardProjectSignal(
                subtitle: DashboardSubtitleBuilder.missingReceipt(missingReceipt),
                color: .appPrimaryAction,
                score: score
            )
        }
        if priceSpike > 0 {
            return DashboardProjectSignal(
                subtitle: DashboardSubtitleBuilder.priceSpike(priceSpike),
                color: .appPrimaryAction,
                score: score
            )
        }
        if missingLog {
            return DashboardProjectSignal(subtitle: String(localized: "未写日志"), color: .appDoc, score: score)
        }
        if openTodos > 0 {
            return DashboardProjectSignal(
                subtitle: DashboardSubtitleBuilder.openTodo(openTodos),
                color: .appPrimaryAction,
                score: score
            )
        }
        return DashboardProjectSignal(subtitle: String(localized: "最近使用"), color: .appSuccess, score: score)
    }

    func overdueCount(for project: Project) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        let overdueProgress = projectStore.progressTasks(for: project.id).filter { task in
            guard task.clampedCompletion < 1,
                  let due = parseLocalDate(task.dueDate) else { return false }
            return due < today
        }.count
        let overdueTodos = projectStore.siteTodos(for: project.id).filter(\.isOverdue).count
        return overdueProgress + overdueTodos
    }

    func todayTodoCount(for project: Project) -> Int {
        projectStore.siteTodos(for: project.id).filter {
            !$0.isDone && $0.dueDate == todayStr
        }.count
    }

    func openTodoCount(for project: Project) -> Int {
        projectStore.siteTodos(for: project.id).filter { !$0.isDone }.count
    }

    func unattachedReceiptCount(for project: Project) -> Int {
        let documents = projectStore.projectDocuments(for: project.id)
        return projectStore.projectFinancialRecords(for: project.id).filter { record in
            guard record.requiresAttachment else { return false }
            let linkedByRecord = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = documents.contains { $0.linkedFinancialRecordId == record.id }
            return !(linkedByRecord || linkedByDocument)
        }.count
    }

    func materialPriceSpikeCount(for project: Project) -> Int {
        financeStore.materialPriceSpikeCount(for: project.id)
    }

    func hasTodayLog(for project: Project) -> Bool {
        projectStore.hasTodayLog(for: project.id)
    }

    func recentActivityDate(for project: Project) -> Date {
        let projectId = project.id
        var latest = projectStore.projectActivitySummary(for: projectId).latestActivityDate ?? .distantPast
        if let startDate = Formatters.parseDateOrDateTime(project.startDate) {
            latest = max(latest, startDate)
        }
        if let latestLabor = financeStore.latestLaborDate(for: projectId) {
            latest = max(latest, latestLabor)
        }
        return latest
    }
}
