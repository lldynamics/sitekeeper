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

    @Test func dataHealthUsesSharedWidgetDefaultsKeys() throws {
        let root = try Self.repositoryRoot()
        let source = try [
            "Sources/Features/我的/DataHealthView.swift",
            "Sources/Features/我的/DataHealthViewActions.swift",
            "Sources/Features/我的/DataHealthViewIssues.swift",
            "Sources/Features/我的/DataHealthSupport.swift",
            "Sources/Shared/Services/DataHealthScanner.swift"
        ]
        .map { try Self.sourceText(root, $0) }
        .joined(separator: "\n")

        #expect(source.contains("WidgetSharedDefaults.suiteName"))
        #expect(source.contains("WidgetSharedDefaults.dataKey"))
        #expect(source.contains("WidgetSharedDefaults.updatedAtKey"))
        #expect(source.contains("\"group.com.chengjinfang.sitekeeper\"") == false)
        #expect(source.contains("\"widget_data\"") == false)
        #expect(source.contains("\"widget_data_updated_at\"") == false)
    }

    @Test func localizationHardcodedUIScanIncludesWidgetTarget() throws {
        let root = try Self.repositoryRoot()
        let script = try Self.sourceText(root, "scripts/localization/check_localization_hardcoded_ui.sh")
        let integrityScript = try Self.sourceText(root, "scripts/localization/check_localization_integrity.sh")
        let widgetSource = try Self.sourceText(root, "Widget/SitekeeperWidget.swift")
        let widgetChineseStrings = try Self.sourceText(root, "Widget/zh-Hans.lproj/Localizable.strings")
        let widgetEnglishStrings = try Self.sourceText(root, "Widget/en.lproj/Localizable.strings")
        let widgetChineseInfoStrings = try Self.sourceText(root, "Widget/zh-Hans.lproj/InfoPlist.strings")
        let widgetEnglishInfoStrings = try Self.sourceText(root, "Widget/en.lproj/InfoPlist.strings")
        let projectYAML = try Self.sourceText(root, "project.yml")

        #expect(script.contains("\"Widget\""))
        #expect(script.contains("configurationDisplayName"))
        #expect(script.contains("description\\("))
        #expect(integrityScript.contains("Widget/zh-Hans.lproj/Localizable.strings"))
        #expect(integrityScript.contains("Widget/en.lproj/Localizable.strings"))
        #expect(widgetSource.contains(".configurationDisplayName(\"") == false)
        #expect(widgetSource.contains(".description(\"") == false)
        #expect(widgetSource.contains(".configurationDisplayName(Text(\"widget_configuration_display_name\"))"))
        #expect(widgetSource.contains(".description(Text(\"widget_configuration_description\"))"))
        #expect(widgetChineseStrings.contains("\"widget_configuration_display_name\" = \"工地掌柜\";"))
        #expect(widgetChineseStrings.contains("\"widget_configuration_description\" = \"今日待办、项目进度、材料库存一目了然\";"))
        #expect(widgetEnglishStrings.contains("\"widget_configuration_display_name\" = \"Sitekeeper\";"))
        #expect(widgetEnglishStrings.contains("\"widget_configuration_description\" = \"Today's to-dos, project progress, and material stock at a glance\";"))
        #expect(widgetChineseInfoStrings.contains("\"CFBundleDisplayName\" = \"工地掌柜小组件\";"))
        #expect(widgetEnglishInfoStrings.contains("\"CFBundleDisplayName\" = \"Sitekeeper Widget\";"))
        #expect(projectYAML.contains("PRODUCT_NAME: SitekeeperWidget"))
        #expect(projectYAML.contains("INFOPLIST_KEY_CFBundleDisplayName: 工地掌柜小组件"))
        #expect(projectYAML.contains("PRODUCT_NAME: 工地掌柜Widget") == false)
        #expect(projectYAML.contains("INFOPLIST_KEY_CFBundleDisplayName: 工地掌柜Widget") == false)
    }

    private static func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let projectFile = url.appendingPathComponent("project.yml")
            if FileManager.default.fileExists(atPath: projectFile.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private static func sourceText(_ root: URL, _ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
