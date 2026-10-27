import SwiftUI

struct RepositoryQuotePageView: View {
    let session: RepositoryWorkspaceSession
    let projectID: UUID?
    @State private var page: RepositoryPageModel
    @State private var searchText = ""
    @State private var versionFilter = ""
    @State private var order = RepositoryOrder.newestFirst
    @State private var status: QuoteStatus?
    @State private var editor: QuoteEditorDestination?
    @Environment(\.scenePhase) private var scenePhase

    init(session: RepositoryWorkspaceSession, projectID: UUID?) {
        self.session = session
        self.projectID = projectID
        _page = State(initialValue: RepositoryPageModel(repository: session.repository,
            query: RepositoryQuery(collection: .quoteItems, project: projectID.map(RepositoryProjectFilter.project) ?? .unassigned, order: .newestFirst)))
    }

    private var query: RepositoryQuery {
        RepositoryQuery(collection: .quoteItems, project: projectID.map(RepositoryProjectFilter.project) ?? .unassigned,
            searchText: searchText, order: order, quoteStatus: status, quoteVersion: versionFilter.isEmpty ? nil : versionFilter)
    }

    var body: some View {
        List {
            Section {
                Picker(AppLocalization.string("报价状态"), selection: $status) {
                    Text(AppLocalization.string("全部状态")).tag(QuoteStatus?.none)
                    ForEach(QuoteStatus.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag(Optional($0)) }
                }
                .accessibilityIdentifier("repository-quote-status-filter")
                TextField(AppLocalization.string("仅此报价版本（留空为全部）"), text: $versionFilter)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("repository-quote-version-filter")
                RepositoryOrderPicker(order: $order)
                Text(AppLocalization.string("按客户确认日期文字排序，未填日期排在最早。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let summary = page.quoteSummary { RepositoryQuoteSummarySection(summary: summary) }
            Section {
                ForEach(page.items, id: \.id) { item in
                    Button { editor = QuoteEditorDestination(recordID: item.id) } label: {
                        RepositoryQuoteRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("repository-quote-record-\(item.id)")
                }
            }
            RepositoryPageControls(page: page)
        }
        .navigationTitle(AppLocalization.string("副本报价单"))
        .safeAreaInset(edge: .bottom) { RepositoryPageNavigation(page: page) }
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索报价名称、版本或备注"))
        .toolbar {
            Button(AppLocalization.string("新建报价")) { editor = QuoteEditorDestination(recordID: nil) }
                .accessibilityIdentifier("repository-quote-create")
        }
        .sheet(item: $editor) { destination in
            RepositoryQuoteEditorView(session: session, projectID: projectID, id: destination.recordID)
        }
        .task(id: query) { await page.reset(to: query) }
        .onChange(of: session.changeID) { _, _ in Task { await page.reset(to: query) } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await page.reset(to: query) } } }
        .refreshable { await page.reset(to: query) }
        .onDisappear { page.cancel() }
    }
}

private struct QuoteEditorDestination: Identifiable {
    let id = UUID()
    let recordID: UUID?
}

private struct RepositoryQuoteRow: View {
    let item: RepositoryListItem
    var body: some View {
        if let fields = item.quote {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).foregroundStyle(.primary).lineLimit(2)
                Text((try? RepositoryQuoteArithmetic.amounts(fields).total).map(RepositoryMoney.display) ?? AppLocalization.string("金额待核对"))
                    .font(.headline).monospacedDigit()
                Text([fields.quantity, fields.unit, "×", fields.unitPrice].joined(separator: " "))
                    .font(.caption).foregroundStyle(.secondary)
                Text([fields.versionName, item.sortKey, AppLocalization.string(String.LocalizationValue(fields.status.rawValue))]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

private struct RepositoryQuoteSummarySection: View {
    let summary: RepositoryQuoteSummary
    var body: some View {
        Section(AppLocalization.string("全部筛选结果的报价金额")) {
            LabeledContent(AppLocalization.string("报价条数"), value: String(summary.count))
            amount("报价基础金额", summary.amounts?.subtotal)
            amount("报价税额", summary.amounts?.tax)
            amount("报价折扣额", summary.amounts?.discount)
            LabeledContent(AppLocalization.string("报价合计"), value: summary.amounts.map { RepositoryMoney.display($0.total) } ?? AppLocalization.string("金额待核对"))
                .accessibilityIdentifier("repository-quote-total")
            if summary.invalidValueCount > 0 {
                Text(String(format: AppLocalization.string("报价数值待核对 %lld 条"), Int64(summary.invalidValueCount)))
            }
            if summary.hasPrecisionError {
                Text(AppLocalization.string("报价金额超出精确计算范围，请核对数量、单价和费率。"))
                    .foregroundStyle(.red)
            }
            Text(AppLocalization.string("合计为基础金额加税额减折扣，税额与折扣均按基础金额计算。包含所选状态和版本；另存的合同金额不计入，也不写回项目合同额。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func amount(_ key: String.LocalizationValue, _ value: Decimal?) -> some View {
        LabeledContent(AppLocalization.string(key), value: value.map(RepositoryMoney.display) ?? AppLocalization.string("金额待核对"))
    }
}
