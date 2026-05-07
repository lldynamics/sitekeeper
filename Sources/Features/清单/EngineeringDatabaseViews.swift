import SwiftUI

struct MaterialPriceDatabaseView: View {
    @Environment(DataStore.self) private var store
    let focusedEntryId: UUID?
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editingEntry: MaterialPriceEntry?
    @State private var didOpenFocusedEntry = false

    init(focusedEntryId: UUID? = nil) {
        self.focusedEntryId = focusedEntryId
    }

    private var filtered: [MaterialPriceEntry] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = store.materialPriceEntries.sorted { $0.updatedAt > $1.updatedAt }
        guard !keyword.isEmpty else { return items }
        return items.filter {
            $0.name.localizedStandardContains(keyword)
                || $0.specification.localizedStandardContains(keyword)
                || $0.brand.localizedStandardContains(keyword)
                || $0.supplier.localizedStandardContains(keyword)
                || $0.category.localizedStandardContains(keyword)
        }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView("暂无材料价格", systemImage: "yensign.circle", description: Text("记录常用材料的品牌、规格、供应商和参考价。"))
            } else {
                ForEach(filtered) { entry in
                    Button { editingEntry = entry } label: {
                        MaterialPriceRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteEntries)
            }

            Section {
                Button {
                    importCommonMaterials()
                } label: {
                    Label("导入预置材料为价格库", systemImage: "tray.and.arrow.down.fill")
                }
            }
        }
        .navigationTitle("材料价格库")
        .searchable(text: $searchText, prompt: "搜索材料、品牌、供应商")
        .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加材料价格") }
        .onAppear(perform: openFocusedEntryIfNeeded)
        .sheet(isPresented: $showAdd) {
            MaterialPriceEditSheet(entry: nil, suppliers: store.supplierProfiles) { entry in
                store.materialPriceEntries.insert(entry, at: 0)
                store.scheduleSave()
                showAdd = false
            }
        }
        .sheet(item: $editingEntry) { entry in
            MaterialPriceEditSheet(entry: entry, suppliers: store.supplierProfiles) { updated in
                if let index = store.materialPriceEntries.firstIndex(where: { $0.id == updated.id }) {
                    store.materialPriceEntries[index] = updated
                    store.scheduleSave()
                }
                editingEntry = nil
            } onDelete: { target in
                store.materialPriceEntries.removeAll { $0.id == target.id }
                store.scheduleSave()
                editingEntry = nil
            }
        }
    }

    private func deleteEntries(_ offsets: IndexSet) {
        let ids = offsets.compactMap { filtered.indices.contains($0) ? filtered[$0].id : nil }
        store.materialPriceEntries.removeAll { ids.contains($0.id) }
        store.scheduleSave()
    }

    private func importCommonMaterials() {
        let existingKeys = Set(store.materialPriceEntries.map { materialKey(name: $0.name, specification: $0.specification, unit: $0.unit) })
        let newItems = MaterialLibrary.all.compactMap { item -> MaterialPriceEntry? in
            let key = materialKey(name: item.name, specification: item.specification, unit: item.unit)
            guard !existingKeys.contains(key) else { return nil }
            return MaterialPriceEntry(name: item.name, specification: item.specification, unit: item.unit, category: item.category.rawValue)
        }
        guard !newItems.isEmpty else { return }
        store.materialPriceEntries.append(contentsOf: newItems)
        store.scheduleSave()
    }

    private func materialKey(name: String, specification: String, unit: String) -> String {
        "\(name)|\(specification)|\(unit)"
    }

    private func openFocusedEntryIfNeeded() {
        guard let focusedEntryId, !didOpenFocusedEntry,
              let entry = store.materialPriceEntries.first(where: { $0.id == focusedEntryId }) else { return }
        didOpenFocusedEntry = true
        searchText = ""
        DispatchQueue.main.async {
            editingEntry = entry
        }
    }
}

