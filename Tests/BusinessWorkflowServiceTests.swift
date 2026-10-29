import Foundation
import Testing
@testable import sitekeeper

@MainActor @Suite(.serialized)
struct BusinessWorkflowServiceTests {
    enum Failure: Error { case injected }

    @Test func partialReceiptsKeepPlannedQuantityAndStockSeparatesUnitAndProject() async throws {
        let store = WorkflowTestStore()
        let project = Project(name: "A", location: "")
        store.projects = [project]
        let material = MaterialItem(name: "Cable", quantity: 10, unit: "m", unitPrice: 2, projectId: project.id)
        store.materialItems = [material]
        let request = MaterialReceiptRequest(materialID: material.id, expectedMaterial: BusinessDraftStore.fingerprint(material), quantity: 4, unitPrice: 2, date: .today(), handler: "Worker", note: "Delivery")
        let received = try await MaterialWarehouseWorkflow.receive(request, store: store)
        store.projectWarehouseMovements += [
            ProjectWarehouseMovement(projectId: project.id, movementType: .outbound, materialName: "Cable", unit: "m", quantity: 1),
            ProjectWarehouseMovement(projectId: project.id, materialName: "Cable", unit: "roll", quantity: 100),
            ProjectWarehouseMovement(projectId: UUID(), materialName: "Cable", unit: "m", quantity: 100)
        ]
        let progress = MaterialWarehouseWorkflow.progress(material: material, movements: store.projectWarehouseMovements)
        #expect(progress.planned == 10 && progress.received == 4 && progress.remaining == 6 && progress.stock == 3)
        #expect(store.materialItems[0].quantity == 10)
        #expect(store.materialItems[0].purchaseStatus == material.purchaseStatus)
        #expect(store.projectFinancialRecords.isEmpty)
        #expect(progress.reviewReason == .statusConflict)
        #expect(received.origin?.materialItemID == material.id)
        await #expect(throws: (any Error).self) { _ = try await MaterialWarehouseWorkflow.receive(request, store: store) }
    }

    @Test func receiptProgressFlagsPartialArrivedAndUsedWithoutLosingKnownQuantities() {
        let projectID = UUID()
        for status in [MaterialPurchaseStatus.arrived, .used] {
            let material = MaterialItem(name: "Cable", quantity: 10, unit: "m", purchaseStatus: status, projectId: projectID)
            let receipt = ProjectWarehouseMovement(projectId: projectID, materialName: "Cable", unit: "m", quantity: 4,
                                                   origin: BusinessRecordOrigin(materialItemID: material.id))
            let partial = MaterialWarehouseWorkflow.progress(material: material, movements: [receipt])
            #expect(partial.received == 4 && partial.remaining == 6)
            #expect(partial.reviewReason == .statusConflict)
            let unknown = MaterialWarehouseWorkflow.progress(material: material, movements: [])
            #expect(unknown.received.isEmpty && unknown.remaining.isEmpty)
            #expect(unknown.reviewReason == .missingReceipts)
            var completeReceipt = receipt
            completeReceipt.quantity = 10
            let complete = MaterialWarehouseWorkflow.progress(material: material, movements: [completeReceipt])
            #expect(complete.received == 10 && complete.remaining == .zero)
            #expect(complete.reviewReason == nil)
            #expect(material.purchaseStatus == status)
        }
    }

    @Test func receiptProgressFlagsUnpurchasedStatusWhenReceiptsExist() {
        let projectID = UUID()
        let material = MaterialItem(name: "Cable", quantity: 10, unit: "m", purchaseStatus: .notPurchased, projectId: projectID)
        let quantities: [QuantityValue] = [4, 10]
        for received in quantities {
            let receipt = ProjectWarehouseMovement(projectId: projectID, materialName: "Cable", unit: "m", quantity: received,
                                                   origin: BusinessRecordOrigin(materialItemID: material.id))
            let progress = MaterialWarehouseWorkflow.progress(material: material, movements: [receipt])
            #expect(progress.received == received)
            #expect(progress.remaining == (received == 4 ? 6 : .zero))
            #expect(progress.reviewReason == .statusConflict)
            #expect(material.purchaseStatus == .notPurchased)
        }
        #expect(MaterialWarehouseWorkflow.progress(material: material, movements: []).reviewReason == nil)
    }

