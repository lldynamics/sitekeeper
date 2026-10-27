import SwiftUI

struct MaterialListView: View {
    enum AddMaterialField: Hashable {
        case quantity
        case unitPrice
    }

    struct PendingMaterialDeletePlan {
        let ids: Set<UUID>
        let message: String
        let successMessage: String
        let endSelectionAfterDelete: Bool
    }

    @Environment(DataStore.self) var store
    @AppStorage(UserPreferenceKeys.useMetric) var useMetric = true
    let focusedMaterialId: UUID?
    @State var searchText = ""
    @State private var pageIndex = 0
    @State var showAdd = false
    @State var editingItem: MaterialItem?
    @State var receivingMaterial: MaterialItem?
    @State var didOpenFocusedMaterial = false
    @State var newName = ""
    @State var newQty = ""
    @State var newUnit = ""
    @State var newUnitPrice = ""
    @State var newSpecification = ""
    @State var newBrand = ""
    @State var newSupplier = ""
    @State var newPurchaseStatus: MaterialPurchaseStatus = .notPurchased
    @State var newArrivalDate: BusinessDateValue = .empty
    @State var newProjectId: UUID?
    @State var projectFilter: UUID?
    @State var selection = Set<UUID>()
    @State var showClearAll = false
    @State var showBulkProjectSheet = false
    @State var isSelecting = false
    @State var bulkProjectId: UUID?
    @State var operationMessage: String?
    @State var operationNotice: OperationToastNotice?
    @State var undoableDeletion = UndoableDeletionCoordinator()
    @State var pendingDeletePlan: PendingMaterialDeletePlan?
    @State var showDeleteConfirm = false

    init(focusedMaterialId: UUID? = nil) {
        self.focusedMaterialId = focusedMaterialId
    }

    var filtered: [MaterialItem] {
        let scopedItems = store.materialItems.filter { item in
            projectFilter == nil || item.projectId == projectFilter
        }
        return SearchMatcher.filter(scopedItems, keyword: searchText)
    }

