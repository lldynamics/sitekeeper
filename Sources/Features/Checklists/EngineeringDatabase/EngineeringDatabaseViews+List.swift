import SwiftUI

extension ConstructionMethodLibraryView {
    var methodList: some View {
        SearchableDatabaseView(
            title: AppLocalization.string("施工工艺库"),
            searchText: $searchText,
            searchPrompt: AppLocalization.string("搜索工艺、专业、教程、质量要求"),
            items: filtered,
            emptyTitle: AppLocalization.string("暂无施工工艺"),
            emptySystemImage: "hammer.fill",
            emptyDescription: Text(AppLocalization.string("沉淀标准做法、质量要求和安全注意事项。")),
            emptyActionTitle: AppLocalization.string("新建施工工艺"),
            onEmptyAction: {
                showAdd = true
            },
            searchSuggestions: searchSuggestions,
            searchEmptyStateText: AppLocalization.string("未找到匹配的工艺、专业、教程或质量要求"),
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
                title: AppLocalization.string("删除施工工艺？"),
                itemNoun: AppLocalization.string("施工工艺"),
                singularMessage: AppLocalization.string("删除后可在提示中撤销，附件会延迟清理。"),
                pluralMessage: { count, noun in
                    String(format: AppLocalization.string("将删除 %lld 条%@，可在提示中撤销，附件会延迟清理。"), Int64(count), noun)
                }
            ),
            onDeleteConfirmed: deleteMethods,
            rowContent: { method in
                VStack(alignment: .leading, spacing: 5) {
                    Text(method.title.isEmpty ? AppLocalization.string("未命名工艺") : method.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text(method.trade.isEmpty ? AppLocalization.string("未分类") : method.trade)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.appDoc)
                        Text(method.versionName.isEmpty ? AppLocalization.string("V1") : method.versionName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(method.publishStatus.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(method.publishStatus == .published ? .appSuccess : method.publishStatus == .deprecated ? .appRisk : .appWarning)
                        if !method.sourceID.isEmpty {
                            Label(AppLocalization.string("工程知识"), systemImage: "globe.asia.australia")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if !method.qualityStandard.isEmpty {
                            Label(AppLocalization.string("有质检要点"), systemImage: "checkmark.seal")
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
                        Text(String(format: AppLocalization.string("教程媒体 %lld 个"), Int64(tutorialMediaCount)))
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
                                Button(item.isEmpty ? AppLocalization.string("全部") : item) { selectedTradeFilter = item }
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
                Section {
                    Button {
                        showMethodPackImport = true
                    } label: {
                        Label(AppLocalization.string("工艺包同步中心"), systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    }
                }
            },
            toolbarContent: {
                Menu {
                    Button {
                        showAdd = true
                    } label: {
                        Label(AppLocalization.string("新建施工工艺"), systemImage: "plus")
                    }
                    Button {
                        showMethodPackImport = true
                    } label: {
                        Label(AppLocalization.string("工艺包同步中心"), systemImage: "arrow.triangle.2.circlepath.circle.fill")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .visibleIconStyle()
                }
                .accessibilityLabel(AppLocalization.string("施工工艺操作"))
            }
        )
    }
}
