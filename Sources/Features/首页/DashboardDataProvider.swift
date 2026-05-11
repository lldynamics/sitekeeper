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

    var dashboardRiskTotal: Int {
        overdueCount + todayTodos.count + projectsWithoutTodayLogCount + unattachedReceiptCount + unsettledFinancialCount
    }

    var hasDashboardRisk: Bool {
        dashboardRiskTotal > 0
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
        actions.append(
            TodayPrimaryQuickAction(
                title: String(localized: "打开日志列表"),
                systemImage: "list.bullet",
                destination: .dailyLog()
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
        actions.append(
            TodayPrimaryQuickAction(
                title: String(localized: "打开待办列表"),
                systemImage: "list.bullet",
                destination: .siteTodo()
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
        actions.append(
            TodayPrimaryQuickAction(
                title: String(localized: "打开施工日志"),
                systemImage: "book.pages.fill",
                destination: .dailyLog()
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
                    title: String(localized: "先选择项目再记账"),
                    systemImage: "list.bullet",
                    destination: .bookkeepingProjectPicker(projects: activeProjects)
                )
            )
        }
        actions.append(
            TodayPrimaryQuickAction(
                title: String(localized: "选择工程记账"),
                systemImage: "building.2.fill",
                destination: .bookkeepingProjectPicker(projects: activeProjects)
            )
        )
        actions.append(
            TodayPrimaryQuickAction(
                title: String(localized: "打开项目列表"),
                systemImage: "list.bullet",
                destination: .projectList()
            )
        )
        return actions
    }

    var dashboardSearchSuggestions: [DashboardSearchSuggestion] {
        let keyword = dashboardSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }
        let query = keyword.lowercased()

        var ranked: [(score: Int, suggestion: DashboardSearchSuggestion)] = []

        for project in projectStore.projects {
            let fields = [project.name, project.location, project.customerName, project.managerName]
            guard let score = searchMatchScore(query: query, fields: fields) else { continue }
            let subtitle = [
                project.status.displayName,
                project.location,
                project.customerName
            ]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
            let activeBoost = (project.status == .active || project.status == .paused) ? 20 : 0
            ranked.append(
                (
                    score + activeBoost,
                    DashboardSearchSuggestion(
                        id: "project-\(project.id.uuidString)",
                        title: project.name,
                        subtitle: subtitle,
                        systemImage: "building.2",
                        tint: project.status == .active || project.status == .paused ? .orange : .secondary,
                        destination: .projectDetail(projectId: project.id)
                    )
                )
            )
        }

        for contact in projectStore.projectContacts {
            let projectName = projectNameByID[contact.projectId] ?? String(localized: "未知项目")
            let fields = [contact.name, contact.roleDisplayName, contact.company, contact.phone, contact.note, projectName]
            guard let score = searchMatchScore(query: query, fields: fields) else { continue }
            let subtitle = [contact.roleDisplayName, contact.phone, projectName]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " · ")
            ranked.append(
                (
                    score,
                    DashboardSearchSuggestion(
                        id: "contact-\(contact.id.uuidString)",
                        title: contact.name.isEmpty ? String(localized: "未命名联系人") : contact.name,
                        subtitle: subtitle,
                        systemImage: "person.crop.rectangle.stack",
                        tint: .blue,
                        destination: .projectContacts(focusedContactId: contact.id)
                    )
                )
            )
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.suggestion.title.localizedStandardCompare(rhs.suggestion.title) == .orderedAscending
            }
            .prefix(8)
            .map(\.suggestion)
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

    func warehouseLinkedDocuments(for movement: ProjectWarehouseMovement) -> [ProjectDocument] {
        let documentIds = Set(movement.linkedDocumentIds)
        guard !documentIds.isEmpty else { return [] }
        return projectStore.projectDocuments.filter { documentIds.contains($0.id) }
    }

    private func searchMatchScore(query: String, fields: [String]) -> Int? {
        var bestScore = 0
        for field in fields {
            let normalized = field.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }
            if normalized == query {
                bestScore = max(bestScore, 300)
            } else if normalized.hasPrefix(query) {
                bestScore = max(bestScore, 220)
            } else if normalized.contains(query) {
                bestScore = max(bestScore, 140)
            }
        }
        return bestScore > 0 ? bestScore : nil
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
        quickActionToastMessage = String(localized: "已打开\(title)")
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
        let missingLog = !hasTodayLog(for: project)
        let openTodos = openTodoCount(for: project)
        let score = overdue * 1000
            + todayTodo * 420
            + missingReceipt * 240
            + (missingLog ? 120 : 0)
            + openTodos * 20

        if overdue > 0 {
            return DashboardProjectSignal(subtitle: String(localized: "延期 \(overdue)"), color: .red, score: score)
        }
        if todayTodo > 0 {
            return DashboardProjectSignal(subtitle: String(localized: "今日 \(todayTodo)"), color: .orange, score: score)
        }
        if missingReceipt > 0 {
            return DashboardProjectSignal(subtitle: String(localized: "缺票 \(missingReceipt)"), color: .pink, score: score)
        }
        if missingLog {
            return DashboardProjectSignal(subtitle: String(localized: "未写日志"), color: .blue, score: score)
        }
        if openTodos > 0 {
            return DashboardProjectSignal(subtitle: String(localized: "待办 \(openTodos)"), color: .orange, score: score)
        }
        return DashboardProjectSignal(subtitle: String(localized: "最近使用"), color: .green, score: score)
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

    func hasTodayLog(for project: Project) -> Bool {
        projectStore.hasTodayLog(for: project.id)
    }

    func recentActivityDate(for project: Project) -> Date {
        let projectId = project.id
        var latest = projectStore.projectActivitySummary(for: projectId).latestActivityDate ?? .distantPast
        if let startDate = Formatters.parseDateOrDateTime(project.startDate) {
            latest = max(latest, startDate)
        }
        if let latestPayment = financeStore.latestPaymentDate(for: projectId) {
            latest = max(latest, latestPayment)
        }
        if let latestLabor = financeStore.latestLaborDate(for: projectId) {
            latest = max(latest, latestLabor)
        }
        return latest
    }
}
