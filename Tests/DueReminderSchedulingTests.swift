import Foundation
import Testing
import UserNotifications
@testable import sitekeeper

@MainActor
struct DueReminderSchedulingTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 10))!
    }

    private func overdueSnapshot(count: Int = 60) -> DueReminderSnapshot {
        DueReminderSnapshot(
            projects: [],
            todos: (0..<count).map { SiteTodo(title: "Overdue \($0)", dueDate: BusinessDateValue(legacyText: "2026-10-14")) },
            financialRecords: []
        )
    }

    @Test func overdueBacklogLeavesFutureReminderScheduled() throws {
        let future = SiteTodo(title: "Tomorrow", dueDate: BusinessDateValue(legacyText: "2026-10-16"))
        let overdue = overdueSnapshot()
        let snapshot = DueReminderSnapshot(projects: [], todos: overdue.todos + [future], financialRecords: [])
        let plans = DueReminderPlanBuilder.makePlans(snapshot: snapshot, now: now, calendar: calendar)
        #expect(plans.count == 2)
        #expect(plans.contains { $0.identifier.hasSuffix(future.id.uuidString) })
        let summary = try #require(plans.first { $0.kind == .overdueSummary })
        #expect(summary.fireDate == now.addingTimeInterval(60))
        #expect(DueReminderPlanBuilder.makePlans(snapshot: snapshot, now: now, calendar: calendar, limit: 1)
            .map(\.kind) == [.todo])
        #expect(DueReminderPlanBuilder.makePlans(snapshot: snapshot, now: now, calendar: calendar, limit: 0).isEmpty)
    }

    @Test func futureQuotaAndClosedItemsAreRespected() {
        let future = (0..<70).map { SiteTodo(title: "Future \($0)", dueDate: BusinessDateValue(legacyText: "2026-10-16")) }
        let closed = SiteTodo(title: "Closed", dueDate: BusinessDateValue(legacyText: "2026-10-14"), isDone: true)
        let snapshot = DueReminderSnapshot(projects: [], todos: future + overdueSnapshot().todos + [closed], financialRecords: [])
        let plans = DueReminderPlanBuilder.makePlans(snapshot: snapshot, now: now, calendar: calendar)
        #expect(plans.count == 60)
        #expect(plans.allSatisfy { $0.kind == .todo && $0.fireDate > now })
    }

    @Test func storedGregorianDatesKeepTheirMeaningWithBuddhistSystemCalendar() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = TimeZone(identifier: "Asia/Bangkok")!
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = buddhist.timeZone
        let tomorrow = SiteTodo(title: "Tomorrow", dueDate: BusinessDateValue(legacyText: "2026-10-16"))
        let plans = DueReminderPlanBuilder.makePlans(
            snapshot: DueReminderSnapshot(projects: [], todos: [tomorrow], financialRecords: []),
            now: now, calendar: buddhist
        )
        let plan = try #require(plans.first)
        #expect(plan.kind == .todo)
        #expect(plan.fireDate == gregorian.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 9)))
    }

    @Test func summaryCombinesFinancialAndTodoItemsAndRejectsInvalidDates() throws {
        let financial = ProjectFinancialRecord(projectId: UUID(), direction: .income, amount: NumericInputSupport.money("100"), dueDate: BusinessDateValue(legacyText: "2026-10-14"), reminderStatus: .pending)
        let invalid = SiteTodo(title: "Invalid date", dueDate: BusinessDateValue(legacyText: "2026-02-30"))
        let snapshot = DueReminderSnapshot(projects: [], todos: overdueSnapshot(count: 1).todos + [invalid], financialRecords: [financial])
        let plans = DueReminderPlanBuilder.makePlans(snapshot: snapshot, now: now, calendar: calendar)
        let summary = try #require(plans.first)
        #expect(plans.count == 1)
        #expect(summary.kind == .overdueSummary)
        #expect(summary.body.contains("1"))
        #expect(!summary.body.contains("2"))
    }

    @Test func refreshPreservesPendingTriggerAndDoesNotRepeatDeliveredSummaryAfterRestart() async throws {
        let fixture = ReminderFixture()
        defer { fixture.cleanUp() }
        var instant = now
        let scheduler = DueReminderNotificationScheduler(center: fixture.center, preferences: fixture.preferences, now: { instant }, calendar: calendar)
        await scheduler.refresh(snapshot: overdueSnapshot())
        let original = try #require(fixture.center.requests.values.first)
        instant = instant.addingTimeInterval(30)
        await scheduler.refresh(snapshot: overdueSnapshot(count: 1))
        #expect(fixture.center.added.count == 2)
        #expect(fixture.center.requests[original.identifier]?.content.body.contains("60") == false)
        #expect((fixture.center.requests[original.identifier]?.trigger as? UNCalendarNotificationTrigger)?.dateComponents
            == (original.trigger as? UNCalendarNotificationTrigger)?.dateComponents)

        // Simulate system delivery and then a cold app launch with the same preferences.
        fixture.center.requests.removeAll()
        let restarted = DueReminderNotificationScheduler(center: fixture.center, preferences: fixture.preferences, now: { instant }, calendar: calendar)
        await restarted.refresh(snapshot: overdueSnapshot())
        #expect(fixture.center.requests.isEmpty)
        #expect(fixture.center.added.count == 2)
        instant = calendar.date(byAdding: .day, value: 1, to: instant)!
        await restarted.refresh(snapshot: overdueSnapshot())
        #expect(fixture.center.requests.count == 1)
        #expect(fixture.center.added.count == 3)
    }

    @Test func completionRemovesSummaryAndFailedSchedulingCanRetry() async {
        let fixture = ReminderFixture()
        defer { fixture.cleanUp() }
        fixture.center.failNextAdd = true
        let scheduler = DueReminderNotificationScheduler(center: fixture.center, preferences: fixture.preferences, now: { now }, calendar: calendar)
        await scheduler.refresh(snapshot: overdueSnapshot())
        #expect(!fixture.preferences.contains(UserPreferenceKeys.dueOverdueSummaryScheduledAt))
        await scheduler.refresh(snapshot: overdueSnapshot())
        #expect(fixture.center.requests.count == 1)
        await scheduler.refresh(snapshot: DueReminderSnapshot(projects: [], todos: [], financialRecords: []))
        #expect(fixture.center.requests.isEmpty)
    }

    @Test func disablingWaitsForSuspendedAddThenRemovesOnlyAppRequests() async {
        let fixture = ReminderFixture()
        defer { fixture.cleanUp() }
        let unrelated = UNNotificationRequest(identifier: "other-feature", content: UNMutableNotificationContent(), trigger: nil)
        fixture.center.requests[unrelated.identifier] = unrelated
        let gate = ReminderAddGate()
        fixture.center.beforeAdd = { await gate.suspend() }
        let scheduler = DueReminderNotificationScheduler(center: fixture.center, preferences: fixture.preferences, now: { now }, calendar: calendar)
        let refresh = Task { await scheduler.refresh(snapshot: overdueSnapshot(count: 1)) }
        await gate.waitUntilSuspended()
        let clear = Task { await scheduler.clearPendingNotifications() }
        await Task.yield()
        gate.resume()
        await refresh.value
        await clear.value
        #expect(Set(fixture.center.requests.keys) == ["other-feature"])
    }

    @Test func cancellingUndeliveredSummaryAllowsSameDayRescheduling() async {
        let fixture = ReminderFixture()
        defer { fixture.cleanUp() }
        let scheduler = DueReminderNotificationScheduler(center: fixture.center, preferences: fixture.preferences, now: { now }, calendar: calendar)
        await scheduler.refresh(snapshot: overdueSnapshot(count: 1))
        await scheduler.clearPendingNotifications()
        #expect(fixture.center.requests.isEmpty)
        #expect(!fixture.preferences.contains(UserPreferenceKeys.dueOverdueSummaryScheduledAt))
        await scheduler.refresh(snapshot: overdueSnapshot(count: 1))
        #expect(fixture.center.requests.count == 1)
        #expect(fixture.center.added.count == 2)
    }
}

