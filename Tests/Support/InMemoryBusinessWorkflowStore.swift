import Foundation
@testable import sitekeeper

/// A deliberately small port double: real services perform all business validation,
/// identity checks and rollback. Native DataStore/disk integration is tested separately.
@MainActor
final class InMemoryBusinessWorkflowStore: BusinessWorkflowStore {
    var projects: [Project] = []
    var materialItems: [MaterialItem] = []
    var projectWarehouseMovements: [ProjectWarehouseMovement] = []
    var projectFinancialRecords: [ProjectFinancialRecord] = []
    var projectDocuments: [ProjectDocument] = []
    var savingPaymentProjects: Set<UUID> = []
    func awaitInitialLoad() async {}
    func requireBusinessWritesAllowed() throws {}
    func flushSaveOrThrow() async throws {}
    @discardableResult func updateProject(_ value: Project) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == value.id }) else { return false }
        projects[index] = value
        return true
    }
    func appendProjectFinancialRecord(_ value: ProjectFinancialRecord) { projectFinancialRecords.append(value) }
    func insertProjectWarehouseMovementAtTop(_ value: ProjectWarehouseMovement) { projectWarehouseMovements.insert(value, at: 0) }
    func rollbackLinkedFinancialRecord(id: UUID) { projectFinancialRecords.removeAll { $0.id == id } }
    func rollbackLinkedWarehouseMovement(id: UUID) { projectWarehouseMovements.removeAll { $0.id == id } }
}
