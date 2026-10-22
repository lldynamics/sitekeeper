import Foundation
import Testing
import UIKit
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

    @Test(arguments: [
        ("Asia/Shanghai", "2026-10-13T00:30:00+08:00"),
        ("America/Los_Angeles", "2026-10-13T00:30:00-07:00")
    ])
    func builderDoesNotTreatTodaysLocalDeadlineAsOverdue(zoneID: String, nowText: String) throws {
        let zone = try #require(TimeZone(identifier: zoneID))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = try #require(ISO8601DateFormatter().date(from: nowText))
        let future = WidgetBuilderProjectInput(id: UUID(), name: "A future", status: "active", isActive: true)
        let today = WidgetBuilderProjectInput(id: UUID(), name: "B today", status: "active", isActive: true)
        let overdue = WidgetBuilderProjectInput(id: UUID(), name: "C overdue", status: "active", isActive: true)

        let result = WidgetDataBuilder.build(
            projects: [today, overdue, future],
            todos: [
                WidgetBuilderTodoInput(projectId: future.id, isDone: false, dueDate: "2026-10-14"),
                WidgetBuilderTodoInput(projectId: today.id, isDone: false, dueDate: "2026-10-13"),
                WidgetBuilderTodoInput(projectId: overdue.id, isDone: false, dueDate: "2026-10-12")
            ],
            tasks: [],
            stockLines: [],
            now: now,
            calendar: calendar
        )

        // Only yesterday's deadline has priority; today's deadline ties with a future day.
        #expect(result.projects.map(\.id) == [overdue.id, future.id, today.id])
    }

    @Test(arguments: [
        ("Asia/Shanghai", "2026-10-13T00:30:00+08:00", "2026-10-12T15:30:00Z", "2026-10-12T17:30:00.000Z"),
        ("America/Los_Angeles", "2026-10-13T00:30:00-07:00", "2026-10-13T01:30:00+08:00", "2026-10-13T08:30:00.000Z")
    ])
    func builderUsesExplicitTimestampOffsetsForLocalDeadlineRisk(
        zoneID: String, nowText: String, overdueText: String, todayText: String
    ) throws {
        let zone = try #require(TimeZone(identifier: zoneID))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = try #require(ISO8601DateFormatter().date(from: nowText))
        let today = WidgetBuilderProjectInput(id: UUID(), name: "A today", status: "active", isActive: true)
        let overdue = WidgetBuilderProjectInput(id: UUID(), name: "B overdue", status: "active", isActive: true)
        let future = WidgetBuilderProjectInput(id: UUID(), name: "C future", status: "active", isActive: true)

        let result = WidgetDataBuilder.build(
            projects: [today, future, overdue],
            todos: [
                WidgetBuilderTodoInput(projectId: today.id, isDone: false, dueDate: todayText),
                WidgetBuilderTodoInput(projectId: overdue.id, isDone: false, dueDate: overdueText),
                WidgetBuilderTodoInput(projectId: future.id, isDone: false, dueDate: "2026-10-14")
            ],
            tasks: [],
            stockLines: [],
            now: now,
            calendar: calendar
        )

        #expect(result.projects.map(\.id) == [overdue.id, today.id, future.id])
    }

    @Test func backupRiskRefreshesWhenTheWidgetTimelineAdvances() {
        let lastBackup = Formatters.date.date(from: "2026-05-01")!.timeIntervalSince1970
        let data = WidgetExportData(
            projects: [],
            pendingTodos: 0,
            materialStockCount: 0,
            lowStockCount: 0,
            backupOverdueCount: 0,
            backupLastSuccessAt: lastBackup,
            backupReminderDays: 7,
            lastUpdatedAt: lastBackup
        )

        #expect(data.refreshingTimeSensitiveRisks(at: Formatters.date.date(from: "2026-05-07")!).backupOverdueCount == 0)
        #expect(data.refreshingTimeSensitiveRisks(at: Formatters.date.date(from: "2026-05-08")!).backupOverdueCount == 1)
    }

    @Test func widgetTimelineUsesCurrentDateButDisplaysStoredUpdateDate() throws {
        let root = try Self.repositoryRoot()
        let source = try Self.sourceText(root, "Widget/SitekeeperWidget.swift")
        let views = try Self.sourceText(root, "Widget/WidgetViews.swift")

        #expect(source.contains("let entry = WidgetEntry(date: now, data: data)"))
        #expect(source.contains("data.lastUpdatedDate ?? date"))
        #expect(views.contains("entry.lastUpdatedDate"))
        #expect(views.contains("string(from: entry.date)") == false)
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

    @Test func widgetViewsAreSplitByFamilyAndLayoutLayers() throws {
        let root = try Self.repositoryRoot()
        let familyViews = try Self.sourceText(root, "Widget/WidgetViews.swift")
        let layoutViews = try Self.sourceText(root, "Widget/WidgetLayoutComponents.swift")
        let supportViews = try Self.sourceText(root, "Widget/WidgetViewSupport.swift")

        #expect(Self.lineCount(of: familyViews) < 320)
        #expect(Self.lineCount(of: layoutViews) < 320)
        #expect(Self.lineCount(of: supportViews) < 360)

        #expect(familyViews.contains("struct SmallWidgetView"))
        #expect(familyViews.contains("struct MediumWidgetView"))
        #expect(familyViews.contains("struct LargeWidgetView"))
        #expect(familyViews.contains("WidgetLocalizedText") == false)

        #expect(layoutViews.contains("struct WidgetSectionHeader"))
        #expect(layoutViews.contains("struct WidgetCompactSignalRow"))
        #expect(layoutViews.contains("struct WidgetProjectProgressRow"))
        #expect(layoutViews.contains("widgetRiskLinkItems") == false)

        #expect(supportViews.contains("enum WidgetDeepLinkURL"))
        #expect(supportViews.contains("enum WidgetLocalizedText"))
        #expect(supportViews.contains("func widgetPrimarySignal"))
    }

    @Test func widgetTextFitsMinimumPixelBudgets() {
        let compactFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let metaFont = UIFont.systemFont(ofSize: 11, weight: .regular)

        let compactCases: [WidgetTextPixelBudget] = [
            .init(id: "compact-risk-en-missing-receipt", text: "No receipt 99", font: compactFont, minimumScaleFactor: 0.78, leadingChrome: 18, availableWidth: 108),
            .init(id: "compact-risk-en-backup-overdue", text: "Backup 99", font: compactFont, minimumScaleFactor: 0.78, leadingChrome: 18, availableWidth: 108),
            .init(id: "compact-risk-zh-price-spike", text: "价格异动 99", font: compactFont, minimumScaleFactor: 0.78, leadingChrome: 18, availableWidth: 108)
        ]
        for item in compactCases {
            Self.expectFitsSingleLine(item)
        }

        let pillCases: [WidgetTextPixelBudget] = [
            .init(id: "pill-en-backup-overdue", text: "Backup 99", font: compactFont, minimumScaleFactor: 0.78, leadingChrome: 29, availableWidth: 104),
            .init(id: "pill-en-missing-receipt", text: "No receipt 99", font: compactFont, minimumScaleFactor: 0.78, leadingChrome: 29, availableWidth: 104),
            .init(id: "pill-zh-backup-overdue", text: "备份超期 99", font: compactFont, minimumScaleFactor: 0.78, leadingChrome: 29, availableWidth: 104)
        ]
        for item in pillCases {
            Self.expectFitsSingleLine(item)
        }

        let metadataCases: [WidgetTextPixelBudget] = [
            .init(id: "updated-time-en", text: "Updated 12:30", font: metaFont, minimumScaleFactor: 1, leadingChrome: 0, availableWidth: 108),
            .init(id: "updated-time-zh", text: "更新 12:30", font: metaFont, minimumScaleFactor: 1, leadingChrome: 0, availableWidth: 108)
        ]
        for item in metadataCases {
            Self.expectFitsSingleLine(item)
        }
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

    private static func lineCount(of source: String) -> Int {
        source.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private static func expectFitsSingleLine(_ item: WidgetTextPixelBudget) {
        let naturalWidth = ceil((item.text as NSString).size(withAttributes: [.font: item.font]).width)
        let scaledWidth = naturalWidth * item.minimumScaleFactor
        let requiredWidth = scaledWidth + item.leadingChrome
        #expect(requiredWidth <= item.availableWidth, "\(item.id): requires \(requiredWidth), budget \(item.availableWidth)")
    }
}

private struct WidgetTextPixelBudget {
    let id: String
    let text: String
    let font: UIFont
    let minimumScaleFactor: CGFloat
    let leadingChrome: CGFloat
    let availableWidth: CGFloat
}
