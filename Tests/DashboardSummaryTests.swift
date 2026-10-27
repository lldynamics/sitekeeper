import Foundation
import Observation
import Testing
@testable import sitekeeper

@MainActor
struct DashboardSummaryTests {
    @Test func decimalMoneyManualFallbackAndDraftRulesMatchExistingBusinessMetrics() {
        let projects = ProjectStore()
        let finance = FinanceStore()
        let overpaid = Project(name: "超收", location: "", contractAmount: 100, paidAmount: 20, materialCost: 50, laborCost: 60)
        let paused = Project(name: "暂停", location: "", status: .paused, expectedEndDate: BusinessDateValue(legacyText: "2026-10-20"), contractAmount: NumericInputSupport.money("100.25"), paidAmount: NumericInputSupport.money("40.10"), materialCost: 70, laborCost: 80)
        let finished = Project(name: "已完工", location: "", status: .completed, contractAmount: 999, paidAmount: 999)
        projects.setProjects([overpaid, paused, finished])
        let collection = ProjectFinancialRecord(projectId: overpaid.id, date: BusinessDateValue(legacyText: "2026-10-27"), direction: .income, category: .collection, amount: 150)
        let draft = ProjectFinancialRecord(projectId: paused.id, date: BusinessDateValue(legacyText: "2026-10-28"), direction: .income, category: .collection, amount: 200, status: .draft, dueDate: BusinessDateValue(legacyText: "2026-10-28"))
        let archived = ProjectFinancialRecord(projectId: paused.id, direction: .income, category: .collection, amount: 300, status: .archived)
        projects.setProjectFinancialRecords([collection, draft, archived])
        finance.setMaterialItems([
            MaterialItem(name: "精度", quantity: NumericInputSupport.quantity("3"), unit: "m", unitPrice: NumericInputSupport.money("0.10"), projectId: paused.id),
            MaterialItem(name: "待采购", quantity: 0, unit: "m", unitPrice: 2, projectId: paused.id),
            MaterialItem(name: "不应计入", quantity: 100, unit: "m", unitPrice: 100, projectId: finished.id)
        ])
        finance.setLaborRecords([LaborRecord(date: BusinessDateValue(legacyText: "2026-10-27"), workers: 1, hours: 2, unitRate: NumericInputSupport.money("0.10"), note: "", projectId: paused.id)])
        let quote = QuoteItem(name: "含税折扣", unitPrice: NumericInputSupport.money("0.10"), quantity: 3, unit: "m", notes: "", taxRate: 13, discountRate: 5, projectId: paused.id)
        let unpriced = QuoteItem(name: "待报价", unitPrice: 0, quantity: 3, unit: "m", notes: "", taxRate: 0, discountRate: 0, projectId: overpaid.id)
        finance.setQuoteItems([quote, unpriced])
        var input = DashboardSummaryInput(projectStore: projects, financeStore: finance)
        // Freeze time for receivable aging independently of the host's current date.
        input = fixedDayInput(copying: input, at: "2026-10-28T04:00:00Z")
        let summary = DashboardSummaryBuilder.build(input).businessSummary
        #expect(summary.contractAmount == NumericInputSupport.money("200.25"))
        #expect(summary.paidAmount == NumericInputSupport.money("190.10"))
        #expect(summary.receivableAmount == NumericInputSupport.money("60.15"))
        #expect(summary.receivableAgeDays == 8)
        #expect(summary.materialCost == NumericInputSupport.money("50.30"))
        #expect(summary.laborCostAmount == NumericInputSupport.money("60.20"))
        #expect(summary.quoteTotal == ReportBuilder.quoteGrandTotal(quote) + ReportBuilder.quoteGrandTotal(unpriced))
        #expect(summary.pendingMaterialCount == 1)
        #expect(summary.unpricedQuoteCount == 1)
        #expect(summary.recentCollection?.amount == collection.amount)
        #expect(summary.recentCollection?.projectName == overpaid.name)
    }

    @Test func todayListsKeepGlobalOrderGeneralLogsAndProjectStatusBoundaries() {
        let projects = ProjectStore()
        let finance = FinanceStore()
        let active = Project(name: "在建", location: "")
        let paused = Project(name: "暂停", location: "", status: .paused)
        let completed = Project(name: "已完工", location: "", status: .completed)
        projects.setProjects([active, paused, completed])
        let logs = [log(projectID: paused.id), log(projectID: nil), log(projectID: completed.id), log(projectID: active.id)]
        projects.setDailyLogs(logs)
        let todos = [todo(projectID: paused.id), todo(projectID: nil), todo(projectID: completed.id), todo(projectID: active.id), todo(projectID: active.id, done: true)]
        projects.setSiteTodos(todos)
        projects.setProgressTasks([
            ProgressTask(projectId: active.id, title: "延期", startDate: BusinessDateValue(legacyText: "2026-10-20"), dueDate: BusinessDateValue(legacyText: "2026-10-27"), completion: 0.5, note: ""),
            ProgressTask(projectId: paused.id, title: "完成", startDate: BusinessDateValue(legacyText: "2026-10-20"), dueDate: BusinessDateValue(legacyText: "2026-10-27"), completion: 1, note: ""),
            ProgressTask(projectId: completed.id, title: "排除", startDate: BusinessDateValue(legacyText: "2026-10-20"), dueDate: BusinessDateValue(legacyText: "2026-10-27"), completion: 0, note: "")
        ])
        let summary = DashboardSummaryBuilder.build(fixedDayInput(copying: DashboardSummaryInput(projectStore: projects, financeStore: finance), at: "2026-10-28T04:00:00Z"))
        #expect(summary.activeProjects.map(\.id) == [active.id, paused.id])
        #expect(summary.todayLogs.map(\.id) == [logs[0].id, logs[1].id, logs[3].id])
        #expect(summary.todayTodos.map(\.id) == [todos[0].id, todos[3].id])
        #expect(summary.openTodos.count == 2)
        #expect(summary.overdueTasks.count == 1)
        #expect(summary.overdueTodos.isEmpty)
        #expect(summary.projectsWithoutTodayLogCount == 0)
    }

