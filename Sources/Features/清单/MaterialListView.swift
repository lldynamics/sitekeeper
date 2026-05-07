import SwiftUI

struct MaterialListView: View {
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
    @State private var selection = Set<UUID>()
    @State private var showClearAll = false
    @State private var showBulkProjectSheet = false
    @State private var isSelecting = false
    @State private var bulkProjectId: UUID?

    init(focusedMaterialId: UUID? = nil) {
        self.focusedMaterialId = focusedMaterialId
    }

    private var filtered: [MaterialItem] {
        if searchText.isEmpty { return store.materialItems }
        return store.materialItems.filter { $0.name.localizedStandardContains(searchText) }
    }

    var body: some View {
        List {
            if isSelecting {
                Section {
                    HStack {
                        Button("全选当前结果") {
                            selection = Set(filtered.map(\.id))
                        }
                        Spacer()
                        Button("清除选择") {
                            selection.removeAll()
                        }
                        .disabled(selection.isEmpty)
                    }
                    .font(.callout)
                }
            }

            ForEach(filtered) { item in
                materialRow(item)
            }
            .onDelete { offsets in
                let ids = offsets.compactMap { filtered.indices.contains($0) ? filtered[$0].id : nil }
                store.materialItems.removeAll { ids.contains($0.id) }
                selection.subtract(ids)
                store.scheduleSave()
            }
        }
        .searchable(text: $searchText, prompt: "搜索材料名称")
        .navigationTitle("材料清单")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { MaterialLibraryView() } label: {
                    Image(systemName: "books.vertical.fill")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if !selection.isEmpty {
                        Button("批量归属") { showBulkProjectSheet = true }
                            .font(.caption)
                        Button("删除(\(selection.count))") {
                            store.materialItems.removeAll { selection.contains($0.id) }
                            selection.removeAll()
                            isSelecting = false
                            store.scheduleSave()
                        }
                        .font(.caption).foregroundStyle(.red)
                    }
                    Menu {
                        Button(isSelecting ? "结束选择" : "选择材料") {
                            isSelecting.toggle()
                            if !isSelecting { selection.removeAll() }
                        }
                        Button("清空全部材料", role: .destructive) {
                            showClearAll = true
                        }
                        .disabled(store.materialItems.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多操作")
                    Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加材料")
                }
            }
        }
        .confirmationDialog("清空全部材料？", isPresented: $showClearAll, titleVisibility: .visible) {
            Button("清空", role: .destructive) {
                store.materialItems.removeAll()
                selection.removeAll()
                isSelecting = false
                store.scheduleSave()
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showAdd) {
            NavigationStack {
                Form {
                    Section("材料") {
                        if !store.templates.filter({ $0.category == .material }).isEmpty {
                            Menu("套用材料模板") {
                                ForEach(store.templates.filter { $0.category == .material }) { template in
                                    Button(template.name) { applyMaterialTemplate(template) }
                                }
                            }
                        }
                        TextField("材料名称", text: $newName)
                        LabeledContent("数量") {
                            TextField("0", text: $newQty)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("单位") {
                            TextField("米 / 卷 / 个", text: $newUnit)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("单价") {
                            TextField("0", text: $newUnitPrice)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        TextField("规格型号", text: $newSpecification)
                        TextField("品牌", text: $newBrand)
                        TextField("供应商", text: $newSupplier)
                        Picker("采购状态", selection: $newPurchaseStatus) {
                            ForEach(MaterialPurchaseStatus.allCases, id: \.self) { item in
                                Text(item.displayName).tag(item)
                            }
                        }
                        TextField("进场日期（yyyy-MM-dd）", text: $newArrivalDate)
                    }
                    Section("归属项目") {
                        Picker("归属项目", selection: $newProjectId) {
                            Text("无归属").tag(nil as UUID?)
                            ForEach(store.projects) { p in Text(p.name).tag(p.id as UUID?) }
                        }
                    }
                }
                .navigationTitle("添加材料").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showAdd = false } }
                    ToolbarItem(placement: .confirmationAction) { Button("添加") { addItem(); showAdd = false }.disabled(!canAddMaterial) }
                }
            }
        }
        .sheet(isPresented: $showBulkProjectSheet) {
            bulkProjectForm
        }
        .sheet(item: $editingItem) { item in
            MaterialEditSheet(item: item, useMetric: useMetric) { updated in
                if let index = store.materialItems.firstIndex(where: { $0.id == updated.id }) {
                    store.materialItems[index] = updated
                    store.scheduleSave()
                }
            } onDelete: { id in
                store.materialItems.removeAll { $0.id == id }
                selection.remove(id)
                store.scheduleSave()
            }
        }
        .onAppear(perform: openFocusedMaterialIfNeeded)
    }

    private func materialRow(_ item: MaterialItem) -> some View {
        HStack(spacing: 12) {
            if isSelecting {
                Button {
                    toggleSelection(item.id)
                } label: {
                    Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection.contains(item.id) ? .orange : .secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.body.weight(.medium))
                HStack {
                    Text(UnitDisplay.quantityWithUnit(item.quantity, unit: item.unit, useMetric: useMetric))
                        .font(.caption).foregroundStyle(.secondary)
                    if !item.specification.isEmpty {
                        Text("· \(item.specification)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !item.brand.isEmpty {
                        Text("· \(item.brand)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !item.supplier.isEmpty {
                        Text("· \(item.supplier)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if ReportBuilder.number(item.unitPrice) > 0 {
                        Text("· \(ReportBuilder.money(ReportBuilder.number(item.unitPrice)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("= \(ReportBuilder.money(ReportBuilder.materialLineTotal(item)))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                    if let pid = item.projectId, let proj = store.projects.first(where: { $0.id == pid }) {
                        Text("· \(proj.name)").font(.caption2).foregroundStyle(.blue)
                    } else {
                        Text("· 未归属").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Text(item.purchaseStatus)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(purchaseStatusColor(item.purchaseStatus))
                    if !item.arrivalDate.isEmpty {
                        Text("进场 \(item.arrivalDate)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if !isSelecting {
                Button {
                    store.materialItems.removeAll { $0.id == item.id }
                    store.scheduleSave()
                } label: {
                    Image(systemName: "trash").foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
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
                Section("已选择") {
                    LabeledContent("材料项", value: "\(selection.count)")
                }
                Section("归属项目") {
                    Picker("归属项目", selection: $bulkProjectId) {
                        Text("无归属").tag(nil as UUID?)
                        ForEach(store.projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
                Section {
                    Button("应用到已选材料") {
                        applyBulkProject()
                        showBulkProjectSheet = false
                    }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
                    .disabled(selection.isEmpty)
                }
            }
            .navigationTitle("批量归属")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { showBulkProjectSheet = false }
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

    private func applyBulkProject() {
        store.materialItems = store.materialItems.map { item in
            var updated = item
            if selection.contains(item.id) {
                updated.projectId = bulkProjectId
            }
            return updated
        }
        selection.removeAll()
        isSelecting = false
        bulkProjectId = nil
        store.scheduleSave()
    }

    private func openFocusedMaterialIfNeeded() {
        guard let focusedMaterialId, !didOpenFocusedMaterial,
              let item = store.materialItems.first(where: { $0.id == focusedMaterialId }) else { return }
        didOpenFocusedMaterial = true
        searchText = ""
        DispatchQueue.main.async {
            editingItem = item
        }
    }

    private func addItem() {
        guard canAddMaterial else { return }
        store.materialItems.append(
            MaterialItem(
                name: newName,
                quantity: newQty,
                unit: newUnit,
                unitPrice: newUnitPrice,
                specification: newSpecification,
                brand: newBrand,
                supplier: newSupplier,
                purchaseStatus: newPurchaseStatus.rawValue,
                arrivalDate: newArrivalDate,
                projectId: newProjectId
            )
        )
        store.scheduleSave()
        newName = ""; newQty = ""; newUnit = ""; newUnitPrice = ""; newProjectId = nil
        newSpecification = ""; newBrand = ""; newSupplier = ""
        newPurchaseStatus = .notPurchased
        newArrivalDate = ""
    }

    private var canAddMaterial: Bool {
        !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !newUnit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        InputValidator.nonNegativeNumber(newQty) &&
        (newUnitPrice.isEmpty || InputValidator.nonNegativeNumber(newUnitPrice))
    }

    private func applyMaterialTemplate(_ template: ProjectTemplate) {
        guard let line = template.content.split(separator: "\n").first else { return }
        let parts = line.split(separator: "×").map { $0.trimmingCharacters(in: .whitespaces) }
        newName = parts.first ?? template.name
        let qtyPart = parts.count > 1 ? parts[1] : "1"
        newQty = qtyPart.filter { "0123456789.".contains($0) }
        newUnit = qtyPart.filter { !"0123456789.".contains($0) && $0 != " " }
        if newQty.isEmpty { newQty = "1" }
        if newUnit.isEmpty { newUnit = "个" }
    }

    private func purchaseStatusColor(_ raw: String) -> Color {
        switch MaterialPurchaseStatus(rawValue: raw) ?? .notPurchased {
        case .notPurchased: return .secondary
        case .purchased: return .orange
        case .arrived: return .blue
        case .used: return .green
        }
    }
}
