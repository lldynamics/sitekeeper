import Foundation
import Testing
@testable import sitekeeper

struct DashboardReceivableTests {
    @Test(arguments: ["150", "200"])
    func overpaidProjectCannotOffsetAnotherProjectsDebt(_ paid: String) {
        let overpaid = Project(name: "超收工程", location: "", contractAmount: "100", paidAmount: paid)
        let unpaid = Project(name: "欠款工程", location: "", contractAmount: "100", paidAmount: "0")
        let projects = [overpaid, unpaid]

        let total = ProjectFinancialMetrics.totalReceivableAmount(projects: projects, recordedCollections: [:])
        let individualTotal = projects.reduce(0) { $0 + ProjectFinancialMetrics.unpaidAmount(project: $1, records: []) }
        #expect(total == 100)
        #expect(total == individualTotal)
    }

    @Test func recordedCollectionsAndManualFallbackUseTheSameProjectBoundaries() {
        let overpaid = Project(name: "账目超收", location: "", contractAmount: "100", paidAmount: "20")
        let unpaid = Project(name: "手动收款", location: "", contractAmount: "100.25", paidAmount: "40.1")
        let record = ProjectFinancialRecord(projectId: overpaid.id, direction: .income, category: .collection, amount: "150")
        let recordedCollections = [overpaid.id: MoneyValue(text: record.amount)]

        let total = ProjectFinancialMetrics.totalReceivableAmount(projects: [overpaid, unpaid], recordedCollections: recordedCollections)
        #expect(total == 60.15)
        #expect(ProjectFinancialMetrics.unpaidAmount(project: overpaid, records: [record]) == 0)
        #expect(ProjectFinancialMetrics.totalReceivableAmount(projects: [], recordedCollections: recordedCollections) == 0)
    }
}
