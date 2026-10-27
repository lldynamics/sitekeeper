import SwiftUI

struct RepositoryWarehousePageView: View {
    let session: RepositoryWorkspaceSession
    let projectID: UUID
    @State private var page: RepositoryPageModel
    @State private var searchText = ""
    @State private var order = RepositoryOrder.newestFirst
    @State private var movementType: WarehouseMovementType?
    @State private var editor: RepositoryWarehouseDestination?
    @Environment(\.scenePhase) private var scenePhase

    init(session: RepositoryWorkspaceSession, projectID: UUID) {
        self.session = session
        self.projectID = projectID
        _page = State(initialValue: RepositoryPageModel(repository: session.repository,
            query: RepositoryQuery(collection: .projectWarehouseMovements, project: .project(projectID), order: .newestFirst)))
    }

    private var query: RepositoryQuery {
        RepositoryQuery(collection: .projectWarehouseMovements, project: .project(projectID), searchText: searchText, order: order, warehouseType: movementType)
    }

    var body: some View {
        List {
            Section {
                NavigationLink { RepositoryStockPageView(session: session, projectID: projectID) } label: {
                    Label(AppLocalization.string("查看库存汇总"), systemImage: "shippingbox")
                }
                .accessibilityIdentifier("repository-stock-entry")
                Picker(AppLocalization.string("出入库"), selection: $movementType) {
                    Text(AppLocalization.string("全部出入库")).tag(WarehouseMovementType?.none)
                    ForEach(WarehouseMovementType.allCases, id: \.self) { Text($0.displayName).tag(Optional($0)) }
                }
                .pickerStyle(.segmented).accessibilityIdentifier("repository-warehouse-type-filter")
                RepositoryOrderPicker(order: $order)
            }
            Section {
                ForEach(page.items, id: \.id) { item in
                    Button { editor = RepositoryWarehouseDestination(recordID: item.id) } label: {
                        RepositoryWarehouseRow(item: item)
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("repository-warehouse-record-\(item.id)")
                }
            }
            RepositoryPageControls(page: page)
        }
        .navigationTitle(AppLocalization.string("副本仓储流水"))
        .safeAreaInset(edge: .bottom) { RepositoryPageNavigation(page: page) }
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索材料、规格、往来或备注"))
        .toolbar {
            Button(AppLocalization.string("新增出入库记录")) { editor = RepositoryWarehouseDestination(recordID: nil) }
                .accessibilityIdentifier("repository-warehouse-create")
        }
        .sheet(item: $editor) { destination in RepositoryWarehouseEditorView(session: session, projectID: projectID, id: destination.recordID) }
        .task(id: query) { await page.reset(to: query) }
        .onChange(of: session.changeID) { _, _ in Task { await page.reset(to: query) } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await page.reset(to: query) } } }
        .refreshable { await page.reset(to: query) }
        .onDisappear { page.cancel() }
    }
}

private struct RepositoryWarehouseDestination: Identifiable {
    let id = UUID()
    let recordID: UUID?
}

private struct RepositoryWarehouseRow: View {
    let item: RepositoryListItem

    var body: some View {
        if let fields = item.warehouse {
            VStack(alignment: .leading, spacing: 4) {
                Text(fields.stockKey == nil ? AppLocalization.string("未命名材料") : item.title).foregroundStyle(.primary).lineLimit(2)
                Text([fields.specification, fields.unit].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption)
                Text(fields.movementType.displayName + " " + (RepositoryMoney.parse(fields.quantity).map(RepositoryMoney.display) ?? AppLocalization.string("数量待核对")))
                    .font(.headline).monospacedDigit()
                Text(item.sortKey).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
