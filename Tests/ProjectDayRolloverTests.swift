import Foundation
import Observation
import Testing
@testable import sitekeeper

@MainActor
struct ProjectDayRolloverTests {
    @Test func midnightRefreshUpdatesOverdueAndTodayLogsWithoutEditingRecords() throws {
        let clock = DayTestClock("2026-10-22T15:59:59Z", zone: "Asia/Shanghai")
        let store = clock.makeStore()
        let project = Project(name: "跨日项目", location: "", status: .active)
        store.setProjects([project])
        store.setDailyLogs([DailyLog(date: BusinessDateValue(legacyText: "2026-10-22"), weather: "", content: "保留原文", workers: NumericInputSupport.quantity("1"), projectId: project.id)])
        store.setProgressTasks([
            task(project.id, completion: 0.5), task(project.id, completion: 1)
        ])
        store.setSiteTodos([
            SiteTodo(title: "未完成", dueDate: BusinessDateValue(legacyText: "2026-10-22"), projectId: project.id),
            SiteTodo(title: "已完成", dueDate: BusinessDateValue(legacyText: "2026-10-22"), isDone: true, projectId: project.id),
            SiteTodo(title: "无项目", dueDate: BusinessDateValue(legacyText: "2026-10-22"))
        ])
        let before = try businessRecordData(store)
        let searchVersion = store.fileSearchVersion
        let reminderVersion = store.dueReminderVersion
        #expect(store.totalOverdueItemCount == 0)
        #expect(store.hasTodayLog(for: project.id))
        #expect(store.missingTodayLogActiveProjectCount == 0)

        clock.now = Self.instant("2026-10-22T16:00:00Z")
        #expect(store.refreshDateSensitiveStateIfNeeded())

        let summary = store.projectActivitySummary(for: project.id)
        #expect(summary.overdueProgressCount == 1)
        #expect(summary.overdueTodoCount == 1)
        #expect(summary.openTodoCount == 1)
        #expect(store.totalOverdueItemCount == 2)
        #expect(!store.hasTodayLog(for: project.id))
        #expect(store.missingTodayLogActiveProjectCount == 1)
        #expect(store.dueReminderVersion == reminderVersion + 1)
        #expect(store.fileSearchVersion == searchVersion)
        #expect(try businessRecordData(store) == before)
    }

    @Test func todayLogLookupAlsoRefreshesOverdueIndexAfterMidnight() {
        let clock = DayTestClock("2026-10-22T15:59:59Z", zone: "Asia/Shanghai")
        let store = clock.makeStore()
        let projectID = UUID()
        store.setProgressTasks([task(projectID, completion: 0)])
        #expect(store.totalOverdueItemCount == 0)
        clock.now = Self.instant("2026-10-22T16:00:00Z")
        #expect(!store.hasTodayLog(for: projectID))
        #expect(store.projectActivitySummary(for: projectID).overdueProgressCount == 1)
    }

    @Test func foregroundRefreshCatchesSeveralBackgroundDaysAndInvalidatesObservers() async {
        let clock = DayTestClock("2026-10-22T15:59:59Z", zone: "Asia/Shanghai")
        let store = clock.makeStore()
        let projectID = UUID()
        store.setProgressTasks([task(projectID, completion: 0)])
        await confirmation(expectedCount: 1) { changed in
            withObservationTracking {
                _ = store.projectActivitySummary(for: projectID).overdueItemCount
            } onChange: {
                changed()
            }
            clock.now = Self.instant("2026-10-25T01:00:00Z")
            #expect(store.refreshDateSensitiveStateIfNeeded())
        }
        #expect(store.projectActivitySummary(for: projectID).overdueItemCount == 1)
        #expect(store.dayContext.day.storageText == "2026-10-25")
    }

    @Test func timezoneChangeReinterpretsDayWithoutChangingDateTextsOrLegacyInstants() throws {
        let clock = DayTestClock("2026-10-22T20:00:00Z", zone: "America/Los_Angeles")
        let store = clock.makeStore()
        let projectID = UUID()
        store.setProgressTasks([task(projectID, completion: 0)])
        store.setSiteTodos([SiteTodo(title: "检查", dueDate: BusinessDateValue(legacyText: "2026-10-22"), projectId: projectID)])
        store.setDailyLogs([DailyLog(date: BusinessDateValue(legacyText: "2026-10-22"), weather: "", content: "", workers: NumericInputSupport.quantity(""), projectId: projectID)])
        let before = try businessRecordData(store)
        let legacyInstant = Formatters.parseDateOrDateTime("2026-10-22 08:30", timeZone: clock.calendar.timeZone)
        #expect(store.totalOverdueItemCount == 0)
        #expect(store.hasTodayLog(for: projectID))

        clock.calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        #expect(store.refreshDateSensitiveStateIfNeeded())
        #expect(store.dayContext.day.storageText == "2026-10-23")
        #expect(store.totalOverdueItemCount == 2)
        #expect(!store.hasTodayLog(for: projectID))
        #expect(try businessRecordData(store) == before)
        #expect(Formatters.parseDateOrDateTime("2026-10-22 08:30", timeZone: clock.calendar.timeZone) == legacyInstant)

        clock.calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        #expect(store.refreshDateSensitiveStateIfNeeded())
        #expect(store.totalOverdueItemCount == 0)
        #expect(store.hasTodayLog(for: projectID))
    }

