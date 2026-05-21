import SwiftUI

struct SearchableDatabaseDeleteConfig {
    var title: String
    var itemNoun: String
    var singularMessage: String
    var pluralMessage: (Int, String) -> String

    init(
        title: String = "确认删除？",
        itemNoun: String = "记录",
        singularMessage: String = "删除后不可撤销。",
        pluralMessage: @escaping (Int, String) -> String = { count, noun in
            "将删除 \(count) 条\(noun)，此操作不可撤销。"
        }
    ) {
        self.title = title
        self.itemNoun = itemNoun
        self.singularMessage = singularMessage
        self.pluralMessage = pluralMessage
    }
}

struct SearchableDatabaseView<
    Item: Identifiable,
    RowContent: View,
    HeaderContent: View,
    FooterContent: View,
    ToolbarContent: View
>: View {
    let title: String
    @Binding var searchText: String
    let searchPrompt: String
    let items: [Item]
    let emptyTitle: String
    let emptySystemImage: String
    let emptyDescription: Text
    var emptyActionTitle: String?
    var emptyActionSystemImage: String = "plus.circle.fill"
    var onEmptyAction: (() -> Void)?
    var searchSuggestions: [RealtimeSearchSuggestion] = []
    var searchEmptyStateText: String = String(localized: "未找到匹配内容")
    let onSelect: (Item) -> Void
    var onSelectSuggestion: ((RealtimeSearchSuggestion) -> Void)? = nil
    var deleteConfig: SearchableDatabaseDeleteConfig? = nil
    var onDeleteConfirmed: (([Item]) -> Void)? = nil
    var onDelete: ((IndexSet, [Item]) -> Void)? = nil
    @ViewBuilder var rowContent: (Item) -> RowContent
    @ViewBuilder var headerContent: () -> HeaderContent
    @ViewBuilder var footerContent: () -> FooterContent
    @ViewBuilder var toolbarContent: () -> ToolbarContent
    @State private var pendingDeleteItems: [Item] = []
    @State private var showDeleteConfirm = false

    var body: some View {
        List {
            Section {
                InlineSearchPanel(
                    text: $searchText,
                    prompt: searchPrompt,
                    suggestions: searchSuggestions,
                    emptyStateText: searchEmptyStateText,
                    materialTone: .secondary,
                    onSelectSuggestion: { suggestion in
                        searchText = suggestion.title
                        onSelectSuggestion?(suggestion)
                    }
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            headerContent()

            if items.isEmpty {
                AppActionableEmptyState(
                    title: emptyTitle,
                    systemImage: emptySystemImage,
                    message: emptyDescription
                ) {
                    if let emptyActionTitle, let onEmptyAction {
                        Button(action: onEmptyAction) {
                            Label(emptyActionTitle, systemImage: emptyActionSystemImage)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.appProminent())
                    }
                }
            } else if onDeleteConfirmed != nil {
                ForEach(items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        rowContent(item)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    pendingDeleteItems = offsets.compactMap { items.indices.contains($0) ? items[$0] : nil }
                    showDeleteConfirm = !pendingDeleteItems.isEmpty
                }
            } else if let onDelete {
                ForEach(items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        rowContent(item)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    onDelete(offsets, items)
                }
            } else {
                ForEach(items) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        rowContent(item)
                    }
                    .buttonStyle(.plain)
                }
            }

            footerContent()
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                toolbarContent()
            }
        }
        .alert(deleteConfig?.title ?? String(localized: "确认删除？"), isPresented: $showDeleteConfirm) {
            Button(String(localized: "取消"), role: .cancel) {
                pendingDeleteItems.removeAll()
            }
            Button(String(localized: "删除"), role: .destructive) {
                let targets = pendingDeleteItems
                pendingDeleteItems.removeAll()
                onDeleteConfirmed?(targets)
            }
        } message: {
            let noun = deleteConfig?.itemNoun ?? String(localized: "记录")
            if pendingDeleteItems.count > 1 {
                Text(
                    deleteConfig?.pluralMessage(pendingDeleteItems.count, noun)
                        ?? String(format: String(localized: "将删除 %lld 条%@，此操作不可撤销。"), Int64(pendingDeleteItems.count), noun)
                )
            } else {
                Text(deleteConfig?.singularMessage ?? String(localized: "删除后不可撤销。"))
            }
        }
    }
}
