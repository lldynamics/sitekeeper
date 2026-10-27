import Foundation

@MainActor
enum DrawingIssueSaveService {
    /// Persist the issue and its drawing link together before closing the editor.
    /// A failed write rolls back only the records still matching this attempt.
    static func save(_ todo: SiteTodo, drawing: ProjectDrawing, store: DataStore,
                     persist: (() async throws -> Void)? = nil) async throws {
        await store.awaitInitialLoad()
        guard store.canEditBusinessData, todo.projectId == drawing.projectId,
              store.projects.contains(where: { $0.id == drawing.projectId }),
              let current = store.projectDrawings.first(where: { $0.id == drawing.id }) else {
            throw DataStore.PersistenceBlockedError(message: AppLocalization.string("原记录已变化，草稿仍保留。请关闭后重新打开并核对。"))
        }
        guard !store.siteTodos.contains(where: { $0.id == todo.id }) else {
            throw DataStore.PersistenceBlockedError(message: AppLocalization.string("原记录已变化，草稿仍保留。请关闭后重新打开并核对。"))
        }
        let before = store.projectDrawings
        var updated = drawing
        // Preserve links added while the drawing detail was open.
        updated.linkedTodoIDs = Array(Set(current.linkedTodoIDs + drawing.linkedTodoIDs + [todo.id])).sorted { $0.uuidString < $1.uuidString }
        if updated.issueStatus == .none { updated.issueStatus = .open }
        if updated.issueNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { updated.issueNote = todo.title }
        store.insertSiteTodoAtTop(todo)
        ProjectDetailAssetActions.saveDrawing(updated, store: store)
        let attempted = Dictionary(uniqueKeysWithValues: store.projectDrawings.map { ($0.id, $0) })
        do {
            if let persist { try await persist() } else { try await store.flushSaveOrThrow() }
        } catch {
            if let live = store.siteTodos.first(where: { $0.id == todo.id }),
               BusinessDraftStore.fingerprint(live) == BusinessDraftStore.fingerprint(todo) {
                store.removeSiteTodos(ids: [todo.id])
            }
            for old in before {
                guard let attempt = attempted[old.id],
                      BusinessDraftStore.fingerprint(old) != BusinessDraftStore.fingerprint(attempt),
                      let live = store.projectDrawings.first(where: { $0.id == old.id }),
                      BusinessDraftStore.fingerprint(live) == BusinessDraftStore.fingerprint(attempt) else { continue }
                store.updateProjectDrawing(old)
            }
            throw error
        }
    }
}
