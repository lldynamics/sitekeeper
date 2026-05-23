import SwiftUI

extension ConstructionMethodLibraryView {
    func deleteMethods(_ methods: [ConstructionMethod]) {
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

    func openFocusedMethodIfNeeded() {
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

    func ensureInitialSelectionIfNeeded() {
        guard horizontalSizeClass == .regular else { return }
        guard selectedMethodID == nil else { return }
        selectedMethodID = filtered.first?.id
    }

    func deleteMethod(_ target: ConstructionMethod) {
        deleteMethods([target])
    }

    func importMethodPacks(_ methods: [ConstructionMethod], newCount: Int, updateCount: Int) {
        guard !methods.isEmpty else { return }
        for method in methods.reversed() {
            store.upsertConstructionMethod(method, insertAtTopWhenNew: true)
        }
        selectedMethodID = methods.first?.id
        store.scheduleSave()
        AppHaptics.success()
        operationNotice = .info(
            String(
                format: String(localized: "已导入 %lld 条工艺，新增 %lld 条，更新 %lld 条"),
                Int64(methods.count),
                Int64(newCount),
                Int64(updateCount)
            )
        )
    }

    func queueMethodDeletion(
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

    func uniqueAttachments(_ attachments: [QuickNoteAttachment]) -> [QuickNoteAttachment] {
        var seen = Set<String>()
        return attachments.filter { attachment in
            guard !attachment.fileName.isEmpty else { return false }
            return seen.insert(attachment.fileName).inserted
        }
    }

    func restoringMethodLinks<Item: Identifiable>(
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

    func updateMethod(_ updated: ConstructionMethod) {
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

    func unlinkDeletedMethodReferences(_ removedIDs: [UUID]) {
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
