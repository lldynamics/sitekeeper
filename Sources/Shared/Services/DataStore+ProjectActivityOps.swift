import Foundation

@MainActor
extension DataStore {
    func appendProject(_ project: Project) {
        replaceProjects(projects + [project])
    }

    @discardableResult
    func updateProject(_ project: Project) -> Bool {
        var current = projects
        guard let index = current.firstIndex(where: { $0.id == project.id }) else { return false }
        current[index] = project
        replaceProjects(current)
        return true
    }

    func mergeProjectsByID(_ values: [Project]) {
        replaceProjects(mergedProjectActivityElementsByID(projects, with: values))
    }

    func appendDailyLog(_ log: DailyLog) {
        replaceDailyLogs(dailyLogs + [log])
    }

    func insertDailyLogAtTop(_ log: DailyLog) {
        var logs = dailyLogs
        logs.insert(log, at: 0)
        replaceDailyLogs(logs)
    }

    @discardableResult
    func updateDailyLog(_ log: DailyLog) -> Bool {
        var current = dailyLogs
        guard let index = current.firstIndex(where: { $0.id == log.id }) else { return false }
        current[index] = log
        replaceDailyLogs(current)
        return true
    }

    func mergeDailyLogsByID(_ logs: [DailyLog]) {
        replaceDailyLogs(mergedProjectActivityElementsByID(dailyLogs, with: logs))
    }

    func restoreDailyLogs(from deletion: DataStoreRemovalResult<DailyLog>) {
        replaceDailyLogs(deletion.restoredItems(current: dailyLogs, id: \.id))
    }

    @discardableResult
    func removeDailyLogs(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<DailyLog> {
        removeProjectActivityElements(
            from: dailyLogs,
            ids: ids,
            id: \.id,
            replace: replaceDailyLogs,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }

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

    private func mergedProjectActivityElementsByID<Element: Identifiable>(
        _ current: [Element],
        with incoming: [Element]
    ) -> [Element] where Element.ID: Hashable {
        guard !incoming.isEmpty else { return current }
        var merged = current
        var existingIDs = Set(current.map(\.id))
        for item in incoming where existingIDs.insert(item.id).inserted {
            merged.append(item)
        }
        return merged
    }

    @discardableResult
    private func removeProjectActivityElements<Element, ID: Hashable>(
        from current: [Element],
        ids: Set<ID>,
        id: (Element) -> ID,
        replace: ([Element]) -> Void,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<Element> {
        guard !ids.isEmpty else {
            return DataStoreRemovalResult(
                snapshot: current,
                removed: [],
                audit: audit,
                deferredFileCleanup: deferredFileCleanup
            )
        }

        let removed = current.filter { ids.contains(id($0)) }
        guard !removed.isEmpty else {
            return DataStoreRemovalResult(
                snapshot: current,
                removed: [],
                audit: audit,
                deferredFileCleanup: deferredFileCleanup
            )
        }

        replace(current.filter { !ids.contains(id($0)) })

        let result = DataStoreRemovalResult(
            snapshot: current,
            removed: removed,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup
        )
        if recordsAuditImmediately {
            result.recordAuditStarted()
            result.performDeferredFileCleanup()
            result.recordAuditSucceeded()
        }
        return result
    }
}
