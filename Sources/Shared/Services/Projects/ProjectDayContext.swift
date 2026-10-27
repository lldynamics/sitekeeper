import Foundation

/// A snapshot of the local calendar day. Stored date-only strings stay Gregorian days;
/// timezone changes affect their interpretation for display, never their persisted text.
struct ProjectDayContext: Equatable {
    let day: CalendarDay
    let dayStart: Date
    let nextDayStart: Date
    let calendar: Calendar

    init(now: Date, calendar: Calendar) {
        var snapshot = calendar
        // Freeze autoupdating zones so an existing context cannot change underneath equality.
        snapshot.timeZone = TimeZone(identifier: calendar.timeZone.identifier) ?? calendar.timeZone
        self.calendar = snapshot
        dayStart = snapshot.startOfDay(for: now)
        nextDayStart = snapshot.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        day = CalendarDay(date: now, timeZone: snapshot.timeZone)
    }

    func isOverdue(date: BusinessDateValue) -> Bool {
        guard let dueDate = date.date(in: calendar.timeZone) else { return false }
        return dueDate < dayStart
    }

    func overlapsCurrentWeek(start: BusinessDateValue, due: BusinessDateValue) -> Bool {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: dayStart),
              let startDate = start.date(in: calendar.timeZone),
              let dueDate = due.date(in: calendar.timeZone),
              startDate <= dueDate else { return false }
        // Due dates are inclusive; the next week's start belongs only to that week.
        return startDate < interval.end && dueDate >= interval.start
    }
}
