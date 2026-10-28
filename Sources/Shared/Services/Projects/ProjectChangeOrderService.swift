import Foundation

/// Changes a single independent record against its current version. Contract and ledgers are untouched.
@MainActor
enum ProjectChangeOrderService {
    static func save(
        _ value: ProjectChangeOrder,
        projectID: UUID,
        expected: ProjectChangeOrder?,
        store: any BusinessWorkflowStore,
        persist: (() async throws -> Void)? = nil
    ) async throws {
        await store.awaitInitialLoad()
        try store.requireBusinessWritesAllowed()
        guard store.savingPaymentProjects.insert(projectID).inserted else {
            throw SaveError.inProgress
        }
        defer { store.savingPaymentProjects.remove(projectID) }
        guard var project = store.projects.first(where: { $0.id == projectID }) else {
            throw BusinessWorkflowError.missingSource
        }
        let previous = project.changeOrders.first { $0.id == value.id }
        guard previous == expected else { throw BusinessWorkflowError.staleSource }
        try value.validate(projectID: projectID, documents: store.projectDocuments)
        if let index = project.changeOrders.firstIndex(where: { $0.id == value.id }) {
            project.changeOrders[index] = value
        } else {
            project.changeOrders.append(value)
        }
        guard store.updateProject(project) else { throw BusinessWorkflowError.missingSource }
        do {
            if let persist { try await persist() } else { try await store.flushSaveOrThrow() }
        } catch {
            // Merge only this operation's rollback; preserve changes made during the await.
            if var current = store.projects.first(where: { $0.id == projectID }),
               current.changeOrders.first(where: { $0.id == value.id }) == value {
                if let index = current.changeOrders.firstIndex(where: { $0.id == value.id }), let previous {
                    current.changeOrders[index] = previous
                } else {
                    current.changeOrders.removeAll { $0.id == value.id }
                }
                store.updateProject(current)
            }
            throw error
        }
    }

    enum SaveError: LocalizedError {
        case inProgress
        var errorDescription: String? {
            AppLocalization.string("该项目正在保存，请稍后重试；当前输入仍保留。")
        }
    }
}
