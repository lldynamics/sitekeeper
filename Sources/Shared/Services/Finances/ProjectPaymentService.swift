import Foundation

@MainActor
enum ProjectPaymentService {
    static func savePlan(_ plan: ProjectPaymentPlan, projectID: UUID, expected: ProjectPaymentPlan?, store: any BusinessWorkflowStore,
                         persist: (() async throws -> Void)? = nil) async throws {
        await store.awaitInitialLoad()
        try store.requireBusinessWritesAllowed()
        guard var project = store.projects.first(where: { $0.id == projectID }) else { throw BusinessWorkflowError.missingSource }
        guard store.savingPaymentProjects.insert(projectID).inserted else { throw BusinessWorkflowError.operationInProgress }
        defer { store.savingPaymentProjects.remove(projectID) }
        let previous = project.paymentPlans.first { $0.id == plan.id }
        guard previous == expected else { throw BusinessWorkflowError.staleSource }
        try ProjectPaymentMetrics.validate(plan, in: project, records: store.projectFinancialRecords)
        if let index = project.paymentPlans.firstIndex(where: { $0.id == plan.id }) {
            project.paymentPlans[index] = plan
        } else {
            project.paymentPlans.append(plan)
        }
        store.updateProject(project)
        do {
            if let persist { try await persist() } else { try await store.flushSaveOrThrow() }
        } catch {
            if var current = store.projects.first(where: { $0.id == projectID }), current.paymentPlans.first(where: { $0.id == plan.id }) == plan {
                if let index = current.paymentPlans.firstIndex(where: { $0.id == plan.id }), let previous {
                    current.paymentPlans[index] = previous
                } else {
                    current.paymentPlans.removeAll { $0.id == plan.id }
                }
                store.updateProject(current)
            }
            throw error
        }
    }

    static func recordPayment(_ record: ProjectFinancialRecord, store: any BusinessWorkflowStore,
                              persist: (() async throws -> Void)? = nil) async throws {
        await store.awaitInitialLoad()
        try store.requireBusinessWritesAllowed()
        guard store.savingPaymentProjects.insert(record.projectId).inserted else { throw BusinessWorkflowError.operationInProgress }
        defer { store.savingPaymentProjects.remove(record.projectId) }
        guard record.paymentAllocation != nil, record.status == .active,
              !store.projectFinancialRecords.contains(where: { $0.id == record.id }) else { throw BusinessWorkflowError.invalidAllocation }
        try ProjectPaymentMetrics.validateAllocation(record, projects: store.projects, records: store.projectFinancialRecords)
        store.appendProjectFinancialRecord(record)
        do {
            if let persist { try await persist() } else { try await store.flushSaveOrThrow() }
        } catch {
            if let current = store.projectFinancialRecords.first(where: { $0.id == record.id }),
               BusinessDraftStore.fingerprint(current) == BusinessDraftStore.fingerprint(record) {
                store.rollbackLinkedFinancialRecord(id: record.id)
            }
            throw error
        }
    }
}
