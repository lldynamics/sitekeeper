import SwiftUI

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
    let onSelect: (Item) -> Void
    var onDelete: ((IndexSet, [Item]) -> Void)? = nil
    @ViewBuilder var rowContent: (Item) -> RowContent
    @ViewBuilder var headerContent: () -> HeaderContent
    @ViewBuilder var footerContent: () -> FooterContent
    @ViewBuilder var toolbarContent: () -> ToolbarContent

    var body: some View {
        List {
            headerContent()

            if items.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptySystemImage,
                    description: emptyDescription
                )
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                toolbarContent()
            }
        }
    }
}
