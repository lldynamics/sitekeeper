import SwiftUI

extension ConstructionMethodLibraryView {
    var methodList: some View {
        SearchableDatabaseView(
            title: String(localized: "施工工艺库"),
            searchText: $searchText,
            searchPrompt: String(localized: "搜索工艺、专业、教程、质量要求"),
            items: filtered,
            emptyTitle: String(localized: "暂无施工工艺"),
            emptySystemImage: "hammer.fill",
            emptyDescription: Text(String(localized: "沉淀标准做法、质量要求和安全注意事项。")),
            emptyActionTitle: String(localized: "新建施工工艺"),
            onEmptyAction: {
                showAdd = true
            },
            searchSuggestions: searchSuggestions,
            searchEmptyStateText: String(localized: "未找到匹配的工艺、专业、教程或质量要求"),
            onSelect: { method in
                if horizontalSizeClass == .regular {
                    selectedMethodID = method.id
                } else {
                    viewingMethod = method
                }
            },
            onSelectSuggestion: { suggestion in
                guard suggestion.category == .method else { return }
                guard let method = constructionMethods.first(where: { $0.id == suggestion.entityId }) else { return }
                if horizontalSizeClass == .regular {
                    selectedMethodID = method.id
                } else {
                    viewingMethod = method
                }
            },
            deleteConfig: SearchableDatabaseDeleteConfig(
                title: String(localized: "删除施工工艺？"),
                itemNoun: String(localized: "施工工艺"),
                singularMessage: String(localized: "删除后可在提示中撤销，附件会延迟清理。"),
                pluralMessage: { count, noun in
                    String(format: String(localized: "将删除 %lld 条%@，可在提示中撤销，附件会延迟清理。"), Int64(count), noun)
                }
            ),
            onDeleteConfirmed: deleteMethods,
            rowContent: { method in
                VStack(alignment: .leading, spacing: 5) {
                    Text(method.title.isEmpty ? String(localized: "未命名工艺") : method.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text(method.trade.isEmpty ? String(localized: "未分类") : method.trade)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.appDoc)
                        Text(method.versionName.isEmpty ? String(localized: "V1") : method.versionName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(method.publishStatus.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(method.publishStatus == .published ? .appSuccess : method.publishStatus == .deprecated ? .appRisk : .appWarning)
                        if !method.qualityStandard.isEmpty {
                            Label(String(localized: "有质检要点"), systemImage: "checkmark.seal")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(method.steps)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    if !method.tutorialBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(method.tutorialBody)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    let tutorialMediaCount = method.tutorialAttachments.count
                    if tutorialMediaCount > 0 {
                        ConstructionMethodAttachmentMiniStrip(attachments: method.tutorialAttachments)
                        Text(String(format: String(localized: "教程媒体 %lld 个"), Int64(tutorialMediaCount)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
            },
            headerContent: {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(tradeFilters, id: \.self) { item in
                                Button(item) { selectedTradeFilter = item }
                                    .buttonStyle(.borderedProminent)
                                    .tint(selectedTradeFilter == item ? .appWarning : .appMutedSurface)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listRowInsets(.init(top: 8, leading: 16, bottom: 2, trailing: 16))
            },
            footerContent: {
                EmptyView()
            },
            toolbarContent: {
                Button { showAdd = true } label: { Image(systemName: "plus").visibleIconStyle() }
                    .accessibilityLabel(String(localized: "添加工艺"))
            }
        )
    }
}
