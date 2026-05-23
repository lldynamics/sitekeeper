import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

struct ConstructionMethodLibraryView: View {
    @Environment(DataStore.self) var store
    @Environment(MaterialLibraryStore.self) var materialLibraryStore
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    let focusedMethodId: UUID?
    @State var searchText = ""
    @State var showAdd = false
    @State var viewingMethod: ConstructionMethod?
    @State var didOpenFocusedMethod = false
    @State var selectedTradeFilter = String(localized: "全部")
    @State var selectedMethodID: UUID?
    @State var operationNotice: OperationToastNotice?
    @State var undoableDeletion = UndoableDeletionCoordinator()
    @State var showMethodPackImport = false

    init(focusedMethodId: UUID? = nil) {
        self.focusedMethodId = focusedMethodId
    }

    var constructionMethods: [ConstructionMethod] {
        materialLibraryStore.constructionMethods
    }

    var allTradeFilter: String {
        String(localized: "全部")
    }

    var tradeFilters: [String] {
        let values = Set(constructionMethods.map { $0.trade.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return [allTradeFilter] + values.sorted()
    }

    var scopedMethods: [ConstructionMethod] {
        constructionMethods.filter {
            selectedTradeFilter == allTradeFilter
                || $0.trade.trimmingCharacters(in: .whitespacesAndNewlines) == selectedTradeFilter
        }
    }

    var filtered: [ConstructionMethod] {
        return SearchMatcher.filter(
            scopedMethods,
            keyword: searchText,
            sort: { $0.updatedAt > $1.updatedAt }
        )
    }

    var searchSuggestions: [RealtimeSearchSuggestion] {
        RealtimeSearchSuggestionBuilder.suggestions(
            keyword: searchText,
            categories: [.method],
            methods: scopedMethods,
            limit: 6
        )
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    methodList
                } detail: {
                    if let selectedMethodID {
                        ConstructionMethodDetailInlineView(
                            methodID: selectedMethodID,
                            onDelete: deleteMethod,
                            onSave: updateMethod
                        )
                    } else {
                        AppActionableEmptyState(
                            title: String(localized: "选择施工工艺"),
                            systemImage: "hammer.fill",
                            message: String(localized: "从左侧选择工艺查看详情，或先新建一条标准做法。")
                        ) {
                            Button {
                                showAdd = true
                            } label: {
                                Label(String(localized: "新建施工工艺"), systemImage: "plus.circle.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.appProminent())
                        }
                        .padding()
                    }
                }
            } else {
                methodList
            }
        }
        .onAppear {
            openFocusedMethodIfNeeded()
            ensureInitialSelectionIfNeeded()
        }
        .sheet(isPresented: $showAdd) {
            ConstructionMethodEditSheet(method: nil) { method in
                store.upsertConstructionMethod(method, insertAtTopWhenNew: true)
                selectedMethodID = method.id
                store.scheduleSave()
                showAdd = false
            }
        }
        .sheet(item: $viewingMethod) { method in
            ConstructionMethodDetailView(
                methodID: method.id,
                onEdit: { target in
                    viewingMethod = target
                },
                onDelete: { target in
                    deleteMethod(target)
                    viewingMethod = nil
                },
                onSave: { updated in
                    updateMethod(updated)
                    viewingMethod = updated
                }
            )
        }
        .sheet(isPresented: $showMethodPackImport) {
            ConstructionMethodPackImportSheet(
                existingMethods: constructionMethods,
                onImport: importMethodPacks(_:newCount:updateCount:)
            )
        }
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
    }
}
