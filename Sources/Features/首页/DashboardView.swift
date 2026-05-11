import SwiftUI

struct DashboardView: View {
    @Environment(DataStore.self) var store
    @Environment(ProjectStore.self) var projectStore
    @Environment(FinanceStore.self) var financeStore
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State var dashboardSearchText = ""
    @State var showDashboardProjectPicker = false
    @State var quickActionToastMessage: String?
    @AppStorage("dashboardCurrentProjectId") var selectedProjectIdRaw = ""
    let dashboardProjectDisplayLimit = 5

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    if usesWideDashboardLayout {
                        wideDashboardContent(containerWidth: proxy.size.width)
                    } else {
                        compactDashboardContent
                    }
                }
                .overlay(alignment: .top) {
                    if let quickActionToastMessage {
                        DashboardToastView(message: quickActionToastMessage)
                            .padding(.top, AppSpacing.normal)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .animation(.snappy(duration: 0.22), value: quickActionToastMessage)
            .navigationTitle(String(localized: "今日工作台"))
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showDashboardProjectPicker) {
                DashboardProjectPickerSheet(
                    rows: rankedDashboardProjectRows,
                    selectedProjectId: currentProject?.id,
                    onSelect: { projectId in
                        selectedProjectIdRaw = projectId?.uuidString ?? ""
                        showDashboardProjectPicker = false
                    }
                )
            }
            .onAppear(perform: cleanupSelectedProject)
            .task(id: quickActionToastMessage) {
                await dismissQuickActionToastAfterDelay()
            }
        }
    }

    @State private var showMoreOverview = false
    private var hasCompactOverviewSignal: Bool {
        hasDashboardRisk
            || !warehouseStockLines.isEmpty
            || overdueCount > 0
            || !todayTodos.isEmpty
            || !todayLogs.isEmpty
    }

    private var compactDashboardContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.normal) {
            globalSearchInput
            currentProjectSelector
            if hasDashboardRisk { dashboardRiskStrip }
            todayQuickActions
            if hasCompactOverviewSignal {
                DisclosureGroup(isExpanded: $showMoreOverview) {
                    VStack(alignment: .leading, spacing: AppSpacing.normal) {
                        warehousePanel
                        overduePanel
                        todayTodoPanel
                        todayLogPanel
                    }
                    .padding(.top, AppSpacing.tight)
                } label: {
                    HStack(spacing: AppSpacing.tight) {
                        Image(systemName: "rectangle.grid.2x2")
                        Text(String(localized: "更多概况"))
                            .font(.subheadline.weight(.semibold))
                        if !showMoreOverview {
                            Spacer()
                            PanelSummaryLabel(
                                warehouse: warehouseStockLines.count,
                                overdue: overdueCount,
                                todos: todayTodos.count,
                                logs: todayLogs.count
                            )
                        }
                    }
                }
            } else {
                VStack(spacing: AppSpacing.normal) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.green)
                    Text(String(localized: "全部良好"))
                        .font(.title3.weight(.semibold))
                    Text(String(localized: "暂无新增提醒，继续保持"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.normal, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
            }
            projectTimelinePanel
        }
        .padding()
    }

    private func wideDashboardContent(containerWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.relaxed - 2) {
            globalSearchInput
            currentProjectSelector
            HStack(alignment: .top, spacing: AppSpacing.normal) {
                wideDashboardSidebar
                    .frame(minWidth: 286, maxWidth: 340)

                wideDashboardMainPanels(containerWidth: containerWidth)
            }
            projectTimelinePanel
        }
        .padding()
    }

    private var wideDashboardSidebar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.normal) {
            DashboardPanel(title: String(localized: "今日快捷动作"), systemImage: "bolt.fill") {
                VStack(alignment: .leading, spacing: AppSpacing.tight) {
                    TodayMiniAction(title: String(localized: "写日志"), systemImage: "book.pages.fill", color: .green, destination: logEntryDestination, quickActions: logQuickActions, onTrigger: { showQuickActionFeedback(title: String(localized: "写日志")) })
                    TodayMiniAction(title: String(localized: "加待办"), systemImage: "checklist", color: .orange, destination: todoEntryDestination, quickActions: todoQuickActions, onTrigger: { showQuickActionFeedback(title: String(localized: "加待办")) })
                    TodayMiniAction(title: String(localized: "拍照片"), systemImage: "camera.fill", color: .blue, destination: photoEntryDestination, quickActions: photoQuickActions, onTrigger: { showQuickActionFeedback(title: String(localized: "拍照片")) })
                    TodayMiniAction(title: String(localized: "记账"), systemImage: "receipt.fill", color: .pink, destination: bookkeepingEntryDestination, quickActions: bookkeepingQuickActions, onTrigger: { showQuickActionFeedback(title: String(localized: "记账")) })
                }
            }

            if hasDashboardRisk { dashboardRiskStrip }
        }
    }

    private func wideDashboardMainPanels(containerWidth: CGFloat) -> some View {
        let canUseTwoColumns = containerWidth >= 1180
        let columns = canUseTwoColumns
            ? [GridItem(.flexible(), spacing: AppSpacing.normal), GridItem(.flexible(), spacing: AppSpacing.normal)]
            : [GridItem(.flexible(), spacing: AppSpacing.normal)]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: AppSpacing.normal) {
            warehousePanel
            overduePanel
            todayTodoPanel
            todayLogPanel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var globalSearchInput: some View {
        let hasSearchKeyword = !dashboardSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AppSpacing.tight + 2) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "搜索项目、联系人"), text: $dashboardSearchText)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                if hasSearchKeyword {
                    Button {
                        dashboardSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "清空搜索"))
                }
            }
            .padding(AppSpacing.normal)

            if hasSearchKeyword {
                Divider()
                    .padding(.horizontal, AppSpacing.normal)
                if dashboardSearchSuggestions.isEmpty {
                    Text(String(localized: "未找到匹配项目或联系人"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, AppSpacing.normal)
                        .padding(.vertical, AppSpacing.tight + 1)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(dashboardSearchSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                            NavigationLink {
                                dashboardDestinationView(suggestion.destination)
                            } label: {
                                DashboardSearchSuggestionRow(suggestion: suggestion)
                            }
                            .buttonStyle(.plain)

                            if index < dashboardSearchSuggestions.count - 1 {
                                Divider()
                                    .padding(.leading, AppSpacing.normal + 20 + AppSpacing.tight)
                            }
                        }
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: AppSpacing.normal - 2).fill(.thinMaterial))
    }

    @ViewBuilder
    private var currentProjectSelector: some View {
        if activeProjects.isEmpty {
            emptyCurrentProjectSelector
        } else {
            focusedProjectSelector
        }
    }

    private var emptyCurrentProjectSelector: some View {
        NavigationLink { ProjectListView() } label: {
            HStack(spacing: AppSpacing.tight) {
                Label(String(localized: "暂无进行中工程"), systemImage: "building.2")
                Spacer()
                Text(String(localized: "去添加"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppSpacing.normal)
        .padding(.vertical, AppSpacing.tight + 1)
        .background(RoundedRectangle(cornerRadius: AppSpacing.normal - 2).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    private var focusedProjectSelector: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            focusedProjectHeader
            focusedCurrentProjectPrimaryRow
            if activeProjects.count > 1 {
                focusedProjectScroller
            }
        }
        .padding(.horizontal, AppSpacing.normal)
        .padding(.vertical, AppSpacing.tight + 1)
        .background(RoundedRectangle(cornerRadius: AppSpacing.normal - 2).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    private var focusedProjectHeader: some View {
        HStack(spacing: AppSpacing.tight) {
            Label(String(localized: "今日关注工程"), systemImage: "scope")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            if activeProjects.count > dashboardProjectDisplayLimit {
                Text(String(localized: "关注 \(dashboardVisibleProjectRows.count)/\(activeProjects.count)"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if activeProjects.count > 1, currentProject == nil {
                Text(String(localized: "请选择工程"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var focusedCurrentProjectPrimaryRow: some View {
        if let currentProject {
            NavigationLink {
                ProjectDetailView(projectId: currentProject.id)
            } label: {
                HStack(spacing: AppSpacing.tight + 2) {
                    Image(systemName: "pin.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: AppSpacing.tight * 0.25) {
                        Text(String(localized: "当前工程"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(currentProject.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if !currentProject.location.isEmpty {
                            Text(currentProject.location)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.normal - 2)
                .padding(.vertical, AppSpacing.tight + 1)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.normal - 2)
                        .fill(Color.appPrimarySurfaceSubtle)
                )
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.orange)
                        .frame(width: 3)
                }
            }
            .buttonStyle(.plain)
        } else {
            Button {
                showDashboardProjectPicker = true
            } label: {
                HStack(spacing: AppSpacing.tight + 2) {
                    Image(systemName: "hand.tap")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: AppSpacing.tight * 0.25) {
                        Text(String(localized: "当前工程"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "请选择工程"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Label(String(localized: "选择"), systemImage: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, AppSpacing.normal - 2)
                .padding(.vertical, AppSpacing.tight + 1)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.normal - 2)
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var focusedProjectScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.tight) {
                ForEach(dashboardVisibleProjectRows) { row in
                    dashboardProjectButton(row)
                }

                if hiddenDashboardProjectCount > 0 {
                    Button {
                        showDashboardProjectPicker = true
                    } label: {
                        DashboardProjectChip(
                            title: String(localized: "更多 \(hiddenDashboardProjectCount)"),
                            subtitle: String(localized: "查看全部"),
                            isSelected: false,
                            color: .blue
                        )
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func dashboardProjectButton(_ row: DashboardProjectRow) -> some View {
        let project = row.project
        return NavigationLink {
            ProjectDetailView(projectId: project.id)
        } label: {
            DashboardProjectChip(
                title: project.name,
                subtitle: row.subtitle,
                isSelected: currentProject?.id == project.id,
                color: row.color
            )
        }
        .simultaneousGesture(TapGesture().onEnded {
            selectedProjectIdRaw = project.id.uuidString
        })
        .contextMenu {
            Button {
                selectedProjectIdRaw = project.id.uuidString
            } label: {
                Label(String(localized: "设为当前工程"), systemImage: "pin.fill")
            }
            NavigationLink {
                DailyLogView(initialProjectId: project.id, autoOpenComposer: true)
            } label: {
                Label(String(localized: "写日志"), systemImage: "book.pages.fill")
            }
            NavigationLink {
                SiteTodoView(initialProjectId: project.id, autoOpenComposer: true)
            } label: {
                Label(String(localized: "加待办"), systemImage: "checklist")
            }
            NavigationLink {
                ProjectDetailView(projectId: project.id, autoOpenFinancialAdd: true)
            } label: {
                Label(String(localized: "记账"), systemImage: "receipt.fill")
            }
            NavigationLink {
                ProjectDetailView(projectId: project.id, autoOpenDocumentScanSetup: true)
            } label: {
                Label(String(localized: "加资料"), systemImage: "doc.badge.plus")
            }
            NavigationLink {
                ProjectDetailView(projectId: project.id, initialMode: .assets)
            } label: {
                Label(String(localized: "联系人/资料"), systemImage: "person.crop.rectangle.stack")
            }
        }
    }

    private var todayQuickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.tight) {
                TodayMiniAction(
                    title: String(localized: "写日志"),
                    systemImage: "book.pages.fill",
                    color: .green,
                    destination: logEntryDestination,
                    quickActions: logQuickActions,
                    onTrigger: { showQuickActionFeedback(title: String(localized: "写日志")) }
                )
                TodayMiniAction(
                    title: String(localized: "加待办"),
                    systemImage: "checklist",
                    color: .orange,
                    destination: todoEntryDestination,
                    quickActions: todoQuickActions,
                    onTrigger: { showQuickActionFeedback(title: String(localized: "加待办")) }
                )
                TodayMiniAction(
                    title: String(localized: "拍照片"),
                    systemImage: "camera.fill",
                    color: .blue,
                    destination: photoEntryDestination,
                    quickActions: photoQuickActions,
                    onTrigger: { showQuickActionFeedback(title: String(localized: "拍照片")) }
                )
                TodayMiniAction(
                    title: String(localized: "记账"),
                    systemImage: "receipt.fill",
                    color: .pink,
                    destination: bookkeepingEntryDestination,
                    quickActions: bookkeepingQuickActions,
                    onTrigger: { showQuickActionFeedback(title: String(localized: "记账")) }
                )
            }
            .padding(.vertical, AppSpacing.tight * 0.25)
        }
    }

    private var dashboardRiskStrip: some View {
        Group {
            if hasDashboardRisk {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.tight) {
                        DashboardRiskPill(title: String(localized: "延期"), value: "\(overdueCount)", color: overdueCount > 0 ? .red : .green, hasRisk: overdueCount > 0, destination: .projectList(initialOverviewFilter: .overdue))
                        DashboardRiskPill(title: String(localized: "今日待办"), value: "\(todayTodos.count)", color: !todayTodos.isEmpty ? .orange : .green, hasRisk: !todayTodos.isEmpty, destination: .projectList(initialOverviewFilter: .todo))
                        DashboardRiskPill(title: String(localized: "应收付"), value: "\(unsettledFinancialCount)", color: unsettledFinancialCount > 0 ? .yellow : .green, hasRisk: unsettledFinancialCount > 0, destination: .projectList(initialOverviewFilter: .financialDue))
                        DashboardRiskPill(title: String(localized: "未写日志"), value: "\(projectsWithoutTodayLogCount)", color: projectsWithoutTodayLogCount > 0 ? .blue : .green, hasRisk: projectsWithoutTodayLogCount > 0, destination: .projectList(initialOverviewFilter: .missingTodayLog))
                        DashboardRiskPill(title: String(localized: "缺票"), value: "\(unattachedReceiptCount)", color: unattachedReceiptCount > 0 ? .pink : .green, hasRisk: unattachedReceiptCount > 0, destination: .projectList(initialOverviewFilter: .missingReceipt))
                    }
                    .padding(.vertical, AppSpacing.tight * 0.25)
                }
            } else {
                HStack(spacing: AppSpacing.tight) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(String(localized: "今日无风险"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    Text(String(localized: "继续保持"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppSpacing.normal)
                .padding(.vertical, AppSpacing.tight + 1)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.normal - 2)
                        .fill(Color.green.opacity(0.12))
                )
            }
        }
    }

    private var todayTodoPanel: some View {
        DashboardPanel(title: String(localized: "今日待办"), systemImage: "checklist", destination: .siteTodo()) {
            let items = todayTodos.isEmpty ? Array(openTodos.prefix(3)) : Array(todayTodos.prefix(4))
            if items.isEmpty {
                NavigationLink { SiteTodoView() } label: {
                    EmptyDashboardRow(text: String(localized: "暂无现场待办"))
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

    private var todayLogPanel: some View {
        DashboardPanel(title: String(localized: "今日现场"), systemImage: "book.pages.fill", destination: .dailyLog()) {
            if todayLogs.isEmpty {
                NavigationLink { DailyLogView() } label: {
                    EmptyDashboardRow(text: String(localized: "今天还没有施工日志"))
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

    // MARK: 总项目时间轴

    private var projectTimelinePanel: some View {
        let activities = collectRecentActivities(limit: 20)
        return DashboardPanel(title: String(localized: "总项目时间轴"), systemImage: "calendar.badge.clock") {
            if activities.isEmpty {
                HStack {
                    Image(systemName: "tray")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "暂无项目活动，完成一次操作后会显示在这里"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, AppSpacing.tight)
            } else {
                if usesWideDashboardLayout {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: AppSpacing.tight), GridItem(.flexible(), spacing: AppSpacing.tight)],
                        alignment: .leading,
                        spacing: AppSpacing.tight * 0.75
                    ) {
                        ForEach(activities, id: \.id) { activity in
                            TimelineActivityRow(
                                activity: activity,
                                projectName: projectName(activity.projectId)
                            )
                        }
                    }
                } else {
                    VStack(spacing: AppSpacing.tight * 0.75) {
                        ForEach(activities, id: \.id) { activity in
                            TimelineActivityRow(
                                activity: activity,
                                projectName: projectName(activity.projectId)
                            )
                        }
                    }
                }
            }
        }
    }

    private var overduePanel: some View {
        DashboardPanel(title: String(localized: "延期提醒"), systemImage: "calendar.badge.exclamationmark", destination: .projectList(initialOverviewFilter: .overdue)) {
            if overdueTasks.isEmpty && overdueTodos.isEmpty {
                EmptyDashboardRow(text: String(localized: "暂无延期事项"))
            } else {
                VStack(spacing: AppSpacing.tight) {
                    ForEach(overdueTodos.prefix(3)) { todo in
                        NavigationLink {
                            SiteTodoView(initialProjectId: todo.projectId, focusedTodoId: todo.id)
                        } label: {
                            IssueRow(title: todo.title, value: todo.dueDate, color: .red)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(overdueTasks.prefix(3)) { task in
                        NavigationLink {
                            TaskProgressView(initialProjectId: task.projectId)
                        } label: {
                            IssueRow(title: task.title, value: task.dueDate, color: .red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var warehousePanel: some View {
        DashboardPanel(title: String(localized: "库存情况"), systemImage: "shippingbox.fill", destination: warehouseOverviewDestination) {
            let lines = warehouseStockLines
            HStack(spacing: AppSpacing.tight) {
                DashboardInventoryPill(title: String(localized: "材料种类"), value: "\(lines.count)", color: .orange, destination: warehouseOverviewDestination)
                DashboardInventoryPill(title: String(localized: "今日出入库"), value: "\(warehouseTodayMovementCount)", color: warehouseTodayMovementCount > 0 ? .blue : Color.secondary, destination: warehouseMovementDestination)
                DashboardInventoryPill(title: String(localized: "负库存"), value: "\(warehouseNegativeCount)", color: warehouseNegativeCount > 0 ? .red : .green, destination: warehouseOverviewDestination)
            }
            if recentWarehouseMovements.isEmpty {
                EmptyDashboardRow(text: String(localized: "暂无仓库出入库记录"))
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
