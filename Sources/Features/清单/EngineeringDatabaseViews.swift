import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

struct ConstructionMethodLibraryView: View {
    @Environment(DataStore.self) private var store
    @Environment(MaterialLibraryStore.self) private var materialLibraryStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let focusedMethodId: UUID?
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var viewingMethod: ConstructionMethod?
    @State private var didOpenFocusedMethod = false
    @State private var selectedTradeFilter = String(localized: "全部")
    @State private var selectedMethodID: UUID?
    @State private var operationNotice: OperationToastNotice?
    @State private var undoableDeletion = UndoableDeletionCoordinator()

    init(focusedMethodId: UUID? = nil) {
        self.focusedMethodId = focusedMethodId
    }

    private var constructionMethods: [ConstructionMethod] {
        materialLibraryStore.constructionMethods
    }

    private var allTradeFilter: String {
        String(localized: "全部")
    }

    private var tradeFilters: [String] {
        let values = Set(constructionMethods.map { $0.trade.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return [allTradeFilter] + values.sorted()
    }

    private var scopedMethods: [ConstructionMethod] {
        constructionMethods.filter {
            selectedTradeFilter == allTradeFilter
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
        .operationToast(notice: $operationNotice)
        .onDisappear {
            undoableDeletion.flushPendingCommit()
        }
    }

    private var methodList: some View {
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

    private func deleteMethods(_ methods: [ConstructionMethod]) {
        let ids = Set(methods.map(\.id))
        guard !ids.isEmpty else { return }

        let todoSnapshot = store.siteTodos
        let logSnapshot = store.dailyLogs
        let previousSelection = selectedMethodID
        let targets = constructionMethods.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        let attachments = uniqueAttachments(targets.flatMap(\.attachments) + targets.flatMap(\.tutorialAttachments))
        let deletion = store.removeConstructionMethods(
            ids: ids,
            audit: DataStoreDeletionAuditContext(
                summary: String(format: String(localized: "删除施工工艺 %lld 条"), Int64(targets.count)),
                detail: ListFormatter.localizedString(byJoining: targets.map(\.title)),
                source: "ConstructionMethodLibraryView"
            ),
            deferredFileCleanup: DataStoreDeferredFileCleanup.quickNoteAttachments(
                attachments,
                summary: "constructionMethod.attachments"
            )
        )
        guard !deletion.isEmpty else { return }

        unlinkDeletedMethodReferences(Array(ids))
        if let selectedMethodID, ids.contains(selectedMethodID) {
            self.selectedMethodID = constructionMethods.first?.id
        }
        queueMethodDeletion(
            deletion,
            deletedIDs: ids,
            todoSnapshot: todoSnapshot,
            logSnapshot: logSnapshot,
            previousSelection: previousSelection
        )
    }

    private func openFocusedMethodIfNeeded() {
        guard let focusedMethodId, !didOpenFocusedMethod,
              let method = constructionMethods.first(where: { $0.id == focusedMethodId }) else { return }
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
        deleteMethods([target])
    }

    private func queueMethodDeletion(
        _ deletion: DataStoreRemovalResult<ConstructionMethod>,
        deletedIDs: Set<UUID>,
        todoSnapshot: [SiteTodo],
        logSnapshot: [DailyLog],
        previousSelection: UUID?
    ) {
        guard !deletion.isEmpty else { return }
        undoableDeletion.queue(
            notice: $operationNotice,
            message: String(format: String(localized: "已删除 %lld 条施工工艺"), Int64(deletion.deletedCount)),
            commit: {
                deletion.performDeferredFileCleanup()
                store.scheduleSave()
            },
            undo: {
                store.restoreConstructionMethods(from: deletion)
                store.replaceSiteTodos(restoringMethodLinks(
                    current: store.siteTodos,
                    snapshot: todoSnapshot,
                    deletedIDs: deletedIDs,
                    links: \.linkedConstructionMethodIDs
                ))
                store.replaceDailyLogs(restoringMethodLinks(
                    current: store.dailyLogs,
                    snapshot: logSnapshot,
                    deletedIDs: deletedIDs,
                    links: \.linkedConstructionMethodIDs
                ))
                if let previousSelection,
                   constructionMethods.contains(where: { $0.id == previousSelection }) {
                    selectedMethodID = previousSelection
                }
                store.scheduleSave()
            },
            audit: deletion.audit.map(UndoableDeletionAuditContext.init)
        )
    }

    private func uniqueAttachments(_ attachments: [QuickNoteAttachment]) -> [QuickNoteAttachment] {
        var seen = Set<String>()
        return attachments.filter { attachment in
            guard !attachment.fileName.isEmpty else { return false }
            return seen.insert(attachment.fileName).inserted
        }
    }

    private func restoringMethodLinks<Item: Identifiable>(
        current: [Item],
        snapshot: [Item],
        deletedIDs: Set<UUID>,
        links: WritableKeyPath<Item, [UUID]>
    ) -> [Item] where Item.ID: Hashable {
        let snapshotByID = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0) })
        return current.map { item in
            guard let before = snapshotByID[item.id] else { return item }
            let removedLinks = before[keyPath: links].filter { deletedIDs.contains($0) }
            guard !removedLinks.isEmpty else { return item }

            var restored = item
            var linkSet = Set(restored[keyPath: links])
            for id in removedLinks where linkSet.insert(id).inserted {
                restored[keyPath: links].append(id)
            }
            return restored
        }
    }

    private func updateMethod(_ updated: ConstructionMethod) {
        guard let existing = constructionMethods.first(where: { $0.id == updated.id }) else { return }
        let oldFiles = Set((existing.attachments + existing.tutorialAttachments).map(\.fileName))
        let newFiles = Set((updated.attachments + updated.tutorialAttachments).map(\.fileName))
        store.upsertConstructionMethod(updated)
        DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
            Array(oldFiles.subtracting(newFiles)),
            summary: "engineeringDatabase.updateMethodAttachments"
        )?.perform()
        selectedMethodID = updated.id
        store.scheduleSave()
    }

    private func unlinkDeletedMethodReferences(_ removedIDs: [UUID]) {
        let removedIDSet = Set(removedIDs)
        guard !removedIDSet.isEmpty else { return }

        var siteTodos = store.siteTodos
        var didUpdateSiteTodos = false
        for index in siteTodos.indices {
            let current = siteTodos[index].linkedConstructionMethodIDs
            let filtered = current.filter { !removedIDSet.contains($0) }
            if filtered.count != current.count {
                siteTodos[index].linkedConstructionMethodIDs = filtered
                didUpdateSiteTodos = true
            }
        }
        if didUpdateSiteTodos {
            store.replaceSiteTodos(siteTodos)
        }

        var dailyLogs = store.dailyLogs
        var didUpdateDailyLogs = false
        for index in dailyLogs.indices {
            let current = dailyLogs[index].linkedConstructionMethodIDs
            let filtered = current.filter { !removedIDSet.contains($0) }
            if filtered.count != current.count {
                dailyLogs[index].linkedConstructionMethodIDs = filtered
                didUpdateDailyLogs = true
            }
        }
        if didUpdateDailyLogs {
            store.replaceDailyLogs(dailyLogs)
        }
    }
}
