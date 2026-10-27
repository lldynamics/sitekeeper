import Foundation
import Testing
@testable import sitekeeper

struct ProgressWeekFilterTests {
    private func context(_ now: String = "2026-10-28T04:00:00Z", zone: String = "Asia/Shanghai", firstWeekday: Int = 2) -> ProjectDayContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 4
        return ProjectDayContext(now: ISO8601DateFormatter().date(from: now)!, calendar: calendar)
    }

    private func overlaps(_ start: String, _ due: String, context: ProjectDayContext) -> Bool {
        context.overlapsCurrentWeek(start: BusinessDateValue(legacyText: start), due: BusinessDateValue(legacyText: due))
    }

    @Test func includesTaskSpanningEntireWeekAndTasksWithinWeek() {
        let value = context()
        #expect(overlaps("2026-10-20", "2026-11-05", context: value))
        #expect(overlaps("2026-10-27", "2026-10-29", context: value))
        #expect(overlaps("2026-10-28", "2026-10-28", context: value))
    }

    @Test func includesBothCalendarDayEdgesAndExcludesAdjacentWeeks() {
        let value = context()
        #expect(overlaps("2026-10-20", "2026-10-26", context: value))
        #expect(overlaps("2026-11-01", "2026-11-05", context: value))
        #expect(!overlaps("2026-10-20", "2026-10-25", context: value))
        #expect(!overlaps("2026-11-02", "2026-11-05", context: value))
    }

    @Test func rejectsMissingInvalidAndReversedDatesWithoutMutatingInput() throws {
        let value = context()
        var task = ProgressTask(projectId: UUID(), title: "Boundary", startDate: BusinessDateValue(legacyText: "2026-10-29"), dueDate: BusinessDateValue(legacyText: "2026-10-27"), completion: 0.3, note: "keep")
        let before = BusinessDraftStore.fingerprint(task)
        #expect(!value.overlapsCurrentWeek(start: task.startDate, due: task.dueDate))
        #expect(BusinessDraftStore.fingerprint(task) == before)
        task.startDate = .empty
        #expect(!value.overlapsCurrentWeek(start: task.startDate, due: task.dueDate))
        #expect(!overlaps("not-a-date", "2026-10-28", context: value))
    }

    @Test func respectsConfiguredFirstWeekday() {
        let monday = context()
        let sunday = context(firstWeekday: 1)
        #expect(!overlaps("2026-10-25", "2026-10-25", context: monday))
        #expect(overlaps("2026-10-25", "2026-10-25", context: sunday))
        #expect(!overlaps("2026-11-01", "2026-11-01", context: sunday))
    }

    @Test func handlesWeekAcrossCalendarYearBoundary() {
        let value = context("2027-01-01T04:00:00Z")
        #expect(overlaps("2026-12-25", "2027-01-08", context: value))
        #expect(overlaps("2026-12-28", "2026-12-28", context: value))
        #expect(overlaps("2027-01-03", "2027-01-03", context: value))
        #expect(!overlaps("2027-01-04", "2027-01-05", context: value))
    }

    @Test func handlesDaylightSavingWeekAndLocalDateOnlyValues() {
        let value = context("2026-03-08T12:00:00Z", zone: "America/Los_Angeles")
        #expect(overlaps("2026-02-28", "2026-03-10", context: value))
        #expect(overlaps("2026-03-08", "2026-03-08", context: value))
        #expect(!overlaps("2026-03-09", "2026-03-09", context: value))
        #expect(overlaps("2026-03-09T06:30:00Z", "2026-03-09T06:59:00Z", context: value))
        #expect(!overlaps("2026-03-09T07:00:00Z", "2026-03-09T08:00:00Z", context: value))
    }
}
