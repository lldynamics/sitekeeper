import SwiftUI
import UIKit

struct DashboardView: View {
    @Environment(DataStore.self) var store
    @Environment(ProjectStore.self) var projectStore
    @Environment(FinanceStore.self) var financeStore
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.expandedPhoneWorkspaceWidth) private var rootWorkspaceWidth
    @State var dashboardSearchText = ""
    @State var dashboardSearchProjectID: UUID?
    @State var dashboardSearchCategory: RealtimeSearchSuggestion.Category?
    @State var selectedDashboardSuggestion: RealtimeSearchSuggestion?
    @State private var selectedDashboardDestination: DashboardDestinationSelection?
    @State var showDashboardProjectPicker = false
    @State var quickActionToastMessage: String?
    @State private var containerWidth: CGFloat = 0
    @State private var padHeaderMeasuredHeight: CGFloat = 240
    @ScaledMetric(relativeTo: .body) private var independentPadMinimumWidth: CGFloat = 820
    @ScaledMetric(relativeTo: .body) private var independentPadMinimumHeight: CGFloat = 520
    @ScaledMetric(relativeTo: .body) private var phoneMinimumPaneHeight: CGFloat = 240
    @AppStorage(UserPreferenceKeys.dashboardCurrentProjectId) var selectedProjectIdRaw = ""
    @AppStorage(UserPreferenceKeys.dashboardIgnoredBackupRiskDay) var ignoredBackupRiskDay = ""
    @AppStorage(UserPreferenceKeys.dashboardIgnoredMissingReceiptRiskDay) var ignoredMissingReceiptRiskDay = ""
    @AppStorage(UserPreferenceKeys.dashboardIgnoredPriceSpikeRiskDay) var ignoredPriceSpikeRiskDay = ""
    @AppStorage(UserPreferenceKeys.dashboardIgnoredNegativeStockRiskDay) var ignoredNegativeStockRiskDay = ""
    let dashboardProjectDisplayLimit = 5

    var body: some View {
        NavigationStack {
            dashboardBodyContent
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
            .navigationBarTitleDisplayMode(usesExpandedPhoneDashboard ? .inline : .large)
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

    private var dashboardBodyContent: some View {
        GeometryReader { geometry in
            if ExpandedPhoneWorkspaceLayout.isAvailable(
                width: geometry.size.width,
                minimumWidth: independentPadMinimumWidth
            ) {
                independentPhoneDashboardContainer(size: geometry.size)
            } else if UIDevice.current.userInterfaceIdiom == .pad,
                      usesWideDashboardLayout,
                      geometry.size.width >= max(820, independentPadMinimumWidth) {
                independentPadDashboardContainer(size: geometry.size)
            } else {
                dashboardScrollContent
            }
        }
    }

    private var usesExpandedPhoneDashboard: Bool {
        ExpandedPhoneWorkspaceLayout.isAvailable(width: containerWidth, minimumWidth: independentPadMinimumWidth)
    }

    private func independentPhoneDashboardContainer(size: CGSize) -> some View {
        // One outer scroller owns navigation/keyboard insets. Short viewports can reach
        // the complete header and panes without moving any content outside that viewport.
        ScrollView(.vertical) {
            independentPhoneDashboard(size: size)
                .frame(width: size.width, alignment: .topLeading)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .modifier(ExpandedPhoneScrollEdgeModifier(isExpanded: true))
    }

    private func independentPhoneDashboard(size: CGSize) -> some View {
        let contentWidth = max(0, size.width - AppSpacing.relaxed * 2 - AppSpacing.normal)
        let workspaceWidth = rootWorkspaceWidth.isFinite && rootWorkspaceWidth > 0 ? rootWorkspaceWidth : size.width
        let sidebarTrackWidth = ExpandedPhoneWorkspaceLayout.sidebarWidth(
            containerWidth: workspaceWidth,
            minimumWorkspaceWidth: independentPadMinimumWidth
        )
        // The card begins after the workspace's leading padding; its trailing edge
        // aligns with the same sidebar track used by Projects, Toolbox and Quick Notes.
        let overviewWidth = max(0, min(contentWidth, sidebarTrackWidth - AppSpacing.relaxed))

        return DashboardPhoneWorkspaceLayout(
            viewportSize: CGSize(width: max(0, size.width - AppSpacing.relaxed * 2),
                                 height: max(0, size.height - AppSpacing.tight * 2)),
            minimumPaneHeight: phoneMinimumPaneHeight,
            spacing: AppSpacing.normal
        ) {
            // Measure the complete intrinsic header directly, not a nested scroll viewport.
            globalSearchInput
                .fixedSize(horizontal: false, vertical: true)
                .accessibilitySortPriority(2)

            HStack(alignment: .top, spacing: AppSpacing.normal) {
                DashboardPanel(title: AppLocalization.string("工作概况"), systemImage: "chart.bar.xaxis") {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: AppSpacing.normal) {
                            currentProjectSelector
                            todayQuickActions
                            todayTodoPanel
                            if showsBusinessOverviewPanel {
                                businessOverviewPanel
                            }
                            warehousePanel
                            todayLogPanel
                            overduePanel
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(.visible)
                    .accessibilityIdentifier("dashboard-expanded-phone-overview-scroll")
                }
                .frame(width: overviewWidth)
                .frame(maxHeight: .infinity, alignment: .topLeading)

                DashboardPanel(title: AppLocalization.string("时间轴"), systemImage: "calendar.badge.clock") {
                    ScrollView(.vertical) {
                        dashboardTimelineContent(prefersSingleColumn: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(.visible)
                    .accessibilityIdentifier("dashboard-expanded-phone-timeline-scroll")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.red.opacity(0.28))
                    .frame(width: 2)
                    .offset(x: overviewWidth - 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            dashboardRiskStrip
                .fixedSize(horizontal: false, vertical: true)
                .accessibilitySortPriority(1)
        }
        .padding(.horizontal, AppSpacing.relaxed)
        .padding(.vertical, AppSpacing.tight)
    }

    private func independentPadDashboardContainer(size: CGSize) -> some View {
        let workspaceHeight = max(size.height, independentPadMinimumHeight)
        // Change only the outer scroll axes, keeping search focus and both pane owners stable.
        // With enough height there is no outer vertical scrolling; short viewports can reach every pane.
        return ScrollView(size.height < independentPadMinimumHeight ? .vertical : []) {
            independentPadDashboard(size: CGSize(width: size.width, height: workspaceHeight))
                .frame(width: size.width, height: workspaceHeight, alignment: .topLeading)
        }
    }

    private var dashboardScrollContent: some View {
        ScrollView {
            if usesWideDashboardLayout {
                wideDashboardContent(containerWidth: containerWidth)
            } else {
                compactDashboardContent
            }
        }
    }

    private func independentPadDashboard(size: CGSize) -> some View {
        let contentWidth = max(0, size.width - AppSpacing.relaxed * 2 - AppSpacing.normal)
        let overviewWidth = min(max(contentWidth * 0.42, 340), 520)

        return VStack(alignment: .leading, spacing: AppSpacing.normal) {
            independentPadHeader(maximumHeight: max(0, size.height * 0.4))

            HStack(alignment: .top, spacing: AppSpacing.normal) {
                DashboardPanel(title: AppLocalization.string("时间轴"), systemImage: "calendar.badge.clock") {
                    ScrollView(.vertical) {
                        dashboardTimelineContent(prefersSingleColumn: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(.visible)
                    .accessibilityIdentifier("dashboard-ipad-timeline-scroll")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                DashboardPanel(title: AppLocalization.string("工作概况"), systemImage: "chart.bar.xaxis") {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: AppSpacing.normal) {
                            todayTodoPanel
                            if showsBusinessOverviewPanel {
                                businessOverviewPanel
                            }
                            warehousePanel
                            todayLogPanel
                            overduePanel
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .scrollIndicators(.visible)
                    .accessibilityIdentifier("dashboard-ipad-overview-scroll")
                }
                .frame(width: overviewWidth)
                .frame(maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)

            dashboardRiskStrip
        }
        .padding(.horizontal, AppSpacing.relaxed)
        .padding(.vertical, AppSpacing.tight)
    }

    private func independentPadHeader(maximumHeight: CGFloat) -> some View {
        // Search suggestions and large text stay reachable without consuming the two panes' viewport.
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: AppSpacing.tight) {
                globalSearchInput
                currentProjectSelector
                todayQuickActions
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 2)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: DashboardPadHeaderHeightKey.self, value: geometry.size.height)
                }
            }
        }
        .frame(height: min(padHeaderMeasuredHeight, maximumHeight))
        .onPreferenceChange(DashboardPadHeaderHeightKey.self) { height in
            guard abs(padHeaderMeasuredHeight - height) > 1 else { return }
            padHeaderMeasuredHeight = max(0, height)
        }
        .accessibilityIdentifier("dashboard-ipad-header-scroll")
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

private struct DashboardPadHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// Keep the three child owners in declaration order: header, scrolling columns, risk strip.
// Place risk labels below search visually, without moving or recreating either owner.
// Only the columns consume the viewport's remaining height.
private struct DashboardPhoneWorkspaceLayout: Layout {
    let viewportSize: CGSize
    let minimumPaneHeight: CGFloat
    let spacing: CGFloat

    private struct Measurements {
        let width: CGFloat
        let headerHeight: CGFloat
        let paneHeight: CGFloat
        let riskHeight: CGFloat

        func totalHeight(spacing: CGFloat) -> CGFloat {
            headerHeight + paneHeight + riskHeight + spacing * 2
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = measurements(proposedWidth: proposal.width, subviews: subviews)
        return CGSize(width: sizes.width, height: sizes.totalHeight(spacing: spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measurements(proposedWidth: bounds.width, subviews: subviews)
        let heights = [sizes.headerHeight, sizes.paneHeight, sizes.riskHeight]
        var y = bounds.minY
        for index in [0, 2, 1] {
            subviews[index].place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                                  proposal: ProposedViewSize(width: sizes.width, height: heights[index]))
            y += heights[index] + spacing
        }
    }

    private func measurements(proposedWidth: CGFloat?, subviews: Subviews) -> Measurements {
        let width = proposedWidth.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? max(0, viewportSize.width)
        let intrinsicProposal = ProposedViewSize(width: width, height: nil)
        let headerHeight = subviews[0].sizeThatFits(intrinsicProposal).height
        let riskHeight = subviews[2].sizeThatFits(intrinsicProposal).height
        let paneHeight = max(minimumPaneHeight, viewportSize.height - headerHeight - riskHeight - spacing * 2)
        return Measurements(width: width, headerHeight: headerHeight, paneHeight: paneHeight, riskHeight: riskHeight)
    }
}