    @Test func warehouseAndReceiptsKeepExistingLinkAndDraftSemantics() {
        let projects = ProjectStore()
        let finance = FinanceStore()
        let project = Project(name: "在建", location: "")
        let completed = Project(name: "完工", location: "", status: .completed)
        projects.setProjects([project, completed])
        let expense = ProjectFinancialRecord(projectId: project.id, amount: 2, dueDate: BusinessDateValue(legacyText: "2026-10-28"))
        let linked = ProjectFinancialRecord(projectId: project.id, amount: 3, linkedDocumentIds: [UUID()])
        let draft = ProjectFinancialRecord(projectId: project.id, amount: 4, status: .draft, dueDate: BusinessDateValue(legacyText: "2026-10-28"))
        projects.setProjectFinancialRecords([expense, linked, draft, ProjectFinancialRecord(projectId: completed.id, amount: 5)])
        let movements = [
            ProjectWarehouseMovement(projectId: project.id, date: BusinessDateValue(legacyText: "2026-10-28"), materialName: "电线", unit: "m", quantity: 2, createdAt: BusinessDateValue(legacyText: "2026-10-28 08:00")),
            ProjectWarehouseMovement(projectId: project.id, date: BusinessDateValue(legacyText: "2026-10-27"), movementType: .outbound, materialName: "电线", unit: "m", quantity: 3, createdAt: BusinessDateValue(legacyText: "2026-10-28 09:00")),
            ProjectWarehouseMovement(projectId: completed.id, date: BusinessDateValue(legacyText: "2026-10-28"), materialName: "排除", quantity: 5)
        ]
        projects.setProjectWarehouseMovements(movements)
        let summary = DashboardSummaryBuilder.build(fixedDayInput(copying: DashboardSummaryInput(projectStore: projects, financeStore: finance), at: "2026-10-28T04:00:00Z"))
        #expect(summary.unattachedReceiptCount == [expense, linked, draft].filter { $0.requiresAttachment && $0.linkedDocumentIds.isEmpty }.count)
        #expect(summary.unsettledFinancialCount == 1)
        #expect(summary.warehouseTodayMovementCount == 1)
        #expect(summary.warehouseNegativeCount == 1)
        #expect(summary.warehouseStockLines[0].quantity == -1)
        #expect(summary.recentWarehouseMovements.map(\.id) == [movements[1].id, movements[0].id])
    }

    @Test func cacheHitsDoNotCaptureOrBuildAndUnrelatedMutationsDoNotInvalidate() {
        let projects = ProjectStore()
        let finance = FinanceStore()
        let cache = DashboardSummaryCache()
        var captures = 0
        for _ in 0..<1_000 {
            _ = cache.value(revision: DashboardSummaryRevision(projectStore: projects, financeStore: finance)) {
                captures += 1
                return DashboardSummaryInput(projectStore: projects, financeStore: finance)
            }
        }
        #expect(captures == 1)
        #expect(cache.buildCount == 1)
        projects.setHistoryRecords([])
        projects.setProjectContacts([])
        projects.setQuickNotes([])
        projects.setProjectDrawings([])
        _ = cache.value(revision: DashboardSummaryRevision(projectStore: projects, financeStore: finance)) {
            captures += 1
            return DashboardSummaryInput(projectStore: projects, financeStore: finance)
        }
        #expect(captures == 1)
        #expect(cache.buildCount == 1)
    }

