import SwiftUI

struct RepositoryContactPageView: View {
    let session: RepositoryWorkspaceSession
    let projectID: UUID?
    @State private var page: RepositoryPageModel
    @State private var searchText = ""
    @State private var order = RepositoryOrder.oldestFirst
    @State private var role: ProjectContactRole?
    @State private var editor: ContactEditorDestination?
    @Environment(\.scenePhase) private var scenePhase

    init(session: RepositoryWorkspaceSession, projectID: UUID?) {
        self.session = session
        self.projectID = projectID
        _page = State(initialValue: RepositoryPageModel(repository: session.repository,
            query: RepositoryQuery(collection: .projectContacts, project: projectID.map(RepositoryProjectFilter.project) ?? .all)))
    }

    private var query: RepositoryQuery {
        RepositoryQuery(collection: .projectContacts, project: projectID.map(RepositoryProjectFilter.project) ?? .all,
            searchText: searchText, order: order, contactRole: role)
    }

    var body: some View {
        List {
            Section {
                Picker(AppLocalization.string("角色"), selection: $role) {
                    Text(AppLocalization.string("全部角色")).tag(ProjectContactRole?.none)
                    ForEach(ProjectContactRole.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                .accessibilityIdentifier("repository-contact-role-filter")
                Picker(AppLocalization.string("名称顺序"), selection: $order) {
                    Text(AppLocalization.string("名称正序")).tag(RepositoryOrder.oldestFirst)
                    Text(AppLocalization.string("名称倒序")).tag(RepositoryOrder.newestFirst)
                }
                Text(AppLocalization.string("按联系人姓名排序，保留主项目及其他项目关联。"))
                    .font(.caption).foregroundStyle(.secondary)
                if projectID == nil {
                    Text(AppLocalization.string("新增往来单位请先进入对应项目。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(page.items, id: \.id) { item in
                    Button { editor = ContactEditorDestination(recordID: item.id, projectID: item.projectID) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title.isEmpty ? AppLocalization.string("未填写姓名") : item.title).font(.headline)
                            if let fields = item.contact {
                                Text(fields.role.displayName).font(.caption).foregroundStyle(.secondary)
                                if !fields.company.isEmpty { Text(fields.company) }
                                if !fields.phone.isEmpty { Text(fields.phone).font(.caption) }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("repository-contact-record-\(item.id)")
                }
            }
            RepositoryPageControls(page: page)
        }
        .navigationTitle(AppLocalization.string("副本往来单位"))
        .safeAreaInset(edge: .bottom) { RepositoryPageNavigation(page: page) }
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索姓名、单位、电话或备注"))
        .toolbar {
            if let projectID {
                Button(AppLocalization.string("添加往来单位")) { editor = ContactEditorDestination(recordID: nil, projectID: projectID) }
                    .accessibilityIdentifier("repository-contact-create")
            }
        }
        .sheet(item: $editor) { destination in
            if let id = destination.projectID {
                RepositoryContactEditorView(session: session, projectID: id, id: destination.recordID)
            }
        }
        .task(id: query) { await page.reset(to: query) }
        .onChange(of: session.changeID) { _, _ in Task { await page.reset(to: query) } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await page.reset(to: query) } } }
        .refreshable { await page.reset(to: query) }
        .onDisappear { page.cancel() }
    }
}

private struct ContactEditorDestination: Identifiable {
    let id = UUID()
    let recordID: UUID?
    let projectID: UUID?
}
