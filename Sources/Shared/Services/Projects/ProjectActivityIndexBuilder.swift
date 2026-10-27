import Foundation

struct ProjectActivityIndexBuilder {
    let context: ProjectDayContext
    let dateFormatter: DateFormatter
    var summaries: [UUID: ProjectActivitySummary] = [:]
    var todayProjectIDs: Set<UUID> = []

    init(context: ProjectDayContext) {
        self.context = context
        dateFormatter = Formatters.dateFormatter(timeZone: context.calendar.timeZone)
    }

    mutating func add(_ values: [DailyLog]) {
        for log in values {
            guard let projectId = log.projectId else { continue }
            var summary = summaries[projectId] ?? ProjectActivitySummary()
            summary.dailyLogCount += 1
            if log.date.calendarDay(in: context.calendar.timeZone) == context.day {
                todayProjectIDs.insert(projectId)
            }
            if let logDate = dateFormatter.date(from: log.date) {
                summary.latestDailyLogDate = Self.maxDate(summary.latestDailyLogDate, logDate)
            }
            summaries[projectId] = summary
        }
    }

    mutating func add(_ values: [ProgressTask]) {
        for task in values {
            var summary = summaries[task.projectId] ?? ProjectActivitySummary()
            summary.progressTaskCount += 1
            if let startDate = dateFormatter.date(from: task.startDate) {
                summary.latestProgressDate = Self.maxDate(summary.latestProgressDate, startDate)
            }
            if let dueDate = dateFormatter.date(from: task.dueDate) {
                summary.latestProgressDate = Self.maxDate(summary.latestProgressDate, dueDate)
                if task.clampedCompletion < 1, dueDate < context.dayStart {
                    summary.overdueProgressCount += 1
                }
            }
            summaries[task.projectId] = summary
        }
    }

    mutating func add(_ values: [SiteTodo]) {
        for todo in values {
            guard let projectId = todo.projectId else { continue }
            var summary = summaries[projectId] ?? ProjectActivitySummary()
            summary.todoCount += 1
            if !todo.isDone {
                summary.openTodoCount += 1
            }
            if !todo.isDone, let dueDate = dateFormatter.date(from: todo.dueDate), dueDate < context.dayStart {
                summary.overdueTodoCount += 1
            }
            if let dueDate = dateFormatter.date(from: todo.dueDate) {
                summary.latestTodoDate = Self.maxDate(summary.latestTodoDate, dueDate)
            }
            summaries[projectId] = summary
        }
    }

    mutating func add(_ values: [ProjectDocument]) {
        for document in values {
            var summary = summaries[document.projectId] ?? ProjectActivitySummary()
            summary.documentCount += 1
            if let createdAt = Formatters.parseDateOrDateTime(document.createdAt, timeZone: context.calendar.timeZone) ?? dateFormatter.date(from: document.createdAt) {
                summary.latestDocumentDate = Self.maxDate(summary.latestDocumentDate, createdAt)
            }
            if let linkedFinancialRecordId = document.linkedFinancialRecordId {
                summary.linkedFinancialRecordIDs.insert(linkedFinancialRecordId)
            }
            summaries[document.projectId] = summary
        }
    }

    mutating func add(_ values: [ProjectDrawing]) {
        for drawing in values {
            var summary = summaries[drawing.projectId] ?? ProjectActivitySummary()
            if let importedAt = Formatters.parseDateOrDateTime(drawing.importedAt, timeZone: context.calendar.timeZone) {
                summary.latestDrawingDate = Self.maxDate(summary.latestDrawingDate, importedAt)
            }
            summaries[drawing.projectId] = summary
        }
    }

    mutating func add(_ values: [ProjectFinancialRecord]) {
        for record in values {
            var summary = summaries[record.projectId] ?? ProjectActivitySummary()
            if let financialAt = Formatters.parseDateOrDateTime(record.date, timeZone: context.calendar.timeZone) {
                summary.latestFinancialDate = Self.maxDate(summary.latestFinancialDate, financialAt)
            }
            if record.countsInBusinessMetrics, record.isCollectionIncome {
                summary.collectedIncomeAmount += record.amount
            }
            if record.countsInBusinessMetrics, record.requiresAttachment {
                let linkedByList = !record.linkedDocumentIds.isEmpty
                let linkedByDocument = summary.linkedFinancialRecordIDs.contains(record.id)
                if !(linkedByList || linkedByDocument) {
                    summary.unattachedReceiptCount += 1
                }
            }
            if record.normalizedStatus == .active,
               !record.dueDate.isEmpty {
                summary.unsettledFinancialCount += 1
            }
            summaries[record.projectId] = summary
        }
    }

    mutating func add(_ values: [ProjectWarehouseMovement]) {
        for movement in values {
            var summary = summaries[movement.projectId] ?? ProjectActivitySummary()
            if let movementAt = Formatters.parseDateOrDateTime(movement.date, timeZone: context.calendar.timeZone) {
                summary.latestWarehouseDate = Self.maxDate(summary.latestWarehouseDate, movementAt)
            }
            summaries[movement.projectId] = summary
        }
    }

    mutating func add(_ values: [QuickNote]) {
        for note in values {
            guard let projectId = note.projectId else { continue }
            var summary = summaries[projectId] ?? ProjectActivitySummary()
            if let noteAt = Formatters.parseDateOrDateTime(note.createdAt, timeZone: context.calendar.timeZone) {
                summary.latestQuickNoteDate = Self.maxDate(summary.latestQuickNoteDate, noteAt)
            }
            summaries[projectId] = summary
        }
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs else { return rhs }
        return max(lhs, rhs)
    }
}
