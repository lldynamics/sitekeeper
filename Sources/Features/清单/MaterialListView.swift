import SwiftUI

struct MaterialListView: View {
    private enum AddMaterialField: Hashable {
        case quantity
        case unitPrice
    }

    private struct PendingMaterialDeletePlan {
        let ids: Set<UUID>
        let message: String
        let successMessage: String
        let endSelectionAfterDelete: Bool
    }

    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.useMetric) private var useMetric = true
    let focusedMaterialId: UUID?
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editingItem: MaterialItem?
    @State private var didOpenFocusedMaterial = false
    @State private var newName = ""
    @State private var newQty = ""
    @State private var newUnit = ""
    @State private var newUnitPrice = ""
    @State private var newSpecification = ""
    @State private var newBrand = ""
    @State private var newSupplier = ""
    @State private var newPurchaseStatus: MaterialPurchaseStatus = .notPurchased
    @State private var newArrivalDate = ""
    @State private var newProjectId: UUID?
    @State private var projectFilter: UUID?
    @State private var selection = Set<UUID>()
    @State private var showClearAll = false
    @State private var showBulkProjectSheet = false
    @State private var isSelecting = false
    @State private var bulkProjectId: UUID?
    @State private var operationMessage: String?
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()
    @State private var pendingDeletePlan: PendingMaterialDeletePlan?
    @State private var showDeleteConfirm = false
    @FocusState private var addMaterialFocusedField: AddMaterialField?

    init(focusedMaterialId: UUID? = nil) {
        self.focusedMaterialId = focusedMaterialId
    }

    private var filtered: [MaterialItem] {
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
                                .focused($addMaterialFocusedField, equals: .quantity)
                        }
                        LabeledContent(String(localized: "单位")) {
                            TextField(String(localized: "米 / 卷 / 个"), text: $newUnit)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent(String(localized: "单价")) {
                            TextField("0", text: $newUnitPrice)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($addMaterialFocusedField, equals: .unitPrice)
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
                    ToolbarItem(placement: .confirmationAction) { Button(String(localized: "添加")) { addItem()
                    showAdd = false }.disabled(!canAddMaterial) }
                    KeyboardNavigationToolbar(
                        focusedField: $addMaterialFocusedField,
                        fields: [.quantity, .unitPrice]
                    )
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

    private func materialRow(_ item: MaterialItem) -> some View {
        HStack(spacing: 12) {
            if isSelecting {
                Button {
                    toggleSelection(item.id)
                } label: {
                    Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection.contains(item.id) ? .appWarning : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "选择材料"))
                .accessibilityValue(selection.contains(item.id) ? String(localized: "已选中") : String(localized: "未选中"))
                .accessibilityHint(String(localized: "双击切换选中状态"))
            }

            let quantityText = UnitDisplay.quantityWithUnit(item.quantity, unit: item.unit, useMetric: useMetric)
            let specText = [item.specification, item.brand, item.supplier].filter { !$0.isEmpty }.joined(separator: " · ")
            let projectText = item.projectId.flatMap { id in store.projects.first(where: { $0.id == id })?.name } ?? String(localized: "未归属")
            let meta = [quantityText, specText, projectText].filter { !$0.isEmpty }.joined(separator: " · ")
            let totalText = item.unitPriceValue.isPositive ? ReportBuilder.money(ReportBuilder.materialLineTotal(item)) : ""
            let noteText = item.arrivalDate.isEmpty
                ? item.purchaseStatus.displayName
                : String(format: String(localized: "%@ · 进场 %@"), item.purchaseStatus.displayName, item.arrivalDate)
            BusinessRecordRow(
                icon: "shippingbox.fill",
                iconColor: purchaseStatusColor(item.purchaseStatus),
                title: item.name,
                meta: meta,
                note: noteText,
                trailing: totalText,
                trailingColor: Color.appPrimaryAction
            )
            Spacer()
            if !isSelecting {
                Button {
                    requestDeleteMaterials(
                        ids: [item.id],
                        message: String(format: String(localized: "确认删除材料「%@」吗？"), item.name),
                        successMessage: String(localized: "已删除材料")
                    )
                } label: {
                    Image(systemName: "trash").foregroundStyle(.appRisk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "删除材料"))
                .accessibilityValue(item.name)
                .accessibilityHint(String(localized: "双击删除当前材料"))
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isSelecting ? String(localized: "双击选择或取消选择该材料") : String(localized: "双击编辑材料"))
        .onTapGesture {
            if isSelecting {
                toggleSelection(item.id)
            } else {
                editingItem = item
            }
        }
    }

    private var bulkProjectForm: some View {
        NavigationStack {
            Form {
                Section(String(localized: "已选择")) {
                    LabeledContent(String(localized: "材料项"), value: "\(selection.count)")
                }
                Section(String(localized: "归属项目")) {
                    Picker(String(localized: "归属项目"), selection: $bulkProjectId) {
                        Text(String(localized: "无归属")).tag(nil as UUID?)
                        ForEach(store.projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
                Section {
                    Button(String(localized: "应用到已选材料")) {
                        applyBulkProject()
                        showBulkProjectSheet = false
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                    .disabled(selection.isEmpty)
                }
            }
            .navigationTitle(String(localized: "批量归属"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { showBulkProjectSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func toggleSelection(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }

    private func requestDeleteMaterials(
        ids: [UUID],
        message: String,
        successMessage: String,
        endSelectionAfterDelete: Bool = false
    ) {
        let normalizedIDs = Set(ids)
        guard !normalizedIDs.isEmpty else { return }
        pendingDeletePlan = PendingMaterialDeletePlan(
            ids: normalizedIDs,
            message: message,
            successMessage: successMessage,
            endSelectionAfterDelete: endSelectionAfterDelete
        )
        showDeleteConfirm = true
    }

    private func confirmDeleteMaterials(_ plan: PendingMaterialDeletePlan) {
        let targets = store.materialItems.filter { plan.ids.contains($0.id) }
        guard !targets.isEmpty else {
            pendingDeletePlan = nil
            return
        }
        let deletion = store.removeMaterialItems(
            ids: plan.ids,
            audit: DataStoreDeletionAuditContext(
                summary: String(localized: "删除材料"),
                detail: materialDeletionDetail(targets),
                source: "MaterialListView"
            )
        )
        guard !deletion.isEmpty else {
            pendingDeletePlan = nil
            return
        }

        let removedIDs = deletion.removedIDs(\.id)
        let selectionSnapshot = selection
        let isSelectingSnapshot = isSelecting

        selection.subtract(removedIDs)
        if plan.endSelectionAfterDelete {
            selection.removeAll()
            isSelecting = false
        } else if selection.isEmpty {
            isSelecting = false
        }
        operationMessage = nil
        undoableDeletion.queue(
            notice: $operationNotice,
            message: plan.successMessage,
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.restoreMaterialItems(from: deletion)
                selection = selectionSnapshot
                isSelecting = isSelectingSnapshot
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
        pendingDeletePlan = nil
    }

    private func clearAllMaterials() {
        let ids = Set(store.materialItems.map(\.id))
        guard !ids.isEmpty else { return }
        let deletion = store.removeMaterialItems(
            ids: ids,
            audit: DataStoreDeletionAuditContext(
                summary: String(localized: "清空全部材料"),
                detail: String(format: String(localized: "已删除 %lld 条材料"), Int64(ids.count)),
                source: "MaterialListView"
            )
        )
        guard !deletion.isEmpty else { return }

        let selectionSnapshot = selection
        let isSelectingSnapshot = isSelecting
        selection.removeAll()
        isSelecting = false
        operationMessage = nil

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(localized: "已清空全部材料"),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.restoreMaterialItems(from: deletion)
                selection = selectionSnapshot
                isSelecting = isSelectingSnapshot
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    private func materialDeletionDetail(_ items: [MaterialItem]) -> String {
        ListFormatter.localizedString(byJoining: items.map(\.name))
    }

    private func applyBulkProject() {
        store.replaceMaterialItems(store.materialItems.map { item in
            var updated = item
            if selection.contains(item.id) {
                updated.projectId = bulkProjectId
            }
            return updated
        })
        selection.removeAll()
        isSelecting = false
        bulkProjectId = nil
        store.scheduleSave()
        operationMessage = String(localized: "已批量更新归属项目")
    }

    private func openFocusedMaterialIfNeeded() {
        guard let focusedMaterialId, !didOpenFocusedMaterial,
              let item = store.materialItems.first(where: { $0.id == focusedMaterialId }) else { return }
        didOpenFocusedMaterial = true
        searchText = ""
        projectFilter = item.projectId
        Task { @MainActor in
            editingItem = item
        }
    }

    private func addItem() {
        guard canAddMaterial else { return }
        store.appendMaterialItem(
            MaterialItem(
                name: newName,
                quantity: newQty,
                unit: newUnit,
                unitPrice: newUnitPrice,
                specification: newSpecification,
                brand: newBrand,
                supplier: newSupplier,
                purchaseStatus: newPurchaseStatus,
                arrivalDate: ProjectDateInput.normalizedStorageText(newArrivalDate),
                projectId: newProjectId
            )
        )
        store.scheduleSave()
        operationMessage = String(localized: "已添加材料")
        newName = ""
        newQty = ""
        newUnit = ""
        newUnitPrice = ""
        newProjectId = nil
        newSpecification = ""
        newBrand = ""
        newSupplier = ""
        newPurchaseStatus = .notPurchased
        newArrivalDate = ""
    }

    private var canAddMaterial: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !newUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        InputValidator.validate(newQty, kind: .quantity, requirement: .requiredNonNegative).isValid &&
        InputValidator.validate(newUnitPrice, kind: .amount, requirement: .optionalNonNegative).isValid
    }

    private func applyMaterialTemplate(_ template: ProjectTemplate) {
        guard let line = template.content
            .split(separator: "\n")
            .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty }) else { return }
        let parsed = NumericInputSupport.parseMaterialTemplateLine(
            line,
            defaultNumber: "1",
            defaultUnit: String(localized: "材料默认单位")
        )
        newName = parsed.name.isEmpty ? template.name : parsed.name
        newQty = parsed.quantity
        newUnit = parsed.unit
        operationMessage = String(localized: "已套用材料模板")
    }

    private func purchaseStatusColor(_ status: MaterialPurchaseStatus) -> Color {
        switch status {
        case .notPurchased: return .secondary
        case .purchased: return .appWarning
        case .arrived: return .appInventory
        case .used: return .appSuccess
        }
    }
}
