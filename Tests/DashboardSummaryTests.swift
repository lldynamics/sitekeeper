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
        // Freeze the business day independently of the host's current date.
        input = fixedDayInput(copying: input, at: "2026-10-28T04:00:00Z")
        let summary = DashboardSummaryBuilder.build(input).businessSummary
        #expect(summary.contractAmount == NumericInputSupport.money("200.25"))
        #expect(summary.paidAmount == NumericInputSupport.money("190.10"))
        #expect(summary.receivableAmount == NumericInputSupport.money("60.15"))
        #expect(summary.unpaidAmount == NumericInputSupport.money("60.15"))
        #expect(summary.scope?.contractUnpaid == NumericInputSupport.money("60.15"))
        #expect(summary.scope?.quoteProjectsNeedingReview == 2)
        #expect(summary.scope?.selectedQuoteAmount == nil)
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

    @Test func overdueItemsCombineBothKindsInDueDateOrderWithoutLosingTheFullCount() {
        let projects = ProjectStore()
        let finance = FinanceStore()
        let active = Project(name: "在建", location: "")
        let paused = Project(name: "暂停", location: "", status: .paused)
        let completed = Project(name: "已完工", location: "", status: .completed)
        projects.setProjects([active, paused, completed])
        let sharedID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let todos = [
            SiteTodo(title: "待办 27", dueDate: BusinessDateValue(legacyText: "2026-10-27"), projectId: active.id),
            SiteTodo(title: "待办 20", dueDate: BusinessDateValue(legacyText: "2026-10-20"), projectId: paused.id),
            SiteTodo(id: sharedID, title: "待办 23", dueDate: BusinessDateValue(legacyText: "2026-10-23"), projectId: active.id),
            SiteTodo(title: "待办 25", dueDate: BusinessDateValue(legacyText: "2026-10-25"), projectId: active.id),
            SiteTodo(title: "已完成", dueDate: BusinessDateValue(legacyText: "2026-10-19"), isDone: true, projectId: active.id),
            SiteTodo(title: "完工项目", dueDate: BusinessDateValue(legacyText: "2026-10-19"), projectId: completed.id),
            SiteTodo(title: "无项目", dueDate: BusinessDateValue(legacyText: "2026-10-19")),
            SiteTodo(title: "日期无效", dueDate: .unresolved("unknown"), projectId: active.id),
            SiteTodo(title: "今天", dueDate: BusinessDateValue(legacyText: "2026-10-28"), projectId: active.id)
        ]
        projects.setSiteTodos(todos)
        func task(_ title: String, _ date: String, id: UUID = UUID(), projectID: UUID, completion: Double = 0) -> ProgressTask {
            ProgressTask(id: id, projectId: projectID, title: title, startDate: BusinessDateValue(legacyText: "2026-10-01"), dueDate: BusinessDateValue(legacyText: date), completion: completion, note: "")
        }
        projects.setProgressTasks([
            task("任务 26", "2026-10-26", projectID: active.id),
            task("任务 23", "2026-10-23", id: sharedID, projectID: active.id),
            task("任务 21", "2026-10-21", projectID: paused.id),
            task("任务 24", "2026-10-24", projectID: active.id),
            task("已完成任务", "2026-10-19", projectID: active.id, completion: 1),
            task("完工项目任务", "2026-10-19", projectID: completed.id)
        ])

        let input = fixedDayInput(copying: DashboardSummaryInput(projectStore: projects, financeStore: finance), at: "2026-10-28T04:00:00Z")
        let summary = DashboardSummaryBuilder.build(input)
        #expect(summary.overdueItems.count == 8)
        #expect(summary.overdueItems.count == summary.overdueTodos.count + summary.overdueTasks.count)
        #expect(summary.overdueItems.map(\.title) == ["待办 20", "任务 21", "任务 23", "待办 23", "任务 24", "待办 25", "任务 26", "待办 27"])
        #expect(Set(summary.overdueItems.map(\.id)).count == 8)
        #expect(Array(summary.overdueItems.prefix(6)).map(\.title).last == "待办 25")
    }

    @Test func overdueSortingUsesTheProjectTimezoneForMixedDateTypes() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let projectID = UUID()
        let day = SiteTodo(title: "date only", dueDate: BusinessDateValue(legacyText: "2026-10-20"), projectId: projectID)
        let instant = ProgressTask(projectId: projectID, title: "local morning", startDate: .empty,
                                   dueDate: .instant(ISO8601DateFormatter().date(from: "2026-10-19T23:00:00Z")!),
                                   completion: 0, note: "")
        let items = DashboardOverdueItem.sorted(todos: [day], tasks: [instant], timeZone: zone)
        #expect(items.map(\.title) == ["date only", "local morning"])
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

    @Test func cacheHitStillRegistersVersionObservation() async {
        let projects = ProjectStore()
        let finance = FinanceStore()
        let cache = DashboardSummaryCache()
        func get() {
            _ = cache.value(revision: DashboardSummaryRevision(projectStore: projects, financeStore: finance)) {
                DashboardSummaryInput(projectStore: projects, financeStore: finance)
            }
        }
        get()
        await confirmation(expectedCount: 1) { changed in
            withObservationTracking {
                get()
            } onChange: {
                changed()
            }
            projects.setDailyLogs([])
        }
        get()
        #expect(cache.buildCount == 2)
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
        let plan = ProjectPaymentPlan(title: "收款", direction: .income, counterparty: "客户", installments: [
            ProjectPaymentInstallment(title: "一期", dueDate: BusinessDateValue(legacyText: "2026-10-29"), amount: 100)
        ])
        let project = Project(name: "跨日", location: "", expectedEndDate: BusinessDateValue(legacyText: "2026-10-27"), contractAmount: 100, paymentPlans: [plan])
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
        #expect(get().businessSummary.scope?.duePlanAmount == 0)
        #expect(get().businessSummary.scope?.futurePlanAmount == 100)
        clock.now = ISO8601DateFormatter().date(from: "2026-10-28T16:00:00Z")!
        #expect(projects.refreshDateSensitiveStateIfNeeded())
        #expect(get().todayLogs.isEmpty)
        #expect(get().overdueTodos.count == 1)
        #expect(get().businessSummary.scope?.duePlanAmount == 100)
        #expect(get().businessSummary.scope?.futurePlanAmount == 0)
        #expect(cache.buildCount == 2)
        clock.calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        #expect(projects.refreshDateSensitiveStateIfNeeded())
        #expect(get().todayLogs.count == 1)
        #expect(get().businessSummary.scope?.duePlanAmount == 0)
        #expect(get().businessSummary.scope?.futurePlanAmount == 100)
        #expect(cache.buildCount == 3)
    }

    @Test func businessScopeUsesSelectedVersionAndKeepsPlansSeparateFromContract() {
        let projects = ProjectStore()
        let finance = FinanceStore()
        let installment = ProjectPaymentInstallment(title: "首期", dueDate: BusinessDateValue(legacyText: "2026-10-27"), amount: 30)
        let plan = ProjectPaymentPlan(title: "计划", direction: .income, counterparty: "客户", installments: [installment])
        let project = Project(name: "经营口径", location: "", contractAmount: 100, materialCost: 10, laborCost: 20,
                              paymentPlans: [plan], businessQuoteVersion: "V1")
        projects.setProjects([project])
        let selected = QuoteItem(name: "当前", unitPrice: 10, quantity: 2, unit: "项", notes: "", taxRate: 0, discountRate: 0,
                                 versionName: "V1", status: .confirmed, projectId: project.id)
        let old = QuoteItem(name: "历史", unitPrice: 80, quantity: 1, unit: "项", notes: "", taxRate: 0, discountRate: 0,
                            versionName: "V2", status: .confirmed, projectId: project.id)
        finance.setQuoteItems([selected, old])
        projects.setProjectFinancialRecords([
            ProjectFinancialRecord(projectId: project.id, direction: .income, category: .collection, amount: 10,
                                   paymentAllocation: ProjectPaymentAllocation(planID: plan.id, installmentID: installment.id)),
            ProjectFinancialRecord(projectId: project.id, direction: .expense, category: .material, amount: 8)
        ])
        let input = fixedDayInput(copying: DashboardSummaryInput(projectStore: projects, financeStore: finance), at: "2026-10-28T04:00:00Z")
        let scope = DashboardSummaryBuilder.build(input).businessSummary.scope
        #expect(scope?.selectedQuoteAmount == 20)
        #expect(scope?.contractUnpaid == 90)
        #expect(scope?.duePlanAmount == 20)
        #expect(scope?.futurePlanAmount == 0)
        #expect(scope?.materialEstimate == 10 && scope?.laborEstimate == 20)
        #expect(scope?.formalExpense == 8 && scope?.estimatedProfit == 70)
    }

    @Test func directBusinessScopePreservesProjectBoundariesAndSelectedQuote() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = ISO8601DateFormatter().date(from: "2026-10-28T04:00:00Z")!
        let installment = ProjectPaymentInstallment(title: "一期", dueDate: BusinessDateValue(legacyText: "2026-10-27"), amount: 30)
        let plan = ProjectPaymentPlan(title: "计划", direction: .income, counterparty: "客户", installments: [installment])
        let first = Project(name: "A", location: "", contractAmount: 100, materialCost: 10, laborCost: 20,
                            paymentPlans: [plan], businessQuoteVersion: "V1")
        let second = Project(name: "B", location: "", contractAmount: 100, paidAmount: 150, materialCost: 0, laborCost: 0)
        let current = QuoteItem(name: "当前", unitPrice: 10, quantity: 2, unit: "项", notes: "", taxRate: 0, discountRate: 0,
                                versionName: "V1", status: .confirmed, projectId: first.id)
        let old = QuoteItem(name: "历史", unitPrice: 80, quantity: 1, unit: "项", notes: "", taxRate: 0, discountRate: 0,
                            versionName: "V2", status: .confirmed, projectId: first.id)
        let receipt = ProjectFinancialRecord(projectId: first.id, direction: .income, category: .collection, amount: 10,
                                             paymentAllocation: ProjectPaymentAllocation(planID: plan.id, installmentID: installment.id))
        let expense = ProjectFinancialRecord(projectId: first.id, direction: .expense, category: .material, amount: 8)
        var input = DashboardSummaryInput(dayContext: ProjectDayContext(now: now, calendar: calendar))
        input.projects = [first, second]
        input.quotesByProjectID = [first.id: [current, old]]
        input.financialRecords = [receipt, expense]
        input.financialRecordsByProjectID = [first.id: [receipt, expense]]
        let summary = DashboardSummaryBuilder.build(input).businessSummary
        #expect(summary.scope?.selectedQuoteAmount == 20)
        #expect(summary.scope?.contractUnpaid == 90 && summary.unpaidAmount == 90)
        #expect(summary.scope?.duePlanAmount == 20 && summary.scope?.futurePlanAmount == 0)
        #expect(summary.scope?.materialEstimate == 10 && summary.scope?.laborEstimate == 20)
        #expect(summary.scope?.formalExpense == 8 && summary.scope?.estimatedProfit == 170)
    }

    @Test func directBusinessScopeKeepsUnresolvedAmountsAndSchedulesUnknown() {
        let zone = TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let installment = ProjectPaymentInstallment(title: "一期", dueDate: BusinessDateValue(legacyText: "2026-10-27"), amount: 30)
        let plan = ProjectPaymentPlan(title: "计划", direction: .income, counterparty: "客户", installments: [installment])
        let project = Project(name: "A", location: "", contractAmount: 100, paidAmount: 10, materialCost: 50,
                              laborCost: 20, paymentPlans: [plan])
        let material = MaterialItem(name: "未填单价", quantity: 2, unit: "m", projectId: project.id)
        let quote = QuoteItem(name: "待选择", unitPrice: 10, quantity: 1, unit: "项", notes: "", taxRate: 0,
                              discountRate: 0, versionName: "V1", status: .confirmed, projectId: project.id)
        let emptyReceipt = ProjectFinancialRecord(projectId: project.id, direction: .income, category: .collection, amount: .empty)
        var input = DashboardSummaryInput(dayContext: ProjectDayContext(now: Date(), calendar: calendar))
        input.projects = [project]
        input.materialsByProjectID = [project.id: [material]]
        input.quotesByProjectID = [project.id: [quote]]
        input.financialRecords = [emptyReceipt]
        input.financialRecordsByProjectID = [project.id: [emptyReceipt]]
        let scope = DashboardSummaryBuilder.build(input).businessSummary.scope
        #expect(scope?.selectedQuoteAmount == nil && scope?.quoteProjectsNeedingReview == 1)
        #expect(scope?.contractUnpaid == nil && scope?.materialEstimate == nil && scope?.estimatedProfit == nil)
        #expect(scope?.duePlanAmount == nil && scope?.plansNeedingReview == 1)
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
