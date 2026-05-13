import SwiftUI

private enum MaterialSheetTargetMode: String, CaseIterable, Hashable {
    case existing
    case create
}

private enum AppendMaterialField: Hashable {
    case quantity
    case unitPrice
    case note
}

struct MaterialLibraryView: View {
    private enum PendingMaterialDeleteTarget {
        case preset(CommonMaterial)
        case user(UserMaterial)
    }

    @Environment(DataStore.self) private var store
    @State private var categoryState = MaterialLibraryCategoryState()
    @State private var priceFilter: MaterialPriceFilter = .all
    @State private var searchText = ""
    @State private var showAddSheet = false
    @State private var priceEditorContext: MaterialPriceEditorContext?
    @State private var appendState = MaterialLibraryAppendState()
    @State private var pendingDeleteTarget: PendingMaterialDeleteTarget?
    @State private var showDeleteConfirm = false
    @State private var operationMessage: String?
    @State private var batchState = MaterialLibraryBatchSelectionState()
    @FocusState private var appendMaterialFocusedField: AppendMaterialField?
    @AppStorage("recentMaterialSearches") private var recentSearchKeywordsRaw = ""
    @AppStorage(UserPreferenceKeys.materialLibraryPromptAfterAdd) private var promptAfterAdd = true
    @AppStorage(UserPreferenceKeys.materialLibraryLastTargetMode) private var lastAppendTargetModeRaw = MaterialSheetTargetMode.existing.rawValue
    @AppStorage(UserPreferenceKeys.materialLibraryLastDraftID) private var lastAppendDraftIDRaw = ""
    @AppStorage(UserPreferenceKeys.materialLibraryLastProjectID) private var lastAppendProjectIDRaw = ""

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
            if let cat = categoryState.selectedCategory, item.category.rawValue != cat {
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
            if let cat = categoryState.selectedCategory, normalizedCategory(item.category) != cat {
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

    private var selectedBatchMaterialContexts: [PendingMaterialAppendContext] {
        batchState.selectedMaterialContextsByKey.values
            .sorted { lhs, rhs in
                lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    private var activeMaterialSheetDraftIDs: [UUID] {
        activeMaterialSheetDrafts.map(\.id)
    }

    private var defaultTargetMaterialSheetDraft: MaterialSheetDraft? {
        let activeDrafts = activeMaterialSheetDrafts
        guard !activeDrafts.isEmpty else { return nil }
        if let selectedDefaultMaterialSheetDraftID = appendState.selectedDefaultMaterialSheetDraftID,
           let selected = activeDrafts.first(where: { $0.id == selectedDefaultMaterialSheetDraftID }) {
            return selected
        }
        if let rememberedId = UUID(uuidString: lastAppendDraftIDRaw),
           let remembered = activeDrafts.first(where: { $0.id == rememberedId }) {
            return remembered
        }
        return activeDrafts.first
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryChip(title: "全部", isSelected: categoryState.selectedCategory == nil) { categoryState.selectedCategory = nil }
                    ForEach(availableCategories, id: \.self) { category in
                        CategoryChip(title: category, isSelected: categoryState.selectedCategory == category) { categoryState.selectedCategory = category }
                    }
                    ForEach(MaterialPriceFilter.allCases, id: \.self) { item in
                        CategoryChip(title: item.title, isSelected: priceFilter == item) { priceFilter = item }
                    }
                    Button {
                        categoryState.showCategoryManager = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.caption)
                            Text("分类管理")
                                .font(.caption.weight(.medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.appPrimarySurfaceSubtle)
                        .foregroundStyle(.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("分类管理")
                }
                .padding(.horizontal).padding(.vertical, 8)
            }
            .background(.ultraThinMaterial)

            defaultMaterialSheetTargetBar

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
                                        Button("从最近移除") { removeRecentKey(item.key) }.tint(Color.appWarning)
                                        Button("删除材料", role: .destructive) { requestDeletePresetMaterial(material) }
                                    }
                            case .user(let material):
                                userMaterialRow(material)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button("从最近移除") { removeRecentKey(item.key) }.tint(Color.appWarning)
                                        Button("删除", role: .destructive) { requestDeleteUserMaterial(material) }
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
                                    Button("删除", role: .destructive) { requestDeleteUserMaterial(mat) }
                                }
                        }
                    }
                }

