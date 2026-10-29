import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct QuotationBusinessRulesTests {
    @Test func generatedQuoteKeyboardOrderContainsOnlyVisibleInputs() {
        let shared: [GenerateQuoteField] = [.laborRate, .taxRate, .discountRate]
        #expect(GenerateQuoteField.visibleFields(for: nil) == shared)
        #expect(GenerateQuoteField.visibleFields(for: .useMaterialPrice) == shared)
        #expect(GenerateQuoteField.visibleFields(for: .leaveUnpriced) == shared)
        #expect(GenerateQuoteField.visibleFields(for: .overrideAll) == [.materialPrice] + shared)
    }

    @Test func materialQuotePriceModeRequiresAnExplicitBusinessChoice() {
        let material = MaterialItem(
            name: "钢筋",
            quantity: NumericInputSupport.quantity("2"),
            unit: "吨",
            unitPrice: NumericInputSupport.money("4200")
        )

        let costReference = MaterialQuoteGenerator.makeQuoteItem(from: material, mode: .useMaterialPrice)
        let externalPrice = MaterialQuoteGenerator.makeQuoteItem(
            from: material,
            mode: .overrideAll,
            overridePrice: NumericInputSupport.money("5000")
        )
        let pendingPrice = MaterialQuoteGenerator.makeQuoteItem(from: material, mode: .leaveUnpriced)

        #expect(costReference.unitPrice.wireText == "4200")
        #expect(externalPrice.unitPrice.wireText == "5000")
        #expect(pendingPrice.unitPrice.isEmpty)
        #expect(pendingPrice.status == .draft)
    }

    @Test func contractWritePlanUsesOnlyConfirmedRowsFromSelectedVersion() throws {
        let project = Project(name: "办公楼", location: "", contractAmount: NumericInputSupport.money("900"))
        let confirmedV1 = QuoteItem(
            name: "钢筋",
            unitPrice: NumericInputSupport.money("100"),
            quantity: NumericInputSupport.quantity("2"),
            unit: "吨",
            notes: "",
            taxRate: NumericInputSupport.quantity("10"),
            discountRate: NumericInputSupport.quantity("0"),
            versionName: "V1",
            status: .confirmed,
            contractAmount: NumericInputSupport.money("210"),
            projectId: project.id
        )
        let draftV1 = QuoteItem(
            name: "草稿项",
            unitPrice: NumericInputSupport.money("999"),
            quantity: NumericInputSupport.quantity("1"),
            unit: "项",
            notes: "",
            taxRate: NumericInputSupport.quantity("0"),
            discountRate: NumericInputSupport.quantity("0"),
            versionName: "V1",
            status: .draft,
            projectId: project.id
        )
        let confirmedV2 = QuoteItem(
            name: "新版",
            unitPrice: NumericInputSupport.money("300"),
            quantity: NumericInputSupport.quantity("1"),
            unit: "项",
            notes: "",
            taxRate: NumericInputSupport.quantity("0"),
            discountRate: NumericInputSupport.quantity("0"),
            versionName: "V2",
            status: .confirmed,
            projectId: project.id
        )

        let plan = try #require(QuotationContractWritePlanner.makePlan(
            project: project,
            versionName: "V1",
            quotes: [confirmedV1, draftV1, confirmedV2]
        ))

        #expect(plan.status == .confirmed)
        #expect(plan.versionName == "V1")
        #expect(plan.itemCount == 1)
        #expect(plan.itemNames == ["钢筋"])
        #expect(plan.oldAmount == NumericInputSupport.money("900"))
        #expect(plan.newAmount == NumericInputSupport.money("210"))
        #expect(plan.canApply)
    }

    @Test func contractWritePlanRejectsMissingPriceAndDetectsPreviewChanges() throws {
        let project = Project(name: "厂房", location: "", contractAmount: NumericInputSupport.money("100"))
        var quote = QuoteItem(
            name: "待补价材料",
            unitPrice: NumericInputSupport.money(""),
            quantity: NumericInputSupport.quantity("2"),
            unit: "件",
            notes: "",
            taxRate: NumericInputSupport.quantity("0"),
            discountRate: NumericInputSupport.quantity("0"),
            versionName: "V3",
            status: .confirmed,
            projectId: project.id
        )
        let missingPricePlan = try #require(QuotationContractWritePlanner.makePlan(
            project: project,
            versionName: "V3",
            quotes: [quote]
        ))
        #expect(missingPricePlan.incompleteItemCount == 1)
        #expect(!missingPricePlan.canApply)

        quote.unitPrice = NumericInputSupport.money("80")
        let refreshedPlan = try #require(QuotationContractWritePlanner.makePlan(
            project: project,
            versionName: "V3",
            quotes: [quote]
        ))
        #expect(refreshedPlan.canApply)
        #expect(refreshedPlan.newAmount == NumericInputSupport.money("160"))
        #expect(refreshedPlan != missingPricePlan)
        #expect(refreshedPlan.selectionSignature != missingPricePlan.selectionSignature)
    }

    @Test func contractWritePlanRejectsInvalidQuantityUnlessAnExplicitContractAmountIsValid() throws {
        let project = Project(name: "住宅楼", location: "")
        var invalidQuantityQuote = QuoteItem(
            name: "非法数量",
            unitPrice: NumericInputSupport.money("100"),
            quantity: NumericInputSupport.quantity("abc"),
            unit: "项",
            notes: "",
            taxRate: NumericInputSupport.quantity("0"),
            discountRate: NumericInputSupport.quantity("0"),
            versionName: "V1",
            status: .confirmed,
            projectId: project.id
        )
        var missingQuantityQuote = QuoteItem(
            name: "缺少数量",
            unitPrice: NumericInputSupport.money("100"),
            quantity: NumericInputSupport.quantity(""),
            unit: "项",
            notes: "",
            taxRate: NumericInputSupport.quantity("0"),
            discountRate: NumericInputSupport.quantity("0"),
            versionName: "V1",
            status: .confirmed,
            projectId: project.id
        )

        let invalidQuantityPlan = try #require(QuotationContractWritePlanner.makePlan(
            project: project,
            versionName: "V1",
            quotes: [invalidQuantityQuote, missingQuantityQuote]
        ))
        #expect(invalidQuantityPlan.incompleteItemCount == 2)
        #expect(!invalidQuantityPlan.canApply)

        missingQuantityQuote.contractAmount = NumericInputSupport.money("250")
        let explicitAmountPlan = try #require(QuotationContractWritePlanner.makePlan(
            project: project,
            versionName: "V1",
            quotes: [invalidQuantityQuote, missingQuantityQuote]
        ))
        #expect(explicitAmountPlan.incompleteItemCount == 1)
        #expect(explicitAmountPlan.newAmount == NumericInputSupport.money("250"))

        invalidQuantityQuote.contractAmount = NumericInputSupport.money("300")
        let allExplicitAmountsPlan = try #require(QuotationContractWritePlanner.makePlan(
            project: project,
            versionName: "V1",
            quotes: [invalidQuantityQuote, missingQuantityQuote]
        ))
        #expect(allExplicitAmountsPlan.incompleteItemCount == 0)
        #expect(allExplicitAmountsPlan.newAmount == NumericInputSupport.money("550"))
        #expect(allExplicitAmountsPlan.canApply)
    }
}

