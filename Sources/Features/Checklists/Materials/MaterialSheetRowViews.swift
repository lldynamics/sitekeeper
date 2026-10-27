import SwiftUI
import PhotosUI

struct MaterialSheetEditableItemRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .callout) private var preferredFieldWidth: CGFloat = 160
    @State private var availableWidth: CGFloat = 0
    @Binding var item: MaterialSheetItem
    let isExpanded: Bool
    let accessibilityLabel: String
    let photoSelection: Binding<[PhotosPickerItem]>
    let suggestedPrice: String?
    let onToggleExpand: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            rowHeader
            if isExpanded {
                Divider().padding(.vertical, 6)
                expandedFields
            }
        }
        .padding(.vertical, 6)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in availableWidth = width }
            }
        }
    }

    private var rowHeader: some View {
        Button(action: onToggleExpand) {
            HStack(alignment: .top, spacing: 8) {
                fieldLayout {
                    materialDescription
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: "\(item.quantity) \(item.unit)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.appPrimaryAction)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(usesStackedFields ? .leading : .trailing)
                        .layoutPriority(1)
                }
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isExpanded ? "双击收起编辑项" : "双击展开编辑项")
    }

    private var expandedFields: some View {
        VStack(spacing: 8) {
            fieldLayout {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string("数量")).font(.caption).foregroundStyle(.secondary)
                    TextField(AppLocalization.string("数量"), text: $item.quantity)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("material-quantity-\(item.id)")
                }
                LabeledContent(AppLocalization.string("单位"), value: item.unit)
            }
            fieldLayout {
                VStack(alignment: .leading, spacing: 6) {
                    unitPriceField
                    suggestedPriceButton
                }
                laborCostField
            }

            fieldLayout {
                TextField(AppLocalization.string("供应商"), text: $item.supplier)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                TextField(AppLocalization.string("使用部位"), text: $item.usageLocation)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
            }

            HStack(spacing: 10) {
                TextField(AppLocalization.string("备注"), text: $item.note)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
            }

            photoAttachments

            HStack {
                Spacer()
                Button(role: .destructive, action: onDelete) {
                    Label(AppLocalization.string("删除此项"), systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(format: AppLocalization.string("删除%@"), item.name))
            }
        }
    }

    private var usesStackedFields: Bool {
        dynamicTypeSize.isAccessibilitySize || availableWidth < preferredFieldWidth * 2 + 10
    }

    // AnyLayout keeps the same bound text fields and their focus through a resize.
    private var fieldLayout: AnyLayout {
        usesStackedFields
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
    }

    private var materialDescription: some View {
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
        .fixedSize(horizontal: false, vertical: true)
    }

    private var photoAttachments: some View {
        let hasAttachment = item.hasAttachment
        return fieldLayout {
            PhotosPicker(selection: photoSelection, maxSelectionCount: 1, matching: .images) {
                Label(
                    hasAttachment ? "已添加照片" : "添加照片",
                    systemImage: hasAttachment ? "photo.fill" : "photo.badge.plus"
                )
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(String(format: AppLocalization.string("%@添加或更换照片"), item.name))

            if hasAttachment {
                HStack(alignment: .top, spacing: 8) {
                    Text(item.attachmentFileName ?? "附件")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        item.attachmentData = nil
                        item.attachmentFileName = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(String(format: AppLocalization.string("移除%@照片"), item.name))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unitPriceField: some View {
        TextField(AppLocalization.string("估价 ¥"), text: $item.unitPrice)
            .keyboardType(.decimalPad)
            .textFieldStyle(.roundedBorder)
            .font(.callout)
            .accessibilityIdentifier("material-price-\(item.id)")
    }

    private var laborCostField: some View {
        TextField(AppLocalization.string("人工费 ¥"), text: $item.laborCost)
            .keyboardType(.decimalPad)
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
        Section(AppLocalization.string("材料单草稿")) {
            if activeDrafts.isEmpty {
                ContentUnavailableView(
                    "暂无材料单",
                    systemImage: "doc.badge.plus",
                    description: Text(AppLocalization.string("可从材料库点击 + 直接创建，或先在这里新建一个。"))
                )
                Button(action: onCreateDraft) {
                    Label(AppLocalization.string("新建材料单"), systemImage: "plus.circle.fill")
                }
                Button(action: onFocusMaterialSearch) {
                    Label(AppLocalization.string("添加材料"), systemImage: "magnifyingglass")
                }
            } else {
                Picker(AppLocalization.string("当前材料单"), selection: $selectedDraftID) {
                    ForEach(activeDrafts) { draft in
                        Text(draftDisplayName(draft)).tag(draft.id as UUID?)
                    }
                }
                .pickerStyle(.menu)

                if let selectedDraft {
                    let updatedAt = Formatters.displayDateText(selectedDraft.updatedAt)
                    let count = selectedDraft.items.count
                    let projectLabel = selectedDraft.projectId.flatMap(projectName) ?? "无归属项目"
                    Text(String(format: AppLocalization.string("%@ · %d 项 · 更新于 %@"), projectLabel, count, updatedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Menu {
                        Button(action: onPrepareRenameDraft) {
                            Label(AppLocalization.string("重命名当前材料单"), systemImage: "pencil")
                        }
                        Button(role: .destructive, action: onArchiveSelectedDraft) {
                            Label(AppLocalization.string("归档当前材料单"), systemImage: "archivebox")
                        }
                    } label: {
                        Label(AppLocalization.string("管理当前材料单"), systemImage: "ellipsis.circle")
                    }
                }

                Button(action: onCreateDraft) {
                    Label(AppLocalization.string("新建材料单"), systemImage: "plus")
                }
                Button(action: onFocusMaterialSearch) {
                    Label(AppLocalization.string("添加材料"), systemImage: "magnifyingglass")
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
        Section(AppLocalization.string("添加材料")) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(AppLocalization.string("搜索材料库"), text: $searchText)
                    .submitLabel(.search)
                    .focused(isMaterialSearchFocused)
            }
            if !searchText.isEmpty {
                if !hasSearchResults {
                    ContentUnavailableView(
                        "材料库没有匹配项",
                        systemImage: "shippingbox",
                        description: Text(AppLocalization.string("请先到材料库新增自定义材料，再加入材料单。"))
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
            title: AppLocalization.string("新建材料单"),
            primaryActionTitle: AppLocalization.string("创建"),
            isPrimaryActionDisabled: titleIsEmpty,
            onCancel: onCancel,
            onPrimaryAction: onCreate
        ) {
            AppBusinessFormValidationSection(
                messages: titleIsEmpty ? [AppLocalization.string("请填写材料单名称")] : []
            )
            Section(AppLocalization.string("基本信息")) {
                TextField(AppLocalization.string("材料单名称"), text: $titleInput)
                Picker(AppLocalization.string("归属项目"), selection: $projectIdInput) {
                    Text(AppLocalization.string("无归属")).tag(nil as UUID?)
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
            title: AppLocalization.string("重命名材料单"),
            isPrimaryActionDisabled: titleIsEmpty,
            onCancel: onCancel,
            onPrimaryAction: onSave
        ) {
            AppBusinessFormValidationSection(
                messages: titleIsEmpty ? [AppLocalization.string("请填写材料单名称")] : []
            )
            Section(AppLocalization.string("材料单名称")) {
                TextField(AppLocalization.string("材料单名称"), text: $renameTitleInput)
            }
        }
    }
}
