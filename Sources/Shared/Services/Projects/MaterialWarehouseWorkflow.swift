import Foundation

struct MaterialReceiptRequest {
    var id = UUID()
    var materialID: UUID
    var expectedMaterial: Data?
    var quantity: QuantityValue
    var unitPrice: MoneyValue
    var date: BusinessDateValue
    var handler: String
    var note: String
}

struct MaterialWarehouseProgress {
    let planned: QuantityValue
    let received: QuantityValue
    let remaining: QuantityValue
    let stock: QuantityValue
}

enum MaterialWarehouseWorkflow {
    static func progress(material: MaterialItem, movements: [ProjectWarehouseMovement]) -> MaterialWarehouseProgress {
        let linked = movements.filter { $0.projectId == material.projectId && $0.origin?.materialItemID == material.id && $0.movementType == .inbound }
        let received = linked.reduce(QuantityValue.zero) { $0 + $1.quantity }
        let remainder = material.quantity - received
        let remaining = remainder.optionalDecimal.map { QuantityValue(max(.zero, $0)) } ?? .empty
        let key = MaterialIdentity.key(name: material.name, specification: material.specification, unit: material.unit)
        let stock = movements.filter {
            $0.projectId == material.projectId && MaterialIdentity.key(name: $0.materialName, specification: $0.specification, unit: $0.unit) == key
        }.reduce(QuantityValue.zero) { total, movement in
            movement.movementType == .inbound ? total + movement.quantity : total - movement.quantity
        }
        return MaterialWarehouseProgress(planned: material.quantity, received: received, remaining: remaining, stock: stock)
    }

    @MainActor
    static func receive(_ request: MaterialReceiptRequest, store: any BusinessWorkflowStore, persist: (() async throws -> Void)? = nil) async throws -> ProjectWarehouseMovement {
        await store.awaitInitialLoad()
        try store.requireBusinessWritesAllowed()
        guard let source = store.materialItems.first(where: { $0.id == request.materialID }),
              let projectID = source.projectId, store.projects.contains(where: { $0.id == projectID }) else { throw BusinessWorkflowError.missingSource }
        guard BusinessDraftStore.fingerprint(source) == request.expectedMaterial else { throw BusinessWorkflowError.staleSource }
        guard request.quantity.isPositive, request.date.calendarDay() != nil,
              request.unitPrice.isEmpty || (request.unitPrice.isValid && !request.unitPrice.isNegative),
              !store.projectWarehouseMovements.contains(where: { $0.id == request.id }) else { throw BusinessWorkflowError.invalidInput }
        let movement = ProjectWarehouseMovement(id: request.id, projectId: projectID, date: request.date, movementType: .inbound,
            materialName: source.name, specification: source.specification, unit: source.unit, quantity: request.quantity,
            counterparty: source.supplier, handler: request.handler, note: request.note,
            origin: BusinessRecordOrigin(materialItemID: source.id, warehouseMovementID: nil, unitPrice: request.unitPrice.isEmpty ? nil : request.unitPrice))
        store.insertProjectWarehouseMovementAtTop(movement)
        // Planned quantity remains a plan; stock is always derived from actual movements.
        do {
            if let persist { try await persist() } else { try await store.flushSaveOrThrow() }
            return movement
        } catch {
            if let current = store.projectWarehouseMovements.first(where: { $0.id == movement.id }),
               BusinessDraftStore.fingerprint(current) == BusinessDraftStore.fingerprint(movement) {
                store.rollbackLinkedWarehouseMovement(id: movement.id)
            }
            throw error
        }
    }

    @MainActor
    static func ledgerDraft(movementID: UUID, expected: Data?, unitPrice: MoneyValue, store: any BusinessWorkflowStore,
                            persist: (() async throws -> Void)? = nil) async throws -> ProjectFinancialRecord {
        await store.awaitInitialLoad()
        try store.requireBusinessWritesAllowed()
        if let existing = store.projectFinancialRecords.first(where: { $0.origin?.warehouseMovementID == movementID }) { return existing }
        guard let movement = store.projectWarehouseMovements.first(where: { $0.id == movementID }),
              movement.movementType == .inbound,
              store.projects.contains(where: { $0.id == movement.projectId }) else { throw BusinessWorkflowError.missingSource }
        guard BusinessDraftStore.fingerprint(movement) == expected else { throw BusinessWorkflowError.staleSource }
        guard movement.linkedDocumentIds.allSatisfy({ id in
            store.projectDocuments.contains { $0.id == id && $0.projectId == movement.projectId }
        }) else { throw BusinessWorkflowError.missingSource }
        guard let quantity = movement.quantity.optionalDecimal, let price = unitPrice.optionalDecimal,
              let amount = RepositoryMaterialArithmetic.product(quantity, price), amount > .zero else { throw BusinessWorkflowError.invalidInput }
        // Stable identity makes delete/regenerate/undo safe: one origin cannot create duplicate ledger rows.
        guard !store.projectFinancialRecords.contains(where: { $0.id == movementID }) else { throw BusinessWorkflowError.duplicateSource }
        let record = ProjectFinancialRecord(id: movementID, projectId: movement.projectId, date: movement.date, direction: .expense,
            category: .material, amount: MoneyValue(amount), counterparty: movement.counterparty,
            linkedDocumentIds: movement.linkedDocumentIds, status: .draft, note: movement.note,
            origin: BusinessRecordOrigin(materialItemID: movement.origin?.materialItemID, warehouseMovementID: movementID, unitPrice: unitPrice))
        store.appendProjectFinancialRecord(record)
        do {
            if let persist { try await persist() } else { try await store.flushSaveOrThrow() }
            return record
        } catch {
            if let current = store.projectFinancialRecords.first(where: { $0.id == record.id }), BusinessDraftStore.fingerprint(current) == BusinessDraftStore.fingerprint(record) {
                store.rollbackLinkedFinancialRecord(id: record.id)
            }
            throw error
        }
    }
}
