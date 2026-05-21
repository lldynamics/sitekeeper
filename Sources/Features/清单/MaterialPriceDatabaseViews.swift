import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

struct MaterialPriceDatabaseView: View {
    @Environment(DataStore.self) private var store
    @Environment(MaterialLibraryStore.self) private var materialLibraryStore
    let focusedEntryId: UUID?
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var editingEntry: MaterialPriceEntry?
    @State private var didOpenFocusedEntry = false
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()

    init(focusedEntryId: UUID? = nil) {
        self.focusedEntryId = focusedEntryId
    }

    private var materialPriceEntries: [MaterialPriceEntry] {
        materialLibraryStore.materialPriceEntries
    }

    private var supplierProfiles: [SupplierProfile] {
        materialLibraryStore.supplierProfiles
    }

    private var filtered: [MaterialPriceEntry] {
        SearchMatcher.filter(
            materialPriceEntries,
            keyword: searchText,
            sort: { $0.updatedAt > $1.updatedAt }
        )
    }

    private var searchSuggestions: [RealtimeSearchSuggestion] {
        RealtimeSearchSuggestionBuilder.suggestions(
            keyword: searchText,
            categories: [.material],
            materials: materialPriceEntries,
            limit: 6
        )
    }

    var body: some View {
        SearchableDatabaseView(
            title: String(localized: "材料价格库"),
            searchText: $searchText,
            searchPrompt: String(localized: "搜索材料、品牌、供应商"),
            items: filtered,
            emptyTitle: String(localized: "暂无材料价格"),
            emptySystemImage: "yensign.circle",
            emptyDescription: Text(String(localized: "记录常用材料的品牌、规格、供应商和参考价。")),
            emptyActionTitle: String(localized: "添加材料价格"),
            onEmptyAction: {
                showAdd = true
            },
            searchSuggestions: searchSuggestions,
            searchEmptyStateText: String(localized: "未找到匹配的材料、品牌或供应商"),
            onSelect: { entry in
                editingEntry = entry
            },
            onSelectSuggestion: { suggestion in
                guard suggestion.category == .material else { return }
                if let entry = materialPriceEntries.first(where: { $0.id == suggestion.entityId }) {
                    editingEntry = entry
                }
            },
            deleteConfig: SearchableDatabaseDeleteConfig(
                title: String(localized: "删除材料价格？"),
                itemNoun: String(localized: "材料价格记录"),
                singularMessage: String(localized: "删除后可在提示中撤销。"),
                pluralMessage: { count, noun in
                    String(format: String(localized: "将删除 %lld 条%@，可在提示中撤销。"), Int64(count), noun)
                }
            ),
            onDeleteConfirmed: deleteEntries,
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
                        Label(String(localized: "导入预置材料为价格库"), systemImage: "tray.and.arrow.down.fill")
                    }
                }
            },
            toolbarContent: {
                Button { showAdd = true } label: { Image(systemName: "plus").visibleIconStyle() }
                    .accessibilityLabel(String(localized: "添加材料价格"))
            }
        )
        .onAppear(perform: openFocusedEntryIfNeeded)
        .sheet(isPresented: $showAdd) {
            MaterialPriceEditSheet(entry: nil, suppliers: supplierProfiles) { entry in
                upsertMaterialPriceEntry(entry)
                showAdd = false
            }
        }
        .sheet(item: $editingEntry) { entry in
            MaterialPriceEditSheet(entry: entry, suppliers: supplierProfiles) { updated in
                upsertMaterialPriceEntry(updated)
                editingEntry = nil
            } onDelete: { target in
                deleteEntries([target])
                editingEntry = nil
            }
        }
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
    }

    private func deleteEntries(_ items: [MaterialPriceEntry]) {
        let ids = Set(items.map(\.id))
        guard !ids.isEmpty else { return }

        let targets = materialPriceEntries.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        let deletion = store.removeMaterialPriceEntries(
            ids: ids,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: String(localized: "删除材料价格 %lld 条"), Int64(targets.count)),
                detail: ListFormatter.localizedString(byJoining: targets.map(\.name)),
                source: "MaterialPriceDatabaseView"
            )
        )
        guard !deletion.isEmpty else { return }

        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: String(localized: "已删除 %lld 条材料价格"), Int64(deletion.deletedCount)),
            commit: {
                store.scheduleSave()
            },
            undo: {
                store.restoreMaterialPriceEntries(from: deletion)
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    private func importCommonMaterials() {
        let existingKeys = Set(materialPriceEntries.map { MaterialIdentity.key(name: $0.name, specification: $0.specification, unit: $0.unit) })
        let newItems = MaterialLibrary.all.compactMap { item -> MaterialPriceEntry? in
            let key = MaterialIdentity.key(name: item.name, specification: item.specification, unit: item.unit)
            guard !existingKeys.contains(key) else { return nil }
            return MaterialPriceEntry(name: item.name, specification: item.specification, unit: item.unit, category: item.category.rawValue)
        }
        guard !newItems.isEmpty else { return }
        store.appendMaterialPriceEntries(newItems)
        store.scheduleSave()
    }

    private func upsertMaterialPriceEntry(_ entry: MaterialPriceEntry) {
        store.upsertMaterialPriceEntry(entry)
        store.scheduleSave()
    }

    private func openFocusedEntryIfNeeded() {
        guard let focusedEntryId, !didOpenFocusedEntry,
              let entry = materialPriceEntries.first(where: { $0.id == focusedEntryId }) else { return }
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
                Section(String(localized: "材料信息")) {
                    TextField(String(localized: "名称"), text: $name)
                    TextField(String(localized: "规格"), text: $specification)
                    TextField(String(localized: "单位"), text: $unit)
                }
                Section(String(localized: "参考价格（可选）")) {
                    TextField(String(localized: "参考单价"), text: $price)
                        .keyboardType(.decimalPad)
                }
                Section(String(localized: "分类")) {
                    TextField(String(localized: "分类（可自定义）"), text: $category)
                    if !suggestedCategories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestedCategories, id: \.self) { value in
                                    Button(value) { category = value }
                                        .buttonStyle(.bordered)
                                        .tint(category == value ? .appWarning : .appMuted)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "新增材料"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "添加")) {
                        let mat = UserMaterial(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            specification: specification.trimmingCharacters(in: .whitespacesAndNewlines),
                            unit: unit.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "个") : unit.trimmingCharacters(in: .whitespaces),
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
                Text(entry.name.isEmpty ? String(localized: "未命名材料") : entry.name)
                    .font(.body.weight(.semibold))
                Spacer()
                if !entry.referencePrice.isEmpty {
                    Text("¥\(entry.referencePrice)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.appWarning)
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
                Section(String(localized: "材料")) {
                    TextField(String(localized: "名称"), text: $name)
                    TextField(String(localized: "规格"), text: $specification)
                    TextField(String(localized: "品牌"), text: $brand)
                    TextField(String(localized: "单位"), text: $unit)
                    TextField(String(localized: "分类"), text: $category)
                }
                Section(String(localized: "价格与供应商")) {
                    TextField(String(localized: "参考单价"), text: $referencePrice)
                        .keyboardType(.decimalPad)
                    TextField(String(localized: "供应商"), text: $supplier)
                    if !suppliers.isEmpty {
                        Picker(String(localized: "选择供应商"), selection: $supplier) {
                            Text(String(localized: "手动填写")).tag(supplier)
                            ForEach(suppliers) { item in
                                Text(item.name).tag(item.name)
                            }
                        }
                    }
                }
                Section(String(localized: "备注")) {
                    TextField(String(localized: "备注"), text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
                if entry != nil {
                    Section {
                        Button(String(localized: "删除材料价格"), role: .destructive) { showDeleteConfirm = true }
                    }
                }
            }
            .navigationTitle(entry == nil ? String(localized: "新增材料价格") : String(localized: "编辑材料价格"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        onSave(updatedEntry)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
            .alert(String(localized: "删除这条材料价格？"), isPresented: $showDeleteConfirm) {
                Button(String(localized: "取消"), role: .cancel) {}
                Button(String(localized: "删除"), role: .destructive) {
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