                Section(searchText.isEmpty ? "全部材料" : "搜索结果") {
                    ForEach(filteredPreset) { mat in
                        presetMaterialRow(mat)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("删除材料", role: .destructive) { requestDeletePresetMaterial(mat) }
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
            if batchState.isBatchSelectionMode {
                Button("取消") {
                    exitBatchSelectionMode()
                }
                Button {
                    openBatchAppendSheet()
                } label: {
                    Label("批量加入", systemImage: "square.and.arrow.down.on.square")
                }
                .disabled(selectedBatchMaterialContexts.isEmpty)
            } else {
                Button("批量") {
                    batchState.isBatchSelectionMode = true
                }
                Button { showAddSheet = true } label: { Image(systemName: "plus").visibleIconStyle() }.accessibilityLabel("添加自定义材料")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddMaterialSheet(
                initialCategory: categoryState.selectedCategory,
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
        .sheet(item: $appendState.pendingAddContext) { context in
            NavigationStack {
                MaterialLibraryAppendToSheetForm(
                    context: context,
                    activeMaterialSheetDrafts: activeMaterialSheetDrafts,
                    projects: store.projects,
                    draftPickerTitle: materialSheetDraftPickerTitle(_:),
                    quantity: $appendState.pendingAddQuantity,
                    unitPrice: $appendState.pendingAddUnitPrice,
                    note: $appendState.pendingAddNote,
                    targetMode: $appendState.pendingAddTargetMode,
                    draftId: $appendState.pendingAddDraftId,
                    draftTitle: $appendState.pendingAddDraftTitle,
                    projectId: $appendState.pendingAddProjectId,
                    focusedField: $appendMaterialFocusedField
                )
                .navigationTitle("添加到材料单")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            appendState.pendingAddContext = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("添加") {
                            let appended = appendMaterialsToSheet(
                                [context],
                                quantityText: appendState.pendingAddQuantity,
                                showPostAddPrompt: false,
                                deferToastUntilSheetDismissal: true
                            ) { _ in
                                appendState.pendingAddUnitPrice
                            }
                            guard appended else { return }
                            appendState.pendingAddContext = nil
                        }
                        .disabled(!canAppendMaterialToSheet)
                    }
                    KeyboardNavigationToolbar(
                        focusedField: $appendMaterialFocusedField,
                        fields: [.quantity, .unitPrice, .note]
                    )
                }
            }
            .onChange(of: appendState.pendingAddTargetMode) { _, mode in
                guard mode == .existing else { return }
                appendState.pendingAddDraftId = appendState.pendingAddDraftId ?? activeMaterialSheetDrafts.first?.id
            }
            .operationToast(message: $operationMessage)
        }
        .sheet(item: $batchState.pendingBatchAddContext) { context in
            batchAppendMaterialSheet(context)
        }
        .sheet(isPresented: $categoryState.showCategoryManager) {
            NavigationStack {
                MaterialCategoryManagementView()
            }
        }
        .onChange(of: categoryState.showCategoryManager) { _, isShowing in
            if !isShowing, let selectedCategory = categoryState.selectedCategory, !availableCategories.contains(selectedCategory) {
                categoryState.selectedCategory = nil
            }
        }
        .confirmationDialog("删除材料", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                confirmPendingDeleteMaterial()
            }
            Button("取消", role: .cancel) {
                pendingDeleteTarget = nil
            }
        } message: {
            Text(deleteConfirmMessage)
        }
        .operationToast(message: $operationMessage)
        .safeAreaInset(edge: .bottom) {
            if batchState.isBatchSelectionMode {
                batchAppendActionBar
            }
        }
        .alert("已添加到材料单", isPresented: $appendState.showOpenMaterialSheetPrompt) {
            Button("不再提示") {
                promptAfterAdd = false
            }
            Button("稍后", role: .cancel) {}
            Button("前往材料单") {
                appendState.navigateToMaterialSheet = true
            }
        } message: {
            let title = appendState.recentlyAddedDraftTitle.isEmpty ? "未命名材料单" : appendState.recentlyAddedDraftTitle
            if appendState.recentlyAddedItemCount > 1 {
                Text("已将 \(appendState.recentlyAddedItemCount) 项材料添加到「\(title)」")
            } else {
                Text("已添加到「\(title)」")
            }
        }
        .navigationDestination(isPresented: $appendState.navigateToMaterialSheet) {
            MaterialSheetView(initialDraftID: appendState.recentlyAddedDraftID)
        }
        .onAppear {
            ensureDefaultMaterialSheetSelection()
        }
        .onChange(of: activeMaterialSheetDraftIDs) { _, _ in
            ensureDefaultMaterialSheetSelection()
        }
        .onChange(of: appendState.selectedDefaultMaterialSheetDraftID) { _, newValue in
            guard let newValue else {
                lastAppendDraftIDRaw = ""
                return
            }
            guard let draft = activeMaterialSheetDrafts.first(where: { $0.id == newValue }) else { return }
            lastAppendTargetModeRaw = MaterialSheetTargetMode.existing.rawValue
            lastAppendDraftIDRaw = newValue.uuidString
            lastAppendProjectIDRaw = draft.projectId?.uuidString ?? ""
        }
        .onChange(of: appendState.pendingAddContext?.id) { _, newValue in
            guard newValue == nil else { return }
            flushDeferredOperationMessage()
        }
        .onChange(of: batchState.pendingBatchAddContext?.id) { _, newValue in
            guard newValue == nil else { return }
            flushDeferredOperationMessage()
        }
    }

