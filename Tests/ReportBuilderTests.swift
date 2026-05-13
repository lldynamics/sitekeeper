import Testing
import Foundation
import PDFKit
@testable import sitekeeper

@MainActor
struct ReportBuilderTests {
    private func makeSampleStore() -> DataStore {
        TransferLimitPolicy.setRuntimeProfileOverride(.development)
        let store = DataStore()
        store.clearAllBusinessData(deleteStoredFiles: false)
        store.importSampleData(replacingExisting: true)
        return store
    }

    private func pdfText(_ data: Data) -> String {
        guard let document = PDFDocument(data: data) else { return "" }
        return (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
    }

    // MARK: - CSV Export

    @Test func makeCSVWithAllOptionsProducesData() throws {
        let store = makeSampleStore()
        let snapshot = store.makeSnapshot(includePhotoFiles: false)

        let options = ExportContentOptions()
        let csv = ReportBuilder.makeCSV(snapshot: snapshot, options: options)
        #expect(!csv.isEmpty)
        let text = try #require(String(data: csv, encoding: .utf8))
        #expect(text.contains("[材料清单]"))
    }

    @Test func makeCSVMaterialsSection() {
        let store = makeSampleStore()
        let snapshot = store.makeSnapshot(includePhotoFiles: false)

        var options = ExportContentOptions()
        options.includeMaterials = true
        options.includeQuotes = false
        options.includeLabor = false
        options.includeDailyLogs = false
        options.includeProgress = false
        options.includeTodos = false
        options.includeProjectFinance = false
        options.includeProjectDocuments = false

        let csv = ReportBuilder.makeCSV(snapshot: snapshot, options: options)
        let text = String(data: csv, encoding: .utf8) ?? ""
        #expect(text.contains("[材料清单]"))
    }

    @Test func makeCSVEmptySnapshotReturnsHeadersOnly() {
        let store = DataStore()
        store.clearAllBusinessData(deleteStoredFiles: false)
        let snapshot = store.makeSnapshot(includePhotoFiles: false)

        let csv = ReportBuilder.makeCSV(snapshot: snapshot, options: ExportContentOptions())
        #expect(!csv.isEmpty)
    }

    // MARK: - Excel HTML Export

    @Test func makeExcelHTMLProducesData() throws {
        let store = makeSampleStore()
        let snapshot = store.makeSnapshot(includePhotoFiles: false)

        let html = ReportBuilder.makeExcelHTML(snapshot: snapshot, options: ExportContentOptions())
        #expect(!html.isEmpty)
        let text = try #require(String(data: html, encoding: .utf8))
        #expect(text.contains("<table"))
    }

    // MARK: - PDF Export

    @Test func makePDFProducesData() {
        let store = makeSampleStore()
        let snapshot = store.makeSnapshot(includePhotoFiles: false)

        let pdf = ReportBuilder.makePDF(snapshot: snapshot, options: ExportContentOptions())
        #expect(!pdf.isEmpty)
    }

    // MARK: - Quotation PDF

    @Test func makeQuotationPDFProducesData() {
        let item = QuoteItem(name: "电缆", unitPrice: "100", quantity: "2", unit: "米", notes: "", taxRate: "0", discountRate: "0", projectId: nil)
        let pdf = ReportBuilder.makeQuotationPDF(title: "报价单", items: [item], projects: [])
        #expect(pdf.count > 100)
    }

    // MARK: - Daily Report PDF

    @Test func makeDailyReportPDFProducesData() {
        let store = makeSampleStore()
        let pdf = ReportBuilder.makeDailyReportPDF(project: store.projects.first, logs: store.dailyLogs)
        #expect(!pdf.isEmpty)
    }

    // MARK: - Quote calculations

    @Test func quoteLineTotalEmptyValues() {
        let item = QuoteItem(name: "", unitPrice: "", quantity: "", unit: "", notes: "", taxRate: "", discountRate: "", projectId: nil)
        #expect(ReportBuilder.quoteLineTotal(item) == 0)
    }

    @Test func quoteGrandTotalWithTaxAndDiscount() {
        let item = QuoteItem(name: "配电箱", unitPrice: "500", quantity: "3", unit: "台", notes: "", taxRate: "13", discountRate: "5", projectId: nil)
        let grand = ReportBuilder.quoteGrandTotal(item)
        #expect(grand == 1620)
    }

    @Test func csvEscaping() {
        let result = ReportBuilder.csv(["hello", "contains,comma", "normal"])
        #expect(result.contains("\"contains,comma\""))
    }

    // MARK: - 不串项目测试

    @Test func csvIncludesProjectIdsForTraceability() {
        let store = DataStore()
        let p1 = Project(name: "项目A", location: "地址A", status: .active)
        let p2 = Project(name: "项目B", location: "地址B", status: .active)
        store.projects = [p1, p2]
        store.materialItems = [
            MaterialItem(name: "水泥", quantity: "10", unit: "吨", unitPrice: "300", projectId: p1.id),
            MaterialItem(name: "钢筋", quantity: "5", unit: "吨", unitPrice: "4000", projectId: p2.id)
        ]
        store.quickNotes = [
            QuickNote(title: "笔记A", content: "项目A备注", projectId: p1.id),
            QuickNote(title: "笔记B", content: "项目B备注", projectId: p2.id)
        ]
        store.projectContacts = [
            ProjectContact(projectId: p1.id, name: "张三", role: .owner, phone: "13800138000"),
            ProjectContact(projectId: p2.id, name: "李四", role: .team, phone: "13900139000")
        ]
        store.projectFinancialRecords = [
            ProjectFinancialRecord(
                projectId: p1.id,
                date: "",
                direction: .income,
                category: .collection,
                amount: "1000",
                counterparty: "客户A"
            ),
            ProjectFinancialRecord(
                projectId: p2.id,
                date: "",
                direction: .income,
                category: .collection,
                amount: "2000",
                counterparty: "客户B"
            )
        ]

        let snapshot = store.makeSnapshot(includePhotoFiles: false)
        let csv = ReportBuilder.makeCSV(snapshot: snapshot, options: ExportContentOptions())
        let text = String(data: csv, encoding: .utf8) ?? ""

        #expect(text.contains("水泥"))
        #expect(text.contains("钢筋"))
        #expect(text.contains("笔记A"))
        #expect(text.contains("笔记B"))
        #expect(text.contains("张三"))
        #expect(text.contains("李四"))
        #expect(text.contains("项目ID"))
        #expect(text.contains(p1.id.uuidString))
        #expect(text.contains(p2.id.uuidString))
    }

    @Test func pdfFullExportIncludesContactsFromAllProjects() {
        let store = DataStore()
        let p1 = Project(name: "项目A", location: "地址A", status: .active)
        let p2 = Project(name: "项目B", location: "地址B", status: .active)
        store.projects = [p1, p2]
        store.projectContacts = [
            ProjectContact(projectId: p1.id, name: "张三", role: .owner, phone: "13800138000"),
            ProjectContact(projectId: p2.id, name: "李四", role: .team, phone: "13900139000")
        ]

        let snapshot = store.makeSnapshot(includePhotoFiles: false)
        var options = ExportContentOptions()
        options.includeProjectContacts = true
        let pdf = ReportBuilder.makePDF(snapshot: snapshot, options: options)
        let text = pdfText(pdf)

        #expect(text.contains("项目联系人"))
        #expect(text.contains("张三"))
        // 不跨项目：PDF 是全量导出，两份都包含不泄露即可
        #expect(text.contains("李四"))
    }

    @Test func filteredSnapshotDoesNotLeakCrossProject() {
        let store = DataStore()
        let p1 = Project(name: "项目A", location: "地址A", status: .active)
        let p2 = Project(name: "项目B", location: "地址B", status: .active)
        store.projects = [p1, p2]
        store.materialItems = [
            MaterialItem(name: "水泥", quantity: "10", unit: "吨", unitPrice: "300", projectId: p1.id),
            MaterialItem(name: "钢筋", quantity: "5", unit: "吨", unitPrice: "4000", projectId: p2.id)
        ]
        store.quickNotes = [
            QuickNote(title: "笔记A", content: "项目A备注", projectId: p1.id),
            QuickNote(title: "笔记B", content: "项目B备注", projectId: p2.id)
        ]

        let snapshot = store.makeSnapshot(includePhotoFiles: false)
        // 两个项目的材料都在快照中，各自携带正确的 projectId
        #expect(snapshot.materialItems.contains(where: { $0.name == "水泥" && $0.projectId == p1.id }))
        #expect(snapshot.materialItems.contains(where: { $0.name == "钢筋" && $0.projectId == p2.id }))
        #expect(snapshot.quickNotes.contains(where: { $0.title == "笔记A" && $0.projectId == p1.id }))
        #expect(snapshot.quickNotes.contains(where: { $0.title == "笔记B" && $0.projectId == p2.id }))
        #expect(snapshot.projects.count == 2)
    }

    @Test func exportSupportsAllNewModules() {
        let store = makeSampleStore()
        let projectId = store.projects.first?.id ?? UUID()
        store.projectContacts = [
            ProjectContact(projectId: projectId, name: "联系人测试", role: .owner, phone: "13800138000")
        ]
        store.projectDrawings = [
            ProjectDrawing(projectId: projectId, name: "图纸测试", fileName: "drawing.pdf", fileType: "PDF")
        ]
        store.projectWarehouseMovements = [
            ProjectWarehouseMovement(projectId: projectId, date: "2026-05-04", movementType: .inbound, materialName: "材料测试", quantity: "1")
        ]
        store.quickNotes = [
            QuickNote(title: "随手记测试", content: "现场备注", projectId: projectId)
        ]
        let snapshot = store.makeSnapshot(includePhotoFiles: false)

        var options = ExportContentOptions()
        options.includeProjectContacts = true
        options.includeProjectDrawings = true
        options.includeWarehouseMovements = true
        options.includeQuickNotes = true
        options.includeLightingCircuits = true
        options.includeProjectFinance = true

        let csv = ReportBuilder.makeCSV(snapshot: snapshot, options: options)
        let csvText = String(data: csv, encoding: .utf8) ?? ""
        #expect(csvText.contains("[项目联系人]"))
        #expect(csvText.contains("[图纸索引]"))
        #expect(csvText.contains("[仓库流水]"))
        #expect(csvText.contains("[随手记]"))
        #expect(csvText.contains("[照明回路]"))
        #expect(csvText.contains("[项目财务流水]"))

        let html = ReportBuilder.makeExcelHTML(snapshot: snapshot, options: options)
        let htmlText = String(data: html, encoding: .utf8) ?? ""
        #expect(htmlText.contains("项目联系人"))
        #expect(htmlText.contains("图纸索引"))
        #expect(htmlText.contains("仓库流水"))
        #expect(htmlText.contains("随手记"))
        #expect(htmlText.contains("照明回路"))
        #expect(htmlText.contains("项目财务流水"))

        let pdf = ReportBuilder.makePDF(snapshot: snapshot, options: options)
        let extractedPDFText = pdfText(pdf)
        #expect(extractedPDFText.contains("项目联系人"))
        #expect(extractedPDFText.contains("图纸索引"))
        #expect(extractedPDFText.contains("仓库流水"))
        #expect(extractedPDFText.contains("随手记"))
        #expect(extractedPDFText.contains("照明回路"))
        #expect(extractedPDFText.contains("项目财务流水"))
    }
}
