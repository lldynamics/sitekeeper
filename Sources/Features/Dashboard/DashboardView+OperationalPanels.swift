import SwiftUI

extension DashboardView {
    var dashboardTimelineColumns: [GridItem] {
        usesWideDashboardLayout
            ? [GridItem(.adaptive(minimum: 320), spacing: AppSpacing.tight)]
            : [GridItem(.flexible(), spacing: AppSpacing.tight)]
    }

    var todayTodoPanel: some View {
        DashboardPanel(title: AppLocalization.string("今日待办"), systemImage: "checklist", destination: .siteTodo()) {
            let items = todayTodos.isEmpty ? Array(openTodos.prefix(3)) : Array(todayTodos.prefix(4))
            if items.isEmpty {
                NavigationLink { SiteTodoView() } label: {
                    EmptyDashboardRow(text: AppLocalization.string("暂无现场待办"))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: AppSpacing.tight) {
                    ForEach(items) { todo in
                        TodoPreviewRow(
                            todo: todo,
                            projectName: projectName(todo.projectId),
                            onToggle: {
                                AppHaptics.success()
                                toggleTodo(todo)
                            }
                        )
                    }
                }
            }
        }
    }

    private func toggleTodo(_ todo: SiteTodo) {
        guard var updated = store.siteTodos.first(where: { $0.id == todo.id }) else { return }
        updated.toggleCompletionForWorkflow()
        if store.updateSiteTodo(updated) {
            store.scheduleSave()
        }
    }

