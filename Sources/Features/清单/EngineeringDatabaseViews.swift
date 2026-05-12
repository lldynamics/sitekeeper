import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

struct ConstructionMethodLibraryView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let focusedMethodId: UUID?
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var viewingMethod: ConstructionMethod?
    @State private var didOpenFocusedMethod = false
    @State private var selectedTradeFilter = "全部"
    @State private var selectedMethodID: UUID?

    init(focusedMethodId: UUID? = nil) {
        self.focusedMethodId = focusedMethodId
    }

    private var tradeFilters: [String] {
        let values = Set(store.constructionMethods.map { $0.trade.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return ["全部"] + values.sorted()
    }

    private var scopedMethods: [ConstructionMethod] {
        store.constructionMethods.filter {
            selectedTradeFilter == "全部"
                || $0.trade.trimmingCharacters(in: .whitespacesAndNewlines) == selectedTradeFilter
        }
    }

    private var filtered: [ConstructionMethod] {
        return SearchMatcher.filter(
            scopedMethods,
            keyword: searchText,
            sort: { $0.updatedAt > $1.updatedAt }
        )
    }

    private var searchSuggestions: [RealtimeSearchSuggestion] {
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
                        ContentUnavailableView("选择施工工艺", systemImage: "hammer.fill")
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
                store.constructionMethods.insert(method, at: 0)
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
    }

    private var methodList: some View {
        SearchableDatabaseView(
            title: "施工工艺库",
            searchText: $searchText,
            searchPrompt: "搜索工艺、专业、教程、质量要求",
            items: filtered,
            emptyTitle: "暂无施工工艺",
            emptySystemImage: "hammer.fill",
            emptyDescription: Text("沉淀标准做法、质量要求和安全注意事项。"),
            searchSuggestions: searchSuggestions,
            onSelect: { method in
                if horizontalSizeClass == .regular {
                    selectedMethodID = method.id
                } else {
                    viewingMethod = method
                }
            },
            onSelectSuggestion: { suggestion in
                guard suggestion.category == .method else { return }
                guard let method = store.constructionMethods.first(where: { $0.id == suggestion.entityId }) else { return }
                if horizontalSizeClass == .regular {
                    selectedMethodID = method.id
                } else {
                    viewingMethod = method
                }
            },
            deleteConfig: SearchableDatabaseDeleteConfig(
                title: "删除施工工艺？",
                itemNoun: "施工工艺"
            ),
            onDeleteConfirmed: deleteMethods,
            rowContent: { method in
                VStack(alignment: .leading, spacing: 5) {
                    Text(method.title.isEmpty ? "未命名工艺" : method.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text(method.trade.isEmpty ? "未分类" : method.trade)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.appDoc)
                        Text(method.versionName.isEmpty ? "V1" : method.versionName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(method.publishStatus.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(method.publishStatus == .published ? .appSuccess : method.publishStatus == .deprecated ? .appRisk : .appWarning)
                        if !method.qualityStandard.isEmpty {
                            Label("有质检要点", systemImage: "checkmark.seal")
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
                        Text("教程媒体 \(tutorialMediaCount) 个")
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
                    .accessibilityLabel("添加工艺")
            }
        )
    }

    private func deleteMethods(_ methods: [ConstructionMethod]) {
        let ids = Set(methods.map(\.id))
        guard !ids.isEmpty else { return }
        let targets = store.constructionMethods.filter { ids.contains($0.id) }
        QuickNoteAttachmentStorage.delete(attachments: targets.flatMap(\.attachments) + targets.flatMap(\.tutorialAttachments))
        store.constructionMethods.removeAll { ids.contains($0.id) }
        unlinkDeletedMethodReferences(Array(ids))
        if let selectedMethodID, ids.contains(selectedMethodID) {
            self.selectedMethodID = store.constructionMethods.first?.id
        }
        store.scheduleSave()
    }

    private func openFocusedMethodIfNeeded() {
        guard let focusedMethodId, !didOpenFocusedMethod,
              let method = store.constructionMethods.first(where: { $0.id == focusedMethodId }) else { return }
        didOpenFocusedMethod = true
        searchText = ""
        Task { @MainActor in
            if horizontalSizeClass == .regular {
                selectedMethodID = method.id
            } else {
                viewingMethod = method
            }
        }
    }

    private func ensureInitialSelectionIfNeeded() {
        guard horizontalSizeClass == .regular else { return }
        guard selectedMethodID == nil else { return }
        selectedMethodID = filtered.first?.id
    }

    private func deleteMethod(_ target: ConstructionMethod) {
        QuickNoteAttachmentStorage.delete(attachments: target.attachments + target.tutorialAttachments)
        store.constructionMethods.removeAll { $0.id == target.id }
        unlinkDeletedMethodReferences([target.id])
        if selectedMethodID == target.id {
            selectedMethodID = store.constructionMethods.first?.id
        }
        store.scheduleSave()
    }

    private func updateMethod(_ updated: ConstructionMethod) {
        if let index = store.constructionMethods.firstIndex(where: { $0.id == updated.id }) {
            let oldFiles = Set((store.constructionMethods[index].attachments + store.constructionMethods[index].tutorialAttachments).map(\.fileName))
            let newFiles = Set((updated.attachments + updated.tutorialAttachments).map(\.fileName))
            store.constructionMethods[index] = updated
            QuickNoteAttachmentStorage.delete(fileNames: Array(oldFiles.subtracting(newFiles)))
            selectedMethodID = updated.id
            store.scheduleSave()
        }
    }

    private func unlinkDeletedMethodReferences(_ removedIDs: [UUID]) {
        let removedIDSet = Set(removedIDs)
        guard !removedIDSet.isEmpty else { return }

        for index in store.siteTodos.indices {
            let current = store.siteTodos[index].linkedConstructionMethodIDs
            let filtered = current.filter { !removedIDSet.contains($0) }
            if filtered.count != current.count {
                store.siteTodos[index].linkedConstructionMethodIDs = filtered
            }
        }

        for index in store.dailyLogs.indices {
            let current = store.dailyLogs[index].linkedConstructionMethodIDs
            let filtered = current.filter { !removedIDSet.contains($0) }
            if filtered.count != current.count {
                store.dailyLogs[index].linkedConstructionMethodIDs = filtered
            }
        }
    }
}
