import SwiftUI

struct DashboardView: View {
    @Environment(DataStore.self) var store
    @Environment(ProjectStore.self) var projectStore
    @Environment(FinanceStore.self) var financeStore
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State var dashboardSearchText = ""
    @State var dashboardSearchProjectID: UUID?
    @State var dashboardSearchCategory: RealtimeSearchSuggestion.Category?
    @State var selectedDashboardSuggestion: RealtimeSearchSuggestion?
    @State private var selectedDashboardDestination: DashboardDestinationSelection?
    @State var showDashboardProjectPicker = false
    @State var quickActionToastMessage: String?
    @State private var containerWidth: CGFloat = 0
    @AppStorage(UserPreferenceKeys.dashboardCurrentProjectId) var selectedProjectIdRaw = ""
    @AppStorage(UserPreferenceKeys.dashboardIgnoredBackupRiskDay) var ignoredBackupRiskDay = ""
    @AppStorage(UserPreferenceKeys.dashboardIgnoredMissingReceiptRiskDay) var ignoredMissingReceiptRiskDay = ""
    @AppStorage(UserPreferenceKeys.dashboardIgnoredPriceSpikeRiskDay) var ignoredPriceSpikeRiskDay = ""
    @AppStorage(UserPreferenceKeys.dashboardIgnoredNegativeStockRiskDay) var ignoredNegativeStockRiskDay = ""
    let dashboardProjectDisplayLimit = 5

    var body: some View {
        NavigationStack {
            ScrollView {
                if usesWideDashboardLayout {
                    wideDashboardContent(containerWidth: containerWidth)
                } else {
                    compactDashboardContent
                }
            }
            .background(DashboardWidthReader(width: $containerWidth))
            .overlay(alignment: .top) {
                if let quickActionToastMessage {
                    DashboardToastView(message: quickActionToastMessage)
                        .padding(.top, AppSpacing.normal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.22), value: quickActionToastMessage)
            .navigationTitle(AppLocalization.string("今日工作台"))
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
            .onChange(of: projectStore.projects.map(\.id)) { _, ids in
                if let id = dashboardSearchProjectID, !ids.contains(id) { dashboardSearchProjectID = nil }
            }
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
                        Text(AppLocalization.string("更多概况"))
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
                .accessibilityIdentifier("dashboard-more-overview")
            } else {
                VStack(spacing: AppSpacing.normal) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(Color.appSuccess)
                    Text(AppLocalization.string("全部良好"))
                        .font(.title3.weight(.semibold))
                    Text(AppLocalization.string("暂无新增提醒，继续保持"))
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
            DashboardPanel(title: AppLocalization.string("今日快捷动作"), systemImage: "bolt.fill") {
                VStack(alignment: .leading, spacing: AppSpacing.tight) {
                    DashboardQuickActionButtons(items: primaryQuickActions, onTrigger: showQuickActionFeedback)
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

    private var currentProjectSelector: some View {
        DashboardProjectSelector(
            activeProjectCount: activeProjects.count,
            displayLimit: dashboardProjectDisplayLimit,
            rows: dashboardVisibleProjectRows,
            hiddenProjectCount: hiddenDashboardProjectCount,
            selectedProjectID: currentProject?.id,
            selectedProjectIdRaw: $selectedProjectIdRaw,
            onShowPicker: { showDashboardProjectPicker = true }
        )
    }

    private var todayQuickActions: some View {
        DashboardQuickActions(items: primaryQuickActions, onTrigger: showQuickActionFeedback)
    }

    private var primaryQuickActions: [DashboardQuickActionItem] {
        [
            DashboardQuickActionItem(
                title: AppLocalization.string("写日志"),
                systemImage: "book.pages.fill",
                color: .appSuccess,
                destination: logEntryDestination,
                quickActions: logQuickActions
            ),
            DashboardQuickActionItem(
                title: AppLocalization.string("加待办"),
                systemImage: "checklist",
                color: .appWarning,
                destination: todoEntryDestination,
                quickActions: todoQuickActions
            ),
            DashboardQuickActionItem(
                title: AppLocalization.string("拍照片"),
                systemImage: "camera.fill",
                color: .appDoc,
                destination: photoEntryDestination,
                quickActions: photoQuickActions
            ),
            DashboardQuickActionItem(
                title: AppLocalization.string("记账"),
                systemImage: "receipt.fill",
                color: .appFinance,
                destination: bookkeepingEntryDestination,
                quickActions: bookkeepingQuickActions
            )
        ]
    }

    private var dashboardRiskStrip: some View {
        DashboardRiskStrip(hasDashboardRisk: hasDashboardRisk, pins: visibleDashboardRiskPins)
    }

    private var businessOverviewPanel: some View {
        DashboardBusinessOverviewPanel(
            summary: dashboardBusinessSummary,
            projectCount: activeProjects.count,
            onOpen: { openDashboardDestination(.projectList(initialOverviewFilter: $0)) }
        )
    }
}

private extension DashboardView {
    func openDashboardDestination(_ destination: DashboardDestination) {
        AppHaptics.impact(.light)
        selectedDashboardDestination = DashboardDestinationSelection(destination: destination)
    }
}

private struct DashboardWidthReader: View {
    @Binding var width: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newWidth in width = newWidth }
        }
    }
}
