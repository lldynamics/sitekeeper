import Foundation

/// Inclusive civil-day range. Undated and unresolved legacy values never acquire a date.
struct ProjectReportPeriod {
    let start: CalendarDay
    let end: CalendarDay
    let timeZone: TimeZone

    init(start: Date, end: Date, timeZone: TimeZone = .current) {
        self.start = CalendarDay(date: start, timeZone: timeZone)
        self.end = CalendarDay(date: end, timeZone: timeZone)
        self.timeZone = timeZone
    }

    var isValid: Bool { start <= end }
    var displayText: String { "\(start.storageText) – \(end.storageText)" }

    func contains(_ value: BusinessDateValue) -> Bool {
        guard isValid, let day = value.calendarDay(in: timeZone) else { return false }
        return start <= day && day <= end
    }
}

struct ProjectFieldReportPhoto: Identifiable {
    let logID: UUID
    let date: BusinessDateValue
    let photo: LogPhoto
    let attachmentIndex: Int
    // Legacy single-photo attachments receive a fresh UUID when adapted by
    // DailyLog.photoAttachments. File name + position keeps selection stable.
    var id: String { "\(logID.uuidString)-\(photo.fileName)-\(attachmentIndex)" }
}

struct ProjectFieldReport {
    let projectID: UUID
    let projectName: String
    let period: ProjectReportPeriod
    let logs: [DailyLog]
    let completedTodos: [SiteTodo]
    let currentOpenTodos: [SiteTodo]
    let currentProgress: [ProgressTask]
    let excludedUndatedLogCount: Int
    let excludedUndatedCompletionCount: Int

    var photos: [ProjectFieldReportPhoto] {
        logs.flatMap { log in
            log.photoAttachments.enumerated().map {
                ProjectFieldReportPhoto(logID: log.id, date: log.date, photo: $0.element, attachmentIndex: $0.offset)
            }
        }
    }

    init(project: Project, period: ProjectReportPeriod, logs: [DailyLog], todos: [SiteTodo], tasks: [ProgressTask]) {
        projectID = project.id
        projectName = project.name
        self.period = period
        let scopedLogs = logs.filter { $0.projectId == project.id }
        let scopedTodos = todos.filter { $0.projectId == project.id }
        self.logs = scopedLogs.filter { period.contains($0.date) }.sorted { $0.date < $1.date }
        completedTodos = scopedTodos.filter { todo in
            todo.isDone && todo.completedAt.map(period.contains) == true
        }.sorted { ($0.completedAt ?? .empty) < ($1.completedAt ?? .empty) }
        currentOpenTodos = scopedTodos.filter { !$0.isDone }.sorted { $0.dueDate < $1.dueDate }
        currentProgress = tasks.filter { $0.projectId == project.id }.sorted { $0.title < $1.title }
        excludedUndatedLogCount = scopedLogs.filter { $0.date.calendarDay(in: period.timeZone) == nil }.count
        excludedUndatedCompletionCount = scopedTodos.filter {
            $0.isDone && $0.completedAt?.calendarDay(in: period.timeZone) == nil
        }.count
    }
}

/// An allowlist for customer delivery. It cannot contain finance notes, costs,
/// counterparties, invoice numbers, attachment identifiers, or contact details.
struct ProjectCustomerStatement {
    struct Receipt: Identifiable {
        let id: UUID
        let date: BusinessDateValue
        let amount: MoneyValue
    }

    struct PlannedReceipt: Identifiable {
        let id: UUID
        let title: String
        let dueDate: BusinessDateValue
        let amount: MoneyValue
    }

    enum PaidSource { case recordedCollections, historicalManual }

    let projectID: UUID
    let projectName: String
    let period: ProjectReportPeriod
    let contractAmount: MoneyValue
    /// Current cumulative amount, never presented as the balance at period end.
    let currentCumulativePaid: MoneyValue
    let paidSource: PaidSource
    let currentOutstanding: MoneyValue
    let periodReceipts: [Receipt]
    let periodReceived: MoneyValue
    let undatedReceiptCount: Int
    let plannedReceipts: [PlannedReceipt]

    init(project: Project, period: ProjectReportPeriod, records: [ProjectFinancialRecord]) {
        projectID = project.id
        projectName = project.name
        self.period = period
        contractAmount = project.contractAmount
        let collections = records.filter {
            $0.projectId == project.id && $0.countsInBusinessMetrics && $0.isCollectionIncome
        }
        let recorded = ProjectFinancialMetrics.strictCollectionAmount(collections) ?? MoneyValue(.nan)
        currentCumulativePaid = ProjectFinancialMetrics.effectivePaidAmount(
            recordedCollectionAmount: recorded, manualPaidAmount: project.paidAmount
        )
        paidSource = recorded.isPositive || (!recorded.isValid && !recorded.isEmpty)
            ? .recordedCollections : .historicalManual
        currentOutstanding = project.contractAmount.isEmpty ? .empty : ProjectFinancialMetrics.unpaidAmount(
            contractAmount: project.contractAmount, paidAmount: currentCumulativePaid
        )
        periodReceipts = collections.filter { period.contains($0.date) }
            .sorted { $0.date < $1.date }
            .map { Receipt(id: $0.id, date: $0.date, amount: $0.amount) }
        periodReceived = periodReceipts.allSatisfy { $0.amount.isValid && !$0.amount.isNegative }
            ? periodReceipts.reduce(MoneyValue.zero) { $0 + $1.amount } : MoneyValue(.nan)
        undatedReceiptCount = collections.filter { $0.date.calendarDay(in: period.timeZone) == nil }.count
        // A payment plan is a schedule, not evidence of payment. Expense plans stay internal.
        plannedReceipts = project.paymentPlans.filter { $0.direction == .income && !$0.isArchived }
            .flatMap { plan in
                plan.installments.map {
                    PlannedReceipt(id: $0.id, title: $0.title, dueDate: $0.dueDate, amount: $0.amount)
                }
            }.sorted { $0.dueDate < $1.dueDate }
    }
}