extension QuotationBusinessRulesTests {
    private func businessQuote(projectID: UUID, version: String = "V1", status: QuoteStatus = .confirmed,
                               price: MoneyValue = 10, quantity: QuantityValue = 2) -> QuoteItem {
        QuoteItem(name: "Synthetic", unitPrice: price, quantity: quantity, unit: "项", notes: "", taxRate: 0,
                  discountRate: 0, versionName: version, status: status, projectId: projectID)
    }

    @Test func businessQuoteNeverInfersAmongConfirmedVersionsAndUsesExplicitNormalizedSelection() {
        var project = Project(name: "A", location: "", contractAmount: 999)
        var first = businessQuote(projectID: project.id, version: " V1 \n")
        first.contractAmount = 777
        let second = businessQuote(projectID: project.id, version: "V2", price: 30)
        let unrelated = businessQuote(projectID: UUID(), version: "V1", price: 999)
        let none = ProjectBusinessQuoteMetrics(project: project, quotes: [first, second, unrelated])
        #expect(none.state == .noSelection)
        #expect(none.amount == nil)
        #expect(none.confirmedVersions == ["V2", "V1"])
        #expect(none.allVersionsAmount == 80)
        project.businessQuoteVersion = " V1 "
        let chosen = ProjectBusinessQuoteMetrics(project: project, quotes: [first, second, unrelated])
        #expect(chosen.state == .ready)
        #expect(chosen.amount == 20)
        #expect(chosen.itemCount == 1)
        #expect(project.contractAmount == 999)
        project.businessQuoteVersion = "V3"
        #expect(ProjectBusinessQuoteMetrics(project: project, quotes: [first, second]).state == .staleSelection)
    }

