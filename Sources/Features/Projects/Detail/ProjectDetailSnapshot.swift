import Foundation

@MainActor
struct ProjectDetailSnapshot {
    let project: Project
    let projectId: UUID
    let dayContext: ProjectDayContext
    let relatedMaterials: [MaterialItem]
    let relatedQuotes: [QuoteItem]
    let relatedLabor: [LaborRecord]
    let relatedWarehouseMovements: [ProjectWarehouseMovement]
    let relatedLogs: [DailyLog]
    let relatedProgress: [ProgressTask]
    let relatedDrawings: [ProjectDrawing]
    let relatedContacts: [ProjectContact]
    let relatedFinancialRecords: [ProjectFinancialRecord]
    let relatedDocuments: [ProjectDocument]
    let relatedQuickNotes: [QuickNote]
    let relatedTodos: [SiteTodo]

    init(project: Project, projectId: UUID, projectStore: ProjectStore, financeStore: FinanceStore) {
        self.project = project
        self.projectId = projectId
        dayContext = projectStore.dayContext
        relatedMaterials = financeStore.materialItems(for: projectId)
        relatedQuotes = financeStore.quoteItems(for: projectId)
        relatedLabor = financeStore.laborRecords(for: projectId)
        relatedWarehouseMovements = projectStore.projectWarehouseMovements(for: projectId)
        relatedLogs = projectStore.dailyLogs(for: projectId)
        relatedProgress = projectStore.progressTasks(for: projectId)
        relatedDrawings = projectStore.projectDrawings(for: projectId)
            .sorted { Formatters.isLater($0.importedAt, than: $1.importedAt) }
        relatedContacts = projectStore.projectContacts(for: projectId)
            .sorted { $0.name < $1.name }
        relatedFinancialRecords = projectStore.projectFinancialRecords(for: projectId)
            .sorted { Formatters.isLater($0.date, than: $1.date) }
        relatedDocuments = projectStore.projectDocuments(for: projectId)
            .sorted { Formatters.isLater($0.createdAt, than: $1.createdAt) }
        relatedQuickNotes = projectStore.quickNotes(for: projectId)
            .sorted { Formatters.isLater($0.createdAt, than: $1.createdAt) }
        relatedTodos = projectStore.siteTodos(for: projectId)
            .sorted { ($0.dueDate, $0.title) < ($1.dueDate, $1.title) }
    }

    func filteredDrawings(for filter: DrawingListFilter) -> [ProjectDrawing] {
        switch filter {
        case .all:
            return relatedDrawings
        case .current:
            return relatedDrawings.filter(\.isCurrentVersion)
        case .withIssue:
            let todosByID = Dictionary(uniqueKeysWithValues: relatedTodos.map { ($0.id, $0) })
            return relatedDrawings.filter {
                let linkedOpenTodoExists = $0.linkedTodoIDs
                    .compactMap { todosByID[$0] }
                    .contains { !$0.isDone }
                return linkedOpenTodoExists
                    || $0.issueStatus == .open
                    || $0.issueStatus == .inProgress
                    || ($0.issueStatus != .closed && !$0.issueNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    var quoteTotal: MoneyValue {
        relatedQuotes.reduce(MoneyValue.zero) { $0 + ReportBuilder.quoteGrandTotal($1) }
    }

    var materialCostAuto: MoneyValue {
        relatedMaterials.reduce(MoneyValue.zero) { $0 + ReportBuilder.materialLineTotal($1) }
    }

    var laborCostAuto: MoneyValue {
        relatedLabor.reduce(MoneyValue.zero) { $0 + ReportBuilder.laborLineTotal($1) }
    }

    var laborHoursTotal: QuantityValue {
        // 兼容旧概览接口；当前概览未显示此值，新的报告汇总按单位拆分。
        relatedLabor.reduce(QuantityValue.zero) { $0 + ReportBuilder.laborHours($1) }
    }

    var projectBookIncome: MoneyValue {
        ProjectFinancialMetrics.income(relatedFinancialRecords)
    }

    var projectBookExpense: MoneyValue {
        ProjectFinancialMetrics.expense(relatedFinancialRecords)
    }

    var overdueProgressCount: Int {
        relatedProgress.filter { $0.clampedCompletion < 1 && dayContext.isOverdue(date: $0.dueDate) }.count
    }

    var overdueTodoCount: Int {
        relatedTodos.filter { !$0.isDone && dayContext.isOverdue(date: $0.dueDate) }.count
    }

    var openTodoCount: Int {
        relatedTodos.filter { !$0.isDone }.count
    }

    var unpricedQuoteCount: Int {
        relatedQuotes.filter { !$0.unitPrice.isPositive }.count
    }

    var missingReceiptCount: Int {
        ProjectFinancialMetrics.missingReceiptRecords(relatedFinancialRecords) { record in
            let linkedByRecord = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = relatedDocuments.contains { $0.linkedFinancialRecordId == record.id }
            return linkedByRecord || linkedByDocument
        }.count
    }

    var unsettledFinancialCount: Int {
        relatedFinancialRecords.filter { record in
            record.normalizedStatus == .active
                && !record.dueDate.isEmpty
        }.count
    }

    var hasTodayLog: Bool {
        relatedLogs.contains { $0.date.calendarDay(in: dayContext.calendar.timeZone) == dayContext.day }
    }
}
