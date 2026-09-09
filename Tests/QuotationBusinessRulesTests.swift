import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct QuotationBusinessRulesTests {
    @Test func materialQuotePriceModeRequiresAnExplicitBusinessChoice() {
        let material = MaterialItem(
            name: "钢筋",
            quantity: "2",
            unit: "吨",
            unitPrice: "4200"
        )

        let costReference = MaterialQuoteGenerator.makeQuoteItem(from: material, mode: .useMaterialPrice)
        let externalPrice = MaterialQuoteGenerator.makeQuoteItem(
            from: material,
            mode: .overrideAll,
            overridePrice: "5000"
        )
        let pendingPrice = MaterialQuoteGenerator.makeQuoteItem(from: material, mode: .leaveUnpriced)

        #expect(costReference.unitPrice == "4200")
        #expect(externalPrice.unitPrice == "5000")
        #expect(pendingPrice.unitPrice.isEmpty)
        #expect(pendingPrice.status == .draft)
    }

    @Test func contractWritePlanUsesOnlyConfirmedRowsFromSelectedVersion() throws {
        let project = Project(name: "办公楼", location: "", contractAmount: "900")
        let confirmedV1 = QuoteItem(
            name: "钢筋",
            unitPrice: "100",
            quantity: "2",
            unit: "吨",
            notes: "",
            taxRate: "10",
            discountRate: "0",
            versionName: "V1",
            status: .confirmed,
            contractAmount: "210",
            projectId: project.id
        )
        let draftV1 = QuoteItem(
            name: "草稿项",
            unitPrice: "999",
            quantity: "1",
            unit: "项",
            notes: "",
            taxRate: "0",
            discountRate: "0",
            versionName: "V1",
            status: .draft,
            projectId: project.id
        )
        let confirmedV2 = QuoteItem(
            name: "新版",
            unitPrice: "300",
            quantity: "1",
            unit: "项",
            notes: "",
            taxRate: "0",
            discountRate: "0",
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
        #expect(plan.oldAmount == MoneyValue(text: "900"))
        #expect(plan.newAmount == MoneyValue(text: "210"))
        #expect(plan.canApply)
    }

    @Test func contractWritePlanRejectsMissingPriceAndDetectsPreviewChanges() throws {
        let project = Project(name: "厂房", location: "", contractAmount: "100")
        var quote = QuoteItem(
            name: "待补价材料",
            unitPrice: "",
            quantity: "2",
            unit: "件",
            notes: "",
            taxRate: "0",
            discountRate: "0",
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

        quote.unitPrice = "80"
        let refreshedPlan = try #require(QuotationContractWritePlanner.makePlan(
            project: project,
            versionName: "V3",
            quotes: [quote]
        ))
        #expect(refreshedPlan.canApply)
        #expect(refreshedPlan.newAmount == MoneyValue(text: "160"))
        #expect(refreshedPlan != missingPricePlan)
        #expect(refreshedPlan.selectionSignature != missingPricePlan.selectionSignature)
    }

    @Test func contractWritePlanRejectsInvalidQuantityUnlessAnExplicitContractAmountIsValid() throws {
        let project = Project(name: "住宅楼", location: "")
        var invalidQuantityQuote = QuoteItem(
            name: "非法数量",
            unitPrice: "100",
            quantity: "abc",
            unit: "项",
            notes: "",
            taxRate: "0",
            discountRate: "0",
            versionName: "V1",
            status: .confirmed,
            projectId: project.id
        )
        var missingQuantityQuote = QuoteItem(
            name: "缺少数量",
            unitPrice: "100",
            quantity: "",
            unit: "项",
            notes: "",
            taxRate: "0",
            discountRate: "0",
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

        missingQuantityQuote.contractAmount = "250"
        let explicitAmountPlan = try #require(QuotationContractWritePlanner.makePlan(
            project: project,
            versionName: "V1",
            quotes: [invalidQuantityQuote, missingQuantityQuote]
        ))
        #expect(explicitAmountPlan.incompleteItemCount == 1)
        #expect(explicitAmountPlan.newAmount == MoneyValue(text: "250"))

        invalidQuantityQuote.contractAmount = "300"
        let allExplicitAmountsPlan = try #require(QuotationContractWritePlanner.makePlan(
            project: project,
            versionName: "V1",
            quotes: [invalidQuantityQuote, missingQuantityQuote]
        ))
        #expect(allExplicitAmountsPlan.incompleteItemCount == 0)
        #expect(allExplicitAmountsPlan.newAmount == MoneyValue(text: "550"))
        #expect(allExplicitAmountsPlan.canApply)
    }
}