    @Test func businessQuoteRejectsPartlyUnconfirmedVersionsAndKeepsValidZeroDistinctFromMissing() {
        let project = Project(name: "A", location: "", businessQuoteVersion: "V1")
        let zero = businessQuote(projectID: project.id, version: "", price: 0)
        let ready = ProjectBusinessQuoteMetrics(project: project, quotes: [zero])
        #expect(ready.state == .ready)
        #expect(ready.amount == 0)
        for status in [QuoteStatus.draft, .sent] {
            let mixed = ProjectBusinessQuoteMetrics(project: project, quotes: [zero, businessQuote(projectID: project.id, status: status)])
            #expect(mixed.state == .unconfirmedItems)
            #expect(mixed.amount == nil)
            #expect(mixed.unconfirmedItemCount == 1)
        }
        for price in [MoneyValue.empty, MoneyValue(storage: .unresolved("unknown"))] {
            let incomplete = ProjectBusinessQuoteMetrics(project: project, quotes: [zero, businessQuote(projectID: project.id, price: price)])
            #expect(incomplete.state == .incompleteAmounts)
            #expect(incomplete.amount == nil)
            #expect(incomplete.allVersionsAmount == nil)
            #expect(incomplete.incompleteItemCount == 1)
        }
        let missingQuantity = businessQuote(projectID: project.id, quantity: .empty)
        #expect(ProjectBusinessQuoteMetrics(project: project, quotes: [missingQuantity]).amount == nil)
        #expect(ProjectBusinessQuoteMetrics(project: project, quotes: []).state == .staleSelection)
    }

    @Test func businessQuoteRejectsAggregatePrecisionOverflowAndContractWriteCannotApplyIt() throws {
        let project = Project(name: "A", location: "", businessQuoteVersion: "V1")
        let large = MoneyValue(Decimal(string: "99999999999999999999999999999999999999")!)
        let first = businessQuote(projectID: project.id, price: large, quantity: 1)
        let second = businessQuote(projectID: project.id, price: large, quantity: 1)
        let metrics = ProjectBusinessQuoteMetrics(project: project, quotes: [first, second])
        #expect(metrics.state == .incompleteAmounts)
        #expect(metrics.amount == nil)
        #expect(metrics.allVersionsAmount == nil)
        let plan = try #require(QuotationContractWritePlanner.makePlan(project: project, versionName: "V1", quotes: [first, second]))
        #expect(!plan.canApply)
    }

