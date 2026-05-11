import SwiftUI

struct MaterialLibraryView: View {
    private enum AppendMaterialField: Hashable {
        case quantity
        case unitPrice
    }

    @Environment(DataStore.self) private var store
    @State private var selectedCategory: String?
    @State private var priceFilter: MaterialPriceFilter = .all
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var showCategoryManager = false
    @State private var priceEditorContext: MaterialPriceEditorContext?
    @State private var pendingAddContext: PendingMaterialAppendContext?
    @State private var pendingAddQuantity = "1"
    @State private var pendingAddProjectId: UUID?
    @State private var pendingAddUnitPrice = ""
    @FocusState private var appendMaterialFocusedField: AppendMaterialField?
    @AppStorage("recentMaterialSearches") private var recentSearchKeywordsRaw = ""

    private var visiblePresetMaterials: [CommonMaterial] {
        MaterialLibrary.all.filter { !isPresetHidden($0) }
    }

    private var priceEntryByKey: [String: MaterialPriceEntry] {
        var map: [String: MaterialPriceEntry] = [:]
        for entry in store.materialPriceEntries {
            let key = materialKey(name: entry.name, specification: entry.specification, unit: entry.unit)
            if map[key] == nil {
                map[key] = entry
            }
        }
        return map
    }

    private var normalizedSearchKeyword: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var recentSearchKeywords: [String] {
        recentSearchKeywordsRaw
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private var filteredPreset: [CommonMaterial] {
        visiblePresetMaterials.filter { item in
            if let cat = selectedCategory, item.category.rawValue != cat {
                return false
            }
            let entry = priceEntry(for: item)
            guard matchesPriceFilter(entry) else { return false }
            return matchesSearch(
                item,
                extraFields: [
                    entry?.brand ?? "",
                    entry?.supplier ?? "",
                    entry?.category ?? "",
                    entry?.note ?? "",
                ]
            )
        }
    }

    private var filteredUser: [UserMaterial] {
        store.userMaterials.filter { item in
            if let cat = selectedCategory, normalizedCategory(item.category) != cat {
                return false
            }
            let entry = priceEntry(forUser: item)
            guard matchesPriceFilter(entry) else { return false }
            return matchesSearch(
                item,
                extraFields: [
                    entry?.brand ?? "",
                    entry?.supplier ?? "",
                    entry?.category ?? "",
                    entry?.note ?? "",
                ]
            )
        }
    }

    private var availableCategories: [String] {
        let preset = MaterialCategory.allCases.map(\.rawValue)
        let presetSet = Set(preset)
        let dynamic = Set(
            (store.userMaterials.map(\.category) + store.materialPriceEntries.map(\.category))
                .map(normalizedCategory)
                .filter { !$0.isEmpty }
        )
        let custom = dynamic.subtracting(presetSet).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return preset + custom
    }

    private var recentMaterials: [RecentMaterialItem] {
        store.recentMaterialKeys.prefix(5).compactMap { key in
            if let preset = MaterialLibrary.all.first(where: {
                materialKey($0) == key || legacyMaterialKey($0) == key
            }) {
                return RecentMaterialItem(key: key, source: .preset(preset))
            }
            if let userMaterial = store.userMaterials.first(where: {
                let normalized = materialKey(name: $0.name, specification: $0.specification, unit: $0.unit)
                let legacy = legacyMaterialKey(name: $0.name, specification: $0.specification, unit: $0.unit)
                return normalized == key || legacy == key
            }) {
                return RecentMaterialItem(key: key, source: .user(userMaterial))
            }
            return nil
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
                    ForEach(availableCategories, id: \.self) { category in
                        CategoryChip(title: category, isSelected: selectedCategory == category) { selectedCategory = category }
                    }
                    ForEach(MaterialPriceFilter.allCases, id: \.self) { item in
                        CategoryChip(title: item.title, isSelected: priceFilter == item) { priceFilter = item }
                    }
                    Button {
                        showCategoryManager = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.caption)
                            Text("分类管理")
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.15))
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("分类管理")
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)

