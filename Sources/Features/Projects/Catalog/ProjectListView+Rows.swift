import SwiftUI

extension ProjectListView {
    @ViewBuilder
    var projectRowsSection: some View {
        ForEach(sortedProjects) { project in
            projectNavigationRow(project)
            .accessibilityIdentifier("project-list-row")
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                NavigationLink {
                    ProjectDetailView(projectId: project.id, initialMode: .finance)
                } label: {
                    Label(AppLocalization.string("财务"), systemImage: "wallet.pass.fill")
                }
                .tint(Color.appFinance)

                NavigationLink {
                    SiteTodoView(initialProjectId: project.id)
                } label: {
                    Label(AppLocalization.string("待办"), systemImage: "checkmark.circle.fill")
                }
                .tint(Color.appSuccess)

                NavigationLink {
                    ProjectDetailView(projectId: project.id, initialMode: .assets)
                } label: {
                    Label(AppLocalization.string("图纸"), systemImage: "square.on.square.squareshape.controlhandles")
                }
                .tint(Color.appPrimaryAction)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                NavigationLink {
                    ProjectDetailView(projectId: project.id, autoOpenDocumentScanSetup: true)
                } label: {
                    Label(AppLocalization.string("加资料"), systemImage: "doc.badge.plus")
                }
                .tint(Color.appDoc)

                NavigationLink {
                    DailyLogView(initialProjectId: project.id, autoOpenComposer: true)
                } label: {
                    Label(AppLocalization.string("写日志"), systemImage: "book.pages.fill")
                }
                .tint(Color.appSuccess)

                NavigationLink {
                    ProjectDetailView(projectId: project.id, autoOpenFinancialAdd: true)
                } label: {
                    Label(AppLocalization.string("记账"), systemImage: "receipt.fill")
                }
                .tint(Color.appFinance)

                if let url = customerPhoneURL(for: project) {
                    Button {
                        openURL(url)
                    } label: {
                        Label(AppLocalization.string("联系客户"), systemImage: "phone.fill")
                    }
                    .tint(Color.appDoc)
                }
            }
        }
        .onDelete { indexSet in
            let ids = indexSet.map { sortedProjects[$0].id }
            if let target = projectStore.projects.first(where: { ids.contains($0.id) }) {
                projectToDelete = target
                showDeleteConfirm = true
            }
        }
    }

    @ViewBuilder
    private func projectNavigationRow(_ project: Project) -> some View {
        if usesProjectSelection {
            NavigationLink(value: project.id) {
                projectRowLabel(project)
            }
            .tag(project.id)
        } else {
            NavigationLink {
                ProjectDetailView(projectId: project.id)
            } label: {
                projectRowLabel(project)
            }
        }
    }

    private func projectRowLabel(_ project: Project) -> some View {
        ProjectRowContent(
            project: project,
            isSelected: selectedProjectID == project.id,
            unpaidAmount: unpaidAmount(for: project),
            badges: projectRiskBadges(for: project)
        )
    }
}

/// The split stays in the hierarchy across size changes, so its detail and sheets keep identity.
struct ProjectWorkspaceView: View {
    @Environment(ProjectStore.self) private var projectStore
    @Environment(\.expandedPhoneWorkspaceWidth) private var rootWorkspaceWidth
    @State private var selectedProjectID: UUID?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @ScaledMetric(relativeTo: .body) private var expandedPhoneMinimumWidth: CGFloat = 820
    let autoOpenComposerToken: Int
    let onAutoOpenComposerConsumed: (Int) -> Void

    private var usesExpandedPhoneSidebar: Bool {
        ExpandedPhoneWorkspaceLayout.isAvailable(width: rootWorkspaceWidth, minimumWidth: expandedPhoneMinimumWidth)
    }

    private var expandedPhoneSidebarWidth: CGFloat {
        ExpandedPhoneWorkspaceLayout.sidebarWidth(
            containerWidth: rootWorkspaceWidth,
            minimumWorkspaceWidth: expandedPhoneMinimumWidth
        )
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ProjectListView(
                selection: $selectedProjectID,
                autoOpenComposerToken: autoOpenComposerToken,
                onAutoOpenComposerConsumed: onAutoOpenComposerConsumed
            )
            .modifier(ExpandedPhoneSidebarScrollModifier(isExpanded: usesExpandedPhoneSidebar))
            .overlay(alignment: .trailing) {
                if usesExpandedPhoneSidebar {
                    ExpandedPhoneColumnDivider()
                        .frame(width: 1)
                        .offset(x: 0.5)
                }
            }
            .navigationSplitViewColumnWidth(
                min: usesExpandedPhoneSidebar ? expandedPhoneSidebarWidth : 280,
                ideal: usesExpandedPhoneSidebar ? expandedPhoneSidebarWidth : 320,
                max: usesExpandedPhoneSidebar ? expandedPhoneSidebarWidth : 400
            )
        } detail: {
            ProjectWorkspaceDetail(selectedProjectID: selectedProjectID)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            if selectedProjectID == nil, usesExpandedPhoneSidebar {
                selectedProjectID = projectStore.projects.first(where: { $0.status == .active })?.id
                    ?? projectStore.projects.first?.id
            }
        }
        .onChange(of: usesExpandedPhoneSidebar) { _, isExpanded in
            if isExpanded, selectedProjectID == nil {
                selectedProjectID = projectStore.projects.first(where: { $0.status == .active })?.id
                    ?? projectStore.projects.first?.id
            }
        }
        .onChange(of: projectStore.projects.map(\.id)) { _, ids in
            if let selectedProjectID, !ids.contains(selectedProjectID) {
                self.selectedProjectID = nil
            }
        }
    }
}

struct ProjectWorkspaceDetail: View {
    let selectedProjectID: UUID?

    var body: some View {
        NavigationStack {
            if let selectedProjectID {
                ProjectDetailView(projectId: selectedProjectID)
                    .accessibilityIdentifier("project-workspace-detail")
            } else {
                ContentUnavailableView(
                    AppLocalization.string("选择项目"),
                    systemImage: "building.2",
                    description: Text(AppLocalization.string("在左侧选择工程后，右侧常驻展示项目详情。"))
                )
                .accessibilityIdentifier("project-workspace-empty")
            }
        }
        // Project changes reset detail navigation; rotation and preferences do not.
        .id(selectedProjectID)
    }
}
