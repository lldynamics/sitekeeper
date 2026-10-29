import Foundation
import Testing
@testable import sitekeeper

struct PracticalFinanceMaterialTests {
    @Test func paidExplanationUsesOnlyCurrentProjectFormalCollectionsWithoutAddingHistory() {
        let project = Project(name: "Synthetic", location: "", paidAmount: money("900"))
        let records = [
            ProjectFinancialRecord(projectId: project.id, direction: .income, category: .collection, amount: money("0.1")),
            ProjectFinancialRecord(projectId: project.id, direction: .income, category: .receipt, amount: money("0.2")),
            ProjectFinancialRecord(projectId: project.id, direction: .income, category: .other, amount: money("100")),
            ProjectFinancialRecord(projectId: project.id, direction: .income, category: .refund, amount: money("200")),
            ProjectFinancialRecord(projectId: project.id, direction: .income, category: .collection, amount: money("300"), status: .draft),
            ProjectFinancialRecord(projectId: project.id, direction: .income, category: .collection, amount: money("400"), status: .archived),
            ProjectFinancialRecord(projectId: UUID(), direction: .income, category: .collection, amount: money("500"))
        ]

        let explanation = ProjectPaidAmountExplanation(project: project, records: records)

        #expect(explanation.recordedCollectionAmount == money("0.3"))
        #expect(explanation.manualPaidAmount == money("900"))
        #expect(explanation.effectivePaidAmount == money("0.3"))
        #expect(explanation.source == .recordedCollections)
        #expect(explanation.requiresReconciliation)
        #expect(!explanation.requiresAmountReview)
        #expect(project.paidAmount == money("900"))
    }

    @Test func paidExplanationFallsBackToHistoryUntilFormalCollectionIsPositive() {
        let project = Project(name: "Synthetic", location: "", paidAmount: money("12.3456789"))
        let zero = ProjectFinancialRecord(projectId: project.id, direction: .income, category: .collection, amount: .zero)
        let explanation = ProjectPaidAmountExplanation(project: project, records: [zero])

        #expect(explanation.effectivePaidAmount == money("12.3456789"))
        #expect(explanation.source == .manualHistory)
        #expect(explanation.recordedCollectionAmount == .zero)
        #expect(explanation.requiresReconciliation)

        let emptyProject = Project(name: "Empty", location: "")
        let empty = ProjectPaidAmountExplanation(project: emptyProject, records: [])
        #expect(empty.effectivePaidAmount == .zero)
        #expect(empty.manualPaidAmount.isEmpty)
        #expect(!empty.requiresReconciliation)
    }

    @Test func paidExplanationPreservesUnknownFormalAmountInsteadOfFallingBack() {
        let project = Project(name: "Synthetic", location: "", paidAmount: money("50"))
        let record = ProjectFinancialRecord(projectId: project.id, direction: .income, category: .collection,
                                            amount: MoneyValue(storage: .unresolved("legacy unknown")))
        let explanation = ProjectPaidAmountExplanation(project: project, records: [record])

        #expect(!explanation.effectivePaidAmount.isValid)
        #expect(explanation.source == .unresolvedCollections)
        #expect(explanation.requiresAmountReview)
        #expect(!explanation.requiresReconciliation)
    }

    @Test func equalPaidSourcesNeedNoReconciliation() {
        let project = Project(name: "Synthetic", location: "", paidAmount: money("1.01"))
        let record = ProjectFinancialRecord(projectId: project.id, direction: .income, category: .collection, amount: money("1.01"))
        let explanation = ProjectPaidAmountExplanation(project: project, records: [record])
        #expect(!explanation.requiresReconciliation)
        #expect(explanation.effectivePaidAmount == money("1.01"))
    }

