import Foundation

@MainActor
extension DataStore {
    func appendProgressTask(_ task: ProgressTask) {
        replaceProgressTasks(progressTasks + [task])
    }

    @discardableResult
    func updateProgressTask(_ task: ProgressTask) -> Bool {
        var current = progressTasks
        guard let index = current.firstIndex(where: { $0.id == task.id }) else { return false }
        current[index] = task
        replaceProgressTasks(current)
        return true
    }

    func mergeProgressTasksByID(_ tasks: [ProgressTask]) {
        replaceProgressTasks(mergedFinanceElementsByID(progressTasks, with: tasks))
    }

    @discardableResult
    func removeProgressTasks(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProgressTask> {
        removeFinanceElements(
            from: progressTasks,
            ids: ids,
            id: \.id,
            replace: replaceProgressTasks,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }
}