    @Test func repeatedSameDayRefreshDoesNotRebuildObservedIndexOrReminderVersion() async {
        let clock = DayTestClock("2026-10-22T01:00:00Z", zone: "Asia/Shanghai")
        let store = clock.makeStore()
        let projectID = UUID()
        store.setProgressTasks([task(projectID, completion: 0)])
        let version = store.dueReminderVersion
        await confirmation(expectedCount: 0) { changed in
            withObservationTracking {
                _ = store.projectActivityIndexByID
            } onChange: {
                changed()
            }
            clock.now = Self.instant("2026-10-22T15:00:00Z")
            #expect(!store.refreshDateSensitiveStateIfNeeded())
            #expect(!store.refreshDateSensitiveStateIfNeeded())
        }
        #expect(store.dueReminderVersion == version)
    }

    @Test func projectDetailSnapshotObservesDayChangeAndMatchesRefreshedIndex() async {
        let clock = DayTestClock("2026-10-22T15:59:59Z", zone: "Asia/Shanghai")
        let store = clock.makeStore()
        let finance = FinanceStore()
        let project = Project(name: "项目概览", location: "")
        store.setDailyLogs([DailyLog(date: BusinessDateValue(legacyText: "2026-10-22"), weather: "", content: "", workers: NumericInputSupport.quantity(""), projectId: project.id)])
        store.setProgressTasks([task(project.id, completion: 0)])
        store.setSiteTodos([SiteTodo(title: "待办", dueDate: BusinessDateValue(legacyText: "2026-10-22"), projectId: project.id)])
        await confirmation(expectedCount: 1) { changed in
            withObservationTracking {
                let snapshot = ProjectDetailSnapshot(project: project, projectId: project.id, projectStore: store, financeStore: finance)
                #expect(snapshot.hasTodayLog)
                #expect(snapshot.overdueProgressCount == 0)
                #expect(snapshot.overdueTodoCount == 0)
            } onChange: {
                changed()
            }
            clock.now = Self.instant("2026-10-22T16:00:00Z")
            #expect(store.refreshDateSensitiveStateIfNeeded())
        }
        let snapshot = ProjectDetailSnapshot(project: project, projectId: project.id, projectStore: store, financeStore: finance)
        #expect(!snapshot.hasTodayLog)
        #expect(snapshot.overdueProgressCount == 1)
        #expect(snapshot.overdueTodoCount == 1)
        #expect(snapshot.overdueProgressCount + snapshot.overdueTodoCount == store.totalOverdueItemCount)
    }

    @Test func dataMutationAtMidnightAlsoRefreshesReminderVersion() {
        let clock = DayTestClock("2026-10-22T15:59:59Z", zone: "Asia/Shanghai")
        let store = clock.makeStore()
        let projectID = UUID()
        store.setProgressTasks([task(projectID, completion: 0)])
        let version = store.dueReminderVersion
        clock.now = Self.instant("2026-10-22T16:00:00Z")
        store.setDailyLogs([DailyLog(date: BusinessDateValue(legacyText: "2026-10-23"), weather: "", content: "", workers: NumericInputSupport.quantity(""), projectId: projectID)])
        #expect(store.dueReminderVersion == version + 1)
        #expect(store.totalOverdueItemCount == 1)
        #expect(!store.refreshDateSensitiveStateIfNeeded())
    }

    @Test func nextBoundaryRespectsDaylightSavingAndTimezoneChangesWithinSameDate() {
        let clock = DayTestClock("2026-03-08T08:00:00Z", zone: "America/Los_Angeles")
        let store = clock.makeStore()
        #expect(store.secondsUntilNextDay == 23 * 60 * 60)
        clock.now = Self.instant("2026-03-08T20:00:00Z")
        #expect(store.secondsUntilNextDay == 11 * 60 * 60)
        clock.calendar.timeZone = TimeZone(identifier: "America/New_York")!
        #expect(store.refreshDateSensitiveStateIfNeeded())
        #expect(store.dayContext.day.storageText == "2026-03-08")
        #expect(store.secondsUntilNextDay == 8 * 60 * 60)
    }

    private func task(_ projectID: UUID, completion: Double) -> ProgressTask {
        ProgressTask(projectId: projectID, title: "进度", startDate: BusinessDateValue(legacyText: "2026-10-21"), dueDate: BusinessDateValue(legacyText: "2026-10-22"), completion: completion, note: "")
    }

    private func businessRecordData(_ store: ProjectStore) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        struct Records: Encodable {
            let projects: [Project]
            let tasks: [ProgressTask]
            let todos: [SiteTodo]
            let logs: [DailyLog]
        }
        return try encoder.encode(Records(projects: store.projects, tasks: store.progressTasks, todos: store.siteTodos, logs: store.dailyLogs))
    }

    fileprivate static func instant(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }
}

@MainActor
private final class DayTestClock {
    var now: Date
    var calendar: Calendar

    init(_ text: String, zone: String) {
        now = ProjectDayRolloverTests.instant(text)
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
    }

    func makeStore() -> ProjectStore {
        ProjectStore(now: { self.now }, calendar: { self.calendar })
    }
}
