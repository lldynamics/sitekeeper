import SwiftUI

struct MaterialLibraryView: View {
    @Environment(DataStore.self) private var store
    @State private var selectedCategory: MaterialCategory?
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var editingEntry: MaterialPriceEntry?

    private var visiblePresetMaterials: [CommonMaterial] {
        MaterialLibrary.all.filter { !store.hiddenPresetKeys.contains(materialKey($0)) }
    }

    private var filteredPreset: [CommonMaterial] {
        let list = visiblePresetMaterials
        let byCategory: [CommonMaterial]
        if let cat = selectedCategory { byCategory = list.filter { $0.category == cat } }
        else { byCategory = list }
        if searchText.isEmpty { return byCategory }
        return byCategory.filter { $0.name.localizedStandardContains(searchText) || $0.specification.localizedStandardContains(searchText) }
    }

    private var filteredUser: [UserMaterial] {
        let list = store.userMaterials
        let byCategory: [UserMaterial]
        if let cat = selectedCategory { byCategory = list.filter { $0.category == cat.rawValue } }
        else { byCategory = list }
        if searchText.isEmpty { return byCategory }
        return byCategory.filter { $0.name.localizedStandardContains(searchText) || $0.specification.localizedStandardContains(searchText) }
    }

    private var recentMaterials: [CommonMaterial] {
        store.recentMaterialKeys.prefix(5).compactMap { key in
            MaterialLibrary.all.first { materialKey($0) == key }
        }
    }

    private var showRecycleBin: Bool {
        !store.deletedUserMaterials.isEmpty || !store.hiddenPresetKeys.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryChip(title: "全部", isSelected: selectedCategory == nil) { selectedCategory = nil }
                    ForEach(MaterialCategory.allCases) { cat in
                        CategoryChip(title: cat.rawValue, isSelected: selectedCategory == cat) { selectedCategory = cat }
                    }
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)

            List {
                if !recentMaterials.isEmpty && searchText.isEmpty {
                    Section("最近使用") {
                        ForEach(recentMaterials) { mat in
                            presetMaterialRow(mat)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("从最近移除") { removeRecent(for: mat) }.tint(.orange)
                                    Button("删除材料", role: .destructive) { hidePresetMaterial(mat) }
                                }
                        }
                    }
                }

