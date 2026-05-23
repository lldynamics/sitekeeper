import SwiftUI

struct DashboardView: View {
    @Environment(DataStore.self) var store
    @Environment(ProjectStore.self) var projectStore
    @Environment(FinanceStore.self) var financeStore
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State var dashboardSearchText = ""
    @State private var selectedDashboardSuggestion: RealtimeSearchSuggestion?
    @State private var selectedDashboardDestination: DashboardDestinationSelection?
    @State var showDashboardProjectPicker = false
    @State var quickActionToastMessage: String?
    @AppStorage(UserPreferenceKeys.dashboardCurrentProjectId) var selectedProjectIdRaw = ""
    @AppStorage(UserPreferenceKeys.dashboardIgnoredBackupRiskDay) var ignoredBackupRiskDay = ""
    @AppStorage(UserPreferenceKeys.dashboardIgnoredMissingReceiptRiskDay) var ignoredMissingReceiptRiskDay = ""
    @AppStorage(UserPreferenceKeys.dashboardIgnoredPriceSpikeRiskDay) var ignoredPriceSpikeRiskDay = ""
    @AppStorage(UserPreferenceKeys.dashboardIgnoredNegativeStockRiskDay) var ignoredNegativeStockRiskDay = ""
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
            .task {
                store.scheduleDataHealthScanIfStale()
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
            .navigationDestination(item: $selectedDashboardSuggestion) { suggestion in
                dashboardDestinationView(dashboardDestination(for: suggestion))
            }
            .navigationDestination(item: $selectedDashboardDestination) { selection in
                dashboardDestinationView(selection.destination)
            }
            .onAppear(perform: cleanupSelectedProject)
            .task(id: quickActionToastMessage) {
                await dismissQuickActionToastAfterDelay()
            }
        }
    }

    @State private var showMoreOverview = false
    private var hasCompactOverviewSignal: Bool {
        !activeProjects.isEmpty
            || hasDashboardRisk
            || !warehouseStockLines.isEmpty
            || overdueCount > 0
            || !todayTodos.isEmpty
            || !todayLogs.isEmpty
    }

    private var showsBusinessOverviewPanel: Bool {
        !activeProjects.isEmpty
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
                        if showsBusinessOverviewPanel {
                            businessOverviewPanel
                        }
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
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(Color.appSuccess)
                    Text(String(localized: "全部良好"))
                        .font(.title3.weight(.semibold))
                    Text(String(localized: "暂无新增提醒，继续保持"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background {
                    AppSurface(tone: .grouped, cornerRadius: AppSpacing.normal) {
                        Color.clear
                    }
                }
            }
            projectTimelinePanel
        }
        .padding()
    }

    @ViewBuilder
    private func wideDashboardContent(containerWidth: CGFloat) -> some View {
        if containerWidth < 820 {
            compactDashboardContent
        } else {
            wideDashboardTwoColumnContent(containerWidth: containerWidth)
        }
    }

    private func wideDashboardTwoColumnContent(containerWidth: CGFloat) -> some View {
        let sidebarWidth = min(max(containerWidth * 0.27, 300), 336)
        return VStack(alignment: .leading, spacing: AppSpacing.normal) {
            wideDashboardTopSection

            HStack(alignment: .top, spacing: AppSpacing.normal) {
                wideDashboardSidebar
                    .frame(width: sidebarWidth, alignment: .topLeading)

                VStack(alignment: .leading, spacing: AppSpacing.normal) {
                    wideDashboardMainPanels
                    projectTimelinePanel
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, AppSpacing.relaxed)
        .padding(.vertical, AppSpacing.normal)
    }

    private var wideDashboardTopSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            globalSearchInput
            currentProjectSelector
        }
    }

    private var wideDashboardSidebar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.normal) {
            DashboardPanel(title: String(localized: "今日快捷动作"), systemImage: "bolt.fill") {
                VStack(alignment: .leading, spacing: AppSpacing.tight) {
                    TodayMiniAction(title: String(localized: "写日志"), systemImage: "book.pages.fill", color: .appSuccess, destination: logEntryDestination, quickActions: logQuickActions, onTrigger: { showQuickActionFeedback(title: String(localized: "写日志")) })
                    TodayMiniAction(title: String(localized: "加待办"), systemImage: "checklist", color: .appWarning, destination: todoEntryDestination, quickActions: todoQuickActions, onTrigger: { showQuickActionFeedback(title: String(localized: "加待办")) })
                    TodayMiniAction(title: String(localized: "拍照片"), systemImage: "camera.fill", color: .appDoc, destination: photoEntryDestination, quickActions: photoQuickActions, onTrigger: { showQuickActionFeedback(title: String(localized: "拍照片")) })
                    TodayMiniAction(title: String(localized: "记账"), systemImage: "receipt.fill", color: .appFinance, destination: bookkeepingEntryDestination, quickActions: bookkeepingQuickActions, onTrigger: { showQuickActionFeedback(title: String(localized: "记账")) })
                }
            }

            if hasDashboardRisk { dashboardRiskStrip }
        }
    }

    private var wideDashboardMainPanels: some View {
        LazyVGrid(columns: wideDashboardPanelColumns, alignment: .leading, spacing: AppSpacing.normal) {
            if showsBusinessOverviewPanel {
                businessOverviewPanel
            }
            warehousePanel
            overduePanel
            todayTodoPanel
            todayLogPanel
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var wideDashboardPanelColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 310), spacing: AppSpacing.normal)]
    }

    private var globalSearchInput: some View {
        InlineSearchPanel(
            text: $dashboardSearchText,
            prompt: String(localized: "搜索项目、联系人、供应商、材料或命令"),
            suggestions: dashboardSearchSuggestions,
            emptyStateText: String(localized: "未找到匹配的项目、联系人、供应商、材料或命令"),
            materialTone: .materialThin,
            onSelectSuggestion: { suggestion in
                dashboardSearchText = ""
                selectedDashboardSuggestion = suggestion
            }
        )
    }

    @ViewBuilder
    private var currentProjectSelector: some View {
        if activeProjects.isEmpty {
            emptyCurrentProjectSelector
        } else {
            focusedProjectScrollerShell
        }
    }

    private var emptyCurrentProjectSelector: some View {
        NavigationLink { ProjectListView() } label: {
            HStack(spacing: AppSpacing.tight) {
                Label(String(localized: "暂无进行中工程"), systemImage: "building.2")
                Spacer()
                Text(String(localized: "去添加"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appPrimaryAction)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppSpacing.normal)
        .padding(.vertical, AppSpacing.tight + 1)
        .background {
            AppSurface(tone: .grouped, cornerRadius: AppSpacing.normal - 2) {
                Color.clear
            }
        }
    }

    private var focusedProjectScrollerShell: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            HStack(spacing: AppSpacing.tight) {
                Label(String(localized: "进行中的工程"), systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if activeProjects.count > dashboardProjectDisplayLimit {
                    Text(String(format: String(localized: "共 %lld 个"), Int64(activeProjects.count)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

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
                                title: String(format: String(localized: "更多 %lld"), Int64(hiddenDashboardProjectCount)),
                                subtitle: String(localized: "查看全部"),
                                isSelected: false,
                                color: .appDoc
                            )
                        }
                    }
                }
            }
        }
        .padding(.horizontal, AppSpacing.normal)
        .padding(.vertical, AppSpacing.tight + 1)
        .background {
            AppSurface(tone: .grouped, cornerRadius: AppSpacing.normal - 2) {
                Color.clear
            }
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
                    color: .appSuccess,
                    destination: logEntryDestination,
                    quickActions: logQuickActions,
                    onTrigger: { showQuickActionFeedback(title: String(localized: "写日志")) }
                )
                TodayMiniAction(
                    title: String(localized: "加待办"),
                    systemImage: "checklist",
                    color: .appWarning,
                    destination: todoEntryDestination,
                    quickActions: todoQuickActions,
                    onTrigger: { showQuickActionFeedback(title: String(localized: "加待办")) }
                )
                TodayMiniAction(
                    title: String(localized: "拍照片"),
                    systemImage: "camera.fill",
                    color: .appDoc,
                    destination: photoEntryDestination,
                    quickActions: photoQuickActions,
                    onTrigger: { showQuickActionFeedback(title: String(localized: "拍照片")) }
                )
                TodayMiniAction(
                    title: String(localized: "记账"),
                    systemImage: "receipt.fill",
                    color: .appFinance,
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
                        ForEach(visibleDashboardRiskPins) { pin in
                            DashboardRiskPill(
                                title: pin.title,
                                value: pin.value,
                                color: pin.color,
                                hasRisk: pin.hasRisk,
                                destination: pin.destination,
                                quickActions: pin.quickActions
                            )
                        }
                    }
                    .padding(.vertical, AppSpacing.tight * 0.25)
                }
            } else {
                HStack(spacing: AppSpacing.tight) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appSuccess)
                    Text(String(localized: "今日无风险"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appSuccess)
                    Spacer()
                    Text(String(localized: "继续保持"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, AppSpacing.normal)
                .padding(.vertical, AppSpacing.tight + 1)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.normal - 2)
                        .fill(Color.appWillowSurfaceSubtle)
                )
            }
        }
    }

    private var businessOverviewPanel: some View {
        DashboardPanel(
            title: String(localized: "经营概况"),
            systemImage: "chart.xyaxis.line",
            destination: .projectList()
        ) {
            ProjectBusinessCardsView(
                summary: dashboardBusinessSummary,
                onOpenReceivableAging: {
                    openDashboardDestination(.projectList(initialOverviewFilter: .receivableAging))
                },
                onOpenRecentCollection: {
                    openDashboardDestination(.projectList(initialOverviewFilter: .recentCollection))
                },
                onOpenCostAnomaly: {
                    openDashboardDestination(.projectList(initialOverviewFilter: .costAnomaly))
                },
                onOpenProfitRisk: {
                    openDashboardDestination(.projectList(initialOverviewFilter: .lowMarginRisk))
                }
            )
            Text(String(format: String(localized: "已关注 %lld 个工程"), Int64(activeProjects.count)))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func openDashboardDestination(_ destination: DashboardDestination) {
        AppHaptics.impact(.light)
        selectedDashboardDestination = DashboardDestinationSelection(destination: destination)
    }
}