    private var defaultMaterialSheetTargetBar: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            if let draft = defaultTargetMaterialSheetDraft {
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.tight) {
                    Label("默认材料单", systemImage: "tray.full.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appPrimaryAction)
                    Spacer()
                    Picker("默认材料单", selection: $appendState.selectedDefaultMaterialSheetDraftID) {
                        ForEach(activeMaterialSheetDrafts) { item in
                            Text(materialSheetDraftPickerTitle(item)).tag(item.id as UUID?)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                HStack(alignment: .top, spacing: AppSpacing.tight) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.title.isEmpty ? "未命名材料单" : draft.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text("项目归属：\(projectName(for: draft.projectId) ?? "无归属") · 当前 \(draft.items.count) 项\(recentlyAddedSummary(for: draft))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: AppSpacing.tight)
                    Button {
                        appendState.recentlyAddedDraftID = draft.id
                        appendState.navigateToMaterialSheet = true
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appPrimaryAction)
                    .accessibilityLabel("打开当前材料单")
                }
            } else {
                HStack(spacing: AppSpacing.tight) {
                    Label("暂无默认材料单", systemImage: "tray")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        createAndSelectDefaultMaterialSheetDraft()
                    } label: {
                        Label("创建", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color.appPrimaryAction)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, AppSpacing.tight)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(alignment: .bottom) {
            Divider()
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
        let context = makeAppendContext(
            name: item.name,
            specification: item.specification,
            unit: item.unit,
            key: materialKey(item),
            priceEntry: entry
        )
        return materialRowContent(
            name: item.name, spec: item.specification, unit: item.unit,
            hasPrice: hasPrice, price: entry?.referencePrice,
            appendContext: context,
            onEdit: { openPriceEditSheet(name: item.name, spec: item.specification, unit: item.unit, category: item.category.rawValue, entry: entry) },
            onAdd: {
                prepareAppendMaterial(context)
            }
        )
    }

    // MARK: - User material row

    private func userMaterialRow(_ item: UserMaterial) -> some View {
        let entry = priceEntry(forUser: item)
        let hasPrice = entry?.referencePrice.isEmpty == false
        let context = makeAppendContext(
            name: item.name,
            specification: item.specification,
            unit: item.unit,
            key: materialKey(name: item.name, specification: item.specification, unit: item.unit),
            priceEntry: entry
        )
        return materialRowContent(
            name: item.name, spec: item.specification, unit: item.unit,
            hasPrice: hasPrice, price: entry?.referencePrice,
            appendContext: context,
            onEdit: { openPriceEditSheet(name: item.name, spec: item.specification, unit: item.unit, category: item.category, entry: entry) },
            onAdd: {
                prepareAppendMaterial(context)
            }
        )
    }

    // MARK: - Shared row content

    private func materialRowContent(
        name: String, spec: String, unit: String,
        hasPrice: Bool, price: String?,
        appendContext: PendingMaterialAppendContext,
        onEdit: @escaping () -> Void,
        onAdd: @escaping () -> Void
    ) -> some View {
        let isSelected = batchState.selectedMaterialContextsByKey[appendContext.key] != nil
        return HStack {
            if batchState.isBatchSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.appPrimaryAction : .secondary)
                    .font(.title3)
            }

            Group {
                if batchState.isBatchSelectionMode {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.body.weight(.medium))
                        Text(spec).font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Button(action: onEdit) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name).font(.body.weight(.medium))
                            Text(spec).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Group {
                if hasPrice, let price {
                    Text("¥\(price)/\(unit)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.appPrimaryAction)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "tag").font(.caption)
                        Text("标价").font(.caption2)
                    }
                    .foregroundStyle(Color.appPrimaryAction)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.appPrimarySurfaceSubtle)
                    .clipShape(Capsule())
                }
            }
            .onTapGesture {
                guard !batchState.isBatchSelectionMode else { return }
                onEdit()
            }

            if batchState.isBatchSelectionMode {
                if isSelected {
                    Text("已选")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.appPrimaryAction)
                }
            } else {
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.appPrimaryAction)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加\(name)到材料单")
                .accessibilityValue(materialAccessibilityLabel(name: name, spec: spec, unit: unit, price: price))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard batchState.isBatchSelectionMode else { return }
            toggleBatchMaterialSelection(appendContext)
        }
    }

