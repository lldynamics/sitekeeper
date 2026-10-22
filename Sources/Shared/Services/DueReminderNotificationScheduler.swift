import Foundation
import UserNotifications

@MainActor
final class DueReminderNotificationScheduler {
    static let shared = DueReminderNotificationScheduler()

    private let center: any DueReminderNotificationDelivering
    private let preferences: UserPreferencesStore
    private let now: () -> Date
    private let calendar: Calendar
    private var operation: Task<Void, Never>?
    private var generation = 0

    init(
        center: (any DueReminderNotificationDelivering)? = nil,
        preferences: UserPreferencesStore = .shared,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.center = center ?? SystemDueReminderNotificationCenter()
        self.preferences = preferences
        self.now = now
        self.calendar = calendar
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
        guard preferences.bool(UserPreferenceKeys.dueNotificationsEnabled, default: false) else {
            return
        }
        await refresh(snapshot: snapshot)
    }

    func refresh(snapshot: DueReminderSnapshot) async {
        await enqueue(snapshot: snapshot)
    }

    func clearPendingNotifications() async {
        await enqueue(snapshot: nil)
    }

    private func enqueue(snapshot: DueReminderSnapshot?) async {
        guard !Task.isCancelled else { return }
        generation += 1
        let currentGeneration = generation
        let previous = operation
        let next = Task { @MainActor [weak self] in
            // Serialize center.add with removals: an older suspended add must finish
            // before disabling notifications removes its request.
            await previous?.value
            guard let self, currentGeneration == self.generation else { return }
            await self.reconcile(snapshot: snapshot, generation: currentGeneration)
        }
        operation = next
        await next.value
        if currentGeneration == generation { operation = nil }
    }

    private func reconcile(snapshot: DueReminderSnapshot?, generation currentGeneration: Int) async {
        let pending = await center.pendingNotificationRequests()
        guard currentGeneration == generation else { return }
        let instant = now()
        let plans = snapshot.map {
            DueReminderPlanBuilder.makePlans(snapshot: $0, now: instant, calendar: calendar)
        } ?? []
        let desired = desiredRequests(plans: plans, pending: pending, instant: instant)
        let desiredIDs = Set(desired.map(\.identifier))
        let obsolete = pending.map(\.identifier).filter {
            $0.hasPrefix(DueReminderPlanBuilder.notificationPrefix) && !desiredIDs.contains($0)
        }
        recordUndeliveredSummaryCancellation(pending: pending, obsolete: obsolete, instant: instant)
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        for request in desired {
            guard currentGeneration == generation else { return }
            if let existing = pending.first(where: { $0.identifier == request.identifier }),
               requestsMatch(existing, request) { continue }
            do {
                try await center.add(request)
                if request.content.userInfo["kind"] as? String == DueReminderPlan.Kind.overdueSummary.rawValue {
                    preferences.setUnixDate(instant, for: UserPreferenceKeys.dueOverdueSummaryScheduledAt)
                }
            } catch {
                StorageIssueLog.recordEvent(
                    "due_reminder.schedule_failed",
                    category: .dataStore,
                    details: ["source": "DueReminderNotificationScheduler.refresh", "identifier": request.identifier],
                    error: error
                )
            }
        }
    }

    private func recordUndeliveredSummaryCancellation(pending: [UNNotificationRequest], obsolete: [String], instant: Date) {
        // A summary cancelled before its trigger was never delivered. Allow a new
        // summary if notifications are re-enabled or another item becomes due today.
        if pending.contains(where: { request in
            guard obsolete.contains(request.identifier),
                  request.content.userInfo["kind"] as? String == DueReminderPlan.Kind.overdueSummary.rawValue,
                  let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let fireDate = calendar.date(from: trigger.dateComponents) else { return false }
            return fireDate > instant
        }) {
            preferences.removeObject(for: UserPreferenceKeys.dueOverdueSummaryScheduledAt)
        }
    }

    private func desiredRequests(plans: [DueReminderPlan], pending: [UNNotificationRequest], instant: Date) -> [UNNotificationRequest] {
        let lastSummary = preferences.unixDate(for: UserPreferenceKeys.dueOverdueSummaryScheduledAt)
        let summaryAlreadyScheduled = lastSummary.map { calendar.isDate($0, inSameDayAs: instant) } ?? false
        var desired: [UNNotificationRequest] = []
        for plan in plans {
            if plan.kind == .overdueSummary, summaryAlreadyScheduled {
                // Keep the original pending trigger instead of postponing it on
                // each refresh. Once delivered, do not enqueue it again today.
                if let existing = pending.first(where: { $0.identifier == plan.identifier }) {
                    let updated = request(for: plan)
                    desired.append(UNNotificationRequest(identifier: plan.identifier, content: updated.content, trigger: existing.trigger))
                }
            } else {
                desired.append(request(for: plan))
            }
        }
        return desired
    }

    private func request(for plan: DueReminderPlan) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.userInfo = ["kind": plan.kind.rawValue]
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.fireDate)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return UNNotificationRequest(
            identifier: plan.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    private func requestsMatch(_ lhs: UNNotificationRequest, _ rhs: UNNotificationRequest) -> Bool {
        lhs.content.title == rhs.content.title && lhs.content.body == rhs.content.body
            && (lhs.trigger as? UNCalendarNotificationTrigger)?.dateComponents
                == (rhs.trigger as? UNCalendarNotificationTrigger)?.dateComponents
    }
}
