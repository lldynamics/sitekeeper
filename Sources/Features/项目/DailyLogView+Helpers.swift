import SwiftUI

extension DailyLogView {
    func logs(on date: Date) -> [DailyLog] {
        let key = Formatters.date.string(from: date)
        return filtered.filter { $0.date == key }
    }

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
        let today = Formatters.date.string(from: Date())
        let items = store.siteTodos.filter { todo in
            guard !todo.isDone else { return false }
            if todo.dueDate != today { return false }
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
        return title.isEmpty ? String(localized: "未命名工艺") : title
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
            String(localized: "来源: 拍照"),
            String(format: String(localized: "拍摄时间: %@"), Formatters.dateTime.string(from: capturedAt)),
            String(format: String(localized: "标签: %@"), composer.cameraPhotoTag.displayName)
        ].compactMap { $0 }.joined(separator: "\n")
    }
}
