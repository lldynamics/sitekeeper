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
        #expect(text.contains("[material_items]"))
        #expect(text.contains("\"name\",\"quantity\",\"unit\",\"unit_price\",\"specification\",\"brand\",\"supplier\",\"purchase_status_key\",\"purchase_status_display\",\"arrival_date\",\"amount_raw\",\"amount_display\",\"project_id\""))
        #expect(!text.contains("[材料清单]"))
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
        #expect(text.contains("[material_items]"))
        #expect(text.contains("\"purchase_status_key\",\"purchase_status_display\""))
        #expect(text.contains("\"amount_raw\",\"amount_display\""))
        #expect(!text.contains("[quote_items]"))
    }

    @Test func csvExportsStableRawAndDisplayAmountColumns() throws {
        let projectId = UUID()
        let documentId = UUID()
        let snapshot = BackupSnapshot(
            materialItems: [
                MaterialItem(name: "水泥", quantity: "2", unit: "袋", unitPrice: "35.5", projectId: projectId)
            ],
            quoteItems: [
                QuoteItem(
                    name: "配电箱",
                    unitPrice: "100",
                    quantity: "3",
                    unit: "台",
                    notes: "",
                    taxRate: "0",
                    discountRate: "0",
                    contractAmount: "8888.6",
                    projectId: projectId
                )
            ],
            laborRecords: [
                LaborRecord(date: "2026-05-16", workers: "2", hours: "3.5", unitRate: "120", note: "", projectId: projectId)
            ],
            projects: [],
            dailyLogs: [],
            historyRecords: [],
            projectFinancialRecords: [
                ProjectFinancialRecord(
                    projectId: projectId,
                    date: "2026-05-16 09:00",
                    direction: .income,
                    category: .collection,
                    amount: "1234.5",
                    counterparty: "客户A",
                    linkedDocumentIds: [documentId]
                )
            ],
            projectDocuments: [
                ProjectDocument(
                    projectId: projectId,
                    title: "收据",
                    category: .receipt,
                    fileName: "receipt.pdf",
                    amount: "450"
                )
            ],
            templates: []
        )

        var options = ExportContentOptions()
        options.includeDailyLogs = false
        options.includeProgress = false
        options.includeTodos = false
        options.includeProjectContacts = false
        options.includeProjectDrawings = false
        options.includeWarehouseMovements = false
        options.includeQuickNotes = false

        let csv = ReportBuilder.makeCSV(snapshot: snapshot, options: options)
        let text = try #require(String(data: csv, encoding: .utf8))

        #expect(text.contains("\"contract_amount_raw\",\"contract_amount_display\""))
        #expect(text.contains("\"amount_raw\",\"amount_display\""))
        #expect(text.contains("\"71.00\",\"¥71.00\""))
        #expect(text.contains("\"840.00\",\"¥840.00\""))
        #expect(text.contains("\"8888.60\",\"¥8888.60\""))
        #expect(text.contains("\"1234.50\",\"¥1234.50\""))
        #expect(text.contains("\"450.00\",\"¥450.00\""))

        options.currencyDisplayMode = .usd
        let usdCSV = ReportBuilder.makeCSV(snapshot: snapshot, options: options)
        let usdText = try #require(String(data: usdCSV, encoding: .utf8))
        #expect(usdText.contains("\"71.00\",\"$71.00\""))
        #expect(usdText.contains("\"1234.50\",\"$1234.50\""))

        options.currencyDisplayMode = .numberOnly
        let numberOnlyCSV = ReportBuilder.makeCSV(snapshot: snapshot, options: options)
        let numberOnlyText = try #require(String(data: numberOnlyCSV, encoding: .utf8))
        #expect(numberOnlyText.contains("\"71.00\",\"71.00\""))
        #expect(!numberOnlyText.contains("¥71.00"))
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

    @Test func reportBuilderExportsOperationAuditOnlyWhenEnabled() throws {
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )
        let auditEntry = OperationAuditEntry(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
            timestamp: Date(timeIntervalSince1970: 1_766_000_000).timeIntervalSince1970,
            action: .import,
            outcome: .failed,
            summary: "导入失败",
            detail: "stage=staging_files",
            source: "BackupView"
        )

        var disabledOptions = ExportContentOptions()
        disabledOptions.operationAuditEntries = [auditEntry]
        let disabledCSV = String(data: ReportBuilder.makeCSV(snapshot: snapshot, options: disabledOptions), encoding: .utf8) ?? ""
        #expect(!disabledCSV.contains("[operation_audit_log]"))

        var options = ExportContentOptions()
        options.includeOperationAuditLogs = true
        options.operationAuditEntries = [auditEntry]

        let csv = String(data: ReportBuilder.makeCSV(snapshot: snapshot, options: options), encoding: .utf8) ?? ""
        #expect(csv.contains("[operation_audit_log]"))
        #expect(csv.contains("\"timestamp\",\"action_key\",\"action_display\",\"outcome_key\",\"outcome_display\",\"summary\",\"detail\",\"source\",\"id\""))
        #expect(csv.contains("stage=staging_files"))

        let html = String(data: ReportBuilder.makeExcelHTML(snapshot: snapshot, options: options), encoding: .utf8) ?? ""
        #expect(html.contains("操作审计日志"))
        #expect(html.contains("BackupView"))

        let pdf = ReportBuilder.makePDF(snapshot: snapshot, options: options)
        let extractedPDFText = pdfText(pdf)
        #expect(extractedPDFText.contains("操作审计日志"))
        #expect(extractedPDFText.contains("stage=staging_files"))
    }

    // MARK: - Quotation PDF

    @Test func makeQuotationPDFProducesData() {
        let item = QuoteItem(name: "电缆", unitPrice: "100", quantity: "2", unit: "米", notes: "", taxRate: "0", discountRate: "0", projectId: nil)
        let pdf = ReportBuilder.makeQuotationPDF(title: "报价单", items: [item], projects: [])
        #expect(pdf.count > 100)
    }

    // MARK: - Daily Logs In Full PDF

    @Test func makeFullPDFWithDailyLogsProducesData() {
        let store = makeSampleStore()
        let snapshot = store.makeSnapshot(includePhotoFiles: false)
        var options = ExportContentOptions()
        options.includeDailyLogs = true

        let pdf = ReportBuilder.makePDF(snapshot: snapshot, options: options)
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
        store.replaceProjects([p1, p2])
        store.replaceMaterialItems([
            MaterialItem(name: "水泥", quantity: "10", unit: "吨", unitPrice: "300", projectId: p1.id),
            MaterialItem(name: "钢筋", quantity: "5", unit: "吨", unitPrice: "4000", projectId: p2.id)
        ])
        store.replaceQuickNotes([
            QuickNote(title: "笔记A", content: "项目A备注", projectId: p1.id),
            QuickNote(title: "笔记B", content: "项目B备注", projectId: p2.id)
        ])
        store.replaceProjectContacts([
            ProjectContact(projectId: p1.id, name: "张三", role: .owner, phone: "13800138000"),
            ProjectContact(projectId: p2.id, name: "李四", role: .team, phone: "13900139000")
        ])
        store.replaceProjectFinancialRecords([
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
        ])

        let snapshot = store.makeSnapshot(includePhotoFiles: false)
        let csv = ReportBuilder.makeCSV(snapshot: snapshot, options: ExportContentOptions())
        let text = String(data: csv, encoding: .utf8) ?? ""

        #expect(text.contains("水泥"))
        #expect(text.contains("钢筋"))
        #expect(text.contains("笔记A"))
        #expect(text.contains("笔记B"))
        #expect(text.contains("张三"))
        #expect(text.contains("李四"))
        #expect(text.contains("project_id"))
        #expect(!text.contains("项目ID"))
        #expect(text.contains(p1.id.uuidString))
        #expect(text.contains(p2.id.uuidString))
    }

    @Test func pdfFullExportIncludesContactsFromAllProjects() {
        let store = DataStore()
        let p1 = Project(name: "项目A", location: "地址A", status: .active)
        let p2 = Project(name: "项目B", location: "地址B", status: .active)
        store.replaceProjects([p1, p2])
        store.replaceProjectContacts([
            ProjectContact(projectId: p1.id, name: "张三", role: .owner, phone: "13800138000"),
            ProjectContact(projectId: p2.id, name: "李四", role: .team, phone: "13900139000")
        ])

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
        store.replaceProjects([p1, p2])
        store.replaceMaterialItems([
            MaterialItem(name: "水泥", quantity: "10", unit: "吨", unitPrice: "300", projectId: p1.id),
            MaterialItem(name: "钢筋", quantity: "5", unit: "吨", unitPrice: "4000", projectId: p2.id)
        ])
        store.replaceQuickNotes([
            QuickNote(title: "笔记A", content: "项目A备注", projectId: p1.id),
            QuickNote(title: "笔记B", content: "项目B备注", projectId: p2.id)
        ])

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
        store.replaceProjectContacts([
            ProjectContact(projectId: projectId, name: "联系人测试", role: .owner, phone: "13800138000")
        ])
        store.replaceProjectDrawings([
            ProjectDrawing(projectId: projectId, name: "图纸测试", fileName: "drawing.pdf", fileType: "PDF")
        ])
        store.replaceProjectWarehouseMovements([
            ProjectWarehouseMovement(projectId: projectId, date: "2026-05-04", movementType: .inbound, materialName: "材料测试", quantity: "1")
        ])
        store.replaceQuickNotes([
            QuickNote(title: "随手记测试", content: "现场备注", projectId: projectId)
        ])
        let snapshot = store.makeSnapshot(includePhotoFiles: false)

        var options = ExportContentOptions()
        options.includeProjectContacts = true
        options.includeProjectDrawings = true
        options.includeWarehouseMovements = true
        options.includeQuickNotes = true
        options.includeProjectFinance = true

        let csv = ReportBuilder.makeCSV(snapshot: snapshot, options: options)
        let csvText = String(data: csv, encoding: .utf8) ?? ""
        #expect(csvText.contains("[project_contacts]"))
        #expect(csvText.contains("[project_drawings]"))
        #expect(csvText.contains("[warehouse_movements]"))
        #expect(csvText.contains("[quick_notes]"))
        #expect(csvText.contains("[project_financial_records]"))
        #expect(csvText.contains("[project_document_checklist]"))
        #expect(csvText.contains("\"role_key\",\"role_display\""))
        #expect(csvText.contains("\"movement_type_key\",\"movement_type_display\""))
        #expect(csvText.contains("\"project_id\",\"project_name\",\"category_key\",\"category_display\",\"status_raw\",\"status_display\""))
        #expect(csvText.contains("\"title\",\"category_key\",\"category_display\",\"version_number\",\"version_state\""))
        #expect(csvText.contains("\"replaces_document_id\",\"replaced_by_document_id\",\"submission_status_raw\""))

        let html = ReportBuilder.makeExcelHTML(snapshot: snapshot, options: options)
        let htmlText = String(data: html, encoding: .utf8) ?? ""
        #expect(htmlText.contains("项目联系人"))
        #expect(htmlText.contains("图纸索引"))
        #expect(htmlText.contains("仓库流水"))
        #expect(htmlText.contains("随手记"))
        #expect(htmlText.contains("项目财务流水"))
        #expect(htmlText.contains("施工资料清单"))

        let pdf = ReportBuilder.makePDF(snapshot: snapshot, options: options)
        let extractedPDFText = pdfText(pdf)
        #expect(extractedPDFText.contains("项目联系人"))
        #expect(extractedPDFText.contains("图纸索引"))
        #expect(extractedPDFText.contains("仓库流水"))
        #expect(extractedPDFText.contains("随手记"))
        #expect(extractedPDFText.contains("项目财务流水"))
        #expect(extractedPDFText.contains("施工资料清单"))
    }
}
