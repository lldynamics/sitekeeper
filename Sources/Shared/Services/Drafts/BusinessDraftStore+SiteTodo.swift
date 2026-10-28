import Foundation
import CryptoKit

/// Issued only after the business transaction commits; identifies its exact attachment.
struct SiteTodoSaveReceipt {
    let record: SiteTodo
    let afterPhotoSourceID: UUID?
    let afterPhotoFileName: String?
    let afterPhotoContentDigest: Data?
}

extension BusinessDraftStore {
    /// Keep the form and its independent photo blobs until the business write succeeds.
    @MainActor
    func commitTodo(
        _ draft: SiteTodoFormDraft,
        key: Key,
        editing: Bool,
        in store: DataStore,
        persist: (() async throws -> Void)? = nil
    ) async throws -> SiteTodo {
        try await commitTodoWithReceipt(draft, key: key, editing: editing, in: store, persist: persist).record
    }

    @MainActor
    func commitTodoWithReceipt(
        _ draft: SiteTodoFormDraft,
        key: Key,
        editing: Bool,
        in store: DataStore,
        persist: (() async throws -> Void)? = nil
    ) async throws -> SiteTodoSaveReceipt {
        await store.awaitInitialLoad()
        try validateTodoDraft(draft, editing: editing, in: store)
        let previous = store.siteTodos.first { $0.id == draft.record.id }
        var value = draft.normalizedRecord
        var attemptNames: [String] = []
        var afterPhotoContentDigest: Data?
        var committed = false
        var didApply = false
        do {
            cleanupUnreferencedTodoPhotos(try pendingPhotoFiles(key: key), in: store)
            let photoIDs = [draft.beforePhotoID, draft.afterPhotoID].compactMap { $0 }
            if !photoIDs.isEmpty {
                let originals = try photoIDs.map { try photo(id: $0, key: key) }
                let attemptID = UUID()
                try registerPhotoAttempt(id: attemptID, count: originals.count, key: key)
                attemptNames = try await PhotoStorage.saveManyAsyncOrThrow(originals: originals, logId: attemptID)
                var index = 0
                if draft.beforePhotoID != nil {
                    value.rectificationBeforePhotoFileName = attemptNames[index]
                    index += 1
                }
                if draft.afterPhotoID != nil {
                    value.rectificationAfterPhotoFileName = attemptNames[index]
                    afterPhotoContentDigest = Data(SHA256.hash(data: originals[index]))
                }
            }
            // Photo preparation suspends; another window may have edited the record meanwhile.
            try validateTodoDraft(draft, editing: editing, in: store)
            if editing { store.updateSiteTodo(value) } else { store.insertSiteTodoAtTop(value) }
            didApply = true
            try await complete(key: key) {
                if let persist { try await persist() } else { try await store.flushSaveOrThrow() }
                committed = true
            }
            let oldNames = [previous?.rectificationBeforePhotoFileName, previous?.rectificationAfterPhotoFileName].compactMap { $0 }
            cleanupUnreferencedTodoPhotos(oldNames, in: store)
            return SiteTodoSaveReceipt(
                record: value,
                afterPhotoSourceID: draft.afterPhotoID == nil ? nil : draft.afterPhotoSourceID,
                afterPhotoFileName: draft.afterPhotoID == nil ? nil : value.rectificationAfterPhotoFileName,
                afterPhotoContentDigest: afterPhotoContentDigest
            )
        } catch {
            if didApply, !committed,
               let current = store.siteTodos.first(where: { $0.id == value.id }),
               Self.fingerprint(current) == Self.fingerprint(value) {
                if let previous { store.updateSiteTodo(previous) } else { store.removeSiteTodos(ids: [value.id]) }
            }
            cleanupUnreferencedTodoPhotos(attemptNames, in: store)
            throw error
        }
    }

    @MainActor
    func discardTodo(key: Key, in store: DataStore) throws {
        guard store.loadState == .ready, !store.isApplyingBackup else {
            throw DataStore.PersistenceBlockedError(message: store.persistenceErrorMessage)
        }
        let referenced = PhotoStorage.referencedFileNames(logs: store.dailyLogs, todos: store.siteTodos)
        let unreferenced = try pendingPhotoFiles(key: key).filter { !referenced.contains($0) }
        try DataStoreDeferredFileCleanup.deletePhotoFilesOrThrow(unreferenced, summary: "todoDraft.discard")
        try discard(key: key)
    }

    @MainActor
    private func validateTodoDraft(_ draft: SiteTodoFormDraft, editing: Bool, in store: DataStore) throws {
        let current = store.siteTodos.first { $0.id == draft.record.id }
        let canWrite = editing
            ? current.map { Self.fingerprint($0) == draft.baseRecord } == true
            : current == nil
        guard store.loadState == .ready, !store.isApplyingBackup, canWrite else {
            throw DataStore.PersistenceBlockedError(message: AppLocalization.string("原记录已变化，草稿仍保留。请关闭后重新打开并核对。"))
        }
        guard !draft.normalizedRecord.title.isEmpty else {
            throw DataStore.PersistenceBlockedError(message: AppLocalization.string("请填写待办事项。"))
        }
        if let projectID = draft.record.projectId, !store.projects.contains(where: { $0.id == projectID }) {
            throw DataStore.PersistenceBlockedError(message: AppLocalization.string("项目不存在"))
        }
    }

    @MainActor
    private func cleanupUnreferencedTodoPhotos(_ names: [String], in store: DataStore) {
        let referenced = PhotoStorage.referencedFileNames(logs: store.dailyLogs, todos: store.siteTodos)
        DataStoreDeferredFileCleanup.photoFiles(names.filter { !referenced.contains($0) }, summary: "todoDraft.cleanup")?.perform()
    }
}