    @Test func businessQuoteSelectionDecodesLegacyProjectAndRoundTripsWithoutChangingOtherFields() throws {
        let project = Project(name: "Legacy", location: "", contractAmount: 123)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        #expect(object["businessQuoteVersion"] == nil)
        let legacy = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.businessQuoteVersion == nil)
        object["businessQuoteVersion"] = "V2"
        let selected = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: object))
        let restored = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(selected))
        #expect(restored.businessQuoteVersion == "V2")
        #expect(restored.contractAmount == 123)
        #expect(restored.changeOrders.isEmpty)
    }

    @Test func businessQuoteSelectionSaveRollsBackOnlySelectionOnFailureAndUsesLatestQuotes() async throws {
        let store = QuoteSelectionTestStore()
        let project = Project(name: "A", location: "", contractAmount: 900)
        store.projects = [project]
        var quotes = [businessQuote(projectID: project.id)]
        do {
            try await ProjectBusinessQuoteSelectionService.save(version: "V1", projectID: project.id, expectedSelection: nil,
                store: store, quotes: { quotes }, persist: {
                    store.projects[0].name = "Concurrent edit"
                    #expect(store.savingPaymentProjects.contains(project.id))
                    throw QuoteSelectionTestStore.Failure.injected
                })
            Issue.record("Expected failure")
        } catch QuoteSelectionTestStore.Failure.injected {}
        #expect(store.projects[0].businessQuoteVersion == nil)
        #expect(store.projects[0].name == "Concurrent edit")
        #expect(store.projects[0].contractAmount == 900)
        #expect(store.savingPaymentProjects.isEmpty)
        quotes[0].status = .draft
        await #expect(throws: (any Error).self) {
            try await ProjectBusinessQuoteSelectionService.save(version: "V1", projectID: project.id, expectedSelection: nil,
                store: store, quotes: { quotes })
        }
        #expect(store.projects[0].businessQuoteVersion == nil)
        quotes[0].status = .confirmed
        try await ProjectBusinessQuoteSelectionService.save(version: " V1 ", projectID: project.id, expectedSelection: nil,
            store: store, quotes: { quotes })
        #expect(store.projects[0].businessQuoteVersion == "V1")
        #expect(store.flushCount == 1)
        await #expect(throws: (any Error).self) {
            try await ProjectBusinessQuoteSelectionService.save(version: nil, projectID: project.id, expectedSelection: nil,
                store: store, quotes: { quotes })
        }
        try await ProjectBusinessQuoteSelectionService.save(version: nil, projectID: project.id, expectedSelection: "V1",
            store: store, quotes: { [] })
        #expect(store.projects[0].businessQuoteVersion == nil)
        #expect(store.projects[0].contractAmount == 900)
    }

    @Test func businessQuoteSelectionRollbackPreservesNewerSelectionAndSharedLockBlocksWrites() async throws {
        let store = QuoteSelectionTestStore()
        let project = Project(name: "A", location: "", businessQuoteVersion: "V1")
        store.projects = [project]
        let quotes = [businessQuote(projectID: project.id, version: "V1"), businessQuote(projectID: project.id, version: "V2")]
        do {
            try await ProjectBusinessQuoteSelectionService.save(version: "V2", projectID: project.id, expectedSelection: "V1",
                store: store, quotes: { quotes }, persist: {
                    await #expect(throws: (any Error).self) {
                        try await ProjectBusinessQuoteSelectionService.save(version: nil, projectID: project.id,
                            expectedSelection: "V2", store: store, quotes: { quotes })
                    }
                    store.projects[0].businessQuoteVersion = "V3"
                    throw QuoteSelectionTestStore.Failure.injected
                })
            Issue.record("Expected failure")
        } catch QuoteSelectionTestStore.Failure.injected {}
        #expect(store.projects[0].businessQuoteVersion == "V3")
        #expect(store.savingPaymentProjects.isEmpty)
    }
}