struct AddMaterialSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onSave: (UserMaterial, String) -> Void

    @State private var name = ""
    @State private var specification = ""
    @State private var unit = ""
    @State private var price = ""
    @State private var category: MaterialCategory = .wire

    var body: some View {
        NavigationStack {
            Form {
                Section("材料信息") {
                    TextField("名称", text: $name)
                    TextField("规格", text: $specification)
                    TextField("单位", text: $unit)
                }
                Section("参考价格（可选）") {
                    TextField("参考单价", text: $price)
                        .keyboardType(.decimalPad)
                }
                Section("分类") {
                    Picker("分类", selection: $category) {
                        ForEach(MaterialCategory.allCases) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                }
            }
            .navigationTitle("新增材料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let mat = UserMaterial(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            specification: specification.trimmingCharacters(in: .whitespacesAndNewlines),
                            unit: unit.trimmingCharacters(in: .whitespaces).isEmpty ? "个" : unit.trimmingCharacters(in: .whitespaces),
                            category: category.rawValue
                        )
                        onSave(mat, price.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct MaterialPriceRow: View {
    let entry: MaterialPriceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.name.isEmpty ? "未命名材料" : entry.name)
                    .font(.body.weight(.semibold))
                Spacer()
                if !entry.referencePrice.isEmpty {
                    Text("¥\(entry.referencePrice)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Text([entry.specification, entry.brand, entry.unit].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !entry.supplier.isEmpty || !entry.category.isEmpty {
                Text([entry.category, entry.supplier].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

struct MaterialPriceEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: MaterialPriceEntry?
    let suppliers: [SupplierProfile]
    let onSave: (MaterialPriceEntry) -> Void
    var onDelete: ((MaterialPriceEntry) -> Void)?

    @State private var name: String
    @State private var specification: String
    @State private var brand: String
    @State private var unit: String
    @State private var referencePrice: String
    @State private var supplier: String
    @State private var category: String
    @State private var note: String
    @State private var showDeleteConfirm = false

    init(entry: MaterialPriceEntry?, suppliers: [SupplierProfile], onSave: @escaping (MaterialPriceEntry) -> Void, onDelete: ((MaterialPriceEntry) -> Void)? = nil) {
        self.entry = entry
        self.suppliers = suppliers
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: entry?.name ?? "")
        _specification = State(initialValue: entry?.specification ?? "")
        _brand = State(initialValue: entry?.brand ?? "")
        _unit = State(initialValue: entry?.unit ?? "")
        _referencePrice = State(initialValue: entry?.referencePrice ?? "")
        _supplier = State(initialValue: entry?.supplier ?? "")
        _category = State(initialValue: entry?.category ?? "")
        _note = State(initialValue: entry?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("材料") {
                    TextField("名称", text: $name)
                    TextField("规格", text: $specification)
                    TextField("品牌", text: $brand)
                    TextField("单位", text: $unit)
                    TextField("分类", text: $category)
                }
                Section("价格与供应商") {
                    TextField("参考单价", text: $referencePrice)
                        .keyboardType(.decimalPad)
                    TextField("供应商", text: $supplier)
                    if !suppliers.isEmpty {
                        Picker("选择供应商", selection: $supplier) {
                            Text("手动填写").tag(supplier)
                            ForEach(suppliers) { item in
                                Text(item.name).tag(item.name)
                            }
                        }
                    }
                }
                Section("备注") {
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
                if entry != nil {
                    Section {
                        Button("删除材料价格", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(entry == nil ? "新增材料价格" : "编辑材料价格")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(updatedEntry)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("删除这条材料价格？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let target = entry { onDelete?(target) }
                    dismiss()
                }
            }
        }
    }

    private var updatedEntry: MaterialPriceEntry {
        var value = entry ?? MaterialPriceEntry()
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.specification = specification.trimmingCharacters(in: .whitespacesAndNewlines)
        value.brand = brand.trimmingCharacters(in: .whitespacesAndNewlines)
        value.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        value.referencePrice = referencePrice.trimmingCharacters(in: .whitespacesAndNewlines)
        value.supplier = supplier.trimmingCharacters(in: .whitespacesAndNewlines)
        value.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        value.updatedAt = Formatters.now()
        return value
    }
}

struct SupplierDatabaseView: View {
    @Environment(DataStore.self) private var store
    let focusedSupplierId: UUID?
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editingSupplier: SupplierProfile?
    @State private var didOpenFocusedSupplier = false

    init(focusedSupplierId: UUID? = nil) {
        self.focusedSupplierId = focusedSupplierId
    }

    private var filtered: [SupplierProfile] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = store.supplierProfiles.sorted { $0.updatedAt > $1.updatedAt }
        guard !keyword.isEmpty else { return items }
        return items.filter {
            $0.name.localizedStandardContains(keyword)
                || $0.category.localizedStandardContains(keyword)
                || $0.contact.localizedStandardContains(keyword)
                || $0.phone.localizedStandardContains(keyword)
                || $0.note.localizedStandardContains(keyword)
        }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView("暂无供应商", systemImage: "person.2.badge.gearshape", description: Text("记录常用供应商、联系人、电话和供货范围。"))
            } else {
                ForEach(filtered) { supplier in
                    Button { editingSupplier = supplier } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(supplier.name.isEmpty ? "未命名供应商" : supplier.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text([supplier.category, supplier.contact, supplier.phone].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !supplier.note.isEmpty {
                                Text(supplier.note)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteSuppliers)
            }
        }
        .navigationTitle("供应商库")
        .searchable(text: $searchText, prompt: "搜索供应商、联系人、电话")
        .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加供应商") }
        .onAppear(perform: openFocusedSupplierIfNeeded)
        .sheet(isPresented: $showAdd) {
            SupplierEditSheet(supplier: nil) { supplier in
                store.supplierProfiles.insert(supplier, at: 0)
                store.scheduleSave()
                showAdd = false
            }
        }
        .sheet(item: $editingSupplier) { supplier in
            SupplierEditSheet(supplier: supplier) { updated in
                if let index = store.supplierProfiles.firstIndex(where: { $0.id == updated.id }) {
                    store.supplierProfiles[index] = updated
                    store.scheduleSave()
                }
                editingSupplier = nil
            } onDelete: { target in
                store.supplierProfiles.removeAll { $0.id == target.id }
                store.scheduleSave()
                editingSupplier = nil
            }
        }
    }

    private func deleteSuppliers(_ offsets: IndexSet) {
        let ids = offsets.compactMap { filtered.indices.contains($0) ? filtered[$0].id : nil }
        store.supplierProfiles.removeAll { ids.contains($0.id) }
        store.scheduleSave()
    }

    private func openFocusedSupplierIfNeeded() {
        guard let focusedSupplierId, !didOpenFocusedSupplier,
              let supplier = store.supplierProfiles.first(where: { $0.id == focusedSupplierId }) else { return }
        didOpenFocusedSupplier = true
        searchText = ""
        DispatchQueue.main.async {
            editingSupplier = supplier
        }
    }
}

private struct SupplierEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let supplier: SupplierProfile?
    let onSave: (SupplierProfile) -> Void
    var onDelete: ((SupplierProfile) -> Void)?

    @State private var name: String
    @State private var category: String
    @State private var contact: String
    @State private var phone: String
    @State private var address: String
    @State private var note: String
    @State private var showDeleteConfirm = false

    init(supplier: SupplierProfile?, onSave: @escaping (SupplierProfile) -> Void, onDelete: ((SupplierProfile) -> Void)? = nil) {
        self.supplier = supplier
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: supplier?.name ?? "")
        _category = State(initialValue: supplier?.category ?? "")
        _contact = State(initialValue: supplier?.contact ?? "")
        _phone = State(initialValue: supplier?.phone ?? "")
        _address = State(initialValue: supplier?.address ?? "")
        _note = State(initialValue: supplier?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("供应商") {
                    TextField("名称", text: $name)
                    TextField("供货范围", text: $category)
                }
                Section("联系信息") {
                    TextField("联系人", text: $contact)
                    TextField("电话", text: $phone)
                        .keyboardType(.phonePad)
                    TextField("地址", text: $address, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("备注") {
                    TextField("备注", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
                if supplier != nil {
                    Section {
                        Button("删除供应商", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(supplier == nil ? "新增供应商" : "编辑供应商")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(updatedSupplier)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("删除这个供应商？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let target = supplier { onDelete?(target) }
                    dismiss()
                }
            }
        }
    }

    private var updatedSupplier: SupplierProfile {
        var value = supplier ?? SupplierProfile()
        value.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        value.contact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        value.phone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        value.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        value.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        value.updatedAt = Formatters.now()
        return value
    }
}

struct ConstructionMethodLibraryView: View {
    @Environment(DataStore.self) private var store
    let focusedMethodId: UUID?
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editingMethod: ConstructionMethod?
    @State private var didOpenFocusedMethod = false

    init(focusedMethodId: UUID? = nil) {
        self.focusedMethodId = focusedMethodId
    }

    private var filtered: [ConstructionMethod] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = store.constructionMethods.sorted { $0.updatedAt > $1.updatedAt }
        guard !keyword.isEmpty else { return items }
        return items.filter {
            $0.title.localizedStandardContains(keyword)
                || $0.trade.localizedStandardContains(keyword)
                || $0.steps.localizedStandardContains(keyword)
                || $0.qualityStandard.localizedStandardContains(keyword)
                || $0.safetyNotes.localizedStandardContains(keyword)
        }
    }

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView("暂无施工工艺", systemImage: "hammer.fill", description: Text("沉淀标准做法、质量要求和安全注意事项。"))
            } else {
                ForEach(filtered) { method in
                    Button { editingMethod = method } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(method.title.isEmpty ? "未命名工艺" : method.title)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(method.trade)
                                .font(.caption)
                                .foregroundStyle(.blue)
                            Text(method.steps)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteMethods)
            }
        }
        .navigationTitle("施工工艺库")
        .searchable(text: $searchText, prompt: "搜索工艺、专业、质量要求")
        .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加工艺") }
        .onAppear(perform: openFocusedMethodIfNeeded)
        .sheet(isPresented: $showAdd) {
            ConstructionMethodEditSheet(method: nil) { method in
                store.constructionMethods.insert(method, at: 0)
                store.scheduleSave()
                showAdd = false
            }
        }
        .sheet(item: $editingMethod) { method in
            ConstructionMethodEditSheet(method: method) { updated in
                if let index = store.constructionMethods.firstIndex(where: { $0.id == updated.id }) {
                    store.constructionMethods[index] = updated
                    store.scheduleSave()
                }
                editingMethod = nil
            } onDelete: { target in
                store.constructionMethods.removeAll { $0.id == target.id }
                store.scheduleSave()
                editingMethod = nil
            }
        }
    }

    private func deleteMethods(_ offsets: IndexSet) {
        let ids = offsets.compactMap { filtered.indices.contains($0) ? filtered[$0].id : nil }
        store.constructionMethods.removeAll { ids.contains($0.id) }
        store.scheduleSave()
    }

    private func openFocusedMethodIfNeeded() {
        guard let focusedMethodId, !didOpenFocusedMethod,
              let method = store.constructionMethods.first(where: { $0.id == focusedMethodId }) else { return }
        didOpenFocusedMethod = true
        searchText = ""
        DispatchQueue.main.async {
            editingMethod = method
        }
    }
}

private struct ConstructionMethodEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let method: ConstructionMethod?
    let onSave: (ConstructionMethod) -> Void
    var onDelete: ((ConstructionMethod) -> Void)?

    @State private var title: String
    @State private var trade: String
    @State private var steps: String
    @State private var qualityStandard: String
    @State private var safetyNotes: String
    @State private var showDeleteConfirm = false

    init(method: ConstructionMethod?, onSave: @escaping (ConstructionMethod) -> Void, onDelete: ((ConstructionMethod) -> Void)? = nil) {
        self.method = method
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: method?.title ?? "")
        _trade = State(initialValue: method?.trade ?? "")
        _steps = State(initialValue: method?.steps ?? "")
        _qualityStandard = State(initialValue: method?.qualityStandard ?? "")
        _safetyNotes = State(initialValue: method?.safetyNotes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("工艺") {
                    TextField("标题", text: $title)
                    TextField("专业/工种", text: $trade)
                }
                Section("施工步骤") {
                    TextField("步骤", text: $steps, axis: .vertical)
                        .lineLimit(6...12)
                }
                Section("质量与安全") {
                    TextField("质量标准", text: $qualityStandard, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("安全注意", text: $safetyNotes, axis: .vertical)
                        .lineLimit(3...8)
                }
                if method != nil {
                    Section {
                        Button("删除施工工艺", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(method == nil ? "新增施工工艺" : "编辑施工工艺")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(updatedMethod)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("删除这条施工工艺？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let target = method { onDelete?(target) }
                    dismiss()
                }
            }
        }
    }

    private var updatedMethod: ConstructionMethod {
        var value = method ?? ConstructionMethod()
        value.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        value.trade = trade.trimmingCharacters(in: .whitespacesAndNewlines)
        value.steps = steps.trimmingCharacters(in: .whitespacesAndNewlines)
        value.qualityStandard = qualityStandard.trimmingCharacters(in: .whitespacesAndNewlines)
        value.safetyNotes = safetyNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        value.updatedAt = Formatters.now()
        return value
    }
}

struct QuotationTemplateLibraryView: View {
    @Environment(DataStore.self) private var store
    let focusedTemplateId: UUID?
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editingTemplate: ProjectTemplate?
    @State private var didOpenFocusedTemplate = false

    init(focusedTemplateId: UUID? = nil) {
        self.focusedTemplateId = focusedTemplateId
    }

    private var templates: [ProjectTemplate] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = store.templates.filter { $0.category == .quotation }
        guard !keyword.isEmpty else { return items }
        return items.filter { $0.name.localizedStandardContains(keyword) || $0.content.localizedStandardContains(keyword) }
    }

    var body: some View {
        List {
            if templates.isEmpty {
                ContentUnavailableView("暂无报价模板", systemImage: "doc.text.fill", description: Text("沉淀常用报价项目和单价，后续可快速套用。"))
            } else {
                ForEach(templates) { template in
                    Button { editingTemplate = template } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(template.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(template.content)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteTemplates)
            }
        }
        .navigationTitle("报价模板库")
        .searchable(text: $searchText, prompt: "搜索模板名称或内容")
        .toolbar { Button { showAdd = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加报价模板") }
        .onAppear(perform: openFocusedTemplateIfNeeded)
        .sheet(isPresented: $showAdd) {
            QuoteTemplateEditSheet(template: nil) { template in
                store.templates.insert(template, at: 0)
                store.scheduleSave()
                showAdd = false
            }
        }
        .sheet(item: $editingTemplate) { template in
            QuoteTemplateEditSheet(template: template) { updated in
                if let index = store.templates.firstIndex(where: { $0.id == updated.id }) {
                    store.templates[index] = updated
                    store.scheduleSave()
                }
                editingTemplate = nil
            } onDelete: { target in
                store.templates.removeAll { $0.id == target.id }
                store.scheduleSave()
                editingTemplate = nil
            }
        }
    }

    private func deleteTemplates(_ offsets: IndexSet) {
        let ids = offsets.compactMap { templates.indices.contains($0) ? templates[$0].id : nil }
        store.templates.removeAll { ids.contains($0.id) }
        store.scheduleSave()
    }

    private func openFocusedTemplateIfNeeded() {
        guard let focusedTemplateId, !didOpenFocusedTemplate,
              let template = store.templates.first(where: { $0.id == focusedTemplateId }) else { return }
        didOpenFocusedTemplate = true
        searchText = ""
        DispatchQueue.main.async {
            editingTemplate = template
        }
    }
}

private struct QuoteTemplateEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let template: ProjectTemplate?
    let onSave: (ProjectTemplate) -> Void
    var onDelete: ((ProjectTemplate) -> Void)?

    @State private var name: String
    @State private var content: String
    @State private var showDeleteConfirm = false

    init(template: ProjectTemplate?, onSave: @escaping (ProjectTemplate) -> Void, onDelete: ((ProjectTemplate) -> Void)? = nil) {
        self.template = template
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: template?.name ?? "")
        _content = State(initialValue: template?.content ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("模板") {
                    TextField("名称", text: $name)
                    TextField("报价内容", text: $content, axis: .vertical)
                        .lineLimit(8...16)
                }
                Section("格式参考") {
                    Text("一行一个项目，例如：\n布线 ¥45/m\n插座安装 ¥25/个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if template != nil {
                    Section {
                        Button("删除报价模板", role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(template == nil ? "新增报价模板" : "编辑报价模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(updatedTemplate)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("删除这个报价模板？", isPresented: $showDeleteConfirm) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let target = template { onDelete?(target) }
                    dismiss()
                }
            }
        }
    }

    private var updatedTemplate: ProjectTemplate {
        if var template {
            template.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            template.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return template
        }
        return ProjectTemplate(name: name.trimmingCharacters(in: .whitespacesAndNewlines), category: .quotation, content: content.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

