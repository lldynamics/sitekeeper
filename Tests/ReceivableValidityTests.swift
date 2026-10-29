import Foundation
import PDFKit
import Testing
@testable import sitekeeper

struct ReceivableValidityTests {
    @Test(arguments: ["无法辨认", "NaN", String(repeating: "9", count: 39)])
    func invalidContractRemainsUnknownInDetailCardAndAggregate(raw: String) {
        let invalid = NumericInputSupport.money(raw)
        let project = Project(name: "待核对金额", location: "", contractAmount: invalid, paidAmount: 100)
        let detail = ProjectDetailMetrics.unpaidAmount(project: project, paidAmount: 100)
        let card = summary(contract: invalid, paid: 100).unpaidAmount
        let total = ProjectFinancialMetrics.totalReceivableAmount(projects: [project], recordedCollections: [:])
        for value in [detail, card, total, ProjectFinancialMetrics.unpaidAmount(project: project, records: [])] {
            #expect(!value.isValid)
            #expect(value.optionalDecimal == nil)
            #expect(value != .zero)
            #expect(ReportBuilder.money(value) == "—")
        }
    }

    @Test func invalidCollectionDoesNotBecomePaidInFullOrFallBackToManualAmount() {
        let project = Project(name: "回款异常", location: "", contractAmount: 1000, paidAmount: 200)
        let records = [ProjectFinancialRecord(projectId: project.id, direction: .income, category: .collection, amount: NumericInputSupport.money("金额待查"))]
        let paid = ProjectFinancialMetrics.paidAmount(project: project, records: records)
        #expect(!paid.isValid)
        #expect(!ProjectDetailMetrics.unpaidAmount(project: project, paidAmount: paid).isValid)
        #expect(!summary(contract: project.contractAmount, paid: paid).unpaidAmount.isValid)
        #expect(!ProjectFinancialMetrics.totalReceivableAmount(projects: [project], recordedCollections: [project.id: paid]).isValid)
    }

    @Test func emptyFormalCollectionCannotFallBackToManualOrAppearAsZero() {
        let project = Project(name: "缺收款金额", location: "", contractAmount: 1000, paidAmount: 200)
        let records = [ProjectFinancialRecord(projectId: project.id, direction: .income, category: .collection, amount: .empty)]
        let paid = ProjectFinancialMetrics.paidAmount(project: project, records: records)
        #expect(!paid.isValid)
        #expect(ProjectFinancialMetrics.strictCollectionAmount(records) == nil)
        #expect(!ProjectFinancialMetrics.unpaidAmount(project: project, records: records).isValid)
        let explanation = ProjectPaidAmountExplanation(project: project, records: records)
        #expect(explanation.source == .unresolvedCollections)
        #expect(explanation.requiresAmountReview)
    }

    @Test func missingContractAndMissingPaidAmountRemainUnknown() {
        #expect(!ProjectFinancialMetrics.unpaidAmount(contractAmount: .empty, paidAmount: 0).isValid)
        #expect(!ProjectFinancialMetrics.unpaidAmount(contractAmount: 100, paidAmount: .empty).isValid)
        let project = Project(name: "未填合同", location: "")
        #expect(!ProjectFinancialMetrics.unpaidAmount(project: project, records: []).isValid)
        #expect(!ProjectFinancialMetrics.totalReceivableAmount(projects: [project], recordedCollections: [:]).isValid)
    }

    @Test func overflowStaysUnknownWhileValidOverpaymentClampsToZero() throws {
        let huge = MoneyValue(try #require(Decimal(string: "1e127")))
        #expect(!ProjectFinancialMetrics.unpaidAmount(contractAmount: huge, paidAmount: MoneyValue(-1)).isValid)
        #expect(ProjectFinancialMetrics.unpaidAmount(contractAmount: 100, paidAmount: 120) == .zero)
        #expect(ProjectFinancialMetrics.unpaidAmount(contractAmount: 100, paidAmount: 100) == .zero)
        #expect(ProjectFinancialMetrics.unpaidAmount(contractAmount: 100, paidAmount: 20) == 80)
    }

    @Test func largeExactAmountsKeepCentsAcrossAllPresentations() {
        let contract = NumericInputSupport.money("9007199254740993.01")
        let paid = NumericInputSupport.money("9007199254740993.00")
        let project = Project(name: "分币", location: "", contractAmount: contract, paidAmount: paid)
        let expected = NumericInputSupport.money("0.01")
        #expect(ProjectDetailMetrics.unpaidAmount(project: project, paidAmount: paid) == expected)
        #expect(summary(contract: contract, paid: paid).unpaidAmount == expected)
        #expect(ProjectFinancialMetrics.totalReceivableAmount(projects: [project], recordedCollections: [:]) == expected)
    }

    @Test(arguments: [false, true]) @MainActor
    func archiveAndDeliveryPDFsDoNotPresentUnknownReceivablesAsZero(invalidPaid: Bool) throws {
        let invalid = NumericInputSupport.money("待核对")
        let project = Project(name: "异常金额导出", location: "", contractAmount: invalidPaid ? 1000 : invalid, paidAmount: invalidPaid ? invalid : 100)
        let expected = ReportBuilder.locFormat("合同金额: %@  已收: %@  未收: %@",
            ReportBuilder.money(project.contractAmount), ReportBuilder.money(project.paidAmount), "—")
            .filter { !$0.isWhitespace }
        let reports = [
            ReportBuilder.makeProjectArchiveReportPDF(project: project, materials: [], quotes: [], labor: [], logs: [], tasks: [], todos: []),
            ReportBuilder.makeProjectPackagePDF(project: project, materials: [], quotes: [], labor: [], logs: [], tasks: [], todos: [])
        ]
        for data in reports {
            let document = try #require(PDFDocument(data: data))
            let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined().filter { !$0.isWhitespace }
            #expect(text.contains(expected))
        }
    }

    private func summary(contract: MoneyValue, paid: MoneyValue) -> ProjectBusinessSummary {
        ProjectBusinessSummary(quoteTotal: 0, contractAmount: contract, paidAmount: paid,
            receivableAmount: ProjectFinancialMetrics.unpaidAmount(contractAmount: contract, paidAmount: paid),
            recentCollection: nil, materialCost: 0, laborCostAmount: 0, pendingMaterialCount: 0, unpricedQuoteCount: 0)
    }
}
