import Foundation
import Testing
@testable import sitekeeper

struct WidgetDataBuilderTests {
    @Test func builderCountsActiveAndPausedProjectsOnly() {
        let active = WidgetBuilderProjectInput(id: UUID(), name: "A", status: "active", isActive: true)
        let paused = WidgetBuilderProjectInput(id: UUID(), name: "B", status: "paused", isActive: true)
        let archived = WidgetBuilderProjectInput(id: UUID(), name: "C", status: "archived", isActive: false)

        let result = WidgetDataBuilder.build(
            projects: [active, paused, archived],
            todos: [],
            tasks: [],
            stockLines: []
        )

        #expect(result.projects.count == 2)
        #expect(result.projects.map(\.name).contains("A"))
        #expect(result.projects.map(\.name).contains("B"))
    }

    @Test func builderComputesTodoAndStockSummary() {
        let project = WidgetBuilderProjectInput(id: UUID(), name: "现场A", status: "active", isActive: true)
        let todoOpen = WidgetBuilderTodoInput(projectId: project.id, isDone: false, dueDate: "2026-05-10")
        let todoDone = WidgetBuilderTodoInput(projectId: project.id, isDone: true, dueDate: "2026-05-10")
        let inStock = WidgetBuilderStockInput(quantity: 10)
        let outStock = WidgetBuilderStockInput(quantity: 0)

        let result = WidgetDataBuilder.build(
            projects: [project],
            todos: [todoOpen, todoDone],
            tasks: [],
            stockLines: [inStock, outStock]
        )

        #expect(result.pendingTodos == 1)
        #expect(result.materialStockCount == 1)
        #expect(result.lowStockCount == 0)
        #expect(result.projects.first?.todoCount == 1)
    }

    @Test func builderPrioritizesOverdueAndPendingRisk() {
        let now = Formatters.date.date(from: "2026-05-10")!
        let highRisk = WidgetBuilderProjectInput(id: UUID(), name: "高风险项目", status: "active", isActive: true)
        let lowRisk = WidgetBuilderProjectInput(id: UUID(), name: "低风险项目", status: "active", isActive: true)

        let result = WidgetDataBuilder.build(
            projects: [lowRisk, highRisk],
            todos: [
                WidgetBuilderTodoInput(projectId: highRisk.id, isDone: false, dueDate: "2026-05-01"),
                WidgetBuilderTodoInput(projectId: lowRisk.id, isDone: false, dueDate: "2026-05-20")
            ],
            tasks: [
                WidgetBuilderTaskInput(projectId: highRisk.id, completion: 0.2),
                WidgetBuilderTaskInput(projectId: lowRisk.id, completion: 0.8)
            ],
            stockLines: [],
            now: now
        )

        #expect(result.projects.first?.id == highRisk.id)
        #expect(result.lastUpdatedAt > 0)
    }
}
