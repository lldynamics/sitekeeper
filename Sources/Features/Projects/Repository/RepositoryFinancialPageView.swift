import SwiftUI

struct RepositoryFinancialPageView: View {
    let session: RepositoryWorkspaceSession
    let projectID: UUID
    @State private var page: RepositoryPageModel
    @State private var searchText = ""
    @State private var order = RepositoryOrder.newestFirst
    @State private var direction: ProjectFinancialDirection?
    @State private var status: ProjectFinancialStatus? = .active
    @State private var editor: FinancialEditorDestination?
    @Environment(\.scenePhase) private var scenePhase

    init(session: RepositoryWorkspaceSession, projectID: UUID) {
        self.session = session
        self.projectID = projectID
        _page = State(initialValue: RepositoryPageModel(repository: session.repository,
            query: RepositoryQuery(collection: .projectFinancialRecords, project: .project(projectID), order: .newestFirst, financialStatus: .active)))
    }

    private var query: RepositoryQuery {
        RepositoryQuery(collection: .projectFinancialRecords, project: .project(projectID), searchText: searchText,
            order: order, financialDirection: direction, financialStatus: status)
    }

    var body: some View {
        List {
            filters
            if let summary = page.financialSummary { RepositoryFinancialSummarySection(summary: summary) }
            Section {
                ForEach(page.items, id: \.id) { item in
                    Button { editor = FinancialEditorDestination(recordID: item.id) } label: {
                        RepositoryFinancialRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("repository-finance-record-\(item.id)")
                }
            }
            RepositoryPageControls(page: page)
        }
        .navigationTitle(AppLocalization.string("副本财务记录"))
        .safeAreaInset(edge: .bottom) { RepositoryPageNavigation(page: page) }
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索往来单位、票号或备注"))
        .toolbar {
            Button(AppLocalization.string("新建财务记录")) { editor = FinancialEditorDestination(recordID: nil) }
                .accessibilityIdentifier("repository-finance-create")
        }
        .sheet(item: $editor) { destination in
            RepositoryFinancialEditorView(session: session, projectID: projectID, id: destination.recordID)
        }
        .task(id: query) { await page.reset(to: query) }
        .onChange(of: session.changeID) { _, _ in Task { await page.reset(to: query) } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await page.reset(to: query) } } }
        .refreshable { await page.reset(to: query) }
        .onDisappear { page.cancel() }
    }

    private var filters: some View {
        Section {
            Picker(AppLocalization.string("收支方向"), selection: $direction) {
                Text(AppLocalization.string("全部收支")).tag(ProjectFinancialDirection?.none)
                ForEach(ProjectFinancialDirection.allCases, id: \.self) { value in
                    Text(LocalizedStringKey(value.rawValue)).tag(Optional(value))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("repository-finance-direction-filter")
            Picker(AppLocalization.string("记录状态"), selection: $status) {
                Text(AppLocalization.string("全部状态")).tag(ProjectFinancialStatus?.none)
                ForEach(ProjectFinancialStatus.allCases, id: \.self) { value in
                    Text(LocalizedStringKey(value.rawValue)).tag(Optional(value))
                }
            }
            .accessibilityIdentifier("repository-finance-status-filter")
            RepositoryOrderPicker(order: $order)
        }
    }
}

private struct FinancialEditorDestination: Identifiable {
    let id = UUID()
    let recordID: UUID?
}

private struct RepositoryFinancialRow: View {
    let item: RepositoryListItem
    var body: some View {
        if let fields = item.financial {
            VStack(alignment: .leading, spacing: 4) {
                Text(fields.counterparty.isEmpty ? AppLocalization.string(String.LocalizationValue(fields.category.rawValue)) : item.title)
                    .foregroundStyle(.primary).lineLimit(2)
                HStack(alignment: .firstTextBaseline) {
                    Text(LocalizedStringKey(fields.direction.rawValue))
                    Text(RepositoryMoney.parse(fields.amount).map(RepositoryMoney.display) ?? AppLocalization.string("金额待核对"))
                        .monospacedDigit()
                }
                .font(.headline)
                Text([item.sortKey, AppLocalization.string(String.LocalizationValue(fields.category.rawValue)),
                      AppLocalization.string(String.LocalizationValue(fields.status.rawValue))].joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