    var body: some View {
        let matching = filtered
        let page = RecordPage(matching, index: pageIndex)
        List {
            Section {
                ProjectContextStrip(
                    title: AppLocalization.string("当前工程"),
                    projects: store.projects,
                    selectedProjectId: $projectFilter,
                    emptyText: AppLocalization.string("全部项目")
                )
            }

            if isSelecting {
                MaterialSelectionControls(
                    hasSelection: !selection.isEmpty,
                    onSelectAll: { selection = Set(filtered.map(\.id)) },
                    onClear: { selection.removeAll() }
                )
            }

            if matching.isEmpty {
                Section {
                    ContentUnavailableView(
                        AppLocalization.string("暂无材料记录"),
                        systemImage: "shippingbox",
                        description: Text(AppLocalization.string("添加材料后可按工程筛选和汇总成本。"))
                    )
                    Button {
                        showAdd = true
                    } label: {
                        Label(AppLocalization.string("添加材料"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.appProminent())
                }
            } else {
                ForEach(page.items) { item in
                    materialRow(item)
                }
                .onDelete { offsets in
                    let ids = offsets.compactMap { page.items.indices.contains($0) ? page.items[$0].id : nil }
                    requestDeleteMaterials(
                        ids: ids,
                        message: String(format: AppLocalization.string("确认删除这 %lld 条材料吗？"), Int64(ids.count)),
                        successMessage: String(format: AppLocalization.string("已删除 %lld 条材料"), Int64(ids.count))
                    )
                }
                RecordPageControls(index: page.index, count: page.count, selection: $pageIndex)
            }
        }
        .searchable(text: $searchText, prompt: AppLocalization.string("搜索材料名称"))
        .onChange(of: searchText) { _, _ in pageIndex = 0 }
        .onChange(of: projectFilter) { _, _ in pageIndex = 0 }
        .navigationTitle(AppLocalization.string("材料清单"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { MaterialLibraryView() } label: {
                    Image(systemName: "books.vertical.fill").visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel(AppLocalization.string("打开材料库"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if !selection.isEmpty {
                        Button(AppLocalization.string("批量归属")) { showBulkProjectSheet = true }
                            .font(.caption)
                        Button(String(format: AppLocalization.string("删除(%lld)"), Int64(selection.count))) {
                            requestDeleteMaterials(
                                ids: Array(selection),
                                message: String(format: AppLocalization.string("确认删除已选 %lld 条材料吗？"), Int64(selection.count)),
                                successMessage: String(format: AppLocalization.string("已删除 %lld 条材料"), Int64(selection.count)),
                                endSelectionAfterDelete: true
                            )
                        }
                        .font(.caption).foregroundStyle(.appRisk)
                    }
                    Menu {
                        Button(isSelecting ? AppLocalization.string("结束选择") : AppLocalization.string("选择材料")) {
                            isSelecting.toggle()
                            if !isSelecting { selection.removeAll() }
                        }
                        Button(AppLocalization.string("清空全部材料"), role: .destructive) {
                            showClearAll = true
                        }
                        .disabled(store.materialItems.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle").visibleIconStyle()
                    }
                    .buttonStyle(.appIcon())
                    .accessibilityLabel(AppLocalization.string("更多操作"))
                    Button { showAdd = true } label: { Image(systemName: "plus").visibleIconStyle() }
                        .accessibilityLabel(AppLocalization.string("添加材料"))
                }
            }
        }
        .confirmationDialog(AppLocalization.string("清空全部材料？"), isPresented: $showClearAll, titleVisibility: .visible) {
            Button(AppLocalization.string("清空"), role: .destructive) {
                clearAllMaterials()
            }
            Button(AppLocalization.string("取消"), role: .cancel) {}
        }
        .confirmationDialog(
            AppLocalization.string("删除材料"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible,
            presenting: pendingDeletePlan
        ) { plan in
            Button(AppLocalization.string("删除"), role: .destructive) {
                confirmDeleteMaterials(plan)
            }
            Button(AppLocalization.string("取消"), role: .cancel) {
                pendingDeletePlan = nil
            }
        } message: { plan in
            Text(plan.message)
        }
        .sheet(item: $receivingMaterial) { material in
            MaterialReceiptSheet(material: material)
        }
        .sheet(isPresented: $showAdd) {
            KeyboardFocusScope(AddMaterialField.self) { focusedField, currentField in
                NavigationStack {
                    Form {
                        Section(AppLocalization.string("材料")) {
                            if !store.templates.filter({ $0.category == .material }).isEmpty {
                                Menu(AppLocalization.string("套用材料模板")) {
                                    ForEach(store.templates.filter { $0.category == .material }) { template in
                                        Button(template.name) { applyMaterialTemplate(template) }
                                    }
                                }
                            }
                            TextField(AppLocalization.string("材料名称"), text: $newName)
                            LabeledContent(AppLocalization.string("数量")) {
                                TextField("0", text: $newQty)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .focused(focusedField, equals: .quantity)
                            }
                            LabeledContent(AppLocalization.string("单位")) {
                                TextField(AppLocalization.string("米 / 卷 / 个"), text: $newUnit)
                                    .multilineTextAlignment(.trailing)
                            }
                            LabeledContent(AppLocalization.string("单价")) {
                                TextField("0", text: $newUnitPrice)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .focused(focusedField, equals: .unitPrice)
                            }
                            TextField(AppLocalization.string("规格型号"), text: $newSpecification)
                            TextField(AppLocalization.string("品牌"), text: $newBrand)
                            TextField(AppLocalization.string("供应商"), text: $newSupplier)
                            Picker(AppLocalization.string("采购状态"), selection: $newPurchaseStatus) {
                                ForEach(MaterialPurchaseStatus.allCases, id: \.self) { item in
                                    Text(item.displayName).tag(item)
                                }
                            }
                            OptionalProjectDatePicker(AppLocalization.string("进场日期"), value: $newArrivalDate)
                        }
                        Section(AppLocalization.string("归属项目")) {
                            Picker(AppLocalization.string("归属项目"), selection: $newProjectId) {
                                Text(AppLocalization.string("无归属")).tag(nil as UUID?)
                                ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                            }
                        }
                    }
                    .navigationTitle(AppLocalization.string("添加材料")).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(AppLocalization.string("取消")) { showAdd = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(AppLocalization.string("添加")) {
                                addItem()
                                showAdd = false
                            }
                            .disabled(!canAddMaterial)
                        }
                    }
                    .appKeyboardToolbar {
                        KeyboardNavigationToolbar(
                            focusedField: focusedField,
                            currentField: currentField,
                            fields: [.quantity, .unitPrice]
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showBulkProjectSheet) {
            bulkProjectForm
        }
        .sheet(item: $editingItem) { item in
            MaterialEditSheet(item: item, useMetric: useMetric) { updated in
                if store.updateMaterialItem(updated) {
                    store.scheduleSave()
                }
            } onDelete: { id in
                requestDeleteMaterials(
                    ids: [id],
                    message: AppLocalization.string("确认删除这条材料记录吗？"),
                    successMessage: AppLocalization.string("已删除材料")
                )
            }
        }
        .onAppear(perform: openFocusedMaterialIfNeeded)
        .operationToast(message: $operationMessage)
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
    }
}
