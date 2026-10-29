import SwiftUI

struct RootPadNavigationShell: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(ProjectStore.self) private var projectStore
    @Binding var selectedTab: Tab
    @State private var selectedProjectID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var compactColumn: NavigationSplitViewColumn = .detail
    let projectComposerOpenToken: Int
    let onComposerConsumed: (Int) -> Void

    var body: some View {
        // Both layouts keep the same global sidebar. Only Projects needs a
        // content column; other modules use the full detail width.
        Group {
            if selectedTab == .records {
                NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
                    moduleSidebar
                } content: {
                    ProjectListView(
                        selection: $selectedProjectID,
                        autoOpenComposerToken: projectComposerOpenToken,
                        onAutoOpenComposerConsumed: onComposerConsumed
                    )
                    .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
                } detail: {
                    ProjectWorkspaceDetail(selectedProjectID: selectedProjectID)
                }
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
                    moduleSidebar
                } detail: {
                    moduleDetail
                        .id(selectedTab)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedTab) { _, tab in
            columnVisibility = .all
            compactColumn = tab == .records ? .content : .detail
        }
        .onChange(of: projectStore.projects.map(\.id)) { _, ids in
            if let selectedProjectID, !ids.contains(selectedProjectID) {
                self.selectedProjectID = nil
            }
        }
    }

    private var moduleSidebar: some View {
        List(selection: moduleSelection) {
            ForEach(Tab.allCases) { tab in
                NavigationLink(value: tab) {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: AppSpacing.tight * 0.5) {
                            Image(systemName: tab.systemImage)
                                .accessibilityHidden(true)
                            Text(tab.title)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                }
                .tag(tab)
                .accessibilityLabel(tab.title)
                .accessibilityIdentifier("primary-module-\(tab.id)")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(AppBrand.displayName)
        .navigationSplitViewColumnWidth(
            min: dynamicTypeSize.isAccessibilitySize ? 280 : 180,
            ideal: dynamicTypeSize.isAccessibilitySize ? 300 : 210,
            max: dynamicTypeSize.isAccessibilitySize ? 360 : 260
        )
        .accessibilityIdentifier("primary-module-sidebar")
    }

    private var moduleSelection: Binding<Tab?> {
        Binding(get: { selectedTab }, set: { if let tab = $0 { selectedTab = tab } })
    }

    @ViewBuilder
    private var moduleDetail: some View {
        switch selectedTab {
        case .dashboard:
            DashboardView()
        case .records:
            ProjectWorkspaceDetail(selectedProjectID: selectedProjectID)
        case .checklist:
            NavigationStack { ChecklistTabView(embedsNavigationStack: false) }
        case .quickNote:
            NavigationStack { QuickNoteView(embedsNavigationStack: false) }
        case .profile:
            NavigationStack { ProfileTabView(embedsNavigationStack: false) }
        }
    }
}
