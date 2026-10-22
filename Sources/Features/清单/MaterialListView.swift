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
    @State var showAdd = false
    @State var editingItem: MaterialItem?
    @State var didOpenFocusedMaterial = false
    @State var newName = ""
    @State var newQty = ""
    @State var newUnit = ""
    @State var newUnitPrice = ""
    @State var newSpecification = ""
    @State var newBrand = ""
    @State var newSupplier = ""
    @State var newPurchaseStatus: MaterialPurchaseStatus = .notPurchased
    @State var newArrivalDate = ""
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
        List {
            Section {
                ProjectContextStrip(
                    title: String(localized: "当前工程"),
                    projects: store.projects,
                    selectedProjectId: $projectFilter,
                    emptyText: String(localized: "全部项目")
                )
            }

            if isSelecting {
                Section {
                    HStack {
                        Button(String(localized: "全选当前结果")) {
                            selection = Set(filtered.map(\.id))
                        }
                        Spacer()
                        Button(String(localized: "清除选择")) {
                            selection.removeAll()
                        }
                        .disabled(selection.isEmpty)
                    }
                    .font(.callout)
                }
            }

            if filtered.isEmpty {
                Section {
                    ContentUnavailableView(
                        String(localized: "暂无材料记录"),
                        systemImage: "shippingbox",
                        description: Text(String(localized: "添加材料后可按工程筛选和汇总成本。"))
                    )
                    Button {
                        showAdd = true
                    } label: {
                        Label(String(localized: "添加材料"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.appProminent())
                }
            } else {
                ForEach(filtered) { item in
                    materialRow(item)
                }
                .onDelete { offsets in
                    let ids = offsets.compactMap { filtered.indices.contains($0) ? filtered[$0].id : nil }
                    requestDeleteMaterials(
                        ids: ids,
                        message: String(format: String(localized: "确认删除这 %lld 条材料吗？"), Int64(ids.count)),
                        successMessage: String(format: String(localized: "已删除 %lld 条材料"), Int64(ids.count))
                    )
                }
            }
        }
        .searchable(text: $searchText, prompt: String(localized: "搜索材料名称"))
        .navigationTitle(String(localized: "材料清单"))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { MaterialLibraryView() } label: {
                    Image(systemName: "books.vertical.fill").visibleIconStyle()
                }
                .buttonStyle(.appIcon())
                .accessibilityLabel(String(localized: "打开材料库"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if !selection.isEmpty {
                        Button(String(localized: "批量归属")) { showBulkProjectSheet = true }
                            .font(.caption)
                        Button(String(format: String(localized: "删除(%lld)"), Int64(selection.count))) {
                            requestDeleteMaterials(
                                ids: Array(selection),
                                message: String(format: String(localized: "确认删除已选 %lld 条材料吗？"), Int64(selection.count)),
                                successMessage: String(format: String(localized: "已删除 %lld 条材料"), Int64(selection.count)),
                                endSelectionAfterDelete: true
                            )
                        }
                        .font(.caption).foregroundStyle(.appRisk)
                    }
                    Menu {
                        Button(isSelecting ? String(localized: "结束选择") : String(localized: "选择材料")) {
                            isSelecting.toggle()
                            if !isSelecting { selection.removeAll() }
                        }
                        Button(String(localized: "清空全部材料"), role: .destructive) {
                            showClearAll = true
                        }
                        .disabled(store.materialItems.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle").visibleIconStyle()
                    }
                    .buttonStyle(.appIcon())
                    .accessibilityLabel(String(localized: "更多操作"))
                    Button { showAdd = true } label: { Image(systemName: "plus").visibleIconStyle() }
                        .accessibilityLabel(String(localized: "添加材料"))
                }
            }
        }
        .confirmationDialog(String(localized: "清空全部材料？"), isPresented: $showClearAll, titleVisibility: .visible) {
            Button(String(localized: "清空"), role: .destructive) {
                clearAllMaterials()
            }
            Button(String(localized: "取消"), role: .cancel) {}
        }
        .confirmationDialog(
            String(localized: "删除材料"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible,
            presenting: pendingDeletePlan
        ) { plan in
            Button(String(localized: "删除"), role: .destructive) {
                confirmDeleteMaterials(plan)
            }
            Button(String(localized: "取消"), role: .cancel) {
                pendingDeletePlan = nil
            }
        } message: { plan in
            Text(plan.message)
        }
        .sheet(isPresented: $showAdd) {
            KeyboardFocusScope(AddMaterialField.self) { focusedField, currentField in
                NavigationStack {
                    Form {
                        Section(String(localized: "材料")) {
                            if !store.templates.filter({ $0.category == .material }).isEmpty {
                                Menu(String(localized: "套用材料模板")) {
                                    ForEach(store.templates.filter { $0.category == .material }) { template in
                                        Button(template.name) { applyMaterialTemplate(template) }
                                    }
                                }
                            }
                            TextField(String(localized: "材料名称"), text: $newName)
                            LabeledContent(String(localized: "数量")) {
                                TextField("0", text: $newQty)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .focused(focusedField, equals: .quantity)
                            }
                            LabeledContent(String(localized: "单位")) {
                                TextField(String(localized: "米 / 卷 / 个"), text: $newUnit)
                                    .multilineTextAlignment(.trailing)
                            }
                            LabeledContent(String(localized: "单价")) {
                                TextField("0", text: $newUnitPrice)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .focused(focusedField, equals: .unitPrice)
                            }
                            TextField(String(localized: "规格型号"), text: $newSpecification)
                            TextField(String(localized: "品牌"), text: $newBrand)
                            TextField(String(localized: "供应商"), text: $newSupplier)
                            Picker(String(localized: "采购状态"), selection: $newPurchaseStatus) {
                                ForEach(MaterialPurchaseStatus.allCases, id: \.self) { item in
                                    Text(item.displayName).tag(item)
                                }
                            }
                            OptionalProjectDatePicker(String(localized: "进场日期"), text: $newArrivalDate)
                        }
                        Section(String(localized: "归属项目")) {
                            Picker(String(localized: "归属项目"), selection: $newProjectId) {
                                Text(String(localized: "无归属")).tag(nil as UUID?)
                                ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                            }
                        }
                    }
                    .navigationTitle(String(localized: "添加材料")).navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { showAdd = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(String(localized: "添加")) {
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
                    message: String(localized: "确认删除这条材料记录吗？"),
                    successMessage: String(localized: "已删除材料")
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
