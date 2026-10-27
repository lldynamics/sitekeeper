import SwiftUI

struct RepositoryStockPageView: View {
    let session: RepositoryWorkspaceSession
    let projectID: UUID
    @State private var page: RepositoryStockPageModel
    @State private var searchText = ""
    @Environment(\.scenePhase) private var scenePhase

    init(session: RepositoryWorkspaceSession, projectID: UUID) {
        self.session = session
        self.projectID = projectID
        _page = State(initialValue: RepositoryStockPageModel(repository: session.repository, query: RepositoryStockQuery(projectID: projectID)))
    }
    private var query: RepositoryStockQuery { RepositoryStockQuery(projectID: projectID, searchText: searchText) }

    var body: some View {
        List {
            Section {
                Text(String(format: AppLocalization.string("匹配库存材料 %lld 种"), Int64(page.totalMaterials))).accessibilityIdentifier("repository-stock-count")
                Text(AppLocalization.string("同名、同规格、同单位的全部出入库计算库存。不同单位不相加；流水筛选不改变库存。"))
                    .font(.caption).foregroundStyle(.secondary)
                if page.unnamedMovements > 0 {
                    Text(String(format: AppLocalization.string("本项目 %lld 条记录缺少材料名称，未纳入库存，请在流水中修正。"), Int64(page.unnamedMovements)))
                        .foregroundStyle(.red)
                }
            }
            Section {
                ForEach(page.items) { RepositoryStockRow(line: $0) }
            }
            Section {
                if page.isLoading { ProgressView() }
                if let error = page.errorMessage {
                    Text(error).foregroundStyle(.red)
                    Button(AppLocalization.string("重试")) { Task { await page.retry() } }
                } else if !page.isLoading, page.items.isEmpty { Text(AppLocalization.string("没有匹配记录")) }
            }
        }
        .navigationTitle(AppLocalization.string("副本库存汇总"))
        .safeAreaInset(edge: .bottom) { navigation }
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索库存材料、规格或单位"))
        .task(id: query) { await page.reset(to: query) }
        .onChange(of: session.changeID) { _, _ in Task { await page.reset(to: query) } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await page.reset(to: query) } } }
        .refreshable { await page.reset(to: query) }
        .onDisappear { page.cancel() }
    }

    private var navigation: some View {
        HStack {
            Button(AppLocalization.string("上一页")) { Task { await page.previous() } }.disabled(page.pageNumber <= 1 || page.isLoading).accessibilityIdentifier("repository-stock-previous")
            Spacer()
            Text(String(format: AppLocalization.string("第 %lld 页"), Int64(page.pageNumber))).accessibilityIdentifier("repository-stock-page-number")
            Spacer()
            Button(AppLocalization.string("下一页")) { Task { await page.next() } }.disabled(page.nextCursor == nil || page.isLoading).accessibilityIdentifier("repository-stock-next")
        }
        .padding().background(.regularMaterial)
    }
}

private struct RepositoryStockRow: View {
    let line: RepositoryStockLine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(line.materialName).font(.headline)
            Text([line.specification, line.unit].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption)
            Text(String(format: AppLocalization.string("共 %lld 条流水"), Int64(line.movementCount))).font(.caption).foregroundStyle(.secondary)
            if let inbound = line.inbound, let outbound = line.outbound, let balance = line.balance {
                Text(AppLocalization.string("入库") + " " + RepositoryMoney.display(inbound))
                Text(AppLocalization.string("出库") + " " + RepositoryMoney.display(outbound))
                Text(AppLocalization.string("库存") + " " + RepositoryMoney.display(balance))
                    .foregroundStyle(balance < 0 ? .red : .primary)
                    .accessibilityIdentifier("repository-stock-balance-\(line.id)")
                if balance < 0 { Text(AppLocalization.string("负库存，请核对出入库记录。")).font(.caption).foregroundStyle(.red) }
            } else {
                Text(line.hasPrecisionError ? AppLocalization.string("数量超出精确计算范围，暂不显示库存。") : AppLocalization.string("存在缺失或无效数量，修正后才能显示库存。"))
                    .foregroundStyle(.red)
            }
        }
        .monospacedDigit().padding(.vertical, 4)
    }
}