            List {
                if !recentSearchKeywords.isEmpty && searchText.isEmpty {
                    Section("最近搜索") {
                        ForEach(recentSearchKeywords, id: \.self) { term in
                            Button {
                                searchText = term
                            } label: {
                                Label(term, systemImage: "clock.arrow.circlepath")
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button("移除", role: .destructive) {
                                    removeRecentSearchKeyword(term)
                                }
                            }
                        }
                    }
                }

                if !recentMaterials.isEmpty && searchText.isEmpty {
                    Section("最近使用") {
                        ForEach(recentMaterials) { item in
                            switch item.source {
                            case .preset(let material):
                                presetMaterialRow(material)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("从最近移除") { removeRecentKey(item.key) }.tint(.orange)
                                        Button("删除材料", role: .destructive) { hidePresetMaterial(material) }
                                    }
                            case .user(let material):
                                userMaterialRow(material)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("从最近移除") { removeRecentKey(item.key) }.tint(.orange)
                                        Button("删除", role: .destructive) { deleteUserMaterial(material) }
                                    }
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
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "搜索材料名称或规格"
            )
            .onSubmit(of: .search) {
                rememberRecentSearchKeyword()
            }
        }
        .navigationTitle("材料库")
        .toolbar {
            Button { showAddSheet = true } label: { Image(systemName: "plus").visibleIconStyle() }.accessibilityLabel("添加自定义材料")
        }
        .sheet(isPresented: $showAddSheet) {
            AddMaterialSheet(
                initialCategory: selectedCategory,
                suggestedCategories: availableCategories
            ) { material, price in
                let key = materialKey(name: material.name, specification: material.specification, unit: material.unit)
                if !store.userMaterials.contains(where: { materialKey(name: $0.name, specification: $0.specification, unit: $0.unit) == key }) {
                    store.userMaterials.append(material)
                }
                if !price.isEmpty {
                    let entry = MaterialPriceEntry(
                        name: material.name,
                        specification: material.specification,
                        unit: material.unit,
                        referencePrice: price,
                        category: material.category
                    )
                    upsertMaterialPriceEntry(entry)
                }
                let displayName = material.specification.isEmpty ? material.name : "\(material.name) \(material.specification)"
                store.materialItems.append(MaterialItem(
                    name: displayName,
                    quantity: "1",
                    unit: material.unit,
                    unitPrice: price,
                    specification: material.specification
                ))
                store.scheduleSave()
            }
        }
        .sheet(item: $priceEditorContext) { context in
            MaterialPriceEditSheet(
                entry: context.entry,
                suppliers: store.supplierProfiles,
                initialName: context.name,
                initialSpecification: context.specification,
                initialUnit: context.unit,
                initialCategory: context.category
            ) { updated in
                upsertMaterialPriceEntry(updated)
                priceEditorContext = nil
            } onDelete: { target in
                store.materialPriceEntries.removeAll { $0.id == target.id }
                store.scheduleSave()
                priceEditorContext = nil
            }
        }
        .sheet(item: $pendingAddContext) { context in
            NavigationStack {
                Form {
                    Section("材料") {
                        LabeledContent("名称", value: context.name)
                        if !context.specification.isEmpty {
                            LabeledContent("规格", value: context.specification)
                        }
                        LabeledContent("单位", value: context.unit)
                    }
                    Section("添加参数") {
                        TextField("数量", text: $pendingAddQuantity)
                            .keyboardType(.decimalPad)
                            .focused($appendMaterialFocusedField, equals: .quantity)
                        TextField("单价（可选）", text: $pendingAddUnitPrice)
                            .keyboardType(.decimalPad)
                            .focused($appendMaterialFocusedField, equals: .unitPrice)
                        Picker("归属项目", selection: $pendingAddProjectId) {
                            Text("无归属").tag(nil as UUID?)
                            ForEach(store.projects) { project in
                                Text(project.name).tag(project.id as UUID?)
                            }
                        }
                    }
                }
                .navigationTitle("添加到材料清单")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            pendingAddContext = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("添加") {
                            confirmAppendMaterial(context)
                            pendingAddContext = nil
                        }
                    }
                    KeyboardNavigationToolbar(
                        focusedField: $appendMaterialFocusedField,
                        fields: [.quantity, .unitPrice]
                    )
                }
            }
        }
        .sheet(isPresented: $showCategoryManager) {
            NavigationStack {
                MaterialCategoryManagementView()
            }
        }
        .onChange(of: showCategoryManager) { _, isShowing in
            if !isShowing, let selectedCategory, !availableCategories.contains(selectedCategory) {
                self.selectedCategory = nil
            }
        }
    }

    // MARK: - Price lookup

    private func priceEntry(for item: CommonMaterial) -> MaterialPriceEntry? {
        priceEntryByKey[materialKey(item)]
    }

    private func priceEntry(forUser item: UserMaterial) -> MaterialPriceEntry? {
        priceEntryByKey[materialKey(name: item.name, specification: item.specification, unit: item.unit)]
    }

    // MARK: - Preset material row

    private func presetMaterialRow(_ item: CommonMaterial) -> some View {
        let entry = priceEntry(for: item)
        let hasPrice = entry?.referencePrice.isEmpty == false
        return materialRowContent(
            name: item.name, spec: item.specification, unit: item.unit,
            hasPrice: hasPrice, price: entry?.referencePrice,
            onEdit: { openPriceEditSheet(name: item.name, spec: item.specification, unit: item.unit, category: item.category.rawValue, entry: entry) },
            onAdd: {
                prepareAppendMaterial(
                    name: item.name,
                    specification: item.specification,
                    unit: item.unit,
                    key: materialKey(item),
                    priceEntry: entry
                )
            }
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
            onAdd: {
                prepareAppendMaterial(
                    name: item.name,
                    specification: item.specification,
                    unit: item.unit,
                    key: materialKey(name: item.name, specification: item.specification, unit: item.unit),
                    priceEntry: entry
                )
            }
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
                    .background(Color.appPrimarySurfaceSubtle)
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
            priceEditorContext = MaterialPriceEditorContext(existing: existing)
        } else {
            priceEditorContext = MaterialPriceEditorContext(
                name: name,
                specification: spec,
                unit: unit,
                category: category
            )
        }
    }

    private func prepareAppendMaterial(
        name: String,
        specification: String,
        unit: String,
        key: String,
        priceEntry: MaterialPriceEntry?
    ) {
        pendingAddContext = PendingMaterialAppendContext(
            name: name,
            specification: specification,
            unit: unit,
            key: key,
            defaultBrand: priceEntry?.brand ?? "",
            defaultSupplier: priceEntry?.supplier ?? ""
        )
        pendingAddQuantity = "1"
        pendingAddProjectId = nil
        pendingAddUnitPrice = priceEntry?.referencePrice ?? ""
    }

    private func confirmAppendMaterial(_ context: PendingMaterialAppendContext) {
        let quantityText = pendingAddQuantity.trimmingCharacters(in: .whitespacesAndNewlines)
        let validQuantity = QuantityValue(text: quantityText).isPositive ? quantityText : "1"
        let unitPriceText = pendingAddUnitPrice.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = context.specification.isEmpty ? context.name : "\(context.name) \(context.specification)"
        store.materialItems.append(
            MaterialItem(
                name: displayName,
                quantity: validQuantity,
                unit: context.unit,
                unitPrice: unitPriceText,
                specification: context.specification,
                brand: context.defaultBrand,
                supplier: context.defaultSupplier,
                projectId: pendingAddProjectId
            )
        )
        appendRecentMaterialKey(context.key)
        store.scheduleSave()
    }

    private func appendRecentMaterialKey(_ key: String) {
        store.recentMaterialKeys.removeAll { $0 == key }
        store.recentMaterialKeys.insert(key, at: 0)
        if store.recentMaterialKeys.count > 20 {
            store.recentMaterialKeys = Array(store.recentMaterialKeys.prefix(20))
        }
    }

    private func removeRecentKey(_ key: String) {
        store.recentMaterialKeys.removeAll { $0 == key }
        store.scheduleSave()
    }

    private func rememberRecentSearchKeyword() {
        let term = normalizedSearchKeyword
        guard !term.isEmpty else { return }
        var items = recentSearchKeywords.filter { $0 != term }
        items.insert(term, at: 0)
        recentSearchKeywordsRaw = items.prefix(8).joined(separator: "\n")
    }

    private func removeRecentSearchKeyword(_ term: String) {
        recentSearchKeywordsRaw = recentSearchKeywords.filter { $0 != term }.joined(separator: "\n")
    }

    private func hidePresetMaterial(_ item: CommonMaterial) {
        let normalizedKey = materialKey(item)
        let legacyKey = legacyMaterialKey(item)
        store.hiddenPresetKeys.insert(normalizedKey)
        store.hiddenPresetKeys.remove(legacyKey)
        store.scheduleSave()
    }

    private func deleteUserMaterial(_ item: UserMaterial) {
        store.userMaterials.removeAll { $0.id == item.id }
        store.deletedUserMaterials.insert(item, at: 0)
        if store.deletedUserMaterials.count > 50 { store.deletedUserMaterials = Array(store.deletedUserMaterials.prefix(50)) }
        store.scheduleSave()
    }

    private func materialKey(_ item: CommonMaterial) -> String {
        materialKey(name: item.name, specification: item.specification, unit: item.unit)
    }

    private func legacyMaterialKey(_ item: CommonMaterial) -> String {
        legacyMaterialKey(name: item.name, specification: item.specification, unit: item.unit)
    }

    private func materialKey(name: String, specification: String, unit: String) -> String {
        MaterialIdentity.key(name: name, specification: specification, unit: unit)
    }

    private func legacyMaterialKey(name: String, specification: String, unit: String) -> String {
        "\(name)|\(specification)|\(unit)"
    }

    private func isPresetHidden(_ item: CommonMaterial) -> Bool {
        store.hiddenPresetKeys.contains(materialKey(item)) || store.hiddenPresetKeys.contains(legacyMaterialKey(item))
    }

    private func normalizedCategory(_ value: String) -> String {
        MaterialIdentity.normalizedCategory(value)
    }

    private func matchesPriceFilter(_ entry: MaterialPriceEntry?) -> Bool {
        switch priceFilter {
        case .all:
            return true
        case .priced:
            return !(entry?.referencePrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        case .unpriced:
            return entry?.referencePrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        }
    }

    private func matchesSearch<Item: Searchable>(_ item: Item, extraFields: [String]) -> Bool {
        SearchMatcher.filter(
            [item],
            keyword: normalizedSearchKeyword,
            extraFields: { _ in extraFields }
        ).isEmpty == false
    }

    private func upsertMaterialPriceEntry(_ entry: MaterialPriceEntry) {
        let entryKey = materialKey(name: entry.name, specification: entry.specification, unit: entry.unit)
        if let index = store.materialPriceEntries.firstIndex(where: { $0.id == entry.id }) {
            store.materialPriceEntries[index] = entry
            store.scheduleSave()
            return
        }
        if let duplicateIndex = store.materialPriceEntries.firstIndex(where: {
            materialKey(name: $0.name, specification: $0.specification, unit: $0.unit) == entryKey
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
}

private enum MaterialPriceFilter: CaseIterable {
    case all
    case priced
    case unpriced

    var title: String {
        switch self {
        case .all:
            return "全部价格"
        case .priced:
            return "已标价"
        case .unpriced:
            return "未标价"
        }
    }
}

private struct MaterialPriceEditorContext: Identifiable {
    let id: UUID
    let entry: MaterialPriceEntry?
    let name: String
    let specification: String
    let unit: String
    let category: String

    init(existing entry: MaterialPriceEntry) {
        id = entry.id
        self.entry = entry
        name = entry.name
        specification = entry.specification
        unit = entry.unit
        category = entry.category
    }

    init(name: String, specification: String, unit: String, category: String) {
        id = UUID()
        entry = nil
        self.name = name
        self.specification = specification
        self.unit = unit
        self.category = category
    }
}

private struct PendingMaterialAppendContext: Identifiable {
    let id = UUID()
    let name: String
    let specification: String
    let unit: String
    let key: String
    let defaultBrand: String
    let defaultSupplier: String
}

private struct RecentMaterialItem: Identifiable {
    enum Source {
        case preset(CommonMaterial)
        case user(UserMaterial)
    }

    let key: String
    let source: Source

    var id: String { key }
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

private struct MaterialCategoryManagementView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var renameSource = ""
    @State private var renameTarget = ""
    @State private var showRenameSheet = false

    @State private var deleteSource = ""
    @State private var deleteTarget = MaterialCategory.other.rawValue
    @State private var showDeleteSheet = false

    private var categoryUsage: [CategoryUsage] {
        let userCategories = store.userMaterials.map { normalizedCategory($0.category) }.filter { !$0.isEmpty }
        let priceCategories = store.materialPriceEntries.map { normalizedCategory($0.category) }.filter { !$0.isEmpty }
        let names = Set(userCategories + priceCategories)

        return names
            .map { name in
                CategoryUsage(
                    name: name,
                    userMaterialCount: userCategories.filter { $0 == name }.count,
                    priceEntryCount: priceCategories.filter { $0 == name }.count
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var migrationTargets: [String] {
        let preset = MaterialCategory.allCases.map(\.rawValue)
        let dynamic = categoryUsage.map(\.name)
        return Array(Set(preset + dynamic)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        List {
            if categoryUsage.isEmpty {
                ContentUnavailableView("暂无可管理分类", systemImage: "tag")
            } else {
                Section("现有分类") {
                    ForEach(categoryUsage) { usage in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(usage.name)
                                .font(.body.weight(.semibold))
                            Text("自定义材料 \(usage.userMaterialCount) 条 · 价格条目 \(usage.priceEntryCount) 条")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("删除", role: .destructive) {
                                deleteSource = usage.name
                                deleteTarget = defaultDeleteTarget(for: usage.name)
                                showDeleteSheet = true
                            }
                            Button("重命名") {
                                renameSource = usage.name
                                renameTarget = usage.name
                                showRenameSheet = true
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("分类管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") { dismiss() }
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            NavigationStack {
                Form {
                    Section("重命名分类") {
                        LabeledContent("原分类", value: renameSource)
                        TextField("新分类名称", text: $renameTarget)
                    }
                }
                .navigationTitle("重命名")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showRenameSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            renameCategory(from: renameSource, to: renameTarget)
                            showRenameSheet = false
                        }
                        .disabled(normalizedCategory(renameTarget).isEmpty || normalizedCategory(renameTarget) == renameSource)
                    }
                }
            }
        }
        .sheet(isPresented: $showDeleteSheet) {
            NavigationStack {
                Form {
                    Section("删除分类并迁移") {
                        Text("分类“\(deleteSource)”将被移除。")
                            .font(.subheadline)
                        Picker("迁移到", selection: $deleteTarget) {
                            ForEach(migrationTargets.filter { $0 != deleteSource }, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                }
                .navigationTitle("删除分类")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showDeleteSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("删除并迁移", role: .destructive) {
                            migrateCategory(from: deleteSource, to: deleteTarget)
                            showDeleteSheet = false
                        }
                        .disabled(deleteTarget == deleteSource || normalizedCategory(deleteTarget).isEmpty)
                    }
                }
            }
        }
    }

    private func renameCategory(from source: String, to target: String) {
        let normalizedSource = normalizedCategory(source)
        let normalizedTarget = normalizedCategory(target)
        guard !normalizedSource.isEmpty, !normalizedTarget.isEmpty, normalizedSource != normalizedTarget else { return }
        migrateCategory(from: normalizedSource, to: normalizedTarget)
    }

    private func migrateCategory(from source: String, to target: String) {
        let normalizedSource = normalizedCategory(source)
        let normalizedTarget = normalizedCategory(target)
        guard !normalizedSource.isEmpty, !normalizedTarget.isEmpty, normalizedSource != normalizedTarget else { return }

        for index in store.userMaterials.indices where normalizedCategory(store.userMaterials[index].category) == normalizedSource {
            store.userMaterials[index].category = normalizedTarget
        }
        for index in store.materialPriceEntries.indices where normalizedCategory(store.materialPriceEntries[index].category) == normalizedSource {
            store.materialPriceEntries[index].category = normalizedTarget
        }
        store.scheduleSave()
    }

    private func defaultDeleteTarget(for source: String) -> String {
        let candidates = migrationTargets.filter { $0 != source }
        return candidates.first ?? MaterialCategory.other.rawValue
    }

    private func normalizedCategory(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct CategoryUsage: Identifiable {
    let name: String
    let userMaterialCount: Int
    let priceEntryCount: Int

    var id: String { name }
}
