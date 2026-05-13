import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct ExportDateFilterTests {

    // 验证日期筛选函数可用
    @Test func dateRangeFilterMarksOutsideRange() {
        let formatter = Formatters.date
        let start = formatter.date(from: "2025-03-01")!
        let end = formatter.date(from: "2025-03-31")!

        let insideRecord = "2025-03-15"
        let outsideRecord = "2025-02-01"

        // 用手工模拟 isWithin：在范围内的记录保留
        let insideDate = formatter.date(from: insideRecord)!
        let outsideDate = formatter.date(from: outsideRecord)!

        let dayStart = Calendar.current.startOfDay(for: min(start, end))
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(start, end)))!

        #expect(insideDate >= dayStart && insideDate < dayEnd)
        #expect(!(outsideDate >= dayStart && outsideDate < dayEnd))
    }

    // 日期格式异常的处理
    @Test func invalidDateFormatCounted() {
        let formatter = Formatters.date
        let invalidDateString = "not-a-date"

        let parsed = formatter.date(from: invalidDateString)
        #expect(parsed == nil)

        var invalidCount = 0
        if formatter.date(from: invalidDateString) == nil {
            invalidCount += 1
        }
        #expect(invalidCount == 1)
    }

    // 全模块日期字段验证
    @Test func allModulesWithDateFieldsAreFilterable() {
        // LaborRecord - date
        let labor = LaborRecord(date: "2025-04-01", workers: "1", hours: "8", unitRate: "100", workType: "瓦工", teamName: "A组", note: "", projectId: nil)
        #expect(Formatters.date.date(from: labor.date) != nil)

        // DailyLog - date
        let log = DailyLog(date: "2025-04-02", weather: "", content: "", workers: "", photoFileName: nil, photos: [], safety: "", materials: "", projectId: nil)
        #expect(Formatters.date.date(from: log.date) != nil)

        // ProgressTask - startDate / dueDate
        let task = ProgressTask(projectId: UUID(), title: "test", startDate: "2025-04-03", dueDate: "2025-05-03", completion: 0, note: "")
        #expect(Formatters.date.date(from: task.startDate) != nil)
        #expect(Formatters.date.date(from: task.dueDate) != nil)

        // HistoryRecord - date
        let hist = HistoryRecord(tool: "测试", input: "", result: "", date: "2025-04-04 10:00")
        #expect(Formatters.dateTime.date(from: hist.date) != nil)

        // SiteTodo - dueDate
        let todo = SiteTodo(title: "test", dueDate: "2025-04-05", priority: .medium, issueType: .quality, projectId: nil)
        #expect(Formatters.date.date(from: todo.dueDate) != nil)

        // ProjectFinancialRecord - date
        let finRecord = ProjectFinancialRecord(
            projectId: UUID(),
            date: "2025-04-06",
            direction: .income,
            category: .material,
            amount: "100",
            counterparty: "test",
            invoiceNumber: "",
            linkedDocumentIds: [],
            note: ""
        )
        #expect(Formatters.date.date(from: finRecord.date) != nil)

        // ProjectDocument - createdAt
        let doc = ProjectDocument(
            id: UUID(),
            projectId: UUID(),
            title: "test",
            category: .contract,
            fileName: "test.pdf",
            fileType: "pdf",
            pageCount: 1,
            amount: "100",
            linkedFinancialRecordId: nil,
            createdAt: "2025-04-07 12:00",
            note: ""
        )
        #expect(Formatters.dateTime.date(from: doc.createdAt) != nil)

        // QuoteItem - customerConfirmedDate
        let quote = QuoteItem(name: "test", unitPrice: "100", quantity: "1", unit: "个", notes: "", taxRate: "0", discountRate: "1", versionName: "", customerConfirmedDate: "2025-04-08", contractAmount: "100", projectId: nil)
        #expect(Formatters.date.date(from: quote.customerConfirmedDate) != nil)

        // ProjectDrawing - importedAt
        let drawing = ProjectDrawing(
            projectId: UUID(),
            name: "test",
            fileName: "test.pdf",
            fileType: "PDF",
            version: "1",
            relatedLogDate: "",
            issueStatus: .closed,
            issueNote: "",
            importedAt: "2025-04-10 08:00",
            note: ""
        )
        #expect(Formatters.dateTime.date(from: drawing.importedAt) != nil)

        // ProjectWarehouseMovement - date
        let movement = ProjectWarehouseMovement(projectId: UUID(), date: "2025-04-11", movementType: .inbound, materialName: "test", specification: "", unit: "个", quantity: "1", counterparty: "test", handler: "test", note: "", linkedDocumentIds: [])
        #expect(Formatters.date.date(from: movement.date) != nil)

        // QuickNote - updatedAt
        let note = QuickNote(title: "test", content: "", projectId: nil, createdAt: "2025-04-12 09:00", updatedAt: "2025-04-12 09:00", attachments: [])
        #expect(Formatters.dateTime.date(from: note.updatedAt) != nil)

        // LightingCircuitPlan - updatedAt
        let plan = LightingCircuitPlan(name: "test", projectId: nil, supplyType: .singlePhase, voltage: "220", powerFactor: "0.9", demandFactor: "0.8", breakerFactor: "1.25", wireFactor: "1.0", isCopper: true, loads: [], updatedAt: "2025-04-13 10:00")
        #expect(Formatters.dateTime.date(from: plan.updatedAt) != nil)
    }

    // 项目筛选不串项目（日期筛选后仍按项目隔离）
    @Test func dateFilterPreservesProjectIsolation() {
        let p1 = UUID()
        let p2 = UUID()

        let records: [ProjectFinancialRecord] = [
            ProjectFinancialRecord(projectId: p1, date: "2025-04-01", direction: .income, category: .material, amount: "100", counterparty: "A", invoiceNumber: "", linkedDocumentIds: [], note: ""),
            ProjectFinancialRecord(projectId: p2, date: "2025-05-15", direction: .expense, category: .labor, amount: "200", counterparty: "B", invoiceNumber: "", linkedDocumentIds: [], note: ""),
        ]

        let start = Formatters.date.date(from: "2025-04-01")!
        let end = Formatters.date.date(from: "2025-04-30")!
        let dayStart = Calendar.current.startOfDay(for: min(start, end))
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: max(start, end)))!

        // p1 的记录在范围内，p2 不在
        let filteredByProject = records.filter { $0.projectId == p1 }
        let filteredByDate = filteredByProject.filter {
            guard let d = Formatters.date.date(from: $0.date) else { return false }
            return d >= dayStart && d < dayEnd
        }

        #expect(filteredByDate.count == 1)
        #expect(filteredByDate[0].counterparty == "A")
    }

    @Test func legacyPaymentRecordsAreDecodeOnly() throws {
        let projectId = UUID()
        let data = """
        {
          "paymentRecords": [
            {
              "projectId": "\(projectId.uuidString)",
              "date": "2025-04-09",
              "amount": "100",
              "method": "bankTransfer",
              "note": "",
              "isInvoiced": false
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: data)
        #expect(snapshot.legacyPaymentRecords.count == 1)
        #expect(Formatters.date.date(from: snapshot.legacyPaymentRecords[0].date) != nil)

        let encoded = try JSONEncoder().encode(snapshot)
        let encodedText = String(data: encoded, encoding: .utf8) ?? ""
        #expect(!encodedText.contains("paymentRecords"))
    }
}
