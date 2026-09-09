import SwiftUI
import PhotosUI

struct MaterialSheetEditableItemRow: View {
    @Binding var item: MaterialSheetItem
    let isExpanded: Bool
    let accessibilityLabel: String
    let photoSelection: Binding<[PhotosPickerItem]>
    let suggestedPrice: String?
    let onToggleExpand: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let hasAttachment = item.hasAttachment
        VStack(spacing: 0) {
            Button(action: onToggleExpand) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        if !item.specification.isEmpty {
                            Text(item.specification)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        Text(item.quantity)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.appPrimaryAction)
                        Text(item.unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint(isExpanded ? "双击收起编辑项" : "双击展开编辑项")

            if isExpanded {
                Divider().padding(.vertical, 6)
                VStack(spacing: 8) {
                    ViewThatFits(in: .horizontal) {
                        priceFieldsRow
                        priceFieldsColumn
                    }

                    HStack(spacing: 10) {
                        TextField(String(localized: "供应商"), text: $item.supplier)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                        TextField(String(localized: "使用部位"), text: $item.usageLocation)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                    }

                    HStack(spacing: 10) {
                        TextField(String(localized: "备注"), text: $item.note)
                            .textFieldStyle(.roundedBorder)
                            .font(.callout)
                    }

                    HStack(spacing: 8) {
                        PhotosPicker(selection: photoSelection, maxSelectionCount: 1, matching: .images) {
                            Label(
                                hasAttachment ? "已添加照片" : "添加照片",
                                systemImage: hasAttachment ? "photo.fill" : "photo.badge.plus"
                            )
                            .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel(String(format: String(localized: "%@添加或更换照片"), item.name))

                        if hasAttachment {
                            Text(item.attachmentFileName ?? "附件")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .appListSecondaryTextLayout()
                            Button {
                                item.attachmentData = nil
                                item.attachmentFileName = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(String(format: String(localized: "移除%@照片"), item.name))
                        }
                        Spacer()
                    }

                    HStack {
                        Spacer()
                        Button(role: .destructive, action: onDelete) {
                            Label(String(localized: "删除此项"), systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(String(format: String(localized: "删除%@"), item.name))
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var unitPriceField: some View {
        TextField(String(localized: "估价 ¥"), text: $item.unitPrice)
            .keyboardType(.decimalPad)
            .frame(minWidth: 100)
            .textFieldStyle(.roundedBorder)
            .font(.callout)
    }

    private var laborCostField: some View {
        TextField(String(localized: "人工费 ¥"), text: $item.laborCost)
            .keyboardType(.decimalPad)
            .frame(minWidth: 100)
            .textFieldStyle(.roundedBorder)
            .font(.callout)
    }

    @ViewBuilder
    private var suggestedPriceButton: some View {
        if let suggestedPrice,
           suggestedPrice != item.unitPrice {
            Button {
                item.unitPrice = suggestedPrice
            } label: {
                Text("¥\(suggestedPrice)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.appPrimarySurfaceSubtle, in: Capsule())
                    .foregroundStyle(Color.appPrimaryAction)
            }
            .buttonStyle(.borderless)
        }
    }

    private var priceFieldsRow: some View {
        HStack(spacing: 10) {
            unitPriceField
            suggestedPriceButton
            laborCostField
            Spacer()
        }
    }

    private var priceFieldsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                unitPriceField
                suggestedPriceButton
            }
            laborCostField
        }
    }
}

struct MaterialSheetDraftSelectorSection: View {
    let activeDrafts: [MaterialSheetDraft]
    @Binding var selectedDraftID: UUID?
    let selectedDraft: MaterialSheetDraft?
    let draftDisplayName: (MaterialSheetDraft) -> String
    let projectName: (UUID) -> String?
    let onCreateDraft: () -> Void
    let onFocusMaterialSearch: () -> Void
    let onPrepareRenameDraft: () -> Void
    let onArchiveSelectedDraft: () -> Void

    var body: some View {
        Section(String(localized: "材料单草稿")) {
            if activeDrafts.isEmpty {
                ContentUnavailableView(
                    "暂无材料单",
                    systemImage: "doc.badge.plus",
                    description: Text(String(localized: "可从材料库点击 + 直接创建，或先在这里新建一个。"))
                )
                Button(action: onCreateDraft) {
                    Label(String(localized: "新建材料单"), systemImage: "plus.circle.fill")
                }
                Button(action: onFocusMaterialSearch) {
                    Label(String(localized: "添加材料"), systemImage: "magnifyingglass")
                }
            } else {
                Picker(String(localized: "当前材料单"), selection: $selectedDraftID) {
                    ForEach(activeDrafts) { draft in
                        Text(draftDisplayName(draft)).tag(draft.id as UUID?)
                    }
                }
                .pickerStyle(.menu)

                if let selectedDraft {
                    let updatedAt = selectedDraft.updatedAt
                    let count = selectedDraft.items.count
                    let projectLabel = selectedDraft.projectId.flatMap(projectName) ?? "无归属项目"
                    Text(String(format: String(localized: "%@ · %d 项 · 更新于 %@"), projectLabel, count, updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Menu {
                        Button(action: onPrepareRenameDraft) {
                            Label(String(localized: "重命名当前材料单"), systemImage: "pencil")
                        }
                        Button(role: .destructive, action: onArchiveSelectedDraft) {
                            Label(String(localized: "归档当前材料单"), systemImage: "archivebox")
                        }
                    } label: {
                        Label(String(localized: "管理当前材料单"), systemImage: "ellipsis.circle")
                    }
                }

                Button(action: onCreateDraft) {
                    Label(String(localized: "新建材料单"), systemImage: "plus")
                }
                Button(action: onFocusMaterialSearch) {
                    Label(String(localized: "添加材料"), systemImage: "magnifyingglass")
                }
            }
        }
    }
}

struct MaterialSheetSearchSection: View {
    @Binding var searchText: String
    var isMaterialSearchFocused: FocusState<Bool>.Binding
    let hasSearchResults: Bool
    let priceSuggestions: [MaterialPriceEntry]
    let librarySuggestions: [CommonMaterial]
    let librarySearchRow: (MaterialPriceEntry) -> AnyView
    let presetSearchRow: (CommonMaterial) -> AnyView

    var body: some View {
        Section(String(localized: "添加材料")) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(String(localized: "搜索材料库"), text: $searchText)
                    .submitLabel(.search)
                    .focused(isMaterialSearchFocused)
            }
            if !searchText.isEmpty {
                if !hasSearchResults {
                    ContentUnavailableView(
                        "材料库没有匹配项",
                        systemImage: "shippingbox",
                        description: Text(String(localized: "请先到材料库新增自定义材料，再加入材料单。"))
                    )
                }
                ForEach(priceSuggestions) { entry in
                    librarySearchRow(entry)
                }
                ForEach(librarySuggestions) { material in
                    presetSearchRow(material)
                }
            }
        }
    }
}

struct MaterialSheetCreateDraftSheet: View {
    @Binding var titleInput: String
    @Binding var projectIdInput: UUID?
    let projects: [Project]
    let onCancel: () -> Void
    let onCreate: () -> Void

    private var titleIsEmpty: Bool {
        titleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        AppBusinessFormSheet(
            title: String(localized: "新建材料单"),
            primaryActionTitle: String(localized: "创建"),
            isPrimaryActionDisabled: titleIsEmpty,
            onCancel: onCancel,
            onPrimaryAction: onCreate
        ) {
            AppBusinessFormValidationSection(
                messages: titleIsEmpty ? [String(localized: "请填写材料单名称")] : []
            )
            Section(String(localized: "基本信息")) {
                TextField(String(localized: "材料单名称"), text: $titleInput)
                Picker(String(localized: "归属项目"), selection: $projectIdInput) {
                    Text(String(localized: "无归属")).tag(nil as UUID?)
                    ForEach(projects) { project in
                        Text(project.name).tag(project.id as UUID?)
                    }
                }
            }
        }
    }
}

struct MaterialSheetRenameDraftSheet: View {
    @Binding var renameTitleInput: String
    let onCancel: () -> Void
    let onSave: () -> Void

    private var titleIsEmpty: Bool {
        renameTitleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        AppBusinessFormSheet(
            title: String(localized: "重命名材料单"),
            isPrimaryActionDisabled: titleIsEmpty,
            onCancel: onCancel,
            onPrimaryAction: onSave
        ) {
            AppBusinessFormValidationSection(
                messages: titleIsEmpty ? [String(localized: "请填写材料单名称")] : []
            )
            Section(String(localized: "材料单名称")) {
                TextField(String(localized: "材料单名称"), text: $renameTitleInput)
            }
        }
    }
}
