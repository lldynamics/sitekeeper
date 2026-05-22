import SwiftUI

extension DailyLogView {
    var filtered: [DailyLog] {
        var result = store.dailyLogs
        if let filterProjectId {
            result = result.filter { $0.projectId == filterProjectId }
        }
        result = SearchMatcher.filter(
            result,
            keyword: searchText,
            extraFields: { log in
                linkedMethodTitles(for: log.linkedConstructionMethodIDs)
            }
        )
        if isDateFilterActive {
            let df = Formatters.date
            let start = Calendar.current.startOfDay(for: filterStart)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: filterEnd)) ?? filterEnd
            result = result.filter {
                guard let d = df.date(from: $0.date) else { return false }
                return d >= start && d < end
            }
        }
        return result
    }

    var selectedDateLogs: [DailyLog] {
        logs(on: selectedCalendarDate)
    }

    var calendarDays: [Date?] {
        let calendar = Calendar.current
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: calendarMonth)),
              let range = calendar.range(of: .day, in: .month, for: monthStart) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: monthStart)
        let leading = (weekday + 5) % 7
        let days = range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        }
        let trailing = (7 - ((leading + days.count) % 7)) % 7
        return Array(repeating: nil, count: leading) + days + Array(repeating: nil, count: trailing)
    }

    var isCalendarOnCurrentMonth: Bool {
        Calendar.current.isDate(calendarMonth, equalTo: Date(), toGranularity: .month)
    }

    var isTodaySelected: Bool {
        Calendar.current.isDateInToday(selectedCalendarDate)
    }

    var usesSplitLogLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var dailyLogSearchSuggestions: [RealtimeSearchSuggestion] {
        filtered.prefix(8).map { log in
            let title = log.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? log.date : log.content
            return RealtimeSearchSuggestion(
                id: "log-\(log.id.uuidString)",
                category: .log,
                entityId: log.id,
                title: title,
                subtitleParts: [
                    log.date,
                    log.projectId.flatMap { projectId in
                        store.projects.first(where: { $0.id == projectId })?.name
                    } ?? "",
                    log.safety,
                ],
                score: 100
            )
        }
    }
}