    var todayLogPanel: some View {
        DashboardPanel(title: AppLocalization.string("今日现场"), systemImage: "book.pages.fill", destination: .dailyLog()) {
            if todayLogs.isEmpty {
                NavigationLink { DailyLogView() } label: {
                    EmptyDashboardRow(text: AppLocalization.string("今天还没有施工日志"))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: AppSpacing.tight) {
                    ForEach(todayLogs.prefix(3)) { log in
                        NavigationLink {
                            DailyLogView(initialProjectId: log.projectId, focusedLogId: log.id)
                        } label: {
                            LogPreviewRow(log: log, projectName: projectName(log.projectId))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    var projectTimelinePanel: some View {
        DashboardPanel(title: AppLocalization.string("总项目时间轴"), systemImage: "calendar.badge.clock") {
            dashboardTimelineContent(prefersSingleColumn: false)
        }
    }

    @ViewBuilder
    func dashboardTimelineContent(prefersSingleColumn: Bool) -> some View {
        let activities = collectRecentActivities(limit: 20)
        if activities.isEmpty {
            HStack {
                Image(systemName: "tray")
                    .foregroundStyle(.secondary)
                Text(AppLocalization.string("暂无项目活动，完成一次操作后会显示在这里"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, AppSpacing.tight)
        } else {
            if usesWideDashboardLayout && !prefersSingleColumn {
                LazyVGrid(
                    columns: dashboardTimelineColumns,
                    alignment: .leading,
                    spacing: AppSpacing.tight * 0.75
                ) {
                    ForEach(activities, id: \.id) { activity in
                        dashboardTimelineRow(activity)
                    }
                }
            } else {
                VStack(spacing: AppSpacing.tight * 0.75) {
                    ForEach(activities, id: \.id) { activity in
                        dashboardTimelineRow(activity)
                    }
                }
            }
        }
    }

    func dashboardTimelineRow(_ activity: TimelineActivity) -> some View {
        NavigationLink {
            LazyDashboardDestinationView(destination: dashboardTimelineDestination(for: activity))
        } label: {
            TimelineActivityRow(
                activity: activity,
                projectName: projectName(activity.projectId),
                showsChevron: true
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            if let projectId = activity.projectId {
                selectedProjectIdRaw = projectId.uuidString
            }
        })
    }

    func dashboardTimelineDestination(for activity: TimelineActivity) -> DashboardDestination {
        guard let projectId = activity.projectId else {
            return .projectList()
        }
        switch activity.type {
        case .log:
            return .dailyLog(initialProjectId: projectId, focusedLogId: activityRecordID(activity, prefix: "log"))
        case .todo:
            return .siteTodo(initialProjectId: projectId, focusedTodoId: activityRecordID(activity, prefix: "todo"))
        default:
            return .projectDetail(projectId: projectId, initialMode: activity.type.projectDetailMode)
        }
    }

    func activityRecordID(_ activity: TimelineActivity, prefix: String) -> UUID? {
        let marker = "\(prefix)-"
        guard activity.id.hasPrefix(marker) else { return nil }
        return UUID(uuidString: String(activity.id.dropFirst(marker.count)))
    }

    var overduePanel: some View {
        let items = dashboardSummary.overdueItems
        return DashboardPanel(title: AppLocalization.string("延期提醒"), systemImage: "calendar.badge.exclamationmark", destination: .overdueItems) {
            HStack {
                Text(String(format: AppLocalization.string("共 %lld 项"), Int64(items.count)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("dashboard-overdue-count")
                Spacer(minLength: AppSpacing.tight)
                NavigationLink {
                    LazyDashboardDestinationView(destination: .overdueItems)
                } label: {
                    HStack(spacing: 4) {
                        Text(AppLocalization.string("查看全部"))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appPrimaryAction)
                .accessibilityIdentifier("dashboard-overdue-view-all")
            }
            if items.isEmpty {
                EmptyDashboardRow(text: AppLocalization.string("暂无延期事项"))
            } else {
                VStack(spacing: AppSpacing.tight) {
                    ForEach(items.prefix(6)) { item in
                        DashboardOverdueItemLink(item: item)
                    }
                }
            }
        }
    }

    var warehousePanel: some View {
        DashboardPanel(title: AppLocalization.string("库存情况"), systemImage: "shippingbox.fill", destination: warehouseOverviewDestination) {
            let lines = warehouseStockLines
            HStack(spacing: AppSpacing.tight) {
                DashboardInventoryPill(title: AppLocalization.string("材料种类"), value: "\(lines.count)", color: .appPrimaryAction, destination: warehouseOverviewDestination)
                DashboardInventoryPill(title: AppLocalization.string("今日出入库"), value: "\(warehouseTodayMovementCount)", color: warehouseTodayMovementCount > 0 ? .appDoc : Color.secondary, destination: warehouseMovementDestination)
                DashboardInventoryPill(title: AppLocalization.string("负库存"), value: "\(warehouseNegativeCount)", color: warehouseNegativeCount > 0 ? .appRisk : .appSuccess, destination: warehouseOverviewDestination)
            }
            if recentWarehouseMovements.isEmpty {
                EmptyDashboardRow(text: AppLocalization.string("暂无仓库出入库记录"))
            } else {
                VStack(spacing: AppSpacing.tight) {
                    ForEach(recentWarehouseMovements) { movement in
                        NavigationLink {
                            ProjectWarehouseMovementDetailView(
                                movement: movement,
                                documents: warehouseLinkedDocuments(for: movement)
                            )
                        } label: {
                            WarehouseMovementRow(movement: movement)
                                .padding(.horizontal, AppSpacing.normal - 2)
                                .padding(.vertical, AppSpacing.tight)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color(uiColor: .separator).opacity(0.10), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

private struct DashboardOverdueItemLink: View {
    let item: DashboardOverdueItem
    var projectName: String? = nil
    var showsDetails = false

    var body: some View {
        NavigationLink {
            switch item {
            case .todo(let todo):
                SiteTodoView(initialProjectId: todo.projectId, focusedTodoId: todo.id)
            case .task(let task):
                TaskProgressView(initialProjectId: task.projectId)
            }
        } label: {
            if showsDetails {
                HStack(alignment: .top, spacing: AppSpacing.normal) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.body)
                        HStack {
                            Text(typeName)
                            if let projectName {
                                Text(projectName)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: AppSpacing.tight)
                    Text(item.dueDate.storageText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appRisk)
                }
            } else {
                IssueRow(title: item.title, value: item.dueDate.storageText, color: .appRisk)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboard-overdue-item-\(item.id)")
    }

    private var typeName: String {
        switch item {
        case .todo: return AppLocalization.string("现场待办")
        case .task: return AppLocalization.string("施工进度")
        }
    }
}

struct DashboardOverdueListView: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(FinanceStore.self) private var financeStore
    @State private var summaryCache = DashboardSummaryCache()

    private var summary: DashboardSummaryModel {
        summaryCache.value(revision: DashboardSummaryRevision(projectStore: projectStore, financeStore: financeStore)) {
            DashboardSummaryInput(projectStore: projectStore, financeStore: financeStore)
        }
    }

    var body: some View {
        let currentSummary = summary
        List {
            Section {
                if currentSummary.overdueItems.isEmpty {
                    ContentUnavailableView(AppLocalization.string("暂无延期事项"), systemImage: "checkmark.circle")
                } else {
                    ForEach(currentSummary.overdueItems) { item in
                        DashboardOverdueItemLink(
                            item: item,
                            projectName: item.projectID.flatMap { currentSummary.projectNameByID[$0] },
                            showsDetails: true
                        )
                    }
                }
            } header: {
                Text(String(format: AppLocalization.string("共 %lld 项"), Int64(currentSummary.overdueItems.count)))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(AppLocalization.string("延期提醒"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("dashboard-overdue-list")
    }
}
