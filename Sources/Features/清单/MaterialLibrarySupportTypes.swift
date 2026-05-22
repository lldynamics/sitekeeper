import SwiftUI

enum MaterialSheetTargetMode: String, CaseIterable, Hashable {
    case existing
    case create
}

enum AppendMaterialField: Hashable {
    case quantity
    case unitPrice
    case note
}

enum MaterialPriceFilter: CaseIterable {
    case all
    case priced
    case unpriced

    var title: String {
        switch self {
        case .all:
            return String(localized: "全部价格")
        case .priced:
            return String(localized: "已标价")
        case .unpriced:
            return String(localized: "未标价")
        }
    }
}

struct MaterialPriceEditorContext: Identifiable {
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

struct PendingMaterialAppendContext: Identifiable {
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

struct PendingBatchMaterialAppendContext: Identifiable {
    let id = UUID()
    let materials: [PendingMaterialAppendContext]
}

struct MaterialLibraryCategoryState {
    var selectedCategory: String?
    var showCategoryManager = false
}

struct MaterialLibraryAppendState {
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

struct MaterialLibraryBatchSelectionState {
    var isBatchSelectionMode = false
    var selectedMaterialContextsByKey: [String: PendingMaterialAppendContext] = [:]
    var pendingBatchAddContext: PendingBatchMaterialAppendContext?
    var pendingBatchAddQuantity = "1"
}

enum MaterialLibraryPendingDeleteTarget {
    case preset(CommonMaterial)
    case user(UserMaterial)
}

struct RecentMaterialItem: Identifiable {
    enum Source {
        case preset(CommonMaterial)
        case user(UserMaterial)
    }

    let key: String
    let source: Source

