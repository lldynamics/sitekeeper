import Foundation
import UserNotifications

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
        let projectNames = Dictionary(uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.name) })
        var plans: [DueReminderPlan] = []

        for todo in snapshot.todos where !todo.isDone {
            guard let dueDate = parsedDay(todo.dueDate, calendar: calendar) else { continue }
            let projectName = todo.projectId.flatMap { projectNames[$0] } ?? String(localized: "未关联项目")
            plans.append(
                DueReminderPlan(
                    identifier: "\(notificationPrefix)todo.\(todo.id.uuidString)",
                    kind: .todo,
                    title: String(localized: "现场待办到期提醒"),
                    body: "\(projectName) · \(todo.title) · \(todo.dueDate)",
                    fireDate: fireDate(for: dueDate, now: now, calendar: calendar)
                )
            )
        }

        for record in snapshot.financialRecords where record.isDueReminderOpen && record.normalizedStatus == .active {
            guard let dueDate = parsedDay(record.dueDate, calendar: calendar) else { continue }
            let projectName = projectNames[record.projectId] ?? String(localized: "未知项目")
            let counterparty = record.counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
            let subject = counterparty.isEmpty ? record.normalizedDirection.displayName : counterparty
            plans.append(
                DueReminderPlan(
                    identifier: "\(notificationPrefix)financial.\(record.id.uuidString)",
                    kind: .financial,
                    title: String(localized: "应收/应付到期提醒"),
                    body: "\(projectName) · \(subject) · \(ReportBuilder.money(ReportBuilder.number(record.amount))) · \(record.dueDate)",
                    fireDate: fireDate(for: dueDate, now: now, calendar: calendar)
                )
            )
        }

        return plans
            .sorted { lhs, rhs in
                if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
                return lhs.identifier < rhs.identifier
            }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    private static func parsedDay(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func fireDate(for dueDate: Date, now: Date, calendar: Calendar) -> Date {
        let scheduled = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueDate) ?? dueDate
        guard scheduled <= now else { return scheduled }
        return now.addingTimeInterval(60)
    }
}

@MainActor
final class DueReminderNotificationScheduler {
    static let shared = DueReminderNotificationScheduler()

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorizationAndRefresh(snapshot: DueReminderSnapshot) async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else {
                await clearPendingNotifications()
                return false
            }
            await refresh(snapshot: snapshot)
            return true
        } catch {
            StorageIssueLog.recordEvent(
                "due_reminder.authorization_failed",
                category: .dataStore,
                details: ["source": "DueReminderNotificationScheduler.requestAuthorizationAndRefresh"],
                error: error
            )
            return false
        }
    }

    func refreshIfEnabled(snapshot: DueReminderSnapshot) async {
        guard UserPreferencesStore.shared.bool(UserPreferenceKeys.dueNotificationsEnabled, default: false) else {
            return
        }
        await refresh(snapshot: snapshot)
    }

    func refresh(snapshot: DueReminderSnapshot) async {
        await clearPendingNotifications()
        for plan in DueReminderPlanBuilder.makePlans(snapshot: snapshot) {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.userInfo = ["kind": plan.kind.rawValue]
            let dateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: plan.fireDate
            )
            let request = UNNotificationRequest(
                identifier: plan.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
            )
            do {
                try await center.add(request)
            } catch {
                StorageIssueLog.recordEvent(
                    "due_reminder.schedule_failed",
                    category: .dataStore,
                    details: [
                        "source": "DueReminderNotificationScheduler.refresh",
                        "identifier": plan.identifier
                    ],
                    error: error
                )
            }
        }
    }

    func clearPendingNotifications() async {
        let requests = await center.pendingNotificationRequests()
        let identifiers = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(DueReminderPlanBuilder.notificationPrefix) }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