    private func makeAppendContext(
        name: String,
        specification: String,
        unit: String,
        key: String,
        priceEntry: MaterialPriceEntry?
    ) -> PendingMaterialAppendContext {
        PendingMaterialAppendContext(
            name: name,
            specification: specification,
            unit: unit,
            key: key,
            defaultBrand: priceEntry?.brand ?? "",
            defaultSupplier: priceEntry?.supplier ?? "",
            defaultUnitPrice: priceEntry?.referencePrice ?? ""
        )
    }

    private func materialAccessibilityLabel(name: String, spec: String, unit: String, price: String?) -> String {
        var parts = [name]
        let trimmedSpec = spec.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSpec.isEmpty {
            parts.append("规格 \(trimmedSpec)")
        }
        parts.append("单位 \(unit)")
        if let price, !price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("参考价 \(price) 元每 \(unit)")
        } else {
            parts.append("未标价")
        }
        return parts.joined(separator: "，")
    }

    private func toggleBatchMaterialSelection(_ context: PendingMaterialAppendContext) {
        var selected = batchState.selectedMaterialContextsByKey
        if selected[context.key] != nil {
            selected.removeValue(forKey: context.key)
        } else {
            selected[context.key] = context
        }
        batchState.selectedMaterialContextsByKey = selected
    }

    private func exitBatchSelectionMode() {
        batchState.isBatchSelectionMode = false
        batchState.selectedMaterialContextsByKey = [:]
        batchState.pendingBatchAddContext = nil
    }

    @ViewBuilder
    private var batchAppendActionBar: some View {
        VStack(spacing: 10) {
            HStack {
                Text(selectedBatchMaterialContexts.isEmpty ? "多选模式：勾选后可批量加入材料单" : "已选择 \(selectedBatchMaterialContexts.count) 项材料")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if !selectedBatchMaterialContexts.isEmpty {
                    Button("清空") {
                        batchState.selectedMaterialContextsByKey = [:]
                    }
                    .font(.footnote)
                }
            }
            Button {
                openBatchAppendSheet()
            } label: {
                Label("批量加入材料单", systemImage: "square.and.arrow.down.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.appPrimaryAction)
            .disabled(selectedBatchMaterialContexts.isEmpty)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }

    private func openBatchAppendSheet() {
        let contexts = selectedBatchMaterialContexts
        guard !contexts.isEmpty else {
            operationMessage = "请先选择材料"
            return
        }
        batchState.pendingBatchAddQuantity = "1"
        appendState.pendingAddNote = ""
        appendState.pendingAddProjectId = nil
        applyRememberedAppendTarget()
        appendState.pendingAddDraftTitle = defaultMaterialSheetDraftTitle(projectId: appendState.pendingAddProjectId)
        batchState.pendingBatchAddContext = PendingBatchMaterialAppendContext(materials: contexts)
    }

    private func batchAppendMaterialSheet(_ context: PendingBatchMaterialAppendContext) -> some View {
        NavigationStack {
            MaterialLibraryBatchAppendForm(
                context: context,
                activeMaterialSheetDrafts: activeMaterialSheetDrafts,
                projects: store.projects,
                draftPickerTitle: materialSheetDraftPickerTitle(_:),
                quantity: $batchState.pendingBatchAddQuantity,
                targetMode: $appendState.pendingAddTargetMode,
                draftId: $appendState.pendingAddDraftId,
                draftTitle: $appendState.pendingAddDraftTitle,
                projectId: $appendState.pendingAddProjectId
            )
            .navigationTitle("批量加入材料单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        batchState.pendingBatchAddContext = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let appended = confirmAppendMaterials(
                            context.materials,
                            quantityText: batchState.pendingBatchAddQuantity,
                            deferToastUntilSheetDismissal: true
                        )
                        guard appended else { return }
                        batchState.pendingBatchAddContext = nil
                        batchState.selectedMaterialContextsByKey = [:]
                    }
                    .disabled(!canAppendMaterialToSheet)
                }
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
            .onChange(of: appendState.pendingAddTargetMode) { _, mode in
                guard mode == .existing else { return }
                appendState.pendingAddDraftId = appendState.pendingAddDraftId ?? activeMaterialSheetDrafts.first?.id
            }
        }
        .operationToast(message: $operationMessage)
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
            .tint(.appSuccess)
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
            .tint(.appSuccess)
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

    private func prepareAppendMaterial(_ context: PendingMaterialAppendContext) {
        appendState.pendingAddContext = context
        appendState.pendingAddQuantity = "1"
        appendState.pendingAddUnitPrice = context.defaultUnitPrice
        appendState.pendingAddNote = ""
        appendState.pendingAddProjectId = nil
        applyRememberedAppendTarget()
        appendState.pendingAddDraftTitle = defaultMaterialSheetDraftTitle(projectId: appendState.pendingAddProjectId)
    }

    @discardableResult
    private func confirmAppendMaterials(
        _ contexts: [PendingMaterialAppendContext],
        quantityText: String,
        showPostAddPrompt: Bool = true,
        deferToastUntilSheetDismissal: Bool = false
    ) -> Bool {
        appendMaterialsToSheet(
            contexts,
            quantityText: quantityText,
            showPostAddPrompt: showPostAddPrompt,
            deferToastUntilSheetDismissal: deferToastUntilSheetDismissal
        ) { context in
            context.defaultUnitPrice
        }
    }

    @discardableResult
    private func appendMaterialsToSheet(
        _ contexts: [PendingMaterialAppendContext],
        quantityText: String,
        showPostAddPrompt: Bool = true,
        deferToastUntilSheetDismissal: Bool = false,
        unitPriceResolver: (PendingMaterialAppendContext) -> String
    ) -> Bool {
        guard !contexts.isEmpty else { return false }
        let trimmedQuantity = quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
        let validQuantity = QuantityValue(text: trimmedQuantity).isPositive ? trimmedQuantity : "1"
        let note = contexts.count == 1 ? appendState.pendingAddNote.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let draftItems = contexts.map { context in
            MaterialSheetDraftItem(
                name: context.name,
                specification: context.specification,
                unit: context.unit,
                quantity: validQuantity,
                unitPrice: unitPriceResolver(context).trimmingCharacters(in: .whitespacesAndNewlines),
                supplier: context.defaultSupplier,
                note: note
            )
        }
        let now = Formatters.now()
        var drafts = store.materialSheetDrafts
        let title: String
        let targetDraftID: UUID

        switch appendState.pendingAddTargetMode {
        case .existing:
            guard let draftId = appendState.pendingAddDraftId,
                  let draftIndex = drafts.firstIndex(where: { $0.id == draftId })
            else {
                operationMessage = "未找到可用材料单，请切换到“新建材料单”后重试"
                appendState.pendingAddTargetMode = .create
                appendState.pendingAddDraftId = nil
                return false
            }
            drafts[draftIndex].items.insert(contentsOf: draftItems, at: 0)
            drafts[draftIndex].updatedAt = now
            title = drafts[draftIndex].title
            targetDraftID = drafts[draftIndex].id
            lastAppendTargetModeRaw = MaterialSheetTargetMode.existing.rawValue
            lastAppendDraftIDRaw = targetDraftID.uuidString
            lastAppendProjectIDRaw = drafts[draftIndex].projectId?.uuidString ?? ""
        case .create:
            let projectId = appendState.pendingAddProjectId
            let resolvedTitle = resolvedMaterialSheetDraftTitle(projectId: projectId)
            let newDraft = MaterialSheetDraft(
                title: resolvedTitle,
                projectId: projectId,
                exportProjectName: projectName(for: projectId) ?? "",
                items: draftItems,
                createdAt: now,
                updatedAt: now
            )
            drafts.insert(newDraft, at: 0)
            title = resolvedTitle
            targetDraftID = newDraft.id
            lastAppendTargetModeRaw = MaterialSheetTargetMode.existing.rawValue
            lastAppendDraftIDRaw = targetDraftID.uuidString
            lastAppendProjectIDRaw = projectId?.uuidString ?? ""
            appendState.pendingAddTargetMode = .existing
            appendState.pendingAddDraftId = targetDraftID
            appendState.selectedDefaultMaterialSheetDraftID = targetDraftID
        }

        store.materialSheetDrafts = drafts
        contexts.forEach { appendRecentMaterialKey($0.key) }
        store.scheduleSave()
        let resolvedTitle = title.isEmpty ? "未命名材料单" : title
        let successMessage: String
        if contexts.count > 1 {
            successMessage = "已添加 \(contexts.count) 项到「\(resolvedTitle)」"
        } else {
            successMessage = "已添加到「\(resolvedTitle)」"
        }
        showOperationMessage(successMessage, deferUntilDismissal: deferToastUntilSheetDismissal)
        appendState.selectedDefaultMaterialSheetDraftID = targetDraftID
        appendState.recentlyAddedDraftID = targetDraftID
        appendState.recentlyAddedDraftTitle = title
        appendState.recentlyAddedItemCount = contexts.count
        appendState.showOpenMaterialSheetPrompt = promptAfterAdd && showPostAddPrompt
        return true
    }

    private func showOperationMessage(_ message: String, deferUntilDismissal: Bool = false) {
        if deferUntilDismissal {
            appendState.deferredOperationMessage = message
        } else {
            operationMessage = message
        }
    }

    private func flushDeferredOperationMessage() {
        guard let message = appendState.deferredOperationMessage else { return }
        appendState.deferredOperationMessage = nil
        operationMessage = message
    }

    private var activeMaterialSheetDrafts: [MaterialSheetDraft] {
        store.materialSheetDrafts
            .filter { !$0.isArchived }
            .sorted { lhs, rhs in
                let lhsDate = Formatters.parseDateOrDateTime(lhs.updatedAt) ?? .distantPast
                let rhsDate = Formatters.parseDateOrDateTime(rhs.updatedAt) ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    private func applyRememberedAppendTarget() {
        let rememberedMode = MaterialSheetTargetMode(rawValue: lastAppendTargetModeRaw) ?? .existing
        let rememberedDraftID = UUID(uuidString: lastAppendDraftIDRaw)
        let rememberedProjectID = UUID(uuidString: lastAppendProjectIDRaw)

        switch rememberedMode {
        case .existing:
            if let rememberedDraftID,
               activeMaterialSheetDrafts.contains(where: { $0.id == rememberedDraftID }) {
                appendState.pendingAddTargetMode = .existing
                appendState.pendingAddDraftId = rememberedDraftID
                appendState.pendingAddProjectId = nil
                return
            }
            if let firstDraftID = activeMaterialSheetDrafts.first?.id {
                appendState.pendingAddTargetMode = .existing
                appendState.pendingAddDraftId = firstDraftID
                appendState.pendingAddProjectId = nil
                return
            }
            appendState.pendingAddTargetMode = .create
            appendState.pendingAddDraftId = nil
            appendState.pendingAddProjectId = normalizedRememberedProjectID(rememberedProjectID)
        case .create:
            appendState.pendingAddTargetMode = .create
            appendState.pendingAddDraftId = activeMaterialSheetDrafts.first?.id
            appendState.pendingAddProjectId = normalizedRememberedProjectID(rememberedProjectID)
        }
    }

    private func ensureDefaultMaterialSheetSelection() {
        if let selectedDefaultMaterialSheetDraftID = appendState.selectedDefaultMaterialSheetDraftID,
           activeMaterialSheetDrafts.contains(where: { $0.id == selectedDefaultMaterialSheetDraftID }) {
            return
        }
        if let rememberedId = UUID(uuidString: lastAppendDraftIDRaw),
           activeMaterialSheetDrafts.contains(where: { $0.id == rememberedId }) {
            appendState.selectedDefaultMaterialSheetDraftID = rememberedId
            return
        }
        appendState.selectedDefaultMaterialSheetDraftID = activeMaterialSheetDrafts.first?.id
    }

    @discardableResult
    private func createAndSelectDefaultMaterialSheetDraft() -> UUID {
        let now = Formatters.now()
        let newDraft = MaterialSheetDraft(
            title: defaultMaterialSheetDraftTitle(projectId: nil),
            items: [],
            createdAt: now,
            updatedAt: now
        )
        var drafts = store.materialSheetDrafts
        drafts.insert(newDraft, at: 0)
        store.materialSheetDrafts = drafts
        store.scheduleSave()
        appendState.selectedDefaultMaterialSheetDraftID = newDraft.id
        lastAppendTargetModeRaw = MaterialSheetTargetMode.existing.rawValue
        lastAppendDraftIDRaw = newDraft.id.uuidString
        lastAppendProjectIDRaw = ""
        operationMessage = "已创建默认材料单「\(newDraft.title)」"
        return newDraft.id
    }

    private func normalizedRememberedProjectID(_ projectID: UUID?) -> UUID? {
        guard let projectID,
              store.projects.contains(where: { $0.id == projectID }) else {
            return nil
        }
        return projectID
    }

    private var canAppendMaterialToSheet: Bool {
        switch appendState.pendingAddTargetMode {
        case .existing:
            return appendState.pendingAddDraftId != nil
        case .create:
            return true
        }
    }

    private func materialSheetDraftPickerTitle(_ draft: MaterialSheetDraft) -> String {
        let resolvedTitle = draft.title.isEmpty ? "未命名材料单" : draft.title
        let projectPart = projectName(for: draft.projectId) ?? "无归属"
        return "\(resolvedTitle) · \(projectPart)"
    }

    private func projectName(for projectId: UUID?) -> String? {
        guard let projectId else { return nil }
        return store.projects.first(where: { $0.id == projectId })?.name
    }

    private func recentlyAddedSummary(for draft: MaterialSheetDraft) -> String {
        guard appendState.recentlyAddedDraftID == draft.id, appendState.recentlyAddedItemCount > 0 else {
            return ""
        }
        return " · 最近添加 \(appendState.recentlyAddedItemCount) 项"
    }

    private func defaultMaterialSheetDraftTitle(projectId: UUID?) -> String {
        if let name = projectName(for: projectId), !name.isEmpty {
            return "\(name)-材料单"
        }
        return "材料单-\(Formatters.date.string(from: Date()))"
    }

    private func resolvedMaterialSheetDraftTitle(projectId: UUID?) -> String {
        let input = appendState.pendingAddDraftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !input.isEmpty {
            return input
        }
        return defaultMaterialSheetDraftTitle(projectId: projectId)
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

    private var deleteConfirmMessage: String {
        switch pendingDeleteTarget {
        case .preset(let item):
            let name = item.specification.isEmpty ? item.name : "\(item.name) \(item.specification)"
            return "确认删除材料「\(name)」吗？可在回收站恢复。"
        case .user(let item):
            let name = item.specification.isEmpty ? item.name : "\(item.name) \(item.specification)"
            return "确认删除自定义材料「\(name)」吗？可在回收站恢复。"
        case .none:
            return "确认删除所选材料吗？"
        }
    }

    private func requestDeletePresetMaterial(_ item: CommonMaterial) {
        pendingDeleteTarget = .preset(item)
        showDeleteConfirm = true
    }

    private func requestDeleteUserMaterial(_ item: UserMaterial) {
        pendingDeleteTarget = .user(item)
        showDeleteConfirm = true
    }

    private func confirmPendingDeleteMaterial() {
        guard let pendingDeleteTarget else { return }
        switch pendingDeleteTarget {
        case .preset(let item):
            hidePresetMaterial(item)
        case .user(let item):
            deleteUserMaterial(item)
        }
        self.pendingDeleteTarget = nil
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
    let defaultUnitPrice: String

    var displayName: String {
        let trimmedSpec = specification.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSpec.isEmpty {
            return name
        }
        return "\(name) \(trimmedSpec)"
    }
}

private struct PendingBatchMaterialAppendContext: Identifiable {
    let id = UUID()
    let materials: [PendingMaterialAppendContext]
}

private struct MaterialLibraryCategoryState {
    var selectedCategory: String?
    var showCategoryManager = false
}

private struct MaterialLibraryAppendState {
    var pendingAddContext: PendingMaterialAppendContext?
    var pendingAddQuantity = "1"
    var selectedDefaultMaterialSheetDraftID: UUID?
    var pendingAddProjectId: UUID?
    var pendingAddUnitPrice = ""
    var pendingAddNote = ""
    var pendingAddTargetMode: MaterialSheetTargetMode = .existing
    var pendingAddDraftId: UUID?
    var pendingAddDraftTitle = ""
    var recentlyAddedDraftID: UUID?
    var recentlyAddedDraftTitle = ""
    var recentlyAddedItemCount = 0
    var showOpenMaterialSheetPrompt = false
    var navigateToMaterialSheet = false
    var deferredOperationMessage: String?
}

private struct MaterialLibraryBatchSelectionState {
    var isBatchSelectionMode = false
    var selectedMaterialContextsByKey: [String: PendingMaterialAppendContext] = [:]
    var pendingBatchAddContext: PendingBatchMaterialAppendContext?
    var pendingBatchAddQuantity = "1"
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

private struct MaterialLibraryAppendToSheetForm: View {
    let context: PendingMaterialAppendContext
    let activeMaterialSheetDrafts: [MaterialSheetDraft]
    let projects: [Project]
    let draftPickerTitle: (MaterialSheetDraft) -> String
    @Binding var quantity: String
    @Binding var unitPrice: String
    @Binding var note: String
    @Binding var targetMode: MaterialSheetTargetMode
    @Binding var draftId: UUID?
    @Binding var draftTitle: String
    @Binding var projectId: UUID?
    var focusedField: FocusState<AppendMaterialField?>.Binding

    var body: some View {
        Form {
            Section("材料") {
                LabeledContent("名称", value: context.name)
                if !context.specification.isEmpty {
                    LabeledContent("规格", value: context.specification)
                }
                LabeledContent("单位", value: context.unit)
            }
            Section("添加参数") {
                TextField("数量", text: $quantity)
                    .keyboardType(.decimalPad)
                    .focused(focusedField, equals: .quantity)
                TextField("单价（可选）", text: $unitPrice)
                    .keyboardType(.decimalPad)
                    .focused(focusedField, equals: .unitPrice)
                TextField("备注（可选）", text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .focused(focusedField, equals: .note)
            }
            Section("保存到材料单") {
                Picker("目标", selection: $targetMode) {
                    Text("已有材料单").tag(MaterialSheetTargetMode.existing)
                    Text("新建材料单").tag(MaterialSheetTargetMode.create)
                }
                .pickerStyle(.segmented)

                if targetMode == .existing {
                    if activeMaterialSheetDrafts.isEmpty {
                        Text("暂无可用材料单，请切换到“新建材料单”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("材料单", selection: $draftId) {
                            ForEach(activeMaterialSheetDrafts) { draft in
                                Text(draftPickerTitle(draft)).tag(draft.id as UUID?)
                            }
                        }
                    }
                } else {
                    TextField("材料单名称", text: $draftTitle)
                    Picker("归属项目", selection: $projectId) {
                        Text("无归属").tag(nil as UUID?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
            }
        }
    }
}

private struct MaterialLibraryBatchAppendForm: View {
    let context: PendingBatchMaterialAppendContext
    let activeMaterialSheetDrafts: [MaterialSheetDraft]
    let projects: [Project]
    let draftPickerTitle: (MaterialSheetDraft) -> String
    @Binding var quantity: String
    @Binding var targetMode: MaterialSheetTargetMode
    @Binding var draftId: UUID?
    @Binding var draftTitle: String
    @Binding var projectId: UUID?

    var body: some View {
        Form {
            Section("已选材料 (\(context.materials.count))") {
                ForEach(context.materials.prefix(5)) { item in
                    Text(item.displayName)
                }
                if context.materials.count > 5 {
                    Text("其余 \(context.materials.count - 5) 项将在保存后一并加入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("添加参数") {
                TextField("数量", text: $quantity)
                    .keyboardType(.decimalPad)
            }

            Section("保存到材料单") {
                Picker("目标", selection: $targetMode) {
                    Text("已有材料单").tag(MaterialSheetTargetMode.existing)
                    Text("新建材料单").tag(MaterialSheetTargetMode.create)
                }
                .pickerStyle(.segmented)

                if targetMode == .existing {
                    if activeMaterialSheetDrafts.isEmpty {
                        Text("暂无可用材料单，请切换到“新建材料单”")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("材料单", selection: $draftId) {
                            ForEach(activeMaterialSheetDrafts) { draft in
                                Text(draftPickerTitle(draft)).tag(draft.id as UUID?)
                            }
                        }
                    }
                } else {
                    TextField("材料单名称", text: $draftTitle)
                    Picker("归属项目", selection: $projectId) {
                        Text("无归属").tag(nil as UUID?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                }
            }
        }
    }
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
                .background(isSelected ? Color.appPrimaryAction : Color(uiColor: .tertiarySystemGroupedBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
