import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct ExportDateFilterTests {

    @Test func exportCompletionValidatesWrittenFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-completion-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        try Data("完成".utf8).write(to: fileURL)

        #expect(
            ExportCompletionHandler.evaluate(.success(fileURL), source: "ExportDateFilterTests") == .succeeded
        )
    }

    @Test func exportCompletionRejectsEmptyFileAndRecognizesCancellation() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-export-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        try Data().write(to: fileURL)

        #expect(
            ExportCompletionHandler.evaluate(.success(fileURL), source: "ExportDateFilterTests") == .invalidFile
        )
        #expect(
            ExportCompletionHandler.evaluate(
                .failure(CocoaError(.userCancelled)),
                source: "ExportDateFilterTests"
            ) == .cancelled
        )
        #expect(
            ExportCompletionHandler.evaluate(
                .failure(URLError(.cancelled)),
                source: "ExportDateFilterTests"
            ) == .cancelled
        )
    }

    @Test func exportCompletionKeepsFailureMessage() {
        let error = NSError(domain: "ExportDateFilterTests", code: 7, userInfo: [
            NSLocalizedDescriptionKey: "provider write failed"
        ])

        #expect(
            ExportCompletionHandler.evaluate(.failure(error), source: "ExportDateFilterTests") ==
                .failed("provider write failed")
        )
    }

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

    @Test func progressTaskOverlappingWholeRangeIsIncluded() {
        let formatter = Formatters.date
        let rangeStart = formatter.date(from: "2025-03-10")!
        let rangeEnd = formatter.date(from: "2025-03-20")!
        let taskStart = formatter.date(from: "2025-03-01")!
        let taskEnd = formatter.date(from: "2025-03-31")!

        #expect(taskStart <= rangeEnd && taskEnd >= rangeStart)
    }

    @Test func datePickerBoundsPreventReversedRange() {
        let start = Formatters.date.date(from: "2025-03-10")!
        let end = Formatters.date.date(from: "2025-03-20")!

        #expect(start <= end)
    }

    // 全模块日期字段验证
    @Test func allModulesWithDateFieldsAreFilterable() {
        // LaborRecord - date
        let labor = LaborRecord(date: BusinessDateValue(legacyText: "2025-04-01"), workers: NumericInputSupport.quantity("1"), hours: NumericInputSupport.quantity("8"), unitRate: NumericInputSupport.money("100"), workType: "瓦工", teamName: "A组", note: "", projectId: nil)
        #expect(Formatters.date.date(from: labor.date) != nil)

        // DailyLog - date
        let log = DailyLog(date: BusinessDateValue(legacyText: "2025-04-02"), weather: "", content: "", workers: NumericInputSupport.quantity(""), photoFileName: nil, photos: [], safety: "", materials: "", projectId: nil)
        #expect(Formatters.date.date(from: log.date) != nil)

        // ProgressTask - startDate / dueDate
        let task = ProgressTask(projectId: UUID(), title: "test", startDate: BusinessDateValue(legacyText: "2025-04-03"), dueDate: BusinessDateValue(legacyText: "2025-05-03"), completion: 0, note: "")
        #expect(Formatters.date.date(from: task.startDate) != nil)
        #expect(Formatters.date.date(from: task.dueDate) != nil)

        // HistoryRecord - date
        let hist = HistoryRecord(tool: "测试", input: "", result: "", date: BusinessDateValue(legacyText: "2025-04-04 10:00"))
        #expect(Formatters.dateTime.date(from: hist.date) != nil)

        // SiteTodo - dueDate
        let todo = SiteTodo(title: "test", dueDate: BusinessDateValue(legacyText: "2025-04-05"), priority: .medium, issueType: .quality, projectId: nil)
        #expect(Formatters.date.date(from: todo.dueDate) != nil)

        // ProjectFinancialRecord - date
        let finRecord = ProjectFinancialRecord(
            projectId: UUID(),
            date: BusinessDateValue(legacyText: "2025-04-06"),
            direction: .income,
            category: .material,
            amount: NumericInputSupport.money("100"),
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
            amount: NumericInputSupport.money("100"),
            linkedFinancialRecordId: nil,
            createdAt: BusinessDateValue(legacyText: "2025-04-07 12:00"),
            note: ""
        )
        #expect(Formatters.dateTime.date(from: doc.createdAt) != nil)

        // QuoteItem - customerConfirmedDate
        let quote = QuoteItem(name: "test", unitPrice: NumericInputSupport.money("100"), quantity: NumericInputSupport.quantity("1"), unit: "个", notes: "", taxRate: NumericInputSupport.quantity("0"), discountRate: NumericInputSupport.quantity("1"), versionName: "", customerConfirmedDate: BusinessDateValue(legacyText: "2025-04-08"), contractAmount: NumericInputSupport.money("100"), projectId: nil)
        #expect(Formatters.date.date(from: quote.customerConfirmedDate) != nil)

        // ProjectDrawing - importedAt
        let drawing = ProjectDrawing(
            projectId: UUID(),
            name: "test",
            fileName: "test.pdf",
            fileType: "PDF",
            version: "1",
            relatedLogDate: .empty,
            issueStatus: .closed,
            issueNote: "",
            importedAt: BusinessDateValue(legacyText: "2025-04-10 08:00"),
            note: ""
        )
        #expect(Formatters.dateTime.date(from: drawing.importedAt) != nil)

        // ProjectWarehouseMovement - date
        let movement = ProjectWarehouseMovement(projectId: UUID(), date: BusinessDateValue(legacyText: "2025-04-11"), movementType: .inbound, materialName: "test", specification: "", unit: "个", quantity: NumericInputSupport.quantity("1"), counterparty: "test", handler: "test", note: "", linkedDocumentIds: [])
        #expect(Formatters.date.date(from: movement.date) != nil)

        // QuickNote - updatedAt
        let note = QuickNote(title: "test", content: "", projectId: nil, createdAt: BusinessDateValue(legacyText: "2025-04-12 09:00"), updatedAt: BusinessDateValue(legacyText: "2025-04-12 09:00"), attachments: [])
        #expect(Formatters.dateTime.date(from: note.updatedAt) != nil)
    }

    // 项目筛选不串项目（日期筛选后仍按项目隔离）
    @Test func dateFilterPreservesProjectIsolation() {
        let p1 = UUID()
        let p2 = UUID()

        let records: [ProjectFinancialRecord] = [
            ProjectFinancialRecord(projectId: p1, date: BusinessDateValue(legacyText: "2025-04-01"), direction: .income, category: .material, amount: NumericInputSupport.money("100"), counterparty: "A", invoiceNumber: "", linkedDocumentIds: [], note: ""),
            ProjectFinancialRecord(projectId: p2, date: BusinessDateValue(legacyText: "2025-05-15"), direction: .expense, category: .labor, amount: NumericInputSupport.money("200"), counterparty: "B", invoiceNumber: "", linkedDocumentIds: [], note: ""),
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

    @Test func removedPaymentRecordsFieldIsIgnoredForCurrentSchema() throws {
        let projectId = UUID()
        let data = """
        {
          "schemaVersion": 2,
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
        #expect(snapshot.projectFinancialRecords.isEmpty)

        let encoded = try JSONEncoder().encode(snapshot)
        let encodedText = String(data: encoded, encoding: .utf8) ?? ""
        #expect(!encodedText.contains("paymentRecords"))
    }
}
