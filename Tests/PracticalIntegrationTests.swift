import Foundation
import Testing
@testable import sitekeeper

struct PracticalIntegrationTests {
    @Test func selectiveCloudCopyDropsOnlyUnavailableChangeOrderDocumentReferences() {
        let projectID = UUID()
        let own = ProjectDocument(projectId: projectID, title: "Own", fileName: "own.pdf")
        let foreign = ProjectDocument(projectId: UUID(), title: "Foreign", fileName: "foreign.pdf")
        let order = ProjectChangeOrder(title: "Extra", documentIDs: [own.id, foreign.id])
        let project = Project(id: projectID, name: "Synthetic", location: "", changeOrders: [order])
        let original = BackupSnapshot(materialItems: [], quoteItems: [], laborRecords: [], projects: [project],
            dailyLogs: [], historyRecords: [], projectDocuments: [own, foreign], templates: [])
        let complete = original.applyingCloudBackupContentOptions(.all)
        #expect(complete.projects[0].changeOrders[0].documentIDs == [own.id])
        var options = CloudBackupContentOptions.all
        options.includeProjectFilesAndNotes = false
        let limited = original.applyingCloudBackupContentOptions(options)
        #expect(limited.projectDocuments.isEmpty)
        #expect(limited.projects[0].changeOrders[0].documentIDs.isEmpty)
        #expect(original.projects[0].changeOrders[0].documentIDs == [own.id, foreign.id])
        #expect(original.projectDocuments.count == 2)
    }

    @Test func backupRoundTripPreservesChangeOrdersReviewHistoryAndFinancialAmounts() throws {
        let moment = BusinessDateValue(legacyText: "2026-10-28T10:00:00Z")
        let order = ProjectChangeOrder(title: "Extra work", proposedAmount: 20, confirmedAmount: 15,
            confirmationState: .confirmed, confirmedBy: "Recorder", confirmedAt: moment)
        let project = Project(name: "Synthetic", location: "", contractAmount: 100, paidAmount: 30, changeOrders: [order])
        var todo = SiteTodo(title: "Repair", projectId: project.id)
        todo.enableReview()
        todo.requestCompletion(at: moment)
        let accepted = todo.recordReview(outcome: .passed, reviewer: "Inspector", note: "Accepted", at: moment)
        #expect(accepted)
        let snapshot = BackupSnapshot(materialItems: [], quoteItems: [], laborRecords: [], projects: [project],
            dailyLogs: [], historyRecords: [], siteTodos: [todo], templates: [])
        let restored = try JSONDecoder().decode(BackupSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(restored.projects[0].changeOrders == [order])
        #expect(restored.siteTodos[0].review == todo.review && restored.siteTodos[0].isDone)
        #expect(restored.projects[0].contractAmount == 100 && restored.projects[0].paidAmount == 30)
        #expect(restored.projectFinancialRecords.isEmpty && restored.projectWarehouseMovements.isEmpty)
    }

    @Test func customerStatementDoesNotLeakInternalRecordsAndKeepsCurrentAndPeriodSeparate() {
        let zone = TimeZone(secondsFromGMT: 0)!
        let period = ProjectReportPeriod(start: Date(timeIntervalSince1970: 1790812800),
            end: Date(timeIntervalSince1970: 1791331200), timeZone: zone)
        let project = Project(name: "Public project", location: "PRIVATE_ADDRESS", customerPhone: "PRIVATE_PHONE",
            contractAmount: 1000, paidAmount: 600, materialCost: 999, laborCost: 888)
        let records = [
            ProjectFinancialRecord(projectId: project.id, date: BusinessDateValue(legacyText: "2026-10-02"),
                direction: .income, category: .collection, amount: NumericInputSupport.money("0.10"),
                counterparty: "PRIVATE_CONTACT", invoiceNumber: "PRIVATE_INVOICE", note: "PRIVATE_NOTE"),
            ProjectFinancialRecord(projectId: project.id, date: BusinessDateValue(legacyText: "2026-10-03"),
                direction: .income, category: .receipt, amount: NumericInputSupport.money("0.20")),
            ProjectFinancialRecord(projectId: project.id, date: BusinessDateValue(legacyText: "2026-10-28"),
                direction: .income, category: .collection, amount: 10),
            ProjectFinancialRecord(projectId: UUID(), direction: .income, category: .collection, amount: 500),
            ProjectFinancialRecord(projectId: project.id, direction: .expense, category: .other, amount: 123, note: "PRIVATE_EXPENSE")
        ]
        let statement = ProjectCustomerStatement(project: project, period: period, records: records)
        #expect(statement.periodReceived == NumericInputSupport.money("0.30"))
        #expect(statement.currentCumulativePaid == NumericInputSupport.money("10.30"))
        #expect(statement.currentOutstanding == NumericInputSupport.money("989.70"))
        let text = ReportBuilder.customerStatementLines(statement).joined(separator: "\n")
        for secret in ["PRIVATE_ADDRESS", "PRIVATE_PHONE", "PRIVATE_CONTACT", "PRIVATE_INVOICE", "PRIVATE_NOTE", "PRIVATE_EXPENSE"] {
            #expect(!text.contains(secret))
        }
    }
}
