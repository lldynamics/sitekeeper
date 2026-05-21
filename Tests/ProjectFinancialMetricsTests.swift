import Foundation
import Testing
@testable import sitekeeper

struct ProjectFinancialMetricsTests {
    @Test func initializerNormalizesDirectionAndCategory() {
        let record = ProjectFinancialRecord(
            projectId: UUID(),
            direction: .income,
            category: .material
        )

        #expect(record.normalizedDirection == .income)
        #expect(record.normalizedCategory == .collection)
        #expect(record.normalizedStatus == .active)
    }

    @Test func businessMetricsIgnoreDraftAndArchivedRecords() {
        let projectId = UUID()
        let records = [
            ProjectFinancialRecord(
                projectId: projectId,
                direction: .income,
                category: .collection,
                amount: "100",
                status: .active
            ),
            ProjectFinancialRecord(
                projectId: projectId,
                direction: .income,
                category: .collection,
                amount: "200",
                status: .draft
            ),
            ProjectFinancialRecord(
                projectId: projectId,
                direction: .expense,
                category: .material,
                amount: "300",
                status: .archived
            ),
            ProjectFinancialRecord(
                projectId: projectId,
                direction: .expense,
                category: .material,
                amount: "50",
                status: .active
            )
        ]

        #expect(ProjectFinancialMetrics.income(records) == 100)
        #expect(ProjectFinancialMetrics.expense(records) == 50)
        #expect(ProjectFinancialMetrics.collectionAmount(records) == 100)
    }

    @Test func metricsParserUsesNormalizedNonNegativeAmounts() {
        let projectId = UUID()
        let records = [
            ProjectFinancialRecord(
                projectId: projectId,
                date: "2026-05-08 10:30",
                direction: .income,
                category: .collection,
                amount: "1200.5"
            ),
            ProjectFinancialRecord(
                projectId: projectId,
                date: "2026-05-09",
                direction: .expense,
                category: .material,
                amount: "300.25"
            )
        ]

        #expect(ProjectFinancialMetrics.income(records) == 1200.5)
        #expect(ProjectFinancialMetrics.expense(records) == 300.25)
        #expect(ProjectFinancialMetrics.latestCollection(records: records, projectName: { _ in nil })?.date == "2026-05-08 10:30")
    }

    @Test func projectFinanceCSVExportsStatusColumn() throws {
        let projectId = UUID()
        let record = ProjectFinancialRecord(
            projectId: projectId,
            date: "2026-05-09 10:30",
            direction: .income,
            category: .collection,
            amount: "100",
            counterparty: "客户",
            invoiceNumber: "R-1",
            status: .draft,
            dueDate: "2026-05-12",
            reminderStatus: .pending,
            note: "待确认"
        )
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [],
            dailyLogs: [],
            historyRecords: [],
            projectFinancialRecords: [record],
            templates: []
        )

        var options = ExportContentOptions()
        options.includeMaterials = false
        options.includeQuotes = false
        options.includeLabor = false
        options.includeDailyLogs = false
        options.includeProgress = false
        options.includeTodos = false
        options.includeProjectDocuments = false
        options.includeProjectContacts = false
        options.includeProjectDrawings = false
        options.includeWarehouseMovements = false
        options.includeQuickNotes = false
        options.includeProjectFinance = true

        let csv = ReportBuilder.makeCSV(snapshot: snapshot, options: options)
        let text = try #require(String(data: csv, encoding: .utf8))

