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

    var effectiveBackupReminderDays: Int {
        let raw = UserDefaults.standard.integer(forKey: UserPreferenceKeys.backupHealthReminderDays)
        return max(1, raw == 0 ? 7 : raw)
    }

    var latestSuccessfulBackupDate: Date? {
        let localRaw = UserDefaults.standard.double(forKey: UserPreferenceKeys.localBackupLastSuccessAt)
        let cloudRaw = UserDefaults.standard.double(forKey: UserPreferenceKeys.cloudBackupLastSuccessAt)
        let localDate = localRaw > 0 ? Date(timeIntervalSince1970: localRaw) : nil
        let cloudDate = cloudRaw > 0 ? Date(timeIntervalSince1970: cloudRaw) : nil
        switch (localDate, cloudDate) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }

    var daysSinceLastSuccessfulBackup: Int? {
        guard let latestSuccessfulBackupDate else { return nil }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: latestSuccessfulBackupDate)
        let today = calendar.startOfDay(for: Date())
        return max(calendar.dateComponents([.day], from: start, to: today).day ?? 0, 0)
    }

    var isBackupReminderOverdue: Bool {
        guard let daysSinceLastSuccessfulBackup else { return true }
        return daysSinceLastSuccessfulBackup >= effectiveBackupReminderDays
    }

    var backupReminderValue: String {
        if isIgnoringBackupReminderToday { return String(localized: "已忽略") }
        guard let daysSinceLastSuccessfulBackup else { return String(localized: "未备份") }
        return "\(daysSinceLastSuccessfulBackup)天"
    }

    var backupReminderRiskCount: Int {
        isBackupReminderOverdue ? 1 : 0
    }

    private var isIgnoringBackupReminderToday: Bool {
        ignoredBackupRiskDay == todayStr
    }

    private var isIgnoringMissingReceiptToday: Bool {
        ignoredMissingReceiptRiskDay == todayStr
    }

    private var isIgnoringPriceSpikeToday: Bool {
        ignoredPriceSpikeRiskDay == todayStr
    }

    private var isIgnoringNegativeStockToday: Bool {
        ignoredNegativeStockRiskDay == todayStr
    }

    var displayedMissingReceiptCount: Int {
        isIgnoringMissingReceiptToday ? 0 : unattachedReceiptCount
    }

    var displayedPriceSpikeCount: Int {
        isIgnoringPriceSpikeToday ? 0 : materialPriceSpikeCount
    }

    var displayedNegativeStockCount: Int {
        isIgnoringNegativeStockToday ? 0 : warehouseNegativeCount
    }

    var isDisplayedBackupReminderOverdue: Bool {
        guard !isIgnoringBackupReminderToday else { return false }
        return isBackupReminderOverdue
    }

    var dashboardRiskTotal: Int {
        overdueCount
            + todayTodos.count
            + projectsWithoutTodayLogCount
            + displayedMissingReceiptCount
            + unsettledFinancialCount
            + displayedPriceSpikeCount
            + displayedNegativeStockCount
            + (isDisplayedBackupReminderOverdue ? 1 : 0)
    }

    var hasDashboardRisk: Bool {
        dashboardRiskTotal > 0
    }

    var dashboardRiskPins: [DashboardRiskPin] {
        let pins: [DashboardRiskPin] = [
            DashboardRiskPin(
                id: "overdue",
                title: String(localized: "延期"),
                value: "\(overdueCount)",
                color: overdueCount > 0 ? .appRisk : .appSuccess,
                hasRisk: overdueCount > 0,
                priority: 1000,
                destination: .projectList(initialOverviewFilter: .overdue)
            ),
            DashboardRiskPin(
                id: "todayTodos",
                title: String(localized: "今日待办"),
                value: "\(todayTodos.count)",
                color: !todayTodos.isEmpty ? .appWarning : .appSuccess,
                hasRisk: !todayTodos.isEmpty,
                priority: 900,
                destination: .projectList(initialOverviewFilter: .todo)
            ),
            DashboardRiskPin(
                id: "backupOverdue",
                title: String(localized: "备份超期"),
                value: backupReminderValue,
                color: isDisplayedBackupReminderOverdue ? .appRisk : .appSuccess,
                hasRisk: isDisplayedBackupReminderOverdue,
                priority: 850,
                destination: .dataManagement(initialTab: "备份"),
                quickActions: backupReminderRiskActions
            ),
            DashboardRiskPin(
                id: "priceSpike",
                title: String(localized: "价格异动"),
                value: "\(displayedPriceSpikeCount)",
                color: displayedPriceSpikeCount > 0 ? .appFinance : .appSuccess,
                hasRisk: displayedPriceSpikeCount > 0,
                priority: 820,
                destination: .materialPriceSpikeDetails,
                quickActions: priceSpikeRiskActions
            ),
            DashboardRiskPin(
                id: "negativeStock",
                title: String(localized: "负库存"),
                value: "\(displayedNegativeStockCount)",
                color: displayedNegativeStockCount > 0 ? .appRisk : .appSuccess,
                hasRisk: displayedNegativeStockCount > 0,
                priority: 780,
                destination: warehouseOverviewDestination,
                quickActions: negativeStockRiskActions
            ),
            DashboardRiskPin(
                id: "missingReceipt",
                title: String(localized: "缺票"),
                value: "\(displayedMissingReceiptCount)",
                color: displayedMissingReceiptCount > 0 ? .appFinance : .appSuccess,
                hasRisk: displayedMissingReceiptCount > 0,
                priority: 740,
                destination: .projectList(initialOverviewFilter: .missingReceipt),
                quickActions: missingReceiptRiskActions
            ),
            DashboardRiskPin(
                id: "financialDue",
                title: String(localized: "应收付"),
                value: "\(unsettledFinancialCount)",
                color: unsettledFinancialCount > 0 ? .appWarning : .appSuccess,
                hasRisk: unsettledFinancialCount > 0,
                priority: 700,
                destination: .projectList(initialOverviewFilter: .financialDue)
            ),
            DashboardRiskPin(
                id: "missingTodayLog",
                title: String(localized: "未写日志"),
                value: "\(projectsWithoutTodayLogCount)",
                color: projectsWithoutTodayLogCount > 0 ? .appDoc : .appSuccess,
                hasRisk: projectsWithoutTodayLogCount > 0,
                priority: 620,
                destination: .projectList(initialOverviewFilter: .missingTodayLog)
            ),
        ]

        return pins.sorted {
            if $0.hasRisk != $1.hasRisk { return $0.hasRisk && !$1.hasRisk }
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    var visibleDashboardRiskPins: [DashboardRiskPin] {
        dashboardRiskPins.filter(\.hasRisk)
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
            categories: [.project, .contact, .supplier, .material],
            projects: projectStore.projects,
            contacts: projectStore.projectContacts,
            suppliers: store.supplierProfiles,
            materials: store.materialPriceEntries,
            limit: 10
        )
    }

    func collectRecentActivities(limit: Int) -> [TimelineActivity] {
        var activities: [TimelineActivity] = []

        for log in projectStore.dailyLogs {
            let title = log.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? String(localized: "施工日志")
                : String(log.content.prefix(40))
            activities.append(
                TimelineActivity(
                    id: "log-\(log.id.uuidString)",
                    projectId: log.projectId,
                    type: .log,
                    title: title,
                    date: log.date,
                    subtitle: String(localized: "施工日志")
                )
            )
        }

        for task in projectStore.progressTasks {
            activities.append(
                TimelineActivity(
                    id: "progress-\(task.id.uuidString)",
                    projectId: task.projectId,
                    type: .progress,
                    title: task.title,
                    date: task.dueDate.isEmpty ? task.startDate : task.dueDate,
                    subtitle: "\(Int(task.clampedCompletion * 100))%"
                )
            )
        }

        for todo in projectStore.siteTodos {
            activities.append(
                TimelineActivity(
                    id: "todo-\(todo.id.uuidString)",
                    projectId: todo.projectId,
                    type: .todo,
                    title: todo.title,
                    date: todo.completedAt ?? todo.dueDate,
                    subtitle: todo.isDone ? String(localized: "已完成") : String(localized: "未完成")
                )
            )
        }

        for item in financeStore.materialItems {
            activities.append(
                TimelineActivity(
                    id: "material-\(item.id.uuidString)",
                    projectId: item.projectId,
                    type: .material,
                    title: item.name,
                    date: item.arrivalDate,
                    subtitle: item.purchaseStatus.displayName
                )
            )
        }

        for item in financeStore.quoteItems {
            activities.append(
                TimelineActivity(
                    id: "quote-\(item.id.uuidString)",
                    projectId: item.projectId,
                    type: .quote,
                    title: item.name,
                    date: item.customerConfirmedDate,
                    subtitle: item.status.displayName
                )
            )
        }

        for item in financeStore.laborRecords {
            activities.append(
                TimelineActivity(
                    id: "labor-\(item.id.uuidString)",
                    projectId: item.projectId,
                    type: .labor,
                    title: item.workType.isEmpty ? String(localized: "人工记录") : item.workType,
                    date: item.date,
                    subtitle: "\(item.workers)人 · \(item.hours)h"
                )
            )
        }

        for record in projectStore.projectFinancialRecords {
            activities.append(
                TimelineActivity(
                    id: "finance-\(record.id.uuidString)",
                    projectId: record.projectId,
                    type: .financial,
                    title: "\(record.normalizedDirection.displayName) \(ReportBuilder.money(ReportBuilder.number(record.amount)))",
                    date: record.date,
                    subtitle: record.normalizedCategory.displayName
                )
            )
        }

        for document in projectStore.projectDocuments {
            activities.append(
                TimelineActivity(
                    id: "document-\(document.id.uuidString)",
                    projectId: document.projectId,
                    type: .document,
                    title: document.title,
                    date: document.createdAt,
                    subtitle: "\(document.category.displayName) · \(document.pageCount)页"
                )
            )
        }

        for movement in projectStore.projectWarehouseMovements {
            activities.append(
                TimelineActivity(
                    id: "warehouse-\(movement.id.uuidString)",
                    projectId: movement.projectId,
                    type: .warehouse,
                    title: "\(movement.normalizedMovementType.displayName) \(movement.materialName)",
                    date: movement.date,
                    subtitle: "\(movement.quantity)\(movement.unit)"
                )
            )
        }

        for note in projectStore.quickNotes {
            activities.append(
                TimelineActivity(
                    id: "note-\(note.id.uuidString)",
                    projectId: note.projectId,
                    type: .note,
                    title: note.title.isEmpty ? String(localized: "随手记") : note.title,
                    date: note.createdAt,
                    subtitle: note.content
                )
            )
        }

        for drawing in projectStore.projectDrawings {
            activities.append(
                TimelineActivity(
                    id: "drawing-\(drawing.id.uuidString)",
                    projectId: drawing.projectId,
                    type: .drawing,
                    title: drawing.name,
                    date: drawing.importedAt,
                    subtitle: drawing.version
                )
            )
        }

        return activities
            .sorted { lhs, rhs in
                let lhsDate = parseDashboardDate(lhs.date) ?? .distantPast
                let rhsDate = parseDashboardDate(rhs.date) ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id > rhs.id
            }
            .prefix(limit)
            .map { $0 }
    }

    func projectName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return projectNameByID[id]
    }

    func dashboardDestination(for suggestion: RealtimeSearchSuggestion) -> DashboardDestination {
        switch suggestion.category {
        case .project:
            return .projectDetail(projectId: suggestion.entityId)
        case .contact:
            return .projectContacts(focusedContactId: suggestion.entityId)
        case .material:
            return .materialPriceDatabase(focusedEntryId: suggestion.entityId)
        case .method:
            return .constructionMethodLibrary(focusedMethodId: suggestion.entityId)
        default:
            return .projectList()
        }
    }

    func warehouseLinkedDocuments(for movement: ProjectWarehouseMovement) -> [ProjectDocument] {
        let documentIds = Set(movement.linkedDocumentIds)
        guard !documentIds.isEmpty else { return [] }
        return projectStore.projectDocuments.filter { documentIds.contains($0.id) }
    }

    func dashboardCollectedAmount(for projectId: UUID) -> Double {
        let financial = projectStore.projectFinancialRecords(for: projectId)
        let byFinancialRecords = ProjectFinancialMetrics.collectionAmount(financial)
        return byFinancialRecords > 0 ? byFinancialRecords : 0
    }

    func dashboardReceivableAgeDays(for project: Project, receivableAmount: Double) -> Int? {
        guard receivableAmount > 0 else { return nil }
        guard let endDate = Formatters.date.date(from: project.expectedEndDate) else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        let dueDate = Calendar.current.startOfDay(for: endDate)
        let days = Calendar.current.dateComponents([.day], from: dueDate, to: today).day ?? 0
        return max(days, 0)
    }

    func dashboardLatestCollection() -> CollectionSnapshot? {
        ProjectFinancialMetrics.latestCollection(
            records: activeFinancialRecords,
            projectName: { projectName($0) }
        )
    }

    func parseLocalDate(_ text: String) -> Date? {
        Self.localDateFormatter.date(from: text)
    }

    func parseDashboardDate(_ text: String) -> Date? {
        if let date = parseLocalDate(text) { return date }
        return Formatters.parseDateOrDateTime(text)
    }

    func todayString(for date: Date) -> String {
        Self.localDateFormatter.string(from: date)
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
                subtitle: String(format: String(localized: "延期 %lld"), Int64(overdue)),
                color: .appRisk,
                score: score
            )
        }
        if todayTodo > 0 {
            return DashboardProjectSignal(
                subtitle: String(format: String(localized: "今日 %lld"), Int64(todayTodo)),
                color: .appPrimaryAction,
                score: score
            )
        }
        if missingReceipt > 0 {
            return DashboardProjectSignal(
                subtitle: String(format: String(localized: "缺票 %lld"), Int64(missingReceipt)),
                color: .appPrimaryAction,
                score: score
            )
        }
        if priceSpike > 0 {
            return DashboardProjectSignal(
                subtitle: String(format: String(localized: "价格异动 %lld"), Int64(priceSpike)),
                color: .appPrimaryAction,
                score: score
            )
        }
        if missingLog {
            return DashboardProjectSignal(subtitle: String(localized: "未写日志"), color: .appDoc, score: score)
        }
        if openTodos > 0 {
            return DashboardProjectSignal(
                subtitle: String(format: String(localized: "待办 %lld"), Int64(openTodos)),
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

    var backupReminderRiskActions: [DashboardRiskQuickAction] {
        guard isDisplayedBackupReminderOverdue else { return [] }
        return [
            DashboardRiskQuickAction(
                id: "backup.ignore",
                title: String(localized: "忽略今日提醒"),
                systemImage: "eye.slash",
                action: ignoreBackupReminderForToday
            ),
            DashboardRiskQuickAction(
                id: "backup.threshold",
                title: String(localized: "阈值 +1 天"),
                systemImage: "slider.horizontal.3",
                action: raiseBackupReminderThreshold
            ),
            DashboardRiskQuickAction(
                id: "backup.todo",
                title: String(localized: "生成待办"),
                systemImage: "checklist",
                action: createBackupFollowupTodo
            )
        ]
    }

    var missingReceiptRiskActions: [DashboardRiskQuickAction] {
        guard displayedMissingReceiptCount > 0 else { return [] }
        return [
            DashboardRiskQuickAction(
                id: "receipt.ignore",
                title: String(localized: "忽略今日提醒"),
                systemImage: "eye.slash",
                action: ignoreMissingReceiptForToday
            ),
            DashboardRiskQuickAction(
                id: "receipt.todo",
                title: String(localized: "生成待办"),
                systemImage: "checklist",
                action: createMissingReceiptTodo
            )
        ]
    }

    var priceSpikeRiskActions: [DashboardRiskQuickAction] {
        guard displayedPriceSpikeCount > 0 else { return [] }
        return [
            DashboardRiskQuickAction(
                id: "spike.ignore",
                title: String(localized: "忽略今日提醒"),
                systemImage: "eye.slash",
                action: ignorePriceSpikeForToday
            ),
            DashboardRiskQuickAction(
                id: "spike.threshold",
                title: String(localized: "上调阈值 +5%"),
                systemImage: "slider.horizontal.3",
                action: raisePriceSpikeThreshold
            ),
            DashboardRiskQuickAction(
                id: "spike.todo",
                title: String(localized: "生成待办"),
                systemImage: "checklist",
                action: createPriceSpikeTodo
            )
        ]
    }

    var negativeStockRiskActions: [DashboardRiskQuickAction] {
        guard displayedNegativeStockCount > 0 else { return [] }
        return [
            DashboardRiskQuickAction(
                id: "stock.ignore",
                title: String(localized: "忽略今日提醒"),
                systemImage: "eye.slash",
                action: ignoreNegativeStockForToday
            ),
            DashboardRiskQuickAction(
                id: "stock.todo",
                title: String(localized: "生成待办"),
                systemImage: "checklist",
                action: createNegativeStockTodo
            )
        ]
    }

    func ignoreBackupReminderForToday() {
        ignoredBackupRiskDay = todayStr
        AppHaptics.impact(.light)
        showDashboardActionFeedback(String(localized: "已忽略今日“备份超期”提醒"))
    }

    func ignoreMissingReceiptForToday() {
        ignoredMissingReceiptRiskDay = todayStr
        AppHaptics.impact(.light)
        showDashboardActionFeedback(String(localized: "已忽略今日“缺票”提醒"))
    }

    func ignorePriceSpikeForToday() {
        ignoredPriceSpikeRiskDay = todayStr
        AppHaptics.impact(.light)
        showDashboardActionFeedback(String(localized: "已忽略今日“价格异动”提醒"))
    }

    func ignoreNegativeStockForToday() {
        ignoredNegativeStockRiskDay = todayStr
        AppHaptics.impact(.light)
        showDashboardActionFeedback(String(localized: "已忽略今日“负库存”提醒"))
    }

    func raisePriceSpikeThreshold() {
        let current = financeStore.materialPriceSpikeThreshold
        let raised = min(current + 0.05, 0.50)
        guard abs(raised - current) > 0.0001 else {
            AppHaptics.warning()
            showDashboardActionFeedback(String(localized: "阈值已到上限"))
            return
        }
        financeStore.setMaterialPriceSpikeThreshold(raised)
        AppHaptics.success()
        showDashboardActionFeedback("已上调阈值到 \(Int((raised * 100).rounded()))%")
    }

    func raiseBackupReminderThreshold() {
        let raw = UserDefaults.standard.integer(forKey: UserPreferenceKeys.backupHealthReminderDays)
        let current = max(1, raw == 0 ? 7 : raw)
        let raised = min(current + 1, 30)
        guard raised != current else {
            AppHaptics.warning()
            showDashboardActionFeedback(String(localized: "备份提醒阈值已到上限"))
            return
        }
        UserDefaults.standard.set(raised, forKey: UserPreferenceKeys.backupHealthReminderDays)
        AppHaptics.success()
        showDashboardActionFeedback("备份提醒阈值已调整为 \(raised) 天")
    }

    func createBackupFollowupTodo() {
        createRiskTodo(
            marker: "[dashboard-risk:backup-overdue]",
            title: "检查备份策略",
            note: "工作台检测到备份超期，请检查本地和云端备份是否成功。",
            projectId: nil
        )
    }

    func createMissingReceiptTodo() {
        let projectId = currentProject?.id
        let projectNameText = currentProject?.name ?? String(localized: "全部项目")
        createRiskTodo(
            marker: "[dashboard-risk:missing-receipt]",
            title: "补齐票据资料",
            note: "\(projectNameText) 当前有 \(displayedMissingReceiptCount) 笔账目缺票，请补齐附件并关联账目。",
            projectId: projectId
        )
    }

    func createPriceSpikeTodo() {
        let projectId = currentProject?.id
        let projectNameText = currentProject?.name ?? String(localized: "全部项目")
        createRiskTodo(
            marker: "[dashboard-risk:price-spike]",
            title: "处理材料价格异动",
            note: "\(projectNameText) 当前有 \(displayedPriceSpikeCount) 项价格异动，请复核采购价或调整阈值。",
            projectId: projectId
        )
    }

    func createNegativeStockTodo() {
        let projectId = currentProject?.id
        let projectNameText = currentProject?.name ?? String(localized: "全部项目")
        createRiskTodo(
            marker: "[dashboard-risk:negative-stock]",
            title: "核对负库存",
            note: "\(projectNameText) 当前有 \(displayedNegativeStockCount) 项负库存，请补录入库或修正数量。",
            projectId: projectId
        )
    }

    func createRiskTodo(marker: String, title: String, note: String, projectId: UUID?) {
        let hasDuplicate = store.siteTodos.contains { todo in
            !todo.isDone
                && todo.note.contains(marker)
                && todo.projectId == projectId
        }
        guard !hasDuplicate else {
            AppHaptics.warning()
            showDashboardActionFeedback(String(localized: "相同提醒待办已存在"))
            return
        }

        let todo = SiteTodo(
            title: title,
            owner: "",
            dueDate: todayStr,
            priority: .medium,
            issueType: .general,
            note: "\(note)\n\(marker)",
            projectId: projectId
        )
        store.insertSiteTodoAtTop(todo)
        store.scheduleSave()
        AppHaptics.success()
        showDashboardActionFeedback(String(localized: "已生成处理待办"))
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