@MainActor
private final class QuoteSelectionTestStore: BusinessWorkflowStore {
    enum Failure: Error { case injected }
    var projects: [Project] = []
    var materialItems: [MaterialItem] = []
    var projectWarehouseMovements: [ProjectWarehouseMovement] = []
    var projectFinancialRecords: [ProjectFinancialRecord] = []
    var projectDocuments: [ProjectDocument] = []
    var savingPaymentProjects: Set<UUID> = []
    var flushCount = 0
    func awaitInitialLoad() async {}
    func requireBusinessWritesAllowed() throws {}
    func flushSaveOrThrow() async throws { flushCount += 1 }
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

extension QuotationBusinessRulesTests {
    @Test func filteredReferenceTotalsPreserveTaxDiscountZeroAndIncompleteStates() throws {
        let project = Project(name: "A", location: "")
        var first = businessQuote(projectID: project.id, price: NumericInputSupport.money("0.1"), quantity: 3)
        first.taxRate = 13
        first.discountRate = 5
        let summary = QuotationReferenceSummary(items: [first])
        let amounts = try #require(summary.amounts)
        #expect(amounts.subtotal == NumericInputSupport.money("0.3"))
        #expect(amounts.tax == NumericInputSupport.money("0.039"))
        #expect(amounts.discount == NumericInputSupport.money("0.015"))
        #expect(amounts.total == NumericInputSupport.money("0.324"))
        #expect(QuotationReferenceSummary(items: [businessQuote(projectID: project.id, price: 0)]).amounts?.total == 0)
        #expect(QuotationReferenceSummary(items: []).amounts == nil)
        let incomplete = QuotationReferenceSummary(items: [first, businessQuote(projectID: project.id, version: "V2", price: .empty)])
        #expect(incomplete.itemCount == 2)
        #expect(incomplete.incompleteItemCount == 1)
        #expect(incomplete.amounts == nil)
        let large = MoneyValue(Decimal(string: "99999999999999999999999999999999999999")!)
        let overflow = QuotationReferenceSummary(items: [businessQuote(projectID: project.id, price: large, quantity: 1),
                                                        businessQuote(projectID: project.id, price: large, quantity: 1)])
        #expect(overflow.amounts == nil)
    }

    @Test func currentBusinessVersionFilterIsExplicitAndNeverFallsBackWhenScopeChanges() {
        var project = Project(name: "A", location: "", businessQuoteVersion: " V1 ")
        let first = businessQuote(projectID: project.id, version: " V1 ")
        let second = businessQuote(projectID: project.id, version: "V2")
        let otherProject = Project(name: "B", location: "", businessQuoteVersion: "V1")
        let unrelated = businessQuote(projectID: otherProject.id)
        let filter = QuotationBusinessVersionFilter(projectID: project.id, version: "V1")
        let quotes = [first, second, unrelated]
        #expect(filter.applying(to: quotes, project: project).map(\.id) == [first.id])
        #expect(filter.applying(to: quotes, project: otherProject).isEmpty)
        #expect(filter.applying(to: quotes, project: nil).isEmpty)
        #expect(filter.applying(to: [second], project: project).isEmpty)
        project.businessQuoteVersion = "V2"
        #expect(filter.applying(to: quotes, project: project).isEmpty)
        project.businessQuoteVersion = nil
        #expect(filter.applying(to: quotes, project: project).isEmpty)
        project.businessQuoteVersion = "V1"
        let draftSameVersion = businessQuote(projectID: project.id, status: .draft)
        #expect(filter.applying(to: quotes + [draftSameVersion], project: project).isEmpty)
        var invalid = first
        invalid.unitPrice = .empty
        #expect(filter.applying(to: [invalid, second], project: project).isEmpty)
        // Search and status apply after this scope in QuotationView; a restrictive
        // status filter may produce no matches and must never expose another version.
        #expect(filter.applying(to: quotes, project: project).filter { $0.status == .sent }.isEmpty)
    }
}
