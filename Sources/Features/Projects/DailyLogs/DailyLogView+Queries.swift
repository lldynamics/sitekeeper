import SwiftUI
import PhotosUI
import UIKit

extension DailyLogView {
    struct CalendarDaySlot: Identifiable {
        let id: String
        let date: Date?
    }

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

    var calendarDaySlots: [CalendarDaySlot] {
        let dateFormatter = Formatters.date
        var placeholderIndex = 0
        return calendarDays.map { day in
            if let day {
                return CalendarDaySlot(
                    id: "day-\(dateFormatter.string(from: day))",
                    date: day
                )
            }
            defer { placeholderIndex += 1 }
            return CalendarDaySlot(
                id: "placeholder-\(placeholderIndex)",
                date: nil
            )
        }
    }

    var isCalendarOnCurrentMonth: Bool {
        Calendar.current.isDate(calendarMonth, equalTo: Date(), toGranularity: .month)
    }

    var isTodaySelected: Bool {
        Calendar.current.isDateInToday(selectedCalendarDate)
    }

    var usesSplitLogLayout: Bool {
        horizontalSizeClass == .regular
    }

    var dailyLogSearchSuggestions: [RealtimeSearchSuggestion] {
        filtered.prefix(8).map { log in
            let title = log.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? log.date.storageText : log.content
            return RealtimeSearchSuggestion(
                id: "log-\(log.id.uuidString)",
                category: .log,
                entityId: log.id,
                title: title,
                subtitleParts: [
                    log.date.storageText,
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

extension DailyLogView {
    func moveMonth(_ value: Int) {
        calendarMonth = Calendar.current.date(byAdding: .month, value: value, to: calendarMonth) ?? calendarMonth
    }

    func jumpToToday() {
        let today = Date()
        selectedCalendarDate = today
        calendarMonth = today
    }

    func monthTitle(_ date: Date) -> String {
        DailyLogDateFormatters.monthTitle.string(from: date)
    }

    func dayTitle(_ date: Date) -> String {
        DailyLogDateFormatters.dayTitle.string(from: date)
    }

    func generateTomorrowPlanFromTodos(for projectId: UUID?) -> String {
        let today = CalendarDay(date: Date())
        let items = store.siteTodos.filter { todo in
            guard !todo.isDone else { return false }
            if todo.dueDate.calendarDay() != today { return false }
            if let projectId {
                return todo.projectId == projectId
            }
            return true
        }
        if items.isEmpty { return "" }
        return items.map { "• \($0.title)" }.joined(separator: "\n")
    }

    func constructionMethodTitle(_ method: ConstructionMethod) -> String {
        let title = method.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? AppLocalization.string("未命名工艺") : title
    }

    func linkedMethodTitles(for ids: [UUID]) -> [String] {
        guard !ids.isEmpty else { return [] }
        let lookup = Dictionary(uniqueKeysWithValues: store.constructionMethods.map { ($0.id, constructionMethodTitle($0)) })
        return ids.compactMap { lookup[$0] }
    }

    func sortedLinkedMethodIDs(_ selectedIDs: Set<UUID>) -> [UUID] {
        store.constructionMethods
            .map(\.id)
            .filter { selectedIDs.contains($0) }
    }

    func logWatermarkPhotoNote(capturedAt: Date) -> String {
        [
            AppLocalization.string("来源: 拍照"),
            String(format: AppLocalization.string("拍摄时间: %@"), Formatters.dateTime.string(from: capturedAt)),
            String(format: AppLocalization.string("标签: %@"), composer.cameraPhotoTag.displayName)
        ].compactMap { $0 }.joined(separator: "\n")
    }
}
