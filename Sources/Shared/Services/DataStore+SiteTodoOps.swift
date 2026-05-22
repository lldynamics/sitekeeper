import Foundation

@MainActor
extension DataStore {
    func appendSiteTodo(_ todo: SiteTodo) {
        replaceSiteTodos(siteTodos + [todo])
    }

    func insertSiteTodoAtTop(_ todo: SiteTodo) {
        var todos = siteTodos
        todos.insert(todo, at: 0)
        replaceSiteTodos(todos)
    }

    @discardableResult
    func updateSiteTodo(_ todo: SiteTodo) -> Bool {
        var current = siteTodos
        guard let index = current.firstIndex(where: { $0.id == todo.id }) else { return false }
        current[index] = todo
        replaceSiteTodos(current)
        return true
    }

    func mergeSiteTodosByID(_ todos: [SiteTodo]) {
        replaceSiteTodos(mergedProjectActivityElementsByID(siteTodos, with: todos))
    }

    func restoreSiteTodos(from deletion: DataStoreRemovalResult<SiteTodo>) {
        replaceSiteTodos(deletion.restoredItems(current: siteTodos, id: \.id))
    }

    @discardableResult
    func removeSiteTodos(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<SiteTodo> {
        removeProjectActivityElements(
            from: siteTodos,
            ids: ids,
            id: \.id,
            replace: replaceSiteTodos,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }
}
