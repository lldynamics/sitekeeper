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
                        NavigationLink {
                            SiteTodoView(initialProjectId: todo.projectId, focusedTodoId: todo.id)
                        } label: {
                            TodoPreviewRow(todo: todo, projectName: projectName(todo.projectId))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
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
        let activities = collectRecentActivities(limit: 20)
        return DashboardPanel(title: AppLocalization.string("总项目时间轴"), systemImage: "calendar.badge.clock") {
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
                if usesWideDashboardLayout {
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
        DashboardPanel(title: AppLocalization.string("延期提醒"), systemImage: "calendar.badge.exclamationmark", destination: .projectList(initialOverviewFilter: .overdue)) {
            if overdueTasks.isEmpty && overdueTodos.isEmpty {
                EmptyDashboardRow(text: AppLocalization.string("暂无延期事项"))
            } else {
                VStack(spacing: AppSpacing.tight) {
                    ForEach(overdueTodos.prefix(3)) { todo in
                        NavigationLink {
                            SiteTodoView(initialProjectId: todo.projectId, focusedTodoId: todo.id)
                        } label: {
                            IssueRow(title: todo.title, value: todo.dueDate.storageText, color: .appRisk)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(overdueTasks.prefix(3)) { task in
                        NavigationLink {
                            TaskProgressView(initialProjectId: task.projectId)
                        } label: {
                            IssueRow(title: task.title, value: task.dueDate.storageText, color: .appRisk)
                        }
                        .buttonStyle(.plain)
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
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
