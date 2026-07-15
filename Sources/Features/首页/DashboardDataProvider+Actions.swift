import SwiftUI

extension DashboardView {
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
            categories: [.command, .project, .contact, .supplier, .material, .log, .todo, .note],
            projects: projectStore.projects,
            contacts: projectStore.projectContacts,
            suppliers: store.supplierProfiles,
            materials: store.materialPriceEntries,
            logs: projectStore.dailyLogs,
            todos: projectStore.siteTodos,
            notes: projectStore.quickNotes,
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
