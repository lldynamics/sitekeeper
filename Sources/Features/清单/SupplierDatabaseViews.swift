import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

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
        SearchMatcher.filter(
            store.supplierProfiles,
            keyword: searchText,
            sort: { $0.updatedAt > $1.updatedAt }
        )
    }

    var body: some View {
        SearchableDatabaseView(
            title: "供应商库",
            searchText: $searchText,
            searchPrompt: "搜索供应商、联系人、电话",
            items: filtered,
            emptyTitle: "暂无供应商",
            emptySystemImage: "person.2.badge.gearshape",
            emptyDescription: Text("记录常用供应商、联系人、电话和供货范围。"),
            onSelect: { supplier in
                editingSupplier = supplier
            },
            onDelete: deleteSuppliers,
            rowContent: { supplier in
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
            },
            headerContent: {
                EmptyView()
            },
            footerContent: {
                EmptyView()
            },
            toolbarContent: {
                Button { showAdd = true } label: { Image(systemName: "plus").visibleIconStyle() }
                    .accessibilityLabel("添加供应商")
            }
        )
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

    private func deleteSuppliers(_ offsets: IndexSet, _ items: [SupplierProfile]) {
        let ids = offsets.compactMap { items.indices.contains($0) ? items[$0].id : nil }
        store.supplierProfiles.removeAll { ids.contains($0.id) }
        store.scheduleSave()
    }

    private func openFocusedSupplierIfNeeded() {
        guard let focusedSupplierId, !didOpenFocusedSupplier,
              let supplier = store.supplierProfiles.first(where: { $0.id == focusedSupplierId }) else { return }
        didOpenFocusedSupplier = true
        searchText = ""
        Task { @MainActor in
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
