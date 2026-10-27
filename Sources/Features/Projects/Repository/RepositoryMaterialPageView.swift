import SwiftUI

struct RepositoryMaterialPageView: View {
    let session: RepositoryWorkspaceSession
    let projectID: UUID?
    @State private var page: RepositoryPageModel
    @State private var searchText = ""
    @State private var order = RepositoryOrder.newestFirst
    @State private var status: MaterialPurchaseStatus?
    @State private var editor: MaterialEditorDestination?
    @Environment(\.scenePhase) private var scenePhase

    init(session: RepositoryWorkspaceSession, projectID: UUID?) {
        self.session = session
        self.projectID = projectID
        _page = State(initialValue: RepositoryPageModel(repository: session.repository,
            query: RepositoryQuery(collection: .materialItems, project: projectID.map(RepositoryProjectFilter.project) ?? .unassigned, order: .newestFirst)))
    }

    private var query: RepositoryQuery {
        RepositoryQuery(collection: .materialItems, project: projectID.map(RepositoryProjectFilter.project) ?? .unassigned,
            searchText: searchText, order: order, materialStatus: status)
    }

    var body: some View {
        List {
            Section {
                Picker(AppLocalization.string("采购状态"), selection: $status) {
                    Text(AppLocalization.string("全部状态")).tag(MaterialPurchaseStatus?.none)
                    ForEach(MaterialPurchaseStatus.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag(Optional($0)) }
                }
                .accessibilityIdentifier("repository-material-status-filter")
                RepositoryOrderPicker(order: $order)
                Text(AppLocalization.string("按进场日期文字排序，未填日期排在最早。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let summary = page.materialSummary { RepositoryMaterialSummarySection(summary: summary) }
            Section {
                ForEach(page.items, id: \.id) { item in
                    Button { editor = MaterialEditorDestination(recordID: item.id) } label: {
                        RepositoryMaterialRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("repository-material-record-\(item.id)")
                }
            }
            RepositoryPageControls(page: page)
        }
        .navigationTitle(AppLocalization.string("副本材料清单"))
        .safeAreaInset(edge: .bottom) { RepositoryPageNavigation(page: page) }
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索材料、规格、品牌或供应商"))
        .toolbar {
            Button(AppLocalization.string("新建材料")) { editor = MaterialEditorDestination(recordID: nil) }
                .accessibilityIdentifier("repository-material-create")
        }
        .sheet(item: $editor) { destination in
            RepositoryMaterialEditorView(session: session, projectID: projectID, id: destination.recordID)
        }
        .task(id: query) { await page.reset(to: query) }
        .onChange(of: session.changeID) { _, _ in Task { await page.reset(to: query) } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await page.reset(to: query) } } }
        .refreshable { await page.reset(to: query) }
        .onDisappear { page.cancel() }
    }
}

private struct MaterialEditorDestination: Identifiable {
    let id = UUID()
    let recordID: UUID?
}

private struct RepositoryMaterialRow: View {
    let item: RepositoryListItem
    var body: some View {
        if let fields = item.material {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).foregroundStyle(.primary).lineLimit(2)
                Text([fields.quantity, fields.unit, "×", fields.unitPrice.isEmpty ? AppLocalization.string("未填单价") : fields.unitPrice].joined(separator: " "))
                    .font(.headline).monospacedDigit()
                Text([fields.specification, fields.brand, fields.supplier, item.sortKey,
                      AppLocalization.string(String.LocalizationValue(fields.purchaseStatus.rawValue))].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
    }
}

private struct RepositoryMaterialSummarySection: View {
    let summary: RepositoryMaterialSummary
    var body: some View {
        Section(AppLocalization.string("全部筛选结果的材料金额")) {
            LabeledContent(AppLocalization.string("材料条数"), value: String(summary.count))
            LabeledContent(AppLocalization.string("材料总额"), value: summary.total.map(RepositoryMoney.display) ?? AppLocalization.string("金额待核对"))
                .accessibilityIdentifier("repository-material-total")
            if summary.total == nil {
                LabeledContent(AppLocalization.string("可计算部分金额"), value: summary.knownSubtotal.map(RepositoryMoney.display) ?? AppLocalization.string("金额待核对"))
                Text(String(format: AppLocalization.string("未填单价 %lld 条，数值待核对 %lld 条"), Int64(summary.unpricedCount), Int64(summary.invalidValueCount)))
            }
            if summary.hasPrecisionError {
                Text(AppLocalization.string("金额超出精确计算范围，请核对数量和单价。"))
                    .foregroundStyle(.red)
            }
            Text(AppLocalization.string("按数量乘单价汇总全部筛选结果，包含所选采购状态；材料金额不等于实际支出，也不改变库存。"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
