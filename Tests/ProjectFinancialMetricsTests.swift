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

    @Test func constructionMethodVersionAndPublishStatusCodable() throws {
        let method = ConstructionMethod(
            title: "墙面找平",
            trade: "泥工",
            versionName: "V2",
            publishStatus: .published,
            tutorialBody: "基层处理"
        )

        let data = try JSONEncoder().encode(method)
        let decoded = try JSONDecoder().decode(ConstructionMethod.self, from: data)
        let legacy = try JSONDecoder().decode(
            ConstructionMethod.self,
            from: #"{"title":"旧工艺","trade":"水电","steps":"放线\n开槽"}"#.data(using: .utf8)!
        )

        #expect(decoded.versionName == "V2")
        #expect(decoded.publishStatus == .published)
        #expect(legacy.versionName == "V1")
        #expect(legacy.publishStatus == .draft)
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