                if !filteredUser.isEmpty {
                    Section("自定义材料") {
                        ForEach(filteredUser) { mat in
                            userMaterialRow(mat)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button("删除", role: .destructive) { deleteUserMaterial(mat) }
                                }
                        }
                    }
                }

                Section(searchText.isEmpty ? "全部材料" : "搜索结果") {
                    ForEach(filteredPreset) { mat in
                        presetMaterialRow(mat)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("删除材料", role: .destructive) { hidePresetMaterial(mat) }
                            }
                    }
                }

                if showRecycleBin {
                    Section("回收站") {
                        ForEach(Array(store.hiddenPresetKeys), id: \.self) { key in
                            deletedPresetRow(key: key)
                        }
                        ForEach(store.deletedUserMaterials) { mat in
                            deletedUserRow(mat)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "搜索材料名称或规格")
        }
        .navigationTitle("材料库")
        .toolbar {
            Button { showAddSheet = true } label: { Image(systemName: "plus") }.accessibilityLabel("添加自定义材料")
        }
        .sheet(isPresented: $showAddSheet) {
            AddMaterialSheet { material, price in
                store.userMaterials.append(material)
                if !price.isEmpty {
                    let entry = MaterialPriceEntry(
                        name: material.name,
                        specification: material.specification,
                        unit: material.unit,
                        referencePrice: price,
                        category: material.category
                    )
                    store.materialPriceEntries.insert(entry, at: 0)
                }
                store.materialItems.append(MaterialItem(name: "\(material.name) \(material.specification)", quantity: "1", unit: material.unit))
                store.scheduleSave()
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

    // MARK: - Price lookup

    private func priceEntry(for item: CommonMaterial) -> MaterialPriceEntry? {
        let key = materialKey(item)
        return store.materialPriceEntries.first { "\($0.name)|\($0.specification)|\($0.unit)" == key }
    }

    private func priceEntry(forUser item: UserMaterial) -> MaterialPriceEntry? {
        let key = "\(item.name)|\(item.specification)|\(item.unit)"
        return store.materialPriceEntries.first { "\($0.name)|\($0.specification)|\($0.unit)" == key }
    }

    // MARK: - Preset material row

    private func presetMaterialRow(_ item: CommonMaterial) -> some View {
        let entry = priceEntry(for: item)
        let hasPrice = entry?.referencePrice.isEmpty == false
        return materialRowContent(
            name: item.name, spec: item.specification, unit: item.unit,
            hasPrice: hasPrice, price: entry?.referencePrice,
            onEdit: { openPriceEditSheet(name: item.name, spec: item.specification, unit: item.unit, category: item.category.rawValue, entry: entry) },
            onAdd: { addMaterialToProject(name: "\(item.name) \(item.specification)", unit: item.unit, key: materialKey(item)) }
        )
    }

    // MARK: - User material row

    private func userMaterialRow(_ item: UserMaterial) -> some View {
        let entry = priceEntry(forUser: item)
        let hasPrice = entry?.referencePrice.isEmpty == false
        return materialRowContent(
            name: item.name, spec: item.specification, unit: item.unit,
            hasPrice: hasPrice, price: entry?.referencePrice,
            onEdit: { openPriceEditSheet(name: item.name, spec: item.specification, unit: item.unit, category: item.category, entry: entry) },
            onAdd: { addMaterialToProject(name: "\(item.name) \(item.specification)", unit: item.unit, key: "\(item.name)|\(item.specification)|\(item.unit)") }
        )
    }

    // MARK: - Shared row content

    private func materialRowContent(
        name: String, spec: String, unit: String,
        hasPrice: Bool, price: String?,
        onEdit: @escaping () -> Void,
        onAdd: @escaping () -> Void
    ) -> some View {
        HStack {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.body.weight(.medium))
                    Text(spec).font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if hasPrice, let price {
                Button(action: onEdit) {
                    Text("¥\(price)/\(unit)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onEdit) {
                    HStack(spacing: 4) {
                        Image(systemName: "tag").font(.caption)
                        Text("标价").font(.caption2)
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.orange.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill").foregroundStyle(.blue).font(.title3)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Recycle bin rows

    private func deletedPresetRow(key: String) -> some View {
        let parts = key.components(separatedBy: "|")
        let name = parts.indices.contains(0) ? parts[0] : key
        let spec = parts.indices.contains(1) ? parts[1] : ""
        return HStack {
            Image(systemName: "trash").foregroundStyle(.secondary).font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.medium)).foregroundStyle(.secondary)
                Text(spec).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("恢复") {
                store.hiddenPresetKeys.remove(key)
                store.scheduleSave()
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.green)
        }
    }

    private func deletedUserRow(_ item: UserMaterial) -> some View {
        HStack {
            Image(systemName: "trash").foregroundStyle(.secondary).font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium)).foregroundStyle(.secondary)
                Text(item.specification).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("恢复") {
                store.deletedUserMaterials.removeAll { $0.id == item.id }
                store.userMaterials.append(item)
                store.scheduleSave()
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.green)
        }
    }

    // MARK: - Actions

    private func openPriceEditSheet(name: String, spec: String, unit: String, category: String, entry: MaterialPriceEntry?) {
        if let existing = entry {
            editingEntry = existing
        } else {
            let newEntry = MaterialPriceEntry(name: name, specification: spec, unit: unit, category: category)
            store.materialPriceEntries.insert(newEntry, at: 0)
            store.scheduleSave()
            editingEntry = newEntry
        }
    }

    private func addMaterialToProject(name: String, unit: String, key: String) {
        store.materialItems.append(MaterialItem(name: name, quantity: "1", unit: unit))
        store.recentMaterialKeys.removeAll { $0 == key }
        store.recentMaterialKeys.insert(key, at: 0)
        if store.recentMaterialKeys.count > 20 { store.recentMaterialKeys = Array(store.recentMaterialKeys.prefix(20)) }
        store.scheduleSave()
    }

    private func removeRecent(for item: CommonMaterial) {
        let key = materialKey(item)
        store.recentMaterialKeys.removeAll { $0 == key }
        store.scheduleSave()
    }

    private func hidePresetMaterial(_ item: CommonMaterial) {
        let key = materialKey(item)
        store.hiddenPresetKeys.insert(key)
        store.materialPriceEntries.removeAll { "\($0.name)|\($0.specification)|\($0.unit)" == key }
        store.scheduleSave()
    }

    private func deleteUserMaterial(_ item: UserMaterial) {
        store.userMaterials.removeAll { $0.id == item.id }
        store.deletedUserMaterials.insert(item, at: 0)
        if store.deletedUserMaterials.count > 50 { store.deletedUserMaterials = Array(store.deletedUserMaterials.prefix(50)) }
        let key = "\(item.name)|\(item.specification)|\(item.unit)"
        store.materialPriceEntries.removeAll { "\($0.name)|\($0.specification)|\($0.unit)" == key }
        store.scheduleSave()
    }

    private func materialKey(_ item: CommonMaterial) -> String { "\(item.name)|\(item.specification)|\(item.unit)" }
}

private struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.orange : Color.gray.opacity(0.15))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