    @Test func everyRelevantCollectionAndSameCountEditsInvalidate() {
        let projects = ProjectStore()
        let finance = FinanceStore()
        let project = Project(name: "原项目", location: "", contractAmount: 100)
        projects.setProjects([project])
        let mutations: [() -> Void] = [
            { projects.setProjects([Project(id: project.id, name: "更名", location: "", status: .paused, contractAmount: 200)]) },
            { projects.setDailyLogs([]) }, { projects.setSiteTodos([]) }, { projects.setProgressTasks([]) },
            { projects.setProjectFinancialRecords([]) }, { projects.setProjectDocuments([]) },
            { projects.setProjectWarehouseMovements([]) }, { finance.setMaterialItems([]) },
            { finance.setQuoteItems([]) }, { finance.setLaborRecords([]) }
        ]
        let cache = DashboardSummaryCache()
        func get() -> DashboardSummaryModel {
            cache.value(revision: DashboardSummaryRevision(projectStore: projects, financeStore: finance)) {
                DashboardSummaryInput(projectStore: projects, financeStore: finance)
            }
        }
        _ = get()
        for (index, mutate) in mutations.enumerated() {
            mutate()
            _ = get()
            #expect(cache.buildCount == index + 2)
        }
        #expect(get().businessSummary.contractAmount == 200)
        projects.setProjects([Project(id: project.id, name: "完工", location: "", status: .completed, contractAmount: 200)])
        #expect(get().activeProjects.isEmpty)
        #expect(get().businessSummary.contractAmount == 0)
    }

    @Test func dayAndTimezoneChangesInvalidateWithoutRecordEdits() {
        let clock = DashboardSummaryTestClock()
        let projects = ProjectStore(now: { clock.now }, calendar: { clock.calendar })
        let finance = FinanceStore()
        let project = Project(name: "跨日", location: "", expectedEndDate: BusinessDateValue(legacyText: "2026-10-27"), contractAmount: 100)
        projects.setProjects([project])
        projects.setDailyLogs([log(projectID: project.id)])
        projects.setSiteTodos([todo(projectID: project.id)])
        let cache = DashboardSummaryCache()
        func get() -> DashboardSummaryModel {
            cache.value(revision: DashboardSummaryRevision(projectStore: projects, financeStore: finance)) {
                DashboardSummaryInput(projectStore: projects, financeStore: finance)
            }
        }
        #expect(get().todayLogs.count == 1)
        #expect(get().businessSummary.receivableAgeDays == 1)
        clock.now = ISO8601DateFormatter().date(from: "2026-10-28T16:00:00Z")!
        #expect(projects.refreshDateSensitiveStateIfNeeded())
        #expect(get().todayLogs.isEmpty)
        #expect(get().overdueTodos.count == 1)
        #expect(get().businessSummary.receivableAgeDays == 2)
        #expect(cache.buildCount == 2)
        clock.calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        #expect(projects.refreshDateSensitiveStateIfNeeded())
        #expect(get().todayLogs.count == 1)
        #expect(cache.buildCount == 3)
    }

    @Test func inputSnapshotRetainsItsValuesAndSourceChangesCannotReuseCachedSummary() {
        let projects = ProjectStore()
        let finance = FinanceStore()
        projects.setProjects([Project(name: "原值", location: "", contractAmount: 100)])
        let input = DashboardSummaryInput(projectStore: projects, financeStore: finance)
        projects.setProjects([Project(name: "新值", location: "", contractAmount: 200)])
        #expect(DashboardSummaryBuilder.build(input).businessSummary.contractAmount == 100)
        let other = ProjectStore()
        let cache = DashboardSummaryCache()
        _ = cache.value(revision: DashboardSummaryRevision(projectStore: projects, financeStore: finance)) {
            DashboardSummaryInput(projectStore: projects, financeStore: finance)
        }
        #expect(cache.value(revision: DashboardSummaryRevision(projectStore: other, financeStore: finance)) {
            DashboardSummaryInput(projectStore: other, financeStore: finance)
        }.activeProjects.isEmpty)
        #expect(cache.buildCount == 2)
    }

    private func log(projectID: UUID?) -> DailyLog {
        DailyLog(date: BusinessDateValue(legacyText: "2026-10-28"), weather: "", content: "日志", workers: 1, projectId: projectID)
    }

    private func todo(projectID: UUID?, done: Bool = false) -> SiteTodo {
        SiteTodo(title: "待办", dueDate: BusinessDateValue(legacyText: "2026-10-28"), isDone: done, projectId: projectID)
    }

    private func fixedDayInput(copying input: DashboardSummaryInput, at timestamp: String) -> DashboardSummaryInput {
        var result = DashboardSummaryInput(dayContext: ProjectDayContext(now: ISO8601DateFormatter().date(from: timestamp)!, calendar: DashboardSummaryTestClock().calendar))
        result.projects = input.projects
        result.dailyLogs = input.dailyLogs
        result.siteTodos = input.siteTodos
        result.progressTasks = input.progressTasks
        result.financialRecords = input.financialRecords
        result.documents = input.documents
        result.warehouseMovements = input.warehouseMovements
        result.materialsByProjectID = input.materialsByProjectID
        result.quotesByProjectID = input.quotesByProjectID
        result.laborByProjectID = input.laborByProjectID
        result.financialRecordsByProjectID = input.financialRecordsByProjectID
        result.warehouseMovementsByProjectID = input.warehouseMovementsByProjectID
        result.materialPriceSpikeCountByProjectID = input.materialPriceSpikeCountByProjectID
        return result
    }
}

@MainActor
private final class DashboardSummaryTestClock {
    var now = ISO8601DateFormatter().date(from: "2026-10-28T04:00:00Z")!
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()
}
