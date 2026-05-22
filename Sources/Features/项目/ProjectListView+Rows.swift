import SwiftUI

extension ProjectListView {
    @ViewBuilder
    var projectRowsSection: some View {
        ForEach(sortedProjects) { project in
            NavigationLink {
                ProjectDetailView(projectId: project.id)
            } label: {
                ProjectRowContent(
                    project: project,
                    isSelected: false,
                    unpaidAmount: unpaidAmount(for: project),
                    badges: projectRiskBadges(for: project)
                )
            }
            .accessibilityIdentifier("project-list-row")
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                NavigationLink {
                    ProjectDetailView(projectId: project.id, initialMode: .finance)
                } label: {
                    Label(String(localized: "财务"), systemImage: "wallet.pass.fill")
                }
                .tint(Color.appFinance)

                NavigationLink {
                    SiteTodoView(initialProjectId: project.id)
                } label: {
                    Label(String(localized: "待办"), systemImage: "checkmark.circle.fill")
                }
                .tint(Color.appSuccess)

                NavigationLink {
                    ProjectDetailView(projectId: project.id, initialMode: .assets)
                } label: {
                    Label(String(localized: "图纸"), systemImage: "square.on.square.squareshape.controlhandles")
                }
                .tint(Color.appPrimaryAction)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                NavigationLink {
                    ProjectDetailView(projectId: project.id, autoOpenDocumentScanSetup: true)
                } label: {
                    Label(String(localized: "加资料"), systemImage: "doc.badge.plus")
                }
                .tint(Color.appDoc)

                NavigationLink {
                    DailyLogView(initialProjectId: project.id, autoOpenComposer: true)
                } label: {
                    Label(String(localized: "写日志"), systemImage: "book.pages.fill")
                }
                .tint(Color.appSuccess)

                NavigationLink {
                    ProjectDetailView(projectId: project.id, autoOpenFinancialAdd: true)
                } label: {
                    Label(String(localized: "记账"), systemImage: "receipt.fill")
                }
                .tint(Color.appFinance)

                if let url = customerPhoneURL(for: project) {
                    Button {
                        openURL(url)
                    } label: {
                        Label(String(localized: "联系客户"), systemImage: "phone.fill")
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
}
