import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct ProductivityUpgradeTests {
    @Test func globalSearchIncludesLogsTodosNotesAndQuickEntryCommands() {
        let projectID = UUID()
        let project = Project(id: projectID, name: "东楼改造", location: "", status: .active)
        let log = DailyLog(date: "2026-07-13", weather: "晴", content: "地下室防水验收", workers: "4", projectId: projectID)
        let todo = SiteTodo(title: "更换配电箱标识", owner: "李工", dueDate: "2026-07-14", projectId: projectID)
        let note = QuickNote(title: "甲方临时要求", content: "走廊增加应急灯", projectId: projectID)

        let logResult = RealtimeSearchSuggestionBuilder.suggestions(
            keyword: "防水验收",
            categories: [.log],
            projects: [project],
            logs: [log]
        )
        let todoResult = RealtimeSearchSuggestionBuilder.suggestions(
            keyword: "配电箱",
            categories: [.todo],
            projects: [project],
            todos: [todo]
        )
        let noteResult = RealtimeSearchSuggestionBuilder.suggestions(
            keyword: "应急灯",
            categories: [.note],
            projects: [project],
            notes: [note]
        )
        let commandResult = RealtimeSearchSuggestionBuilder.suggestions(
            keyword: "记账",
            categories: [.command]
        )

        #expect(logResult.map(\.entityId) == [log.id])
        #expect(todoResult.map(\.entityId) == [todo.id])
        #expect(noteResult.map(\.entityId) == [note.id])
        #expect(commandResult.contains { $0.id == RealtimeSearchCommand.newBookkeeping.suggestionId })
    }

    @Test func dueReminderPlansExcludeClosedItemsAndCapPendingRequests() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 13, hour: 8))!
        let projectID = UUID()
        let project = Project(id: projectID, name: "东楼改造", location: "", status: .active)
        let openTodo = SiteTodo(title: "检查防护", dueDate: "2026-07-14", projectId: projectID)
        let closedTodo = SiteTodo(title: "已完成", dueDate: "2026-07-14", isDone: true, projectId: projectID)
        let openFinancial = ProjectFinancialRecord(
            projectId: projectID,
            direction: .income,
            amount: "1200",
            counterparty: "甲方",
            dueDate: "2026-07-15",
            reminderStatus: .pending
        )
        let closedFinancial = ProjectFinancialRecord(
            projectId: projectID,
            direction: .expense,
            amount: "800",
            dueDate: "2026-07-15",
            reminderStatus: .done
        )
        let snapshot = DueReminderSnapshot(
            projects: [project],
            todos: [openTodo, closedTodo],
            financialRecords: [openFinancial, closedFinancial]
        )

        let plans = DueReminderPlanBuilder.makePlans(
            snapshot: snapshot,
            now: now,
            calendar: calendar,
            limit: 1
        )

        #expect(plans.count == 1)
        #expect(plans[0].identifier.contains(openTodo.id.uuidString))
        #expect(plans[0].fireDate == calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 9)))
    }
}
