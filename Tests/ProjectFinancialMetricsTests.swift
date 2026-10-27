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
                amount: NumericInputSupport.money("100"),
                status: .active
            ),
            ProjectFinancialRecord(
                projectId: projectId,
                direction: .income,
                category: .collection,
                amount: NumericInputSupport.money("200"),
                status: .draft
            ),
            ProjectFinancialRecord(
                projectId: projectId,
                direction: .expense,
                category: .material,
                amount: NumericInputSupport.money("300"),
                status: .archived
            ),
            ProjectFinancialRecord(
                projectId: projectId,
                direction: .expense,
                category: .material,
                amount: NumericInputSupport.money("50"),
                status: .active
            )
        ]

        #expect(ProjectFinancialMetrics.income(records) == 100)
        #expect(ProjectFinancialMetrics.expense(records) == 50)
        #expect(ProjectFinancialMetrics.collectionAmount(records) == 100)
    }

    @Test func missingReceiptMetricsIgnoreDraftAndArchivedRecords() {
        let projectId = UUID()
        let active = ProjectFinancialRecord(
            projectId: projectId,
            category: .material,
            status: .active
        )
        let draft = ProjectFinancialRecord(
            projectId: projectId,
            category: .material,
            status: .draft
        )
        let archived = ProjectFinancialRecord(
            projectId: projectId,
            category: .labor,
            status: .archived
        )

        let missing = ProjectFinancialMetrics.missingReceiptRecords(
            [active, draft, archived],
            hasLinkedDocument: { _ in false }
        )

        #expect(missing.map(\.id) == [active.id])
    }

    @Test @MainActor func projectActivityMissingReceiptCountUsesFormalRecordsOnly() {
        let projectId = UUID()
        let store = ProjectStore()
        store.setProjectFinancialRecords([
            ProjectFinancialRecord(projectId: projectId, category: .material, status: .active),
            ProjectFinancialRecord(projectId: projectId, category: .material, status: .draft),
            ProjectFinancialRecord(projectId: projectId, category: .labor, status: .archived)
        ])

        #expect(store.projectActivitySummary(for: projectId).unattachedReceiptCount == 1)
    }

    @Test func zeroValuedDetailsDoNotFallBackToStaleManualCosts() {
        let project = Project(
            name: "零价明细",
            location: "",
            materialCost: NumericInputSupport.money("1000"),
            laborCost: NumericInputSupport.money("500")
        )

        #expect(ProjectDetailMetrics.currentMaterialCost(
            project: project,
            materialCostAuto: 0,
            hasMaterialDetails: true
        ) == 0)
        #expect(ProjectDetailMetrics.currentLaborCost(
            project: project,
            laborCostAuto: 0,
            hasLaborDetails: true
        ) == 0)
        #expect(ProjectDetailMetrics.currentMaterialCost(
            project: project,
            materialCostAuto: 0,
            hasMaterialDetails: false
        ) == 1000)
        #expect(ProjectDetailMetrics.currentLaborCost(
            project: project,
            laborCostAuto: 0,
            hasLaborDetails: false
        ) == 500)
    }

    @Test func missingReceiptFilterExcludesDraftAndArchivedRecords() {
        let projectId = UUID()
        let active = ProjectFinancialRecord(projectId: projectId, category: .material, status: .active)
        let draft = ProjectFinancialRecord(projectId: projectId, category: .material, status: .draft)
        let archived = ProjectFinancialRecord(projectId: projectId, category: .material, status: .archived)

        #expect(BookAttachmentFilter.unattached.matches(active) { _ in [] })
        #expect(!BookAttachmentFilter.unattached.matches(draft) { _ in [] })
        #expect(!BookAttachmentFilter.unattached.matches(archived) { _ in [] })
    }

    @Test func financialSummaryAndPaidFallbackUseOneSharedRule() {
        let projectId = UUID()
        let project = Project(
            id: projectId,
            name: "统一财务规则",
            location: "",
            status: .active,
            contractAmount: NumericInputSupport.money("1000"),
            paidAmount: NumericInputSupport.money("600")
        )
        let records = [
            ProjectFinancialRecord(
                projectId: projectId,
                direction: .income,
                category: .collection,
                amount: NumericInputSupport.money("200"),
                status: .active
            ),
            ProjectFinancialRecord(
                projectId: projectId,
                direction: .income,
                category: .receipt,
                amount: NumericInputSupport.money("300"),
                status: .draft
            ),
            ProjectFinancialRecord(
                projectId: projectId,
                direction: .expense,
                category: .material,
                amount: NumericInputSupport.money("50"),
                status: .active
            )
        ]

        let summary = ProjectFinancialMetrics.summary(records)
        #expect(summary.income == 200)
        #expect(summary.expense == 50)
        #expect(summary.collectionAmount == 200)
        #expect(summary.balance == 150)
        #expect(ProjectFinancialMetrics.paidAmount(project: project, records: records) == 200)
        #expect(ProjectFinancialMetrics.unpaidAmount(project: project, records: records) == 800)
        #expect(ProjectFinancialMetrics.paidAmount(project: project, records: []) == 600)
    }

    @Test @MainActor func projectActivitySummaryExcludesDraftAndArchivedCollections() {
        let projectId = UUID()
        let store = ProjectStore()
        store.setProjectFinancialRecords([
            ProjectFinancialRecord(
                projectId: projectId,
                direction: .income,
                category: .collection,
                amount: NumericInputSupport.money("125"),
                status: .active
            ),
            ProjectFinancialRecord(
                projectId: projectId,
                direction: .income,
                category: .collection,
                amount: NumericInputSupport.money("400"),
                status: .draft
            ),
            ProjectFinancialRecord(
                projectId: projectId,
                direction: .income,
                category: .collection,
                amount: NumericInputSupport.money("500"),
                status: .archived
            )
        ])

        #expect(store.projectActivitySummary(for: projectId).collectedIncomeAmount == 125)
    }

    @Test func metricsParserUsesNormalizedNonNegativeAmounts() {
        let projectId = UUID()
        let records = [
            ProjectFinancialRecord(
                projectId: projectId,
                date: BusinessDateValue(legacyText: "2026-05-08 10:30"),
                direction: .income,
                category: .collection,
                amount: NumericInputSupport.money("1200.5")
            ),
            ProjectFinancialRecord(
                projectId: projectId,
                date: BusinessDateValue(legacyText: "2026-05-09"),
                direction: .expense,
                category: .material,
                amount: NumericInputSupport.money("300.25")
            )
        ]

        #expect(ProjectFinancialMetrics.income(records) == MoneyValue(Decimal(string: "1200.5")!))
        #expect(ProjectFinancialMetrics.expense(records) == MoneyValue(Decimal(string: "300.25")!))
        #expect(ProjectFinancialMetrics.latestCollection(records: records, projectName: { _ in nil })?.date.storageText == "2026-05-08 10:30")
    }
}