    @Test func followUpCountsOnlyExplicitlyLinkedInboundAndKeepsSeparatePlans() throws {
        let projectID = UUID()
        let first = material(projectID: projectID, specification: "A", unit: "kg", quantity: "1.25")
        let second = material(projectID: projectID, specification: "B", unit: "kg", quantity: "10")
        let third = material(projectID: projectID, specification: "A", unit: "袋", quantity: "20")
        let fourth = material(projectID: projectID, specification: "A", unit: "kg", quantity: "30")
        let movements = [
            inbound(projectID: projectID, materialID: first.id, quantity: "0.125"),
            inbound(projectID: projectID, materialID: first.id, quantity: "0.375"),
            inbound(projectID: projectID, materialID: second.id, quantity: "2"),
            inbound(projectID: UUID(), materialID: first.id, quantity: "100"),
            inbound(projectID: projectID, materialID: nil, quantity: "100"),
            ProjectWarehouseMovement(projectId: projectID, movementType: .outbound, materialName: "同名材料", unit: "kg",
                                     quantity: quantity("0.25"), origin: BusinessRecordOrigin(materialItemID: first.id))
        ]
        let rows = MaterialFollowUpSummary.rows(projectID: projectID, materials: [first, second, third, fourth], movements: movements)

        #expect(rows.count == 4)
        let firstRow = try #require(rows.first { $0.id == first.id })
        #expect(firstRow.received == quantity("0.5"))
        #expect(firstRow.remaining == quantity("0.75"))
        #expect(rows.first { $0.id == second.id }?.remaining == quantity("8"))
        #expect(rows.first { $0.id == third.id }?.received == .zero)
        #expect(rows.first { $0.id == fourth.id }?.received == .zero)
    }

    @Test func followUpFiltersSupplierAndPendingStatusWithoutTreatingStatusAsReceipt() throws {
        let projectID = UUID()
        let unpurchased = material(projectID: projectID, supplier: " Supplier A ", status: .notPurchased)
        let awaiting = material(projectID: projectID, supplier: "Supplier A", status: .purchased)
        let otherSupplier = material(projectID: projectID, supplier: "Supplier AB", status: .purchased)
        let unassigned = material(projectID: projectID, supplier: "   ", status: .notPurchased)
        let complete = material(projectID: projectID, supplier: "Supplier A", status: .purchased)
        let arrived = material(projectID: projectID, supplier: "Supplier A", status: .arrived)
        let used = material(projectID: projectID, supplier: "Supplier A", status: .used)
        let unrelated = material(projectID: UUID(), supplier: "Supplier A")
        let materials = [unpurchased, awaiting, otherSupplier, unassigned, complete, arrived, used, unrelated]
        let movements = [inbound(projectID: projectID, materialID: complete.id, quantity: "10")]

        let all = MaterialFollowUpSummary.rows(projectID: projectID, materials: materials, movements: movements)
        #expect(Set(all.map(\.id)) == Set([unpurchased.id, awaiting.id, otherSupplier.id, unassigned.id, arrived.id, used.id]))
        #expect(MaterialFollowUpSummary.suppliers(in: all) == ["", "Supplier A", "Supplier AB"])
        let purchased = MaterialFollowUpSummary.rows(projectID: projectID, materials: materials, movements: movements,
                                                     supplier: "Supplier A", filter: .awaitingArrival)
        #expect(purchased.map(\.id) == [awaiting.id])
        #expect(try #require(purchased.first).received == .zero)
        #expect(purchased.first?.reviewReason == nil)
        let notPurchased = MaterialFollowUpSummary.rows(projectID: projectID, materials: materials, movements: movements,
                                                        supplier: "Supplier A", filter: .notPurchased)
        #expect(notPurchased.map(\.id) == [unpurchased.id])
        let review = MaterialFollowUpSummary.rows(projectID: projectID, materials: materials, movements: movements,
                                                 supplier: "Supplier A", filter: .needsReview)
        #expect(Set(review.map(\.id)) == Set([arrived.id, used.id]))
        #expect(review.allSatisfy { $0.reviewReason == .missingReceipts && $0.received.isEmpty && $0.remaining.isEmpty })
    }