    @Test func receiptProgressRequiresCompatibleUnitsAndKnownNonnegativeQuantities() {
        let projectID = UUID()
        let material = MaterialItem(name: "Cable", quantity: 10, unit: " m ", purchaseStatus: .purchased, projectId: projectID)
        let valid = ProjectWarehouseMovement(projectId: projectID, materialName: "Cable", unit: "m\n", quantity: 4,
                                             origin: BusinessRecordOrigin(materialItemID: material.id))
        let matched = MaterialWarehouseWorkflow.progress(material: material, movements: [valid])
        #expect(matched.received == 4 && matched.remaining == 6 && matched.reviewReason == nil)
        for unit in ["roll", "M", ""] {
            var incompatible = valid
            incompatible.id = UUID()
            incompatible.unit = unit
            let progress = MaterialWarehouseWorkflow.progress(material: material, movements: [valid, incompatible])
            #expect(progress.received.isEmpty && progress.remaining.isEmpty)
            #expect(progress.reviewReason == .receiptUnits)
        }
        for quantity in [QuantityValue.empty, QuantityValue(storage: .unresolved("legacy unknown")), NumericInputSupport.quantity("-1")] {
            var unknown = valid
            unknown.id = UUID()
            unknown.quantity = quantity
            let progress = MaterialWarehouseWorkflow.progress(material: material, movements: [valid, unknown])
            #expect(progress.received.isEmpty && progress.remaining.isEmpty && progress.stock.isEmpty)
            #expect(progress.reviewReason == .quantityUnknown)
        }
        var unknownPlan = material
        unknownPlan.quantity = .empty
        #expect(MaterialWarehouseWorkflow.progress(material: unknownPlan, movements: [valid]).reviewReason == .quantityUnknown)
    }

    @Test func receiptProgressRetainsExcessAndSeparatesProjectsMaterialLinksAndStock() {
        let projectID = UUID()
        let material = MaterialItem(name: "Cable", quantity: 10, unit: "m", purchaseStatus: .purchased, projectId: projectID)
        let receipt = ProjectWarehouseMovement(projectId: projectID, materialName: "Cable", unit: "m", quantity: 4,
                                               origin: BusinessRecordOrigin(materialItemID: material.id))
        let unrelated = [
            ProjectWarehouseMovement(projectId: UUID(), materialName: "Cable", unit: "m", quantity: 100,
                                     origin: BusinessRecordOrigin(materialItemID: material.id)),
            ProjectWarehouseMovement(projectId: projectID, materialName: "Other", unit: "m", quantity: 100,
                                     origin: BusinessRecordOrigin(materialItemID: UUID())),
            ProjectWarehouseMovement(projectId: projectID, movementType: .outbound, materialName: "Cable", unit: "m", quantity: 1,
                                     origin: BusinessRecordOrigin(materialItemID: material.id)),
            ProjectWarehouseMovement(projectId: projectID, materialName: "Cable", unit: "roll", quantity: 100)
        ]
        let scoped = MaterialWarehouseWorkflow.progress(material: material, movements: [receipt] + unrelated)
        #expect(scoped.received == 4 && scoped.remaining == 6 && scoped.stock == 3)
        #expect(scoped.reviewReason == nil)
        var excess = receipt
        excess.quantity = 11
        let over = MaterialWarehouseWorkflow.progress(material: material, movements: [excess])
        #expect(over.received == 11 && over.stock == 11 && over.remaining.isEmpty)
        #expect(over.reviewReason == .receivedExceedsPlan)
    }

