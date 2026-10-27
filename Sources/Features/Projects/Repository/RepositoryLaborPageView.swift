import SwiftUI

struct RepositoryLaborPageView: View {
    let session: RepositoryWorkspaceSession
    let projectID: UUID?
    @State private var page: RepositoryPageModel
    @State private var searchText = ""
    @State private var order = RepositoryOrder.newestFirst
    @State private var settled: Bool?
    @State private var unit: LaborWorkloadUnit?
    @State private var editor: LaborEditorDestination?
    @Environment(\.scenePhase) private var scenePhase

    init(session: RepositoryWorkspaceSession, projectID: UUID?) {
        self.session = session
        self.projectID = projectID
        _page = State(initialValue: RepositoryPageModel(repository: session.repository,
            query: RepositoryQuery(collection: .laborRecords, project: projectID.map(RepositoryProjectFilter.project) ?? .unassigned, order: .newestFirst)))
    }

    private var query: RepositoryQuery {
        RepositoryQuery(collection: .laborRecords, project: projectID.map(RepositoryProjectFilter.project) ?? .unassigned,
            searchText: searchText, order: order, laborSettled: settled, laborUnit: unit)
    }

    var body: some View {
        List {
            Section {
                Picker(AppLocalization.string("结算状态"), selection: $settled) {
                    Text(AppLocalization.string("全部状态")).tag(Bool?.none)
                    Text(AppLocalization.string("未结算")).tag(Optional(false))
                    Text(AppLocalization.string("已结算")).tag(Optional(true))
                }
                .accessibilityIdentifier("repository-labor-settled-filter")
                Picker(AppLocalization.string("计量单位"), selection: $unit) {
                    Text(AppLocalization.string("全部单位")).tag(LaborWorkloadUnit?.none)
                    ForEach(LaborWorkloadUnit.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                .accessibilityIdentifier("repository-labor-unit-filter")
                RepositoryOrderPicker(order: $order)
            }
            if let summary = page.laborSummary { RepositoryLaborSummarySection(summary: summary) }
            Section {
                ForEach(page.items, id: \.id) { item in
                    Button { editor = LaborEditorDestination(recordID: item.id) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title.isEmpty ? AppLocalization.string("人工记录") : item.title).font(.headline)
                            if let fields = item.labor {
                                Text(fields.amount.map(RepositoryMoney.display) ?? AppLocalization.string("金额待核对")).monospacedDigit()
                                Text([fields.workType, fields.workloadUnit.displayName,
                                      AppLocalization.string(fields.isSettled ? "已结算" : "未结算")].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("repository-labor-record-\(item.id)")
                }
            }
            RepositoryPageControls(page: page)
        }
        .navigationTitle(AppLocalization.string("副本人工记录"))
        .safeAreaInset(edge: .bottom) { RepositoryPageNavigation(page: page) }
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索班组、工种或备注"))
        .toolbar {
            Button(AppLocalization.string("添加人工记录")) { editor = LaborEditorDestination(recordID: nil) }
                .accessibilityIdentifier("repository-labor-create")
        }
        .sheet(item: $editor) { destination in
            RepositoryLaborEditorView(session: session, projectID: projectID, id: destination.recordID)
        }
        .task(id: query) { await page.reset(to: query) }
        .onChange(of: session.changeID) { _, _ in Task { await page.reset(to: query) } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await page.reset(to: query) } } }
        .refreshable { await page.reset(to: query) }
        .onDisappear { page.cancel() }
    }
}

private struct LaborEditorDestination: Identifiable {
    let id = UUID()
    let recordID: UUID?
}

private struct RepositoryLaborSummarySection: View {
    let summary: RepositoryLaborSummary

    var body: some View {
        Section(AppLocalization.string("全部筛选结果的人工金额")) {
            LabeledContent(AppLocalization.string("记录数"), value: String(summary.count))
            LabeledContent(AppLocalization.string("合计人工费"), value: summary.total.map(RepositoryMoney.display) ?? AppLocalization.string("金额待核对"))
                .accessibilityIdentifier("repository-labor-total")
            LabeledContent(AppLocalization.string("未结算金额"), value: summary.unsettled.map(RepositoryMoney.display) ?? AppLocalization.string("金额待核对"))
                .accessibilityIdentifier("repository-labor-unsettled")
            if summary.unpricedCount > 0 || summary.invalidValueCount > 0 {
                LabeledContent(AppLocalization.string("可计算部分金额"), value: summary.knownSubtotal.map(RepositoryMoney.display) ?? AppLocalization.string("金额待核对"))
                LabeledContent(AppLocalization.string("未填单价"), value: String(summary.unpricedCount))
                LabeledContent(AppLocalization.string("数值待核对"), value: String(summary.invalidValueCount))
            }
            if summary.hasPrecisionError { Text(AppLocalization.string("金额超出可精确计算范围，请核对原始数值。")).foregroundStyle(.red) }
            if summary.unconfirmedUnitCount > 0 {
                LabeledContent(AppLocalization.string("待确认单位"), value: String(summary.unconfirmedUnitCount))
            }
            Text(AppLocalization.string("金额按人数乘工作量再乘单价计算；历史空人数沿用原工作量。工时与工天不换算，待确认单位保留原金额，不自动写入财务或报价。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
