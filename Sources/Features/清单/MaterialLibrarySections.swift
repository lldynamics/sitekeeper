import SwiftUI

struct MaterialLibraryDefaultTargetBar: View {
    let draft: MaterialSheetDraft?
    let activeDrafts: [MaterialSheetDraft]
    let draftTitle: (MaterialSheetDraft) -> String
    let projectName: (UUID?) -> String?
    let recentlyAddedSummary: (MaterialSheetDraft) -> String
    let onSelectDraft: (UUID) -> Void
    let onCreateDraft: () -> Void
    let onOpenDraft: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            if let draft {
                HStack(alignment: .center, spacing: AppSpacing.tight) {
                    Label(String(localized: "默认目标材料单"), systemImage: "pin.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appPrimaryAction)
                    Spacer()
                    Menu {
                        ForEach(activeDrafts) { item in
                            Button {
                                onSelectDraft(item.id)
                            } label: {
                                Label(
                                    draftTitle(item),
                                    systemImage: item.id == draft.id ? "checkmark.circle.fill" : "tray"
                                )
                            }
                        }
                        Divider()
                        Button(action: onCreateDraft) {
                            Label(String(localized: "新建材料单"), systemImage: "plus.circle.fill")
                        }
                    } label: {
                        Label(String(localized: "切换"), systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                HStack(alignment: .top, spacing: AppSpacing.tight) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.title.isEmpty ? "未命名材料单" : draft.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text("项目归属：\(projectName(draft.projectId) ?? "无归属") · 当前 \(draft.items.count) 项\(recentlyAddedSummary(draft))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: AppSpacing.tight)
                    Button(action: onCreateDraft) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appPrimaryAction)
                    .accessibilityLabel(String(localized: "新建默认材料单"))
                    Button {
                        onOpenDraft(draft.id)
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appPrimaryAction)
                    .accessibilityLabel(String(localized: "打开当前材料单"))
                }

                Label(String(localized: "点材料后的 + 默认加入这里；需要换单时先在这里切换。"), systemImage: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: AppSpacing.tight) {
                    Label(String(localized: "暂无默认材料单"), systemImage: "tray")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onCreateDraft) {
                        Label(String(localized: "创建"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.appProminent())
                    .controlSize(.small)
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
}

struct MaterialLibraryMaterialRowContent: View {
    let name: String
    let spec: String
    let unit: String
    let hasPrice: Bool
    let price: String?
    let isBatchSelectionMode: Bool
    let isSelected: Bool
    let onEdit: () -> Void
    let onAdd: () -> Void
    let onToggleSelection: () -> Void

    var body: some View {
        HStack {
            if isBatchSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.appPrimaryAction : .secondary)
                    .font(.title3)
            }

            Group {
                if isBatchSelectionMode {
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
                        Text(String(localized: "标价")).font(.caption2)
                    }
                    .foregroundStyle(Color.appPrimaryAction)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.appPrimarySurfaceSubtle)
                    .clipShape(Capsule())
                }
            }
            .onTapGesture {
                guard !isBatchSelectionMode else { return }
                onEdit()
            }

            if isBatchSelectionMode {
                if isSelected {
                    Text(String(localized: "已选"))
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
                .accessibilityLabel(String(format: String(localized: "添加%@到材料单"), name))
                .accessibilityValue(accessibilityValue)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard isBatchSelectionMode else { return }
            onToggleSelection()
        }
    }

    private var accessibilityValue: String {
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
}

struct MaterialLibraryBatchAppendActionBar: View {
    let selectedCount: Int
    let onClear: () -> Void
    let onOpenBatchAppend: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(selectedCount == 0 ? "多选模式：勾选后可批量加入材料单" : "已选择 \(selectedCount) 项材料")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if selectedCount > 0 {
                    Button(String(localized: "清空"), action: onClear)
                        .font(.footnote)
                }
            }
            Button(action: onOpenBatchAppend) {
                Label(String(localized: "批量加入材料单"), systemImage: "square.and.arrow.down.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appProminent())
            .disabled(selectedCount == 0)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }
}

struct MaterialLibraryDeletedPresetRow: View {
    let key: String
    let onRestore: () -> Void

    var body: some View {
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
            Button(String(localized: "恢复"), action: onRestore)
                .font(.caption)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.appSuccess)
        }
    }
}

struct MaterialLibraryDeletedUserRow: View {
    let item: UserMaterial
    let onRestore: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "trash").foregroundStyle(.secondary).font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium)).foregroundStyle(.secondary)
                Text(item.specification).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(String(localized: "恢复"), action: onRestore)
                .font(.caption)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(.appSuccess)
        }
    }
}