    @Test func arrivedAndUsedPartialReceiptsRemainVisibleWithoutChangingBusinessRecords() throws {
        let projectID = UUID()
        for status in [MaterialPurchaseStatus.arrived, .used] {
            let plan = material(projectID: projectID, status: status)
            let receipt = inbound(projectID: projectID, materialID: plan.id, quantity: "4.25")
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let originalPlan = try encoder.encode(plan)
            let originalReceipt = try encoder.encode(receipt)
            let row = try #require(MaterialFollowUpSummary.rows(projectID: projectID, materials: [plan], movements: [receipt]).first)

            #expect(row.received == quantity("4.25"))
            #expect(row.remaining == quantity("5.75"))
            #expect(row.purchaseStatus == status)
            #expect(row.followUpStatus == .needsReview)
            #expect(row.reviewReason == .statusConflict)
            #expect(try encoder.encode(plan) == originalPlan)
            #expect(try encoder.encode(receipt) == originalReceipt)
        }
    }

    @Test func fullyReceivedPlansAreExcludedWhenPurchaseStatusIsConsistent() {
        let projectID = UUID()
        for status in [MaterialPurchaseStatus.purchased, .arrived, .used] {
            let plan = material(projectID: projectID, status: status)
            let receipt = inbound(projectID: projectID, materialID: plan.id, quantity: "10")
            #expect(MaterialFollowUpSummary.rows(projectID: projectID, materials: [plan], movements: [receipt]).isEmpty)
        }
    }

    @Test func unpurchasedPlansWithReceiptsRemainVisibleForReview() throws {
        let projectID = UUID()
        let plan = material(projectID: projectID, status: .notPurchased)
        for amount in ["4.25", "10"] {
            let receipt = inbound(projectID: projectID, materialID: plan.id, quantity: amount)
            let row = try #require(MaterialFollowUpSummary.rows(projectID: projectID, materials: [plan], movements: [receipt]).first)
            #expect(row.received == quantity(amount))
            #expect(row.remaining == quantity(amount == "10" ? "0" : "5.75"))
            #expect(row.purchaseStatus == .notPurchased)
            #expect(row.followUpStatus == .needsReview)
            #expect(row.reviewReason == .statusConflict)
        }
        let none = try #require(MaterialFollowUpSummary.rows(projectID: projectID, materials: [plan], movements: []).first)
        #expect(none.followUpStatus == .notPurchased && none.reviewReason == nil)
    }

    @Test func excessReceiptsStayVisibleForReviewInsteadOfBeingClampedToComplete() throws {
        let projectID = UUID()
        for status in MaterialPurchaseStatus.allCases {
            let plan = material(projectID: projectID, status: status)
            let receipt = inbound(projectID: projectID, materialID: plan.id, quantity: "10.125")
            let row = try #require(MaterialFollowUpSummary.rows(projectID: projectID, materials: [plan], movements: [receipt]).first)
            #expect(row.received == quantity("10.125"))
            #expect(row.remaining.isEmpty)
            #expect(row.followUpStatus == .needsReview)
            #expect(row.reviewReason == .receivedExceedsPlan)
        }
    }

    @Test func completedStatusWithUnknownOrIncompatibleReceiptDoesNotImplyDelivery() throws {
        let projectID = UUID()
        for status in [MaterialPurchaseStatus.arrived, .used] {
            let plan = material(projectID: projectID, status: status)
            var unknown = inbound(projectID: projectID, materialID: plan.id, quantity: "10")
            unknown.quantity = .empty
            var incompatible = inbound(projectID: projectID, materialID: plan.id, quantity: "10")
            incompatible.unit = "袋"
            for receipt in [unknown, incompatible] {
                let row = try #require(MaterialFollowUpSummary.rows(projectID: projectID, materials: [plan], movements: [receipt]).first)
                #expect(row.received.isEmpty)
                #expect(row.remaining.isEmpty)
                #expect(row.followUpStatus == .needsReview)
                #expect(row.reviewReason == (receipt.unit == "kg" ? .quantityUnknown : .receiptUnits))
            }
        }
    }