    var id: String { key }
}

struct MaterialLibraryAppendToSheetForm: View {
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
            Section(String(localized: "材料")) {
                LabeledContent(String(localized: "名称"), value: context.name)
                if !context.specification.isEmpty {
                    LabeledContent(String(localized: "规格"), value: context.specification)
                }
                LabeledContent(String(localized: "单位"), value: context.unit)
            }
            Section(String(localized: "添加参数")) {
                HStack {
                    TextField(String(localized: "数量"), text: $quantity)
                        .keyboardType(.decimalPad)
                        .focused(focusedField, equals: .quantity)
                    Text(context.unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    TextField(String(localized: "单价（可选）"), text: $unitPrice)
                        .keyboardType(.decimalPad)
                        .focused(focusedField, equals: .unitPrice)
                    Text(String(format: String(localized: "元/%@"), context.unit))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                TextField(String(localized: "备注（可选）"), text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .focused(focusedField, equals: .note)
            }
            Section(String(localized: "保存到材料单")) {
                if targetMode == .existing {
                    if activeMaterialSheetDrafts.isEmpty {
                        Text(String(localized: "暂无可用材料单，请新建一个材料单。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            targetMode = .create
                            projectId = nil
                        } label: {
                            Label(String(localized: "新建材料单"), systemImage: "plus.circle.fill")
                        }
                    } else {
                        LabeledContent(String(localized: "当前目标")) {
                            Text(selectedDraftTitle)
                                .multilineTextAlignment(.trailing)
                        }
                        Menu {
                            ForEach(activeMaterialSheetDrafts) { draft in
                                Button {
                                    targetMode = .existing
                                    draftId = draft.id
                                } label: {
                                    Label(
                                        draftPickerTitle(draft),
                                        systemImage: draft.id == draftId ? "checkmark.circle.fill" : "tray"
                                    )
                                }
                            }
                            Divider()
                            Button {
                                targetMode = .create
                                projectId = nil
                            } label: {
                                Label(String(localized: "新建材料单"), systemImage: "plus.circle.fill")
                            }
                        } label: {
                            Label(String(localized: "切换目标"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } else {
                    TextField(String(localized: "材料单名称"), text: $draftTitle)
                    Picker(String(localized: "归属项目"), selection: $projectId) {
                        Text(String(localized: "无归属")).tag(nil as UUID?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    if !activeMaterialSheetDrafts.isEmpty {
                        Button {
                            targetMode = .existing
                            draftId = draftId ?? activeMaterialSheetDrafts.first?.id
                        } label: {
                            Label(String(localized: "改用已有材料单"), systemImage: "tray.full.fill")
                        }
                    }
                }
            }
        }
    }

    private var selectedDraftTitle: String {
        guard let draftId,
              let draft = activeMaterialSheetDrafts.first(where: { $0.id == draftId }) else {
            return String(localized: "未选择材料单")
        }
        return draftPickerTitle(draft)
    }
}

struct MaterialLibraryAppendToSheetModal: View {
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
    @Binding var operationMessage: String?
    let canAppendMaterialToSheet: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Bool
    let onEnsureExistingDraftSelection: () -> Void

    var body: some View {
        NavigationStack {
            MaterialLibraryAppendToSheetForm(
                context: context,
                activeMaterialSheetDrafts: activeMaterialSheetDrafts,
                projects: projects,
                draftPickerTitle: draftPickerTitle,
                quantity: $quantity,
                unitPrice: $unitPrice,
                note: $note,
                targetMode: $targetMode,
                draftId: $draftId,
                draftTitle: $draftTitle,
                projectId: $projectId,
                focusedField: focusedField
            )
            .navigationTitle(String(localized: "materials.library.appendSheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.add")) {
                        guard onConfirm() else { return }
                        onCancel()
                    }
                    .disabled(!canAppendMaterialToSheet)
                }
                KeyboardNavigationToolbar(
                    focusedField: focusedField,
                    fields: [.quantity, .unitPrice, .note]
                )
            }
        }
        .onChange(of: targetMode) { _, mode in
            guard mode == .existing else { return }
            onEnsureExistingDraftSelection()
        }
        .operationToast(message: $operationMessage)
    }
}

struct MaterialLibraryBatchAppendForm: View {
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
            Section(String(format: String(localized: "已选材料 (%d)"), context.materials.count)) {
                ForEach(context.materials.prefix(5)) { item in
                    Text(item.displayName)
                }
                if context.materials.count > 5 {
                    Text(String(format: String(localized: "其余 %d 项将在保存后一并加入"), context.materials.count - 5))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "添加参数")) {
                HStack {
                    TextField(String(localized: "数量"), text: $quantity)
                        .keyboardType(.decimalPad)
                    Text(String(localized: "每项"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "保存到材料单")) {
                if targetMode == .existing {
                    if activeMaterialSheetDrafts.isEmpty {
                        Text(String(localized: "暂无可用材料单，请新建一个材料单。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            targetMode = .create
                            projectId = nil
                        } label: {
                            Label(String(localized: "新建材料单"), systemImage: "plus.circle.fill")
                        }
                    } else {
                        LabeledContent(String(localized: "当前目标")) {
                            Text(selectedDraftTitle)
                                .multilineTextAlignment(.trailing)
                        }
                        Menu {
                            ForEach(activeMaterialSheetDrafts) { draft in
                                Button {
                                    targetMode = .existing
                                    draftId = draft.id
                                } label: {
                                    Label(
                                        draftPickerTitle(draft),
                                        systemImage: draft.id == draftId ? "checkmark.circle.fill" : "tray"
                                    )
                                }
                            }
                            Divider()
                            Button {
                                targetMode = .create
                                projectId = nil
                            } label: {
                                Label(String(localized: "新建材料单"), systemImage: "plus.circle.fill")
                            }
                        } label: {
                            Label(String(localized: "切换目标"), systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                } else {
                    TextField(String(localized: "材料单名称"), text: $draftTitle)
                    Picker(String(localized: "归属项目"), selection: $projectId) {
                        Text(String(localized: "无归属")).tag(nil as UUID?)
                        ForEach(projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    if !activeMaterialSheetDrafts.isEmpty {
                        Button {
                            targetMode = .existing
                            draftId = draftId ?? activeMaterialSheetDrafts.first?.id
                        } label: {
                            Label(String(localized: "改用已有材料单"), systemImage: "tray.full.fill")
                        }
                    }
                }
            }
        }
    }

    private var selectedDraftTitle: String {
        guard let draftId,
              let draft = activeMaterialSheetDrafts.first(where: { $0.id == draftId }) else {
            return String(localized: "未选择材料单")
        }
        return draftPickerTitle(draft)
    }
}

struct MaterialLibraryBatchAppendSheet: View {
    let context: PendingBatchMaterialAppendContext
    let activeMaterialSheetDrafts: [MaterialSheetDraft]
    let projects: [Project]
    let draftPickerTitle: (MaterialSheetDraft) -> String
    @Binding var quantity: String
    @Binding var targetMode: MaterialSheetTargetMode
    @Binding var draftId: UUID?
    @Binding var draftTitle: String
    @Binding var projectId: UUID?
    @Binding var operationMessage: String?
    let canAppendMaterialToSheet: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Bool
    let onEnsureExistingDraftSelection: () -> Void

    var body: some View {
        NavigationStack {
            MaterialLibraryBatchAppendForm(
                context: context,
                activeMaterialSheetDrafts: activeMaterialSheetDrafts,
                projects: projects,
                draftPickerTitle: draftPickerTitle,
                quantity: $quantity,
                targetMode: $targetMode,
                draftId: $draftId,
                draftTitle: $draftTitle,
                projectId: $projectId
            )
            .navigationTitle(String(localized: "materials.library.batchAppendSheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.add")) {
                        guard onConfirm() else { return }
                        onCancel()
                    }
                    .disabled(!canAppendMaterialToSheet)
                }
                KeyboardDismissToolbar {
                    AppKeyboard.dismiss()
                }
            }
            .onChange(of: targetMode) { _, mode in
                guard mode == .existing else { return }
                onEnsureExistingDraftSelection()
            }
        }
        .operationToast(message: $operationMessage)
    }
}

struct MaterialLibraryFilterBar: View {
    let selectedCategory: String?
    let availableCategories: [String]
    let priceFilter: MaterialPriceFilter
    let onSelectCategory: (String?) -> Void
    let onSelectPriceFilter: (MaterialPriceFilter) -> Void
    let onOpenCategoryManager: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(
                    title: String(localized: "materials.library.category.all"),
                    isSelected: selectedCategory == nil
                ) {
                    onSelectCategory(nil)
                }
                ForEach(availableCategories, id: \.self) { category in
                    CategoryChip(
                        title: category,
                        isSelected: selectedCategory == category
                    ) {
                        onSelectCategory(category)
                    }
                }
                ForEach(MaterialPriceFilter.allCases, id: \.self) { item in
                    CategoryChip(title: item.title, isSelected: priceFilter == item) {
                        onSelectPriceFilter(item)
                    }
                }
                Button(action: onOpenCategoryManager) {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption)
                        Text(String(localized: "materials.library.categoryManagement.title"))
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.appPrimarySurfaceSubtle)
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "materials.library.categoryManagement.title"))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct MaterialLibraryListView: View {
    let recentSearchKeywords: [String]
    @Binding var searchText: String
    let recentMaterials: [RecentMaterialItem]
    let filteredUser: [UserMaterial]
    let filteredPreset: [CommonMaterial]
    let showRecycleBin: Bool
    let hiddenPresetKeys: [String]
    let deletedUserMaterials: [UserMaterial]
    let onSelectRecentSearch: (String) -> Void
    let onRemoveRecentSearch: (String) -> Void
    let onRemoveRecentMaterial: (String) -> Void
    let onDeletePresetMaterial: (CommonMaterial) -> Void
    let onDeleteUserMaterial: (UserMaterial) -> Void
    let presetRow: (CommonMaterial) -> AnyView
    let userRow: (UserMaterial) -> AnyView
    let deletedPresetRow: (String) -> AnyView
    let deletedUserRow: (UserMaterial) -> AnyView
    let onSubmitSearch: () -> Void

    var body: some View {
        List {
            if !recentSearchKeywords.isEmpty && searchText.isEmpty {
                Section(String(localized: "materials.library.recentSearches.section")) {
                    ForEach(recentSearchKeywords, id: \.self) { term in
                        Button {
                            onSelectRecentSearch(term)
                        } label: {
                            Label(term, systemImage: "clock.arrow.circlepath")
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(String(localized: "materials.library.remove.button"), role: .destructive) {
                                onRemoveRecentSearch(term)
                            }
                        }
                    }
                }
            }

            if !recentMaterials.isEmpty && searchText.isEmpty {
                Section(String(localized: "materials.library.recentlyUsed.section")) {
                    ForEach(recentMaterials) { item in
                        switch item.source {
                        case .preset(let material):
                            presetRow(material)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(String(localized: "materials.library.removeFromRecent.button")) {
                                        onRemoveRecentMaterial(item.key)
                                    }
                                    .tint(Color.appWarning)
                                    Button(String(localized: "materials.library.deleteMaterial.button"), role: .destructive) {
                                        onDeletePresetMaterial(material)
                                    }
                                }
                        case .user(let material):
                            userRow(material)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(String(localized: "materials.library.removeFromRecent.button")) {
                                        onRemoveRecentMaterial(item.key)
                                    }
                                    .tint(Color.appWarning)
                                    Button(String(localized: "common.delete"), role: .destructive) {
                                        onDeleteUserMaterial(material)
                                    }
                                }
                        }
                    }
                }
            }

            if !filteredUser.isEmpty {
                Section(String(localized: "materials.library.customMaterials.section")) {
                    ForEach(filteredUser) { item in
                        userRow(item)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(String(localized: "common.delete"), role: .destructive) {
                                    onDeleteUserMaterial(item)
                                }
                            }
                    }
                }
            }

            Section(
                searchText.isEmpty
                    ? String(localized: "materials.library.allMaterials.section")
                    : String(localized: "materials.library.searchResults.section")
            ) {
                ForEach(filteredPreset) { item in
                    presetRow(item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(String(localized: "materials.library.deleteMaterial.button"), role: .destructive) {
                                onDeletePresetMaterial(item)
                            }
                        }
                }
            }

            if showRecycleBin {
                Section(String(localized: "materials.library.recycleBin.section")) {
                    ForEach(hiddenPresetKeys, id: \.self) { key in
                        deletedPresetRow(key)
                    }
                    ForEach(deletedUserMaterials) { item in
                        deletedUserRow(item)
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: Text(String(localized: "materials.library.search.prompt"))
        )
        .onSubmit(of: .search) {
            onSubmitSearch()
        }
    }
}

struct CategoryChip: View {
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
