import Foundation

struct DueReminderSnapshot: Sendable {
    let projects: [Project]
    let todos: [SiteTodo]
    let financialRecords: [ProjectFinancialRecord]
}

extension DueReminderSnapshot {
    @MainActor
    init(store: DataStore) {
        self.init(
            projects: store.projects,
            todos: store.siteTodos,
            financialRecords: store.projectFinancialRecords
        )
    }
}

struct DueReminderPlan: Equatable, Sendable {
    enum Kind: String, Sendable {
        case todo
        case financial
        case overdueSummary
    }

    let identifier: String
    let kind: Kind
    let title: String
    let body: String
    let fireDate: Date
}

enum DueReminderPlanBuilder {
    static let notificationPrefix = "sitekeeper.due."

    static func makePlans(
        snapshot: DueReminderSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current,
        limit: Int = 60
    ) -> [DueReminderPlan] {
        // Stored business dates are Gregorian even when the system uses another
        // calendar. Preserve the user's time zone for the local 09:00 trigger.
        var storageCalendar = Calendar(identifier: .gregorian)
        storageCalendar.timeZone = calendar.timeZone
        let projectNames = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.name) })
        var plans: [DueReminderPlan] = []

        for todo in snapshot.todos where !todo.isDone {
            guard let dueDate = parsedDay(todo.dueDate, calendar: storageCalendar) else { continue }
            let projectName = todo.projectId.flatMap { projectNames[$0] } ?? String(localized: "未关联项目")
            plans.append(
                DueReminderPlan(
                    identifier: "\(notificationPrefix)todo.\(todo.id.uuidString)",
                    kind: .todo,
                    title: String(localized: "现场待办到期提醒"),
                    body: "\(projectName) · \(todo.title) · \(todo.dueDate)",
                    fireDate: fireDate(for: dueDate, calendar: storageCalendar)
                )
            )
        }

        for record in snapshot.financialRecords where record.isDueReminderOpen && record.normalizedStatus == .active {
            guard let dueDate = parsedDay(record.dueDate, calendar: storageCalendar) else { continue }
            let projectName = projectNames[record.projectId] ?? String(localized: "未知项目")
            let counterparty = record.counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = counterparty.isEmpty ? record.normalizedDirection.displayName : counterparty
            plans.append(
                DueReminderPlan(
                    identifier: "\(notificationPrefix)financial.\(record.id.uuidString)",
                    kind: .financial,
                    title: String(localized: "应收/应付到期提醒"),
                    body: "\(projectName) · \(subject) · \(ReportBuilder.money(ReportBuilder.number(record.amount))) · \(record.dueDate)",
                    fireDate: fireDate(for: dueDate, calendar: storageCalendar)
                )
            )
        }

        // Future reminders get the available slots first. Old tasks consume at most
        // one slot, regardless of how many unfinished records have accumulated.
        let futurePlans = plans.filter { $0.fireDate > now }
            .sorted { lhs, rhs in
                if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
                return lhs.identifier < rhs.identifier
            }
        var selected = Array(futurePlans.prefix(max(limit, 0)))
        let overdue = plans.filter { $0.fireDate <= now }
        if !overdue.isEmpty, selected.count < limit {
            selected.append(summary(for: overdue, now: now, calendar: calendar))
        }
        return selected
    }

    private static func summary(for overdue: [DueReminderPlan], now: Date, calendar: Calendar) -> DueReminderPlan {
        DueReminderPlan(
            identifier: overdueSummaryIdentifier(now: now, calendar: calendar),
            kind: .overdueSummary,
            title: String(localized: "到期事项汇总"),
            body: String(
                format: String(localized: "有 %lld 项待办及 %lld 项应收/应付已到期，请打开应用查看。"),
                Int64(overdue.filter { $0.kind == .todo }.count),
                Int64(overdue.filter { $0.kind == .financial }.count)
            ),
            fireDate: now.addingTimeInterval(60)
        )
    }

    static func overdueSummaryIdentifier(now: Date, calendar: Calendar) -> String {
        let day = calendar.dateComponents([.era, .year, .month, .day], from: now)
        return "\(notificationPrefix)overdue.\(day.era ?? 0).\(day.year ?? 0).\(day.month ?? 0).\(day.day ?? 0)"
    }

    private static func parsedDay(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == parts[0], resolved.month == parts[1], resolved.day == parts[2] else { return nil }
        return date
    }

    private static func fireDate(for dueDate: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueDate) ?? dueDate
    }
}