        #expect(text.contains("\"date\",\"direction_key\",\"direction_display\",\"category_key\",\"category_display\",\"status_key\",\"status_display\",\"due_date\",\"reminder_status_key\",\"reminder_status_display\",\"amount_raw\",\"amount_display\""))
        #expect(text.contains("\"draft\",\"草稿\""))
        #expect(text.contains("2026-05-12"))
        #expect(text.contains("\"pending\",\"待提醒\""))
        #expect(text.contains("\"100.00\",\"¥100.00\""))
        #expect(text.contains(projectId.uuidString))
    }

    @Test func dueReminderFlagsRespectStatusAndDate() {
        let overdue = ProjectFinancialRecord(
            projectId: UUID(),
            dueDate: "2000-01-01",
            reminderStatus: .pending
        )
        let done = ProjectFinancialRecord(
            projectId: UUID(),
            dueDate: "2000-01-01",
            reminderStatus: .done
        )
        let none = ProjectFinancialRecord(projectId: UUID(), dueDate: "2000-01-01")

        #expect(overdue.hasDueReminder)
        #expect(overdue.isDueReminderOpen)
        #expect(overdue.isDueReminderOverdue)
        #expect(!done.isDueReminderOpen)
        #expect(!none.hasDueReminder)
    }

    @Test func duplicateDetectorMatchesNormalizedInvoiceNumber() {
        let projectId = UUID()
        let existing = ProjectFinancialRecord(
            projectId: projectId,
            date: "2026-05-09 09:00",
            direction: .expense,
            amount: "1200.50",
            invoiceNumber: "fp-2026-000188"
        )
        let draft = ProjectFinancialRecord(
            projectId: projectId,
            date: "2026-05-10 10:00",
            direction: .expense,
            amount: "800",
            invoiceNumber: "FP2026000188"
        )

        let warnings = ProjectFinancialDuplicateDetector.warnings(for: draft, in: [existing])

        #expect(warnings.count == 1)
        #expect(warnings.first?.record.id == existing.id)
        #expect(warnings.first?.reasons.contains(.invoiceNumber) == true)
    }

    @Test func duplicateDetectorMatchesSameAmountAndDateWithinProject() {
        let projectId = UUID()
        let otherProjectId = UUID()
        let existing = ProjectFinancialRecord(
            projectId: projectId,
            date: "2026-05-09 09:00",
            direction: .expense,
            amount: "1200.50"
        )
        let otherProject = ProjectFinancialRecord(
            projectId: otherProjectId,
            date: "2026-05-09 12:00",
            direction: .expense,
            amount: "1200.50"
        )
        let draft = ProjectFinancialRecord(
            projectId: projectId,
            date: "2026-05-09 18:30",
            direction: .expense,
            amount: "1200.5"
        )

        let warnings = ProjectFinancialDuplicateDetector.warnings(for: draft, in: [existing, otherProject])

        #expect(warnings.count == 1)
        #expect(warnings.first?.record.id == existing.id)
        #expect(warnings.first?.reasons.contains(.amountAndDate) == true)
    }

    @Test func duplicateDetectorIgnoresCurrentRecordWhenEditing() {
        let projectId = UUID()
        let record = ProjectFinancialRecord(
            projectId: projectId,
            date: "2026-05-09 09:00",
            direction: .expense,
            amount: "1200.50",
            invoiceNumber: "FP2026000188"
        )

        let warnings = ProjectFinancialDuplicateDetector.warnings(
            for: record,
            in: [record],
            ignoring: record.id
        )

        #expect(warnings.isEmpty)
    }

    @Test func constructionMethodVersionAndPublishStatusCodable() throws {
        let method = ConstructionMethod(
            title: "墙面找平",
            trade: "泥工",
            versionName: "V2",
            publishStatus: .published,
            tutorialBody: "基层处理",
            procedureSteps: ["放线", "打点"],
            qualityChecklist: ["平整度检查"],
            safetyChecklist: ["高处作业佩戴安全带"]
        )

        let data = try JSONEncoder().encode(method)
        let decoded = try JSONDecoder().decode(ConstructionMethod.self, from: data)
        let encodedObject = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let legacy = try JSONDecoder().decode(
            ConstructionMethod.self,
            from: #"{"title":"旧工艺","trade":"水电","steps":"放线\n开槽"}"#.data(using: .utf8)!
        )

        #expect(encodedObject["steps"] == nil)
        #expect(encodedObject["qualityStandard"] == nil)
        #expect(encodedObject["safetyNotes"] == nil)
        #expect((encodedObject["procedureSteps"] as? [String]) == ["放线", "打点"])
        #expect((encodedObject["qualityChecklist"] as? [String]) == ["平整度检查"])
        #expect((encodedObject["safetyChecklist"] as? [String]) == ["高处作业佩戴安全带"])
        #expect(decoded.versionName == "V2")
        #expect(decoded.publishStatus == .published)
        #expect(decoded.procedureSteps == ["放线", "打点"])
        #expect(decoded.qualityChecklist == ["平整度检查"])
        #expect(decoded.safetyChecklist == ["高处作业佩戴安全带"])
        #expect(legacy.versionName == "V1")
        #expect(legacy.publishStatus == .draft)
        #expect(legacy.procedureSteps == ["放线", "开槽"])
    }

    @Test func projectTimelineSortsMixedItemsByDate() {
        let projectId = UUID()
        let log = DailyLog(
            date: "2026-05-08",
            weather: "晴",
            content: "安装桥架",
            workers: "3",
            projectId: projectId
        )
        let finance = ProjectFinancialRecord(
            projectId: projectId,
            date: "2026-05-09 10:30",
            direction: .expense,
            category: .material,
            amount: "100"
        )
        let material = MaterialItem(
            name: "桥架",
            quantity: "10",
            unit: "米",
            arrivalDate: "2026-05-07",
            projectId: projectId
        )

        let items = ProjectTimelineBuilder.makeItems(
            logs: [log],
            progress: [],
            materials: [material],
            quotes: [],
            labor: [],
            financialRecords: [finance],
            documents: [],
            warehouseMovements: [],
            quickNotes: [],
            siteTodos: [],
            drawings: []
        )

        #expect(items.first?.type == "记账")
        #expect(items.map(\.type) == ["记账", "日志", "材料"])
    }
}