// MARK: - Export, reminders and duplicates
extension ProjectFinancialMetricsTests {
    @Test func projectFinanceCSVExportsStatusColumn() throws {
        let projectId = UUID()
        let record = ProjectFinancialRecord(
            projectId: projectId,
            date: BusinessDateValue(legacyText: "2026-05-09 10:30"),
            direction: .income,
            category: .collection,
            amount: NumericInputSupport.money("100"),
            counterparty: "客户",
            invoiceNumber: "R-1",
            status: .draft,
            dueDate: BusinessDateValue(legacyText: "2026-05-12"),
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
            dueDate: BusinessDateValue(legacyText: "2000-01-01"),
            reminderStatus: .pending
        )
        let done = ProjectFinancialRecord(
            projectId: UUID(),
            dueDate: BusinessDateValue(legacyText: "2000-01-01"),
            reminderStatus: .done
        )
        let none = ProjectFinancialRecord(projectId: UUID(), dueDate: BusinessDateValue(legacyText: "2000-01-01"))

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
            date: BusinessDateValue(legacyText: "2026-05-09 09:00"),
            direction: .expense,
            amount: NumericInputSupport.money("1200.50"),
            invoiceNumber: "fp-2026-000188"
        )
        let draft = ProjectFinancialRecord(
            projectId: projectId,
            date: BusinessDateValue(legacyText: "2026-05-10 10:00"),
            direction: .expense,
            amount: NumericInputSupport.money("800"),
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
            date: BusinessDateValue(legacyText: "2026-05-09T09:00:00+08:00"),
            direction: .expense,
            amount: NumericInputSupport.money("1200.50")
        )
        let otherProject = ProjectFinancialRecord(
            projectId: otherProjectId,
            date: BusinessDateValue(legacyText: "2026-05-09T12:00:00+08:00"),
            direction: .expense,
            amount: NumericInputSupport.money("1200.50")
        )
        let draft = ProjectFinancialRecord(
            projectId: projectId,
            date: BusinessDateValue(legacyText: "2026-05-09T18:30:00+08:00"),
            direction: .expense,
            amount: NumericInputSupport.money("1200.5")
        )

        let warnings = ProjectFinancialDuplicateDetector.warnings(for: draft, in: [existing, otherProject], timeZone: TimeZone(identifier: "Asia/Shanghai")!)

        #expect(warnings.count == 1)
        #expect(warnings.first?.record.id == existing.id)
        #expect(warnings.first?.reasons.contains(.amountAndDate) == true)
    }

    @Test func duplicateDaysRespectLegacyUTCAndExplicitOffsets() throws {
        let zone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        #expect(ProjectFinancialDuplicateDetector.normalizedDay(from: BusinessDateValue(legacyText: "2026-05-09 18:30"), timeZone: zone) == "2026-05-10")
        #expect(ProjectFinancialDuplicateDetector.normalizedDay(from: BusinessDateValue(legacyText: "2026-05-10T02:30:00+08:00"), timeZone: zone) == "2026-05-10")
        #expect(ProjectFinancialDuplicateDetector.normalizedDay(from: BusinessDateValue(legacyText: "2026-05-09"), timeZone: zone) == "2026-05-09")
    }

    @Test func duplicateDetectorIgnoresCurrentRecordWhenEditing() {
        let projectId = UUID()
        let record = ProjectFinancialRecord(
            projectId: projectId,
            date: BusinessDateValue(legacyText: "2026-05-09 09:00"),
            direction: .expense,
            amount: NumericInputSupport.money("1200.50"),
            invoiceNumber: "FP2026000188"
        )

        let warnings = ProjectFinancialDuplicateDetector.warnings(
            for: record,
            in: [record],
            ignoring: record.id
        )

        #expect(warnings.isEmpty)
    }
}