    @Test func receiptSaveUsesCurrentSourceAndNeverPostsMoneyOrChangesPurchaseStatus() async throws {
        let store = WorkflowTestStore()
        let project = Project(name: "A", location: "")
        store.projects = [project]
        let original = MaterialItem(name: "Cable", quantity: 10, unit: "m", purchaseStatus: .arrived, projectId: project.id)
        var current = original
        current.quantity = 12
        store.materialItems = [current]
        let stale = MaterialReceiptRequest(materialID: original.id, expectedMaterial: BusinessDraftStore.fingerprint(original),
                                           quantity: 2, unitPrice: 3, date: .today(), handler: "", note: "")
        await #expect(throws: (any Error).self) { _ = try await MaterialWarehouseWorkflow.receive(stale, store: store) }
        #expect(store.projectWarehouseMovements.isEmpty)
        var confirmed = stale
        confirmed.expectedMaterial = BusinessDraftStore.fingerprint(current)
        let movement = try await MaterialWarehouseWorkflow.receive(confirmed, store: store)
        #expect(movement.projectId == project.id && movement.quantity == 2 && movement.unit == "m")
        #expect(store.materialItems.first?.purchaseStatus == .arrived)
        #expect(store.materialItems.first?.quantity == 12)
        #expect(store.projectFinancialRecords.isEmpty)
    }

    @Test func ledgerDraftKeepsDocumentsCostAndIdempotencyAndDoesNotPostCash() async throws {
        let store = WorkflowTestStore()
        let project = Project(name: "A", location: "")
        store.projects = [project]
        let document = ProjectDocument(projectId: project.id, title: "Delivery", fileName: "delivery.pdf")
        store.projectDocuments = [document]
        let movement = ProjectWarehouseMovement(projectId: project.id, materialName: "Cable", quantity: NumericInputSupport.quantity("0.1"), linkedDocumentIds: [document.id])
        store.projectWarehouseMovements = [movement]
        let record = try await MaterialWarehouseWorkflow.ledgerDraft(movementID: movement.id, expected: BusinessDraftStore.fingerprint(movement), unitPrice: NumericInputSupport.money("0.2"), store: store)
        let repeated = try await MaterialWarehouseWorkflow.ledgerDraft(movementID: movement.id, expected: nil, unitPrice: 999, store: store)
        #expect(record.id == repeated.id && store.projectFinancialRecords.count == 1)
        #expect(record.amount == NumericInputSupport.money("0.02"))
        #expect(record.linkedDocumentIds == [document.id] && record.status == .draft)
        #expect(ProjectFinancialMetrics.businessRecords(store.projectFinancialRecords).isEmpty)
        let restored = try JSONDecoder().decode(ProjectFinancialRecord.self, from: JSONEncoder().encode(record))
        #expect(restored.origin == record.origin)
    }

    @Test func staleSourcesAndBrokenAttachmentsCannotGenerateCash() async throws {
        let store = WorkflowTestStore()
        let project = Project(name: "A", location: "")
        store.projects = [project]
        let material = MaterialItem(name: "Cable", quantity: 10, unit: "m", projectId: project.id)
        store.materialItems = [material]
        let request = MaterialReceiptRequest(materialID: material.id, expectedMaterial: nil, quantity: 1, unitPrice: .empty, date: .today(), handler: "", note: "")
        await #expect(throws: (any Error).self) { _ = try await MaterialWarehouseWorkflow.receive(request, store: store) }
        let movement = ProjectWarehouseMovement(projectId: project.id, materialName: "Cable", quantity: 1, linkedDocumentIds: [UUID()])
        store.projectWarehouseMovements = [movement]
        await #expect(throws: (any Error).self) { _ = try await MaterialWarehouseWorkflow.ledgerDraft(movementID: movement.id, expected: BusinessDraftStore.fingerprint(movement), unitPrice: 2, store: store) }
        #expect(store.projectFinancialRecords.isEmpty)
    }

