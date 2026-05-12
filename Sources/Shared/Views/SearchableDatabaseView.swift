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
    var searchSuggestions: [RealtimeSearchSuggestion] = []
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
            headerContent()

            if items.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptySystemImage,
                    description: emptyDescription
                )
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
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: searchPrompt
        )
        .searchSuggestions {
            let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !keyword.isEmpty {
                ForEach(searchSuggestions) { suggestion in
                    Button {
                        searchText = suggestion.title
                        onSelectSuggestion?(suggestion)
                    } label: {
                        RealtimeSearchSuggestionMenuRow(suggestion: suggestion)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                toolbarContent()
            }
        }
        .alert(deleteConfig?.title ?? "确认删除？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {
                pendingDeleteItems.removeAll()
            }
            Button("删除", role: .destructive) {
                let targets = pendingDeleteItems
                pendingDeleteItems.removeAll()
                onDeleteConfirmed?(targets)
            }
        } message: {
            let noun = deleteConfig?.itemNoun ?? "记录"
            if pendingDeleteItems.count > 1 {
                Text(deleteConfig?.pluralMessage(pendingDeleteItems.count, noun) ?? "将删除 \(pendingDeleteItems.count) 条\(noun)，此操作不可撤销。")
            } else {
                Text(deleteConfig?.singularMessage ?? "删除后不可撤销。")
            }
        }
    }
}
