import Testing
import Foundation
import PDFKit
@testable import sitekeeper

@MainActor
struct PracticalProjectReportTests {
    private let zone = TimeZone(secondsFromGMT: 8 * 3600)!

    private func date(_ text: String) -> BusinessDateValue { BusinessDateValue(legacyText: text) }
    private func money(_ text: String) -> MoneyValue { NumericInputSupport.money(text) }
    private func period() -> ProjectReportPeriod {
        ProjectReportPeriod(start: date("2026-10-01").date(in: zone)!,
                            end: date("2026-10-07").date(in: zone)!, timeZone: zone)
    }
    private func pdfText(_ data: Data) -> String {
        guard let document = PDFDocument(data: data) else { return "" }
        return (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    }

    @Test func civilDayRangeUsesLocalBoundariesAndRejectsUnknownDates() {
        let range = period()
        #expect(range.contains(date("2026-09-30T16:00:00.000Z")))
        #expect(range.contains(date("2026-10-07T15:59:59.999Z")))
        #expect(!range.contains(date("2026-10-07T16:00:00.000Z")))
        #expect(!range.contains(.unresolved("last week")))
        #expect(!range.contains(.empty))
        let reversed = ProjectReportPeriod(start: date("2026-10-07").date(in: zone)!,
                                           end: date("2026-10-01").date(in: zone)!, timeZone: zone)
        #expect(!reversed.isValid)
        #expect(!reversed.contains(date("2026-10-03")))
    }

    @Test func fieldReportScopesLogsPhotosAndExplicitCompletionsInsideCore() {
        let project = Project(name: "A", location: "")
        let other = UUID()
        let included = DailyLog(date: date("2026-10-01"), weather: "", content: "in-period", workers: 1,
                                photos: [LogPhoto(fileName: "selected.jpg")], projectId: project.id)
        let logs = [included,
                    DailyLog(date: date("2026-10-08"), weather: "", content: "future", workers: 1,
                             photos: [LogPhoto(fileName: "outside.jpg")], projectId: project.id),
                    DailyLog(date: .unresolved("unknown"), weather: "", content: "undated", workers: 1, projectId: project.id),
                    DailyLog(date: date("2026-10-01"), weather: "", content: "other", workers: 1, projectId: other)]
        let done = SiteTodo(title: "explicit", isDone: true, completedAt: date("2026-10-07"), projectId: project.id)
        let noDate = SiteTodo(title: "legacy", isDone: true, projectId: project.id)
        let open = SiteTodo(title: "current", dueDate: date("2026-11-01"), projectId: project.id)
        let todos = [done, noDate, open,
                     SiteTodo(title: "outside", isDone: true, completedAt: date("2026-10-08"), projectId: project.id),
                     SiteTodo(title: "other", isDone: true, completedAt: date("2026-10-02"), projectId: other)]
        let progress = ProgressTask(projectId: project.id, title: "current progress", startDate: date("2026-11-01"),
                                    dueDate: .empty, completion: 0.6, note: "")
        let report = ProjectFieldReport(project: project, period: period(), logs: logs, todos: todos, tasks: [progress])
        #expect(report.logs.map(\.id) == [included.id])
        #expect(report.photos.map { $0.photo.fileName } == ["selected.jpg"])
        #expect(report.completedTodos.map(\.id) == [done.id])
        #expect(report.currentOpenTodos.map(\.id) == [open.id])
        #expect(report.currentProgress.map(\.id) == [progress.id])
        #expect(report.excludedUndatedLogCount == 1)
        #expect(report.excludedUndatedCompletionCount == 1)
    }

    @Test func statementFiltersFormalCollectionsAndPreservesExactDecimalAmounts() {
        let project = Project(name: "A", location: "", contractAmount: money("1000.50"), paidAmount: money("999"))
        let other = UUID()
        let formal = ProjectFinancialRecord(projectId: project.id, date: date("2026-10-02"), direction: .income,
                                             category: .collection, amount: money("0.10"), counterparty: "PRIVATE_CONTACT",
                                             invoiceNumber: "PRIVATE_INVOICE", linkedDocumentIds: [UUID()], note: "PRIVATE_NOTE")
        let receipt = ProjectFinancialRecord(projectId: project.id, date: date("2026-10-07"), direction: .income,
                                              category: .receipt, amount: money("0.20"))
        let records = [formal, receipt,
                       ProjectFinancialRecord(projectId: project.id, date: date("2026-10-08"), direction: .income, category: .collection, amount: money("10")),
                       ProjectFinancialRecord(projectId: project.id, date: .unresolved("unknown"), direction: .income, category: .collection, amount: money("5")),
                       ProjectFinancialRecord(projectId: project.id, date: date("2026-10-02"), direction: .expense, category: .other, amount: money("100"), note: "PRIVATE_EXPENSE"),
                       ProjectFinancialRecord(projectId: project.id, date: date("2026-10-02"), direction: .income, category: .refund, amount: money("100")),
                       ProjectFinancialRecord(projectId: project.id, date: date("2026-10-02"), direction: .income, category: .other, amount: money("100")),
                       ProjectFinancialRecord(projectId: project.id, date: date("2026-10-02"), direction: .income, category: .collection, amount: money("100"), status: .draft),
                       ProjectFinancialRecord(projectId: project.id, date: date("2026-10-02"), direction: .income, category: .collection, amount: money("100"), status: .archived),
                       ProjectFinancialRecord(projectId: other, date: date("2026-10-02"), direction: .income, category: .collection, amount: money("100"))]
        let statement = ProjectCustomerStatement(project: project, period: period(), records: records)
        #expect(statement.periodReceipts.map(\.id) == [formal.id, receipt.id])
        #expect(statement.periodReceived == money("0.30"))
        #expect(statement.currentCumulativePaid == money("15.30"))
        #expect(statement.currentOutstanding == money("985.20"))
        #expect(statement.paidSource == .recordedCollections)
        #expect(statement.undatedReceiptCount == 1)
        let text = ReportBuilder.customerStatementLines(statement).joined(separator: "\n")
        let exported = pdfText(ReportBuilder.makeCustomerStatementPDF(statement))
        #expect(!exported.isEmpty)
        for secret in ["PRIVATE_CONTACT", "PRIVATE_INVOICE", "PRIVATE_NOTE", "PRIVATE_EXPENSE"] {
            #expect(!text.contains(secret))
            #expect(!exported.contains(secret))
        }
    }

    @Test func historicalManualPaidNeverBecomesPeriodIncomeAndOnlyIncomePlansAreExported() {
        let installment = ProjectPaymentInstallment(title: "Customer stage", dueDate: date("2026-10-03"), amount: money("100"))
        let income = ProjectPaymentPlan(title: "Receivable", direction: .income, counterparty: "PRIVATE_CONTACT", installments: [installment])
        let expense = ProjectPaymentPlan(title: "PRIVATE_EXPENSE", direction: .expense, counterparty: "", installments: [installment])
        var archived = income
        archived.id = UUID()
        archived.isArchived = true
        let project = Project(name: "A", location: "", contractAmount: money("500"), paidAmount: money("200.25"),
                              paymentPlans: [income, expense, archived])
        let statement = ProjectCustomerStatement(project: project, period: period(), records: [])
        #expect(statement.paidSource == .historicalManual)
        #expect(statement.currentCumulativePaid == money("200.25"))
        #expect(statement.periodReceived == .zero)
        #expect(statement.periodReceipts.isEmpty)
        #expect(statement.currentOutstanding == money("299.75"))
        #expect(statement.plannedReceipts.map(\.id) == [installment.id])
    }

    @Test func legacySinglePhotoSelectionKeepsStableIdentity() {
        let project = Project(name: "A", location: "")
        let log = DailyLog(date: date("2026-10-01"), weather: "", content: "", workers: 1,
                           photoFileName: "legacy.jpg", projectId: project.id)
        let report = ProjectFieldReport(project: project, period: period(), logs: [log], todos: [], tasks: [])
        #expect(report.photos.map(\.id) == report.photos.map(\.id))
    }

    @Test func longConstructionContentSurvivesPDFPagination() throws {
        let project = Project(name: "A", location: "")
        let text = String(repeating: "施工记录longtext", count: 650) + "VISIBLE_END_MARKER"
        let log = DailyLog(date: date("2026-10-01"), weather: "", content: text, workers: 1, projectId: project.id)
        let report = ProjectFieldReport(project: project, period: period(), logs: [log], todos: [], tasks: [])
        let data = ReportBuilder.makeFieldReportPDF(report, title: "Test")
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount > 1)
        #expect(pdfText(data).replacingOccurrences(of: "\n", with: "").contains("VISIBLE_END_MARKER"))
    }

    @Test func missingSelectedPhotoProducesExplicitCoverAndKeepsOtherPeriodsOut() async throws {
        let project = Project(name: "A", location: "")
        let log = DailyLog(date: date("2026-10-01"), weather: "", content: "", workers: 1,
                           photos: [LogPhoto(fileName: "missing-\(UUID().uuidString).jpg")], projectId: project.id)
        let report = ProjectFieldReport(project: project, period: period(), logs: [log], todos: [], tasks: [])
        let data = await ReportBuilder.makeFieldReportPhotosPDF(report, selectedPhotoIDs: [report.photos[0].id, "outside-period"])
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 2)
        let text = pdfText(data)
        #expect(text.contains(ReportBuilder.loc("照片文件缺失")))
    }
}
