import Foundation

/// The workflow owns validation and rollback; DataStore owns persistence and indexes.
/// This narrow port also permits running business transactions without a device UI.
@MainActor
protocol BusinessWorkflowStore: AnyObject {
    var projects: [Project] { get }
    var materialItems: [MaterialItem] { get }
    var projectWarehouseMovements: [ProjectWarehouseMovement] { get }
    var projectFinancialRecords: [ProjectFinancialRecord] { get }
    var projectDocuments: [ProjectDocument] { get }
    var savingPaymentProjects: Set<UUID> { get set }
    func awaitInitialLoad() async
    func requireBusinessWritesAllowed() throws
    func flushSaveOrThrow() async throws
    @discardableResult func updateProject(_ value: Project) -> Bool
    func appendProjectFinancialRecord(_ value: ProjectFinancialRecord)
    func insertProjectWarehouseMovementAtTop(_ value: ProjectWarehouseMovement)
    func rollbackLinkedFinancialRecord(id: UUID)
    func rollbackLinkedWarehouseMovement(id: UUID)
}
