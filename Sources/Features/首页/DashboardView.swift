import SwiftUI

struct DashboardView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var dashboardSearchText = ""
    @State private var showGlobalSearch = false
    @State private var showDashboardProjectPicker = false
    @AppStorage("dashboardCurrentProjectId") private var selectedProjectIdRaw = ""
    private let dashboardProjectDisplayLimit = 5

    private var todayStr: String { Formatters.date.string(from: Date()) }
    private var todayLogs: [DailyLog] { store.dailyLogs.filter { $0.date == todayStr } }
    private var activeProjects: [Project] {
        store.projects.filter { $0.status == ProjectStatus.active.rawValue || $0.status == ProjectStatus.paused.rawValue }
    }
    private var currentProject: Project? {
        if let selectedProjectId = UUID(uuidString: selectedProjectIdRaw),
           let selected = activeProjects.first(where: { $0.id == selectedProjectId }) {
            return selected
        }
        return activeProjects.count == 1 ? activeProjects.first : nil
    }
    private var rankedDashboardProjectRows: [DashboardProjectRow] {
        activeProjects
            .map(dashboardProjectRow(for:))
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.activityDate != rhs.activityDate { return lhs.activityDate > rhs.activityDate }
                return lhs.project.name.localizedStandardCompare(rhs.project.name) == .orderedAscending
            }
    }
    private var dashboardVisibleProjectRows: [DashboardProjectRow] {
        let ranked = rankedDashboardProjectRows
        var visible = Array(ranked.prefix(dashboardProjectDisplayLimit))
        if let currentProject,
           !visible.contains(where: { $0.project.id == currentProject.id }),
           let currentRow = ranked.first(where: { $0.project.id == currentProject.id }) {
            visible = [currentRow] + Array(ranked.filter { $0.project.id != currentProject.id }.prefix(max(dashboardProjectDisplayLimit - 1, 0)))
        }
        return visible
    }
    private var hiddenDashboardProjectCount: Int {
        max(activeProjects.count - dashboardVisibleProjectRows.count, 0)
    }
    private var logEntryDestination: AnyView {
        AnyView(DailyLogView(initialProjectId: currentProject?.id, autoOpenComposer: true))
    }
    private var todoEntryDestination: AnyView {
        AnyView(SiteTodoView(initialProjectId: currentProject?.id, autoOpenComposer: true))
    }
    private var photoEntryDestination: AnyView {
        AnyView(WatermarkCameraToolView(initialProjectId: currentProject?.id, autoOpenCameraOnAppear: true))
    }
    private var bookkeepingEntryDestination: AnyView {
        if let project = currentProject {
            return AnyView(ProjectDetailView(projectId: project.id, autoOpenFinancialAdd: true))
        }
        if activeProjects.count > 1 {
            return AnyView(BookkeepingProjectPickerView(projects: activeProjects))
        }
        return AnyView(ProjectListView())
    }
    private var warehouseOverviewDestination: AnyView {
        AnyView(ProjectWarehouseOverviewView())
    }
    private var warehouseMovementDestination: AnyView {
        if let project = currentProject {
            return AnyView(ProjectWarehouseView(project: project))
        }
        return AnyView(ProjectWarehouseOverviewView())
    }
    private var openTodos: [SiteTodo] {
        store.siteTodos.filter { !$0.isDone }
    }
    private var todayTodos: [SiteTodo] {
        openTodos.filter { $0.dueDate == todayStr }
    }
    private var overdueTasks: [ProgressTask] {
        store.progressTasks.filter { task in
            guard task.clampedCompletion < 1, let due = Formatters.date.date(from: task.dueDate) else { return false }
            return due < Calendar.current.startOfDay(for: Date())
        }
    }
    private var overdueTodos: [SiteTodo] {
        store.siteTodos.filter(\.isOverdue)
    }
    private var overdueCount: Int {
        overdueTasks.count + overdueTodos.count
    }
    private var projectsWithoutTodayLogCount: Int {
        activeProjects.filter { project in
            !store.dailyLogs.contains { $0.projectId == project.id && $0.date == todayStr }
        }.count
    }
    private var unattachedReceiptCount: Int {
        store.projectFinancialRecords.filter { record in
            guard record.requiresAttachment else { return false }
            let linkedByRecord = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = store.projectDocuments.contains { $0.linkedFinancialRecordId == record.id }
            return !(linkedByRecord || linkedByDocument)
        }.count
    }
    private var dashboardRiskTotal: Int {
        overdueCount + todayTodos.count + projectsWithoutTodayLogCount + unattachedReceiptCount
    }
    private var hasDashboardRisk: Bool {
        dashboardRiskTotal > 0
    }

    @State private var threeColumnAvailable = false

    private var usesWideDashboardLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }
    private var logQuickActions: [TodayPrimaryQuickAction] {
        var actions: [TodayPrimaryQuickAction] = []
        if let project = currentProject {
            actions.append(
                TodayPrimaryQuickAction(
                    title: "当前项目新建日志（\(project.name)）",
                    systemImage: "building.2.fill",
                    destination: AnyView(DailyLogView(initialProjectId: project.id, autoOpenComposer: true))
                )
            )
        }
        actions.append(
            TodayPrimaryQuickAction(
                title: "直接新建日志",
                systemImage: "square.and.pencil",
                destination: AnyView(DailyLogView(autoOpenComposer: true))
            )
        )
        actions.append(
            TodayPrimaryQuickAction(
                title: "打开日志列表",
                systemImage: "list.bullet",
                destination: AnyView(DailyLogView())
            )
        )
        return actions
    }
    private var todoQuickActions: [TodayPrimaryQuickAction] {
        var actions: [TodayPrimaryQuickAction] = []
        if let project = currentProject {
            actions.append(
                TodayPrimaryQuickAction(
                    title: "当前项目新建待办（\(project.name)）",
                    systemImage: "building.2.fill",
                    destination: AnyView(SiteTodoView(initialProjectId: project.id, autoOpenComposer: true))
                )
            )
        }
        actions.append(
            TodayPrimaryQuickAction(
                title: "直接新建待办",
                systemImage: "plus.circle",
                destination: AnyView(SiteTodoView(autoOpenComposer: true))
            )
        )
        actions.append(
            TodayPrimaryQuickAction(
                title: "打开待办列表",
                systemImage: "list.bullet",
                destination: AnyView(SiteTodoView())
            )
        )
        return actions
    }
    private var photoQuickActions: [TodayPrimaryQuickAction] {
        var actions: [TodayPrimaryQuickAction] = []
        if let project = currentProject {
            actions.append(
                TodayPrimaryQuickAction(
                    title: "当前项目拍摄水印照片（\(project.name)）",
                    systemImage: "camera.fill",
                    destination: AnyView(WatermarkCameraToolView(initialProjectId: project.id, autoOpenCameraOnAppear: true))
                )
            )
        }
        actions.append(
            TodayPrimaryQuickAction(
                title: "打开水印相机",
                systemImage: "camera.badge.ellipsis",
                destination: AnyView(WatermarkCameraToolView(initialProjectId: currentProject?.id))
            )
        )
        actions.append(
            TodayPrimaryQuickAction(
                title: "打开施工日志",
                systemImage: "book.pages.fill",
                destination: AnyView(DailyLogView())
            )
        )
        return actions
    }
    private var bookkeepingQuickActions: [TodayPrimaryQuickAction] {
        var actions: [TodayPrimaryQuickAction] = []
        if activeProjects.count == 1, let project = activeProjects.first {
            actions.append(
                TodayPrimaryQuickAction(
                    title: "当前项目记账（\(project.name)）",
                    systemImage: "receipt.fill",
                    destination: AnyView(ProjectDetailView(projectId: project.id, autoOpenFinancialAdd: true))
                )
            )
        } else if activeProjects.count > 1 {
            actions.append(
                TodayPrimaryQuickAction(
                    title: "先选择项目再记账",
                    systemImage: "list.bullet",
                    destination: AnyView(BookkeepingProjectPickerView(projects: activeProjects))
                )
            )
        }
        actions.append(
            TodayPrimaryQuickAction(
                title: "选择工程记账",
                systemImage: "building.2.fill",
                destination: AnyView(ProjectListView())
            )
        )
        actions.append(
            TodayPrimaryQuickAction(
                title: "打开项目列表",
                systemImage: "list.bullet",
                destination: AnyView(ProjectListView())
            )
        )
        return actions
    }

    var body: some View {
        GeometryReader { geo in
            NavigationStack {
            ScrollView {
                if usesWideDashboardLayout {
                    wideDashboardContent
                } else {
                    compactDashboardContent
                }
            }
            .navigationTitle("今日工作台")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(isPresented: $showGlobalSearch) {
                GlobalSearchView(initialKeyword: dashboardSearchText)
            }
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
            .onAppear {
                threeColumnAvailable = geo.size.width >= 1180
                cleanupSelectedProject()
            }
            .onChange(of: geo.size.width) { _, width in
                threeColumnAvailable = width >= 1180
            }
        }
        }
    }

    private var compactDashboardContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            globalSearchInput
            currentProjectSelector
            todayQuickActions
            dashboardRiskStrip
            warehousePanel
            overduePanel
            todayTodoPanel
            todayLogPanel
        }
        .padding()
    }

    private var wideDashboardContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            globalSearchInput
            currentProjectSelector
            HStack(alignment: .top, spacing: 12) {
                wideDashboardSidebar
                    .frame(minWidth: 286, maxWidth: 340)

                wideDashboardMainPanels
            }
        }
        .padding()
    }

    private var wideDashboardSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            DashboardPanel(title: "今日快捷动作", systemImage: "bolt.fill") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    TodayMiniAction(
                        title: "写日志",
                        systemImage: "book.pages.fill",
                        color: .green,
                        destination: logEntryDestination,
                        quickActions: logQuickActions
                    )
                    TodayMiniAction(
                        title: "加待办",
                        systemImage: "checklist",
                        color: .orange,
                        destination: todoEntryDestination,
                        quickActions: todoQuickActions
                    )
                    TodayMiniAction(
                        title: "拍照片",
                        systemImage: "camera.fill",
                        color: .blue,
                        destination: photoEntryDestination,
                        quickActions: photoQuickActions
                    )
                    TodayMiniAction(
                        title: "记账",
                        systemImage: "receipt.fill",
                        color: .pink,
                        destination: bookkeepingEntryDestination,
                        quickActions: bookkeepingQuickActions
                    )
                }
            }

            DashboardPanel(title: "风险条", systemImage: "exclamationmark.triangle.fill", destination: AnyView(SiteTodoView())) {
                dashboardRiskStrip
            }
        }
    }

    private var wideDashboardMainPanels: some View {
        let columns = threeColumnAvailable
            ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible(), spacing: 12)]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            warehousePanel
            overduePanel
            todayTodoPanel
            todayLogPanel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var globalSearchInput: some View {
        let hasSearchKeyword = !dashboardSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索项目、联系人、票号、日志、资料", text: $dashboardSearchText)
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                .onSubmit { openDashboardSearch() }
            if hasSearchKeyword {
                Button(action: openDashboardSearch) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("搜索")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
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
            HStack(spacing: 8) {
                Label("暂无进行中工程", systemImage: "building.2")
                Spacer()
                Text("去添加")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    private var focusedProjectSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            focusedProjectHeader
            focusedCurrentProjectPrimaryRow
            if activeProjects.count > 1 {
                focusedProjectScroller
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }

    private var focusedProjectHeader: some View {
        HStack(spacing: 8) {
            Label("今日关注工程", systemImage: "scope")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            if activeProjects.count > dashboardProjectDisplayLimit {
                Text("关注 \(dashboardVisibleProjectRows.count)/\(activeProjects.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if activeProjects.count > 1, currentProject == nil {
                Text("请选择工程")
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
                HStack(spacing: 10) {
                    Image(systemName: "pin.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前工程")
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
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        } else {
            Button {
                showDashboardProjectPicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "hand.tap")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前工程")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("请选择工程")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Label("选择", systemImage: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var focusedProjectScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(dashboardVisibleProjectRows) { row in
                    dashboardProjectButton(row)
                }

                if hiddenDashboardProjectCount > 0 {
                    Button {
                        showDashboardProjectPicker = true
                    } label: {
                        DashboardProjectChip(
                            title: "更多 \(hiddenDashboardProjectCount)",
                            subtitle: "查看全部",
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
                Label("设为当前工程", systemImage: "pin.fill")
            }
            NavigationLink {
                DailyLogView(initialProjectId: project.id, autoOpenComposer: true)
            } label: {
                Label("写日志", systemImage: "book.pages.fill")
            }
            NavigationLink {
                SiteTodoView(initialProjectId: project.id, autoOpenComposer: true)
            } label: {
                Label("加待办", systemImage: "checklist")
            }
            NavigationLink {
                ProjectDetailView(projectId: project.id, autoOpenFinancialAdd: true)
            } label: {
                Label("记账", systemImage: "receipt.fill")
            }
            NavigationLink {
                ProjectDetailView(projectId: project.id, autoOpenDocumentScanSetup: true)
            } label: {
                Label("加资料", systemImage: "doc.badge.plus")
            }
            NavigationLink {
                ProjectDetailView(projectId: project.id, initialMode: .assets)
            } label: {
                Label("联系人/资料", systemImage: "person.crop.rectangle.stack")
            }
        }
    }

    private var todayQuickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                TodayMiniAction(
                    title: "写日志",
                    systemImage: "book.pages.fill",
                    color: .green,
                    destination: logEntryDestination,
                    quickActions: logQuickActions
                )
                TodayMiniAction(
                    title: "加待办",
                    systemImage: "checklist",
                    color: .orange,
                    destination: todoEntryDestination,
                    quickActions: todoQuickActions
                )
                TodayMiniAction(
                    title: "拍照片",
                    systemImage: "camera.fill",
                    color: .blue,
                    destination: photoEntryDestination,
                    quickActions: photoQuickActions
                )
                TodayMiniAction(
                    title: "记账",
                    systemImage: "receipt.fill",
                    color: .pink,
                    destination: bookkeepingEntryDestination,
                    quickActions: bookkeepingQuickActions
                )
            }
            .padding(.vertical, 2)
        }
    }

    private var dashboardRiskStrip: some View {
        Group {
            if hasDashboardRisk {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        DashboardRiskPill(title: "延期", value: "\(overdueCount)", color: overdueCount > 0 ? .red : .green, destination: AnyView(SiteTodoView()))
                        DashboardRiskPill(title: "今日待办", value: "\(todayTodos.count)", color: todayTodos.isEmpty ? .green : .orange, destination: AnyView(SiteTodoView()))
                        DashboardRiskPill(title: "未写日志", value: "\(projectsWithoutTodayLogCount)", color: projectsWithoutTodayLogCount > 0 ? .blue : .green, destination: AnyView(DailyLogView()))
                        DashboardRiskPill(title: "缺票", value: "\(unattachedReceiptCount)", color: unattachedReceiptCount > 0 ? .pink : .green, destination: AnyView(ProjectListView(initialOverviewFilter: .missingReceipt)))
                    }
                    .padding(.vertical, 2)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Text("今日无风险")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    Text("继续保持")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.green.opacity(0.12))
                )
            }
        }
    }

    private var todayTodoPanel: some View {
        DashboardPanel(title: "今日待办", systemImage: "checklist", destination: AnyView(SiteTodoView())) {
            let items = todayTodos.isEmpty ? Array(openTodos.prefix(3)) : Array(todayTodos.prefix(4))
            if items.isEmpty {
                NavigationLink { SiteTodoView() } label: {
                    EmptyDashboardRow(text: "暂无现场待办")
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
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
        DashboardPanel(title: "今日现场", systemImage: "book.pages.fill", destination: AnyView(DailyLogView())) {
            if todayLogs.isEmpty {
                NavigationLink { DailyLogView() } label: {
                    EmptyDashboardRow(text: "今天还没有施工日志")
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 8) {
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

    private var overduePanel: some View {
        DashboardPanel(title: "延期提醒", systemImage: "calendar.badge.exclamationmark", destination: AnyView(SiteTodoView())) {
            if overdueTasks.isEmpty && overdueTodos.isEmpty {
                EmptyDashboardRow(text: "暂无延期事项")
            } else {
                VStack(spacing: 8) {
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
        DashboardPanel(title: "库存情况", systemImage: "shippingbox.fill", destination: warehouseOverviewDestination) {
            let lines = activeProjects.flatMap { project in
                WarehouseStockCalculator.stockLines(for: project.id, movements: store.projectWarehouseMovements)
            }
            let todayMovementCount = store.projectWarehouseMovements.filter { $0.date == todayStr }.count
            let negativeCount = lines.filter { $0.quantity < 0 }.count
            HStack(spacing: 8) {
                DashboardInventoryPill(title: "材料种类", value: "\(lines.count)", color: .orange, destination: warehouseOverviewDestination)
                DashboardInventoryPill(title: "今日出入库", value: "\(todayMovementCount)", color: todayMovementCount > 0 ? .blue : Color.secondary, destination: warehouseMovementDestination)
                DashboardInventoryPill(title: "负库存", value: "\(negativeCount)", color: negativeCount > 0 ? .red : .green, destination: warehouseOverviewDestination)
            }
            let recent = store.projectWarehouseMovements.sorted { $0.createdAt > $1.createdAt }.prefix(3)
            if recent.isEmpty {
                EmptyDashboardRow(text: "暂无仓库出入库记录")
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(recent)) { movement in
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

    private func projectName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return store.projects.first(where: { $0.id == id })?.name
    }

    private func warehouseLinkedDocuments(for movement: ProjectWarehouseMovement) -> [ProjectDocument] {
        let documentIds = Set(movement.linkedDocumentIds)
        guard !documentIds.isEmpty else { return [] }
        return store.projectDocuments.filter { documentIds.contains($0.id) }
    }

    private func openDashboardSearch() {
        guard !dashboardSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        showGlobalSearch = true
    }

    private func cleanupSelectedProject() {
        guard !selectedProjectIdRaw.isEmpty else { return }
        if !activeProjects.contains(where: { $0.id.uuidString == selectedProjectIdRaw }) {
            selectedProjectIdRaw = ""
        }
    }

    private func dashboardProjectRow(for project: Project) -> DashboardProjectRow {
        let signal = dashboardProjectSignal(for: project)
        return DashboardProjectRow(
            project: project,
            subtitle: signal.subtitle,
            color: signal.color,
            score: signal.score,
            activityDate: recentActivityDate(for: project)
        )
    }

    private func dashboardProjectSignal(for project: Project) -> DashboardProjectSignal {
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
            return DashboardProjectSignal(subtitle: "延期 \(overdue)", color: .red, score: score)
        }
        if todayTodo > 0 {
            return DashboardProjectSignal(subtitle: "今日 \(todayTodo)", color: .orange, score: score)
        }
        if missingReceipt > 0 {
            return DashboardProjectSignal(subtitle: "缺票 \(missingReceipt)", color: .pink, score: score)
        }
        if missingLog {
            return DashboardProjectSignal(subtitle: "未写日志", color: .blue, score: score)
        }
        if openTodos > 0 {
            return DashboardProjectSignal(subtitle: "待办 \(openTodos)", color: .orange, score: score)
        }
        return DashboardProjectSignal(subtitle: "最近使用", color: .green, score: score)
    }

    private func overdueCount(for project: Project) -> Int {
        let today = Calendar.current.startOfDay(for: Date())
        let overdueProgress = store.progressTasks.filter { task in
            guard task.projectId == project.id,
                  task.clampedCompletion < 1,
                  let due = Formatters.date.date(from: task.dueDate) else { return false }
            return due < today
        }.count
        let overdueTodos = store.siteTodos.filter { $0.projectId == project.id && $0.isOverdue }.count
        return overdueProgress + overdueTodos
    }

    private func todayTodoCount(for project: Project) -> Int {
        store.siteTodos.filter {
            $0.projectId == project.id && !$0.isDone && $0.dueDate == todayStr
        }.count
    }

    private func openTodoCount(for project: Project) -> Int {
        store.siteTodos.filter { $0.projectId == project.id && !$0.isDone }.count
    }

    private func unattachedReceiptCount(for project: Project) -> Int {
        store.projectFinancialRecords.filter { record in
            guard record.projectId == project.id, record.requiresAttachment else { return false }
            let linkedByRecord = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = store.projectDocuments.contains { $0.linkedFinancialRecordId == record.id }
            return !(linkedByRecord || linkedByDocument)
        }.count
    }

    private func hasTodayLog(for project: Project) -> Bool {
        store.dailyLogs.contains { $0.projectId == project.id && $0.date == todayStr }
    }

    private func recentActivityDate(for project: Project) -> Date {
        var dates: [Date] = []
        let projectId = project.id
        if let start = Formatters.date.date(from: project.startDate) {
            dates.append(start)
        }
        for item in store.dailyLogs where item.projectId == projectId {
            if let date = Formatters.date.date(from: item.date) {
                dates.append(date)
            }
        }
        for item in store.paymentRecords where item.projectId == projectId {
            if let date = Formatters.date.date(from: item.date) {
                dates.append(date)
            }
        }
        for item in store.projectFinancialRecords where item.projectId == projectId {
            if let date = Formatters.date.date(from: item.date) {
                dates.append(date)
            }
        }
        for item in store.laborRecords where item.projectId == projectId {
            if let date = Formatters.date.date(from: item.date) {
                dates.append(date)
            }
        }
        for item in store.progressTasks where item.projectId == projectId {
            if let date = Formatters.date.date(from: item.startDate) {
                dates.append(date)
            }
            if let date = Formatters.date.date(from: item.dueDate) {
                dates.append(date)
            }
        }
        for item in store.siteTodos where item.projectId == projectId {
            if let date = Formatters.date.date(from: item.dueDate) {
                dates.append(date)
            }
        }
        for item in store.projectDrawings where item.projectId == projectId {
            if let date = Formatters.dateTime.date(from: item.importedAt) {
                dates.append(date)
            }
        }
        for item in store.projectDocuments where item.projectId == projectId {
            if let date = Formatters.dateTime.date(from: item.createdAt) {
                dates.append(date)
            }
        }
        return dates.max() ?? .distantPast
    }
}

private struct ProjectContextRow: View {
    let project: Project
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(project.name)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(project.status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 8) {
                if !project.location.isEmpty {
                    Label(project.location, systemImage: "mappin.and.ellipse")
                }
                if !project.managerName.isEmpty {
                    Label(project.managerName, systemImage: "person.fill")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(note)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DashboardProjectRow: Identifiable {
    var id: UUID { project.id }
    let project: Project
    let subtitle: String
    let color: Color
    let score: Int
    let activityDate: Date
}

private struct DashboardProjectSignal {
    let subtitle: String
    let color: Color
    let score: Int
}

private struct DashboardProjectPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rows: [DashboardProjectRow]
    let selectedProjectId: UUID?
    let onSelect: (UUID?) -> Void
    @State private var searchText = ""

    private var filteredRows: [DashboardProjectRow] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return rows }
        return rows.filter {
            $0.project.name.localizedStandardContains(query)
            || $0.project.location.localizedStandardContains(query)
            || $0.subtitle.localizedStandardContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("今日关注工程") {
                    ForEach(filteredRows) { row in
                        Button {
                            onSelect(row.project.id)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selectedProjectId == row.project.id ? "checkmark.circle.fill" : "building.2")
                                    .foregroundStyle(selectedProjectId == row.project.id ? row.color : .secondary)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(row.project.name)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 8) {
                                        Text(row.subtitle)
                                            .foregroundStyle(row.color)
                                        if !row.project.location.isEmpty {
                                            Text(row.project.location)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索工程")
            .navigationTitle("选择当前工程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct DashboardProjectChip: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let color: Color

    private var minChipWidth: CGFloat {
        isSelected ? 124 : 104
    }

    private var maxChipWidth: CGFloat {
        isSelected ? 240 : 152
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isSelected ? .white : color)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(subtitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(isSelected ? .white.opacity(0.88) : color)
                .lineLimit(1)
        }
        .frame(minWidth: minChipWidth, maxWidth: maxChipWidth, alignment: .leading)
        .frame(minHeight: 52, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? color : color.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(isSelected ? color : color.opacity(0.28), lineWidth: 1)
        )
    }
}

