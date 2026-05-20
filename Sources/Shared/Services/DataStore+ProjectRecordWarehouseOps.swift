import Foundation

@MainActor
extension DataStore {
    func appendProjectWarehouseMovement(_ movement: ProjectWarehouseMovement) {
        replaceProjectWarehouseMovements(projectWarehouseMovements + [movement])
    }

    func insertProjectWarehouseMovementAtTop(_ movement: ProjectWarehouseMovement) {
        var movements = projectWarehouseMovements
        movements.insert(movement, at: 0)
        replaceProjectWarehouseMovements(movements)
    }

    @discardableResult
    func updateProjectWarehouseMovement(_ movement: ProjectWarehouseMovement) -> Bool {
        var current = projectWarehouseMovements
        guard let index = current.firstIndex(where: { $0.id == movement.id }) else { return false }
        current[index] = movement
        replaceProjectWarehouseMovements(current)
        return true
    }

    @discardableResult
    func mutateProjectWarehouseMovement(
        id: UUID,
        _ mutation: (inout ProjectWarehouseMovement) -> Void
    ) -> Bool {
        var current = projectWarehouseMovements
        guard let index = current.firstIndex(where: { $0.id == id }) else { return false }
        mutation(&current[index])
        replaceProjectWarehouseMovements(current)
        return true
    }

    func mergeProjectWarehouseMovementsByID(_ movements: [ProjectWarehouseMovement]) {
        replaceProjectWarehouseMovements(mergedProjectRecordElementsByID(projectWarehouseMovements, with: movements))
    }

    func restoreProjectWarehouseMovements(from deletion: DataStoreRemovalResult<ProjectWarehouseMovement>) {
        replaceProjectWarehouseMovements(deletion.restoredItems(current: projectWarehouseMovements, id: \.id))
    }

    @discardableResult
    func removeProjectWarehouseMovements(
        ids: Set<UUID>,
        audit: DataStoreDeletionAuditContext? = nil,
        deferredFileCleanup: DataStoreDeferredFileCleanup? = nil,
        recordsAuditImmediately: Bool = false
    ) -> DataStoreRemovalResult<ProjectWarehouseMovement> {
        removeProjectRecordElements(
            from: projectWarehouseMovements,
            ids: ids,
            id: \.id,
            replace: replaceProjectWarehouseMovements,
            audit: audit,
            deferredFileCleanup: deferredFileCleanup,
            recordsAuditImmediately: recordsAuditImmediately
        )
    }
}