    @Test func completedStatusCannotBorrowReceiptFromAnotherProjectOrMaterial() throws {
        let projectID = UUID()
        let plan = material(projectID: projectID, status: .arrived)
        var foreignPlan = plan
        foreignPlan.projectId = UUID()
        let otherPlan = material(projectID: projectID, status: .used)
        let movements = [
            inbound(projectID: foreignPlan.projectId!, materialID: plan.id, quantity: "10"),
            inbound(projectID: projectID, materialID: otherPlan.id, quantity: "10"),
            inbound(projectID: projectID, materialID: nil, quantity: "10")
        ]
        let rows = MaterialFollowUpSummary.rows(projectID: projectID, materials: [plan, foreignPlan, otherPlan], movements: movements)
        #expect(rows.map(\.id) == [plan.id])
        let row = try #require(rows.first)
        #expect(row.reviewReason == .missingReceipts)
        #expect(row.received.isEmpty)
    }

    @Test func followUpKeepsUnknownPlanAndReceiptQuantitiesForReview() throws {
        let projectID = UUID()
        var unknownPlan = material(projectID: projectID)
        unknownPlan.quantity = .empty
        let unknownReceipt = material(projectID: projectID)
        var movement = inbound(projectID: projectID, materialID: unknownReceipt.id, quantity: "1")
        movement.quantity = QuantityValue(storage: .unresolved("unknown"))
        let rows = MaterialFollowUpSummary.rows(projectID: projectID, materials: [unknownPlan, unknownReceipt], movements: [movement])

        #expect(rows.count == 2)
        #expect(try #require(rows.first { $0.id == unknownPlan.id }).remaining.isEmpty)
        let receiptRow = try #require(rows.first { $0.id == unknownReceipt.id })
        #expect(receiptRow.received.isEmpty)
        #expect(receiptRow.remaining.isEmpty)
        #expect(receiptRow.followUpStatus == .needsReview)
        #expect(receiptRow.reviewReason == .quantityUnknown)
        #expect(MaterialFollowUpSummary.quantityText(receiptRow.remaining, unit: "kg") != "0 kg")
    }

