import Foundation
import PDFKit
import Testing
@testable import sitekeeper

@MainActor
struct DecimalReportTests {
    @Test func malformedAmountsAreNotExportedAsTheirNumericPrefix() {
        let record = ProjectFinancialRecord(projectId: UUID(), amount: NumericInputSupport.money("12oops"))
        let snapshot = BackupSnapshot(materialItems: [], quoteItems: [], laborRecords: [], projects: [],
            dailyLogs: [], historyRecords: [], projectFinancialRecords: [record], templates: [])
        let rows = ReportBuilder.projectFinanceCSVRows(snapshot: snapshot, options: ExportContentOptions())
        #expect(rows.count == 4)
        #expect(!rows[2].contains("12.00"))
        #expect(ReportBuilder.amountDisplay(value: record.amount, currencyDisplayMode: .cny) == "12oops")
    }

    @Test func exportsPreserveLargeAmountsAndTheOneCentBalance() throws {
        let project = Project(name: "Decimal report", location: "", contractAmount: NumericInputSupport.money("9007199254740993.01"), paidAmount: NumericInputSupport.money("9007199254740993.00"))
        let records = [
            ProjectFinancialRecord(projectId: project.id, direction: .income, category: .other, amount: NumericInputSupport.money("9007199254740993.01")),
            ProjectFinancialRecord(projectId: project.id, direction: .expense, amount: NumericInputSupport.money("9007199254740993.00"))
        ]
        let snapshot = BackupSnapshot(materialItems: [], quoteItems: [], laborRecords: [], projects: [project],
            dailyLogs: [], historyRecords: [], projectFinancialRecords: records, templates: [])
        let csv = String(decoding: ReportBuilder.makeCSV(snapshot: snapshot, options: ExportContentOptions()), as: UTF8.self)
        let html = String(decoding: ReportBuilder.makeHTMLReport(snapshot: snapshot, options: ExportContentOptions()), as: UTF8.self)
        #expect(csv.contains("9007199254740993.01"))
        #expect(html.contains("9007199254740993.01"))
        let data = ReportBuilder.makeProjectArchiveReportPDF(project: project, materials: [], quotes: [], labor: [], logs: [], tasks: [], todos: [], financialRecords: records)
        let document = try #require(PDFDocument(data: data))
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        #expect(text.contains("9007199254740993.01"))
        #expect(text.contains("0.01"))
    }
}
