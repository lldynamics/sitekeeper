import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

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
        SearchMatcher.filter(
            store.materialPriceEntries,
            keyword: searchText,
            sort: { $0.updatedAt > $1.updatedAt }
        )
    }

    var body: some View {
        SearchableDatabaseView(
            title: "材料价格库",
            searchText: $searchText,
            searchPrompt: "搜索材料、品牌、供应商",
            items: filtered,
            emptyTitle: "暂无材料价格",
            emptySystemImage: "yensign.circle",
            emptyDescription: Text("记录常用材料的品牌、规格、供应商和参考价。"),
            onSelect: { entry in
                editingEntry = entry
            },
            onDelete: deleteEntries,
            rowContent: { entry in
                MaterialPriceRow(entry: entry)
            },
            headerContent: {
                EmptyView()
            },
            footerContent: {
                Section {
                    Button {
                        importCommonMaterials()
                    } label: {
                        Label("导入预置材料为价格库", systemImage: "tray.and.arrow.down.fill")
                    }
                }
            },
            toolbarContent: {
                Button { showAdd = true } label: { Image(systemName: "plus").visibleIconStyle() }
                    .accessibilityLabel("添加材料价格")
            }
        )
        .onAppear(perform: openFocusedEntryIfNeeded)
        .sheet(isPresented: $showAdd) {
            MaterialPriceEditSheet(entry: nil, suppliers: store.supplierProfiles) { entry in
                upsertMaterialPriceEntry(entry)
                showAdd = false
            }
        }
        .sheet(item: $editingEntry) { entry in
            MaterialPriceEditSheet(entry: entry, suppliers: store.supplierProfiles) { updated in
                upsertMaterialPriceEntry(updated)
                editingEntry = nil
            } onDelete: { target in
                store.materialPriceEntries.removeAll { $0.id == target.id }
                store.scheduleSave()
                editingEntry = nil
            }
        }
    }

    private func deleteEntries(_ offsets: IndexSet, _ items: [MaterialPriceEntry]) {
        let ids = offsets.compactMap { items.indices.contains($0) ? items[$0].id : nil }
        store.materialPriceEntries.removeAll { ids.contains($0.id) }
        store.scheduleSave()
    }

    private func importCommonMaterials() {
        let existingKeys = Set(store.materialPriceEntries.map { MaterialIdentity.key(name: $0.name, specification: $0.specification, unit: $0.unit) })
        let newItems = MaterialLibrary.all.compactMap { item -> MaterialPriceEntry? in
            let key = MaterialIdentity.key(name: item.name, specification: item.specification, unit: item.unit)
            guard !existingKeys.contains(key) else { return nil }
            return MaterialPriceEntry(name: item.name, specification: item.specification, unit: item.unit, category: item.category.rawValue)
        }
        guard !newItems.isEmpty else { return }
        store.materialPriceEntries.append(contentsOf: newItems)
        store.scheduleSave()
    }

    private func upsertMaterialPriceEntry(_ entry: MaterialPriceEntry) {
        let entryKey = MaterialIdentity.key(name: entry.name, specification: entry.specification, unit: entry.unit)
        if let index = store.materialPriceEntries.firstIndex(where: { $0.id == entry.id }) {
            store.materialPriceEntries[index] = entry
            store.scheduleSave()
            return
        }
        if let duplicateIndex = store.materialPriceEntries.firstIndex(where: {
            MaterialIdentity.key(name: $0.name, specification: $0.specification, unit: $0.unit) == entryKey
        }) {
            var merged = entry
            merged.id = store.materialPriceEntries[duplicateIndex].id
            store.materialPriceEntries[duplicateIndex] = merged
            store.scheduleSave()
            return
        }
        store.materialPriceEntries.insert(entry, at: 0)
        store.scheduleSave()
    }

    private func openFocusedEntryIfNeeded() {
        guard let focusedEntryId, !didOpenFocusedEntry,
              let entry = store.materialPriceEntries.first(where: { $0.id == focusedEntryId }) else { return }
        didOpenFocusedEntry = true
        searchText = ""
        Task { @MainActor in
            editingEntry = entry
        }
    }
}

struct AddMaterialSheet: View {
    @Environment(\.dismiss) private var dismiss
    let suggestedCategories: [String]
    let onSave: (UserMaterial, String) -> Void

    @State private var name = ""
    @State private var specification = ""
    @State private var unit = ""
    @State private var price = ""
    @State private var category: String

    init(
        initialCategory: String? = nil,
        suggestedCategories: [String] = MaterialCategory.allCases.map(\.rawValue),
        onSave: @escaping (UserMaterial, String) -> Void
    ) {
        self.suggestedCategories = suggestedCategories
        self.onSave = onSave
        let normalizedInitial = initialCategory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        _category = State(initialValue: normalizedInitial.isEmpty ? MaterialCategory.wire.rawValue : normalizedInitial)
    }

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
                    TextField("分类（可自定义）", text: $category)
                    if !suggestedCategories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestedCategories, id: \.self) { value in
                                    Button(value) { category = value }
                                        .buttonStyle(.bordered)
                                        .tint(category == value ? .orange : .gray)
                                }
                            }
                            .padding(.vertical, 2)
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
                            category: category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? MaterialCategory.other.rawValue : category.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        onSave(mat, price.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
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

    init(
        entry: MaterialPriceEntry?,
        suppliers: [SupplierProfile],
        initialName: String = "",
        initialSpecification: String = "",
        initialBrand: String = "",
        initialUnit: String = "",
        initialReferencePrice: String = "",
        initialSupplier: String = "",
        initialCategory: String = "",
        initialNote: String = "",
        onSave: @escaping (MaterialPriceEntry) -> Void,
        onDelete: ((MaterialPriceEntry) -> Void)? = nil
    ) {
        self.entry = entry
        self.suppliers = suppliers
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: entry?.name ?? initialName)
        _specification = State(initialValue: entry?.specification ?? initialSpecification)
        _brand = State(initialValue: entry?.brand ?? initialBrand)
        _unit = State(initialValue: entry?.unit ?? initialUnit)
        _referencePrice = State(initialValue: entry?.referencePrice ?? initialReferencePrice)
        _supplier = State(initialValue: entry?.supplier ?? initialSupplier)
        _category = State(initialValue: entry?.category ?? initialCategory)
        _note = State(initialValue: entry?.note ?? initialNote)
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
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
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