    @Test func followUpRequiresMatchingReceiptUnitsAndValidNonnegativeQuantities() throws {
        let projectID = UUID()
        let plan = material(projectID: projectID, unit: " kg ")
        var valid = inbound(projectID: projectID, materialID: plan.id, quantity: "1.25")
        valid.unit = "kg\n"
        let matched = try #require(MaterialFollowUpSummary.rows(
            projectID: projectID, materials: [plan], movements: [valid]
        ).first)
        #expect(matched.received == quantity("1.25"))
        #expect(matched.remaining == quantity("8.75"))

        var differentDimension = valid
        differentDimension.id = UUID()
        differentDimension.unit = "m"
        var differentSpelling = valid
        differentSpelling.id = UUID()
        differentSpelling.unit = "KG"
        var negative = valid
        negative.id = UUID()
        negative.quantity = quantity("-1")
        var invalid = valid
        invalid.id = UUID()
        invalid.quantity = QuantityValue(storage: .unresolved("unknown"))
        for incompatible in [differentDimension, differentSpelling, negative, invalid] {
            let row = try #require(MaterialFollowUpSummary.rows(
                projectID: projectID, materials: [plan], movements: [valid, incompatible]
            ).first)
            #expect(row.received.isEmpty)
            #expect(row.remaining.isEmpty)
            #expect(row.followUpStatus == .needsReview)
        }
    }

    @Test func reviewExportShowsOriginalStatusAndRecordedQuantitiesWithoutPrivateFields() throws {
        let projectID = UUID()
        var plan = material(projectID: projectID, status: .used)
        plan.unitPrice = money("123456789.99")
        plan.brand = "PRIVATE_BRAND"
        var receipt = inbound(projectID: projectID, materialID: plan.id, quantity: "2.125")
        receipt.note = "PRIVATE_FINANCE_NOTE"
        receipt.handler = "PRIVATE_HANDLER"
        let rows = MaterialFollowUpSummary.rows(projectID: projectID, materials: [plan], movements: [receipt], filter: .needsReview)
        let row = try #require(rows.first)
        let text = MaterialFollowUpSummary.exportText(projectName: "Synthetic project", rows: rows, supplier: nil, filter: .needsReview)
        let originalStatusLine = String(format: AppLocalization.string("material_follow_up_purchase_status_format"), row.purchaseStatus.displayName)

        #expect(text.contains(row.followUpStatus.displayName))
        #expect(originalStatusLine.contains(row.purchaseStatus.displayName))
        #expect(text.components(separatedBy: .newlines).contains(originalStatusLine))
        #expect(text.contains(try #require(row.reviewReason).displayName))
        #expect(text.contains("2.125 kg"))
        #expect(text.contains("7.875 kg"))
        #expect(!text.contains("123456789.99"))
        #expect(!text.contains("PRIVATE_BRAND"))
        #expect(!text.contains("PRIVATE_FINANCE_NOTE"))
        #expect(!text.contains("PRIVATE_HANDLER"))
    }

    @Test func followUpExportContainsAllSelectedRowsAndExcludesFinancialAndFreeTextFields() {
        let projectID = UUID()
        let materials = (1...55).map { index in
            MaterialItem(name: "Synthetic material \(index)", quantity: quantity("10.125"), unit: "kg",
                         unitPrice: money("987654321.99"), specification: "Spec \(index)", brand: "PRIVATE_BRAND",
                         supplier: "Supplier A", purchaseStatus: .purchased, projectId: projectID)
        }
        var movement = inbound(projectID: projectID, materialID: materials[0].id, quantity: "0.125")
        movement.note = "PRIVATE_FINANCE_NOTE"
        movement.handler = "PRIVATE_HANDLER"
        let rows = MaterialFollowUpSummary.rows(projectID: projectID, materials: materials, movements: [movement],
                                                supplier: "Supplier A", filter: .awaitingArrival)
        let text = MaterialFollowUpSummary.exportText(projectName: "Synthetic project", rows: rows,
                                                     supplier: "Supplier A", filter: .awaitingArrival)

        #expect(rows.count == 55)
        #expect(text.contains("Synthetic material 55"))
        #expect(text.contains("Spec 55"))
        #expect(text.contains("10.125 kg"))
        #expect(text.contains("0.125 kg"))
        #expect(!text.contains("987654321.99"))
        #expect(!text.contains("PRIVATE_BRAND"))
        #expect(!text.contains("PRIVATE_FINANCE_NOTE"))
        #expect(!text.contains("PRIVATE_HANDLER"))
    }

    private func money(_ text: String) -> MoneyValue { NumericInputSupport.money(text) }
    private func quantity(_ text: String) -> QuantityValue { NumericInputSupport.quantity(text) }

    private func material(projectID: UUID, specification: String = "A", unit: String = "kg", quantity text: String = "10",
                          supplier: String = "Supplier A", status: MaterialPurchaseStatus = .purchased) -> MaterialItem {
        MaterialItem(name: "同名材料", quantity: quantity(text), unit: unit, specification: specification,
                     supplier: supplier, purchaseStatus: status, projectId: projectID)
    }

    private func inbound(projectID: UUID, materialID: UUID?, quantity text: String) -> ProjectWarehouseMovement {
        ProjectWarehouseMovement(projectId: projectID, materialName: "同名材料", specification: "A", unit: "kg",
                                 quantity: quantity(text), origin: materialID.map { BusinessRecordOrigin(materialItemID: $0) })
    }
}
