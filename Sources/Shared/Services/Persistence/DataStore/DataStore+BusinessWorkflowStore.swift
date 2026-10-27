import Foundation

extension DataStore: BusinessWorkflowStore {
    func rollbackLinkedFinancialRecord(id: UUID) {
        removeProjectFinancialRecords(ids: [id])
    }

    func rollbackLinkedWarehouseMovement(id: UUID) {
        removeProjectWarehouseMovements(ids: [id])
    }
}
