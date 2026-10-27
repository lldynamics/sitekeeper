import SwiftUI

struct RepositoryWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    let session: RepositoryWorkspaceSession

    var body: some View {
        NavigationStack {
            RepositoryProjectPageView(session: session)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppLocalization.string("关闭副本")) { dismiss() }
                            .accessibilityIdentifier("repository-workspace-close")
                    }
                }
        }
    }
}

struct RepositoryProjectPageView: View {
    let session: RepositoryWorkspaceSession
    @State private var page: RepositoryPageModel
    @State private var searchText = ""
    @State private var order = RepositoryOrder.newestFirst
    @State private var showCreate = false
    @Environment(\.scenePhase) private var scenePhase

    init(session: RepositoryWorkspaceSession) {
        self.session = session
        _page = State(initialValue: RepositoryPageModel(repository: session.repository, query: RepositoryQuery(collection: .projects, order: .newestFirst)))
    }

    private var query: RepositoryQuery { RepositoryQuery(collection: .projects, searchText: searchText, order: order) }

    var body: some View {
        List {
            Section {
                NavigationLink { RepositoryContactPageView(session: session, projectID: nil) } label: {
                    Label(AppLocalization.string("全部往来单位"), systemImage: "person.crop.rectangle.stack")
                }
                .accessibilityIdentifier("repository-all-contacts-entry")
                NavigationLink { RepositoryMaterialPageView(session: session, projectID: nil) } label: {
                    Label(AppLocalization.string("未关联项目的材料"), systemImage: "list.bullet.rectangle")
                }
                .accessibilityIdentifier("repository-unassigned-material-entry")
                NavigationLink { RepositoryLaborPageView(session: session, projectID: nil) } label: {
                    Label(AppLocalization.string("未关联项目的人工记录"), systemImage: "person.2")
                }
                .accessibilityIdentifier("repository-unassigned-labor-entry")
                NavigationLink { RepositoryQuotePageView(session: session, projectID: nil) } label: {
                    Label(AppLocalization.string("未关联项目的报价"), systemImage: "doc.text")
                }
                .accessibilityIdentifier("repository-unassigned-quote-entry")
                RepositoryOrderPicker(order: $order)
                Text(AppLocalization.string("按项目开工日期排序"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ForEach(page.items, id: \.id) { item in
                    NavigationLink(value: item.id) {
                        RepositorySummaryRow(item: item)
                    }
                    .accessibilityIdentifier("repository-project-\(item.id)")
                }
            }
            RepositoryPageControls(page: page)
        }
        .navigationTitle(AppLocalization.string("副本项目"))
        .navigationDestination(for: UUID.self) { id in
            RepositoryDailyLogPageView(session: session, projectID: id)
        }
        .safeAreaInset(edge: .bottom) { RepositoryPageNavigation(page: page) }
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索项目名称、地址或联系人"))
        .toolbar {
            Button(AppLocalization.string("新建项目")) { showCreate = true }
                .accessibilityIdentifier("repository-project-create")
        }
        .sheet(isPresented: $showCreate) { RepositoryProjectEditorView(session: session, id: nil) }
        .task(id: query) { await page.reset(to: query) }
        .onChange(of: session.changeID) { _, _ in Task { await page.reset(to: query) } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await page.reset(to: query) } } }
        .refreshable { await page.reset(to: query) }
        .onDisappear { page.cancel() }
    }
}

struct RepositoryDailyLogPageView: View {
    let session: RepositoryWorkspaceSession
    let projectID: UUID
    @State private var projectName = ""
    @State private var projectError: String?
    @State private var page: RepositoryPageModel
    @State private var searchText = ""
    @State private var order = RepositoryOrder.newestFirst
    @State private var showProject = false
    @State private var editor: RepositoryLogDestination?
    @Environment(\.scenePhase) private var scenePhase