    @Test func failedReceiptAndLedgerSaveRollBackOnlyTheirOwnChangesThenRetry() async throws {
        let store = WorkflowTestStore()
        let project = Project(name: "A", location: "")
        store.projects = [project]
        let material = MaterialItem(name: "Cable", quantity: 10, unit: "m", projectId: project.id)
        store.materialItems = [material]
        let request = MaterialReceiptRequest(materialID: material.id, expectedMaterial: BusinessDraftStore.fingerprint(material), quantity: 4, unitPrice: 2, date: .today(), handler: "", note: "")
        let unrelated = ProjectWarehouseMovement(projectId: project.id, materialName: "Other", quantity: 3)
        do {
            _ = try await MaterialWarehouseWorkflow.receive(request, store: store, persist: {
                store.projectWarehouseMovements.append(unrelated)
                throw Failure.injected
            })
            Issue.record("Expected failure")
        } catch Failure.injected {}
        #expect(store.projectWarehouseMovements.map(\.id) == [unrelated.id])
        let movement = try await MaterialWarehouseWorkflow.receive(request, store: store)
        do {
            _ = try await MaterialWarehouseWorkflow.ledgerDraft(movementID: movement.id, expected: BusinessDraftStore.fingerprint(movement), unitPrice: 2, store: store, persist: { throw Failure.injected })
            Issue.record("Expected failure")
        } catch Failure.injected {}
        #expect(store.projectFinancialRecords.isEmpty)
        let record = try await MaterialWarehouseWorkflow.ledgerDraft(movementID: movement.id, expected: BusinessDraftStore.fingerprint(movement), unitPrice: 2, store: store)
        #expect(record.amount == 8 && store.projectFinancialRecords.count == 1)
    }

    @Test func failedPlanSavePreservesOtherProjectEditsAndBlocksInterleavedPayment() async throws {
        let store = WorkflowTestStore()
        let project = Project(name: "A", location: "")
        store.projects = [project]
        let plan = ProjectPaymentPlan(title: "Contract", direction: .income, counterparty: "Customer", installments: [ProjectPaymentInstallment(title: "Deposit", dueDate: .today(), amount: 100)])
        do {
            try await ProjectPaymentService.savePlan(plan, projectID: project.id, expected: nil, store: store, persist: {
                store.projects[0].name = "Other edit"
                let record = ProjectFinancialRecord(projectId: project.id, direction: .income, category: .collection, amount: 10,
                    paymentAllocation: ProjectPaymentAllocation(planID: plan.id, installmentID: plan.installments[0].id))
                await #expect(throws: (any Error).self) { try await ProjectPaymentService.recordPayment(record, store: store) }
                throw Failure.injected
            })
            Issue.record("Expected failure")
        } catch Failure.injected {}
        #expect(store.projects[0].name == "Other edit" && store.projects[0].paymentPlans.isEmpty)
        #expect(store.projectFinancialRecords.isEmpty && store.savingPaymentProjects.isEmpty)
        try await ProjectPaymentService.savePlan(plan, projectID: project.id, expected: nil, store: store)
        await #expect(throws: (any Error).self) { try await ProjectPaymentService.savePlan(plan, projectID: project.id, expected: nil, store: store) }
    }

    @Test func partialCashRollbackRetryAndOverpayGuardUseCurrentRemainingAmount() async throws {
        let store = WorkflowTestStore()
        let plan = ProjectPaymentPlan(title: "Contract", direction: .expense, counterparty: "Supplier", installments: [ProjectPaymentInstallment(title: "First", dueDate: .today(), amount: 100)])
        let project = Project(name: "A", location: "", paymentPlans: [plan])
        store.projects = [project]
        let record = ProjectFinancialRecord(projectId: project.id, direction: .expense, category: .receipt, amount: 30,
            paymentAllocation: ProjectPaymentAllocation(planID: plan.id, installmentID: plan.installments[0].id))
        do {
            try await ProjectPaymentService.recordPayment(record, store: store, persist: { throw Failure.injected })
            Issue.record("Expected failure")
        } catch Failure.injected {}
        #expect(store.projectFinancialRecords.isEmpty)
        try await ProjectPaymentService.recordPayment(record, store: store)
        await #expect(throws: (any Error).self) { try await ProjectPaymentService.recordPayment(record, store: store) }
        var extra = record
        extra.id = UUID()
        extra.amount = 71
        await #expect(throws: (any Error).self) { try await ProjectPaymentService.recordPayment(extra, store: store) }
        extra.amount = 70
        try await ProjectPaymentService.recordPayment(extra, store: store)
        #expect(ProjectPaymentMetrics.summaries(project: project, records: store.projectFinancialRecords).first?.remaining.isZero == true)
        #expect(ProjectFinancialMetrics.summary(store.projectFinancialRecords).expense == 100)
    }
}

/// A deliberately small port double: real services perform all business validation,
/// identity checks and rollback. Native DataStore/disk integration is tested separately.
@MainActor
private final class WorkflowTestStore: BusinessWorkflowStore {
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
