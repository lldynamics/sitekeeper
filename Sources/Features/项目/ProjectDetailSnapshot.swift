import Foundation

@MainActor
struct ProjectDetailSnapshot {
    let project: Project
    let projectId: UUID
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
        relatedMaterials = financeStore.materialItems(for: projectId)
        relatedQuotes = financeStore.quoteItems(for: projectId)
        relatedLabor = financeStore.laborRecords(for: projectId)
        relatedWarehouseMovements = projectStore.projectWarehouseMovements(for: projectId)
        relatedLogs = projectStore.dailyLogs(for: projectId)
        relatedProgress = projectStore.progressTasks(for: projectId)
        relatedDrawings = projectStore.projectDrawings(for: projectId)
            .sorted { $0.importedAt > $1.importedAt }
        relatedContacts = projectStore.projectContacts(for: projectId)
            .sorted { $0.name < $1.name }
        relatedFinancialRecords = projectStore.projectFinancialRecords(for: projectId)
            .sorted { $0.date > $1.date }
        relatedDocuments = projectStore.projectDocuments(for: projectId)
            .sorted { $0.createdAt > $1.createdAt }
        relatedQuickNotes = projectStore.quickNotes(for: projectId)
            .sorted { $0.createdAt > $1.createdAt }
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

    var quoteTotal: Double {
        relatedQuotes.reduce(0) { $0 + ReportBuilder.quoteGrandTotal($1) }
    }

    var materialCostAuto: Double {
        relatedMaterials.reduce(0) { $0 + ReportBuilder.materialLineTotal($1) }
    }

    var laborCostAuto: Double {
        relatedLabor.reduce(0) { $0 + ReportBuilder.laborLineTotal($1) }
    }

    var laborHoursTotal: Double {
        relatedLabor.reduce(0) { $0 + ReportBuilder.laborHours($1) }
    }

    var projectBookIncome: Double {
        ProjectFinancialMetrics.income(relatedFinancialRecords)
    }

    var projectBookExpense: Double {
        ProjectFinancialMetrics.expense(relatedFinancialRecords)
    }

    var overdueProgressCount: Int {
        let today = Calendar.current.startOfDay(for: Date())
        return relatedProgress.filter { task in
            guard task.clampedCompletion < 1,
                  let due = Formatters.date.date(from: task.dueDate) else { return false }
            return due < today
        }.count
    }

    var overdueTodoCount: Int {
        relatedTodos.filter(\.isOverdue).count
    }

    var openTodoCount: Int {
        relatedTodos.filter { !$0.isDone }.count
    }

    var unpricedQuoteCount: Int {
        relatedQuotes.filter { !$0.unitPriceValue.isPositive }.count
    }

    var missingReceiptCount: Int {
        relatedFinancialRecords.filter { record in
            guard record.requiresAttachment else { return false }
            let linkedByRecord = !record.linkedDocumentIds.isEmpty
            let linkedByDocument = relatedDocuments.contains { $0.linkedFinancialRecordId == record.id }
            return !(linkedByRecord || linkedByDocument)
        }.count
    }

    var unsettledFinancialCount: Int {
        relatedFinancialRecords.filter { record in
            record.normalizedStatus == .active
                && !record.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
    }

    var hasTodayLog: Bool {
        let today = Formatters.date.string(from: Date())
        return relatedLogs.contains { $0.date == today }
    }
}