    init(session: RepositoryWorkspaceSession, projectID: UUID) {
        self.session = session
        self.projectID = projectID
        _page = State(initialValue: RepositoryPageModel(repository: session.repository, query: RepositoryQuery(collection: .dailyLogs, project: .project(projectID), order: .newestFirst)))
    }

    private var query: RepositoryQuery {
        RepositoryQuery(collection: .dailyLogs, project: .project(projectID), searchText: searchText, order: order)
    }

    var body: some View {
        List {
            Section {
                Text(projectName)
                if let projectError { Text(projectError).foregroundStyle(.red) }
                Button(AppLocalization.string("项目详情")) { showProject = true }
                    .accessibilityIdentifier("repository-project-edit")
                NavigationLink { RepositoryContactPageView(session: session, projectID: projectID) } label: {
                    Label(AppLocalization.string("往来单位"), systemImage: "person.crop.rectangle.stack")
                }
                .accessibilityIdentifier("repository-contacts-entry")
                NavigationLink { RepositoryFinancialPageView(session: session, projectID: projectID) } label: {
                    Label(AppLocalization.string("财务记录"), systemImage: "yensign.circle")
                }
                .accessibilityIdentifier("repository-finance-entry")
                NavigationLink { RepositoryWarehousePageView(session: session, projectID: projectID) } label: {
                    Label(AppLocalization.string("仓储记录"), systemImage: "shippingbox")
                }
                .accessibilityIdentifier("repository-warehouse-entry")
                NavigationLink { RepositoryMaterialPageView(session: session, projectID: projectID) } label: {
                    Label(AppLocalization.string("材料清单"), systemImage: "list.bullet.rectangle")
                }
                .accessibilityIdentifier("repository-material-entry")
                NavigationLink { RepositoryLaborPageView(session: session, projectID: projectID) } label: {
                    Label(AppLocalization.string("人工记录"), systemImage: "person.2")
                }
                .accessibilityIdentifier("repository-labor-entry")
                NavigationLink { RepositoryQuotePageView(session: session, projectID: projectID) } label: {
                    Label(AppLocalization.string("报价单"), systemImage: "doc.text")
                }
                .accessibilityIdentifier("repository-quote-entry")
                RepositoryOrderPicker(order: $order)
            }
            Section {
                ForEach(page.items, id: \.id) { item in
                    Button { editor = RepositoryLogDestination(recordID: item.id) } label: { RepositorySummaryRow(item: item) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("repository-log-\(item.id)")
                }
            }
            RepositoryPageControls(page: page)
        }
        .navigationTitle(AppLocalization.string("副本施工日志"))
        .task(id: session.changeID) { await refreshProjectName() }
        .safeAreaInset(edge: .bottom) { RepositoryPageNavigation(page: page) }
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索日志文字"))
        .toolbar {
            Button(AppLocalization.string("新建日志")) { editor = RepositoryLogDestination(recordID: nil) }
                .accessibilityIdentifier("repository-log-create")
        }
        .sheet(isPresented: $showProject) { RepositoryProjectEditorView(session: session, id: projectID) }
        .sheet(item: $editor) { destination in RepositoryDailyLogEditorView(session: session, projectID: projectID, id: destination.recordID) }
        .task(id: query) { await page.reset(to: query) }
        .onChange(of: session.changeID) { _, _ in Task { await page.reset(to: query) } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await page.reset(to: query) } } }
        .refreshable { await page.reset(to: query) }
        .onDisappear { page.cancel() }
    }
    private func refreshProjectName() async {
        do {
            guard let detail = try await session.repository.detail(.projects, id: projectID) else { throw RepositoryError.missingRecord }
            try Task.checkCancellation()
            projectName = try JSONDecoder().decode(Project.self, from: detail.payload).name
            projectError = nil
        } catch {
            if !Task.isCancelled { projectError = RepositoryUserMessage.describe(error) }
        }
    }
}

private struct RepositoryLogDestination: Identifiable {
    let id = UUID()
    let recordID: UUID?
}