@MainActor
private struct ReminderFixture {
    let suite = "DueReminderSchedulingTests.\(UUID().uuidString)"
    let center = FakeReminderCenter()
    let preferences: UserPreferencesStore

    init() {
        preferences = UserPreferencesStore(defaults: UserDefaults(suiteName: suite)!)
    }

    func cleanUp() { preferences.removePersistentDomain(forName: suite) }
}

@MainActor
private final class FakeReminderCenter: DueReminderNotificationDelivering {
    var requests: [String: UNNotificationRequest] = [:]
    var added: [String] = []
    var failNextAdd = false
    var beforeAdd: (() async -> Void)?

    func requestAuthorization(options _: UNAuthorizationOptions) async throws -> Bool { true }
    func pendingNotificationRequests() async -> [UNNotificationRequest] { Array(requests.values) }
    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        for identifier in identifiers { requests.removeValue(forKey: identifier) }
    }

    func add(_ request: UNNotificationRequest) async throws {
        await beforeAdd?()
        if failNextAdd {
            failNextAdd = false
            throw CocoaError(.fileWriteUnknown)
        }
        requests[request.identifier] = request
        added.append(request.identifier)
    }
}

@MainActor
private final class ReminderAddGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation {
            continuation = $0
            started?.resume()
            started = nil
        }
    }

    func waitUntilSuspended() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
