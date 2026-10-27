import Foundation

enum WidgetSharedDefaults {
    static let suiteName = "group.com.chengjinfang.sitekeeper"
    static let widgetKind = "SitekeeperWidget"
    static let dataKey = "widget_data"
    static let updatedAtKey = "widget_data_updated_at"
    static let languageCodeKey = "languageCode"
    static let appleLanguagesKey = "AppleLanguages"
    static let storageIssueLogKey = "storageIssueLogEntries"
}

enum WidgetSharedStorageIssueLog {
    private static let maxEntries = 120

    @discardableResult
    static func record(_ message: String, source: String? = nil) -> Bool {
        guard let defaults = UserDefaults(suiteName: WidgetSharedDefaults.suiteName) else { return false }
        append(message, source: source, defaults: defaults)
        return true
    }

    static func entries() -> [String] {
        guard let defaults = UserDefaults(suiteName: WidgetSharedDefaults.suiteName) else { return [] }
        return defaults.stringArray(forKey: WidgetSharedDefaults.storageIssueLogKey) ?? []
    }

    static func clear() {
        guard let defaults = UserDefaults(suiteName: WidgetSharedDefaults.suiteName) else { return }
        defaults.removeObject(forKey: WidgetSharedDefaults.storageIssueLogKey)
    }

    static func append(_ message: String, source: String? = nil, defaults: UserDefaults) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let normalizedSource = source?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourcePrefix = normalizedSource.map { $0.isEmpty ? "" : "[\($0)] " } ?? ""
        let entry = "[\(timestampString(for: Date()))] \(sourcePrefix)\(trimmed)"
        var entries = defaults.stringArray(forKey: WidgetSharedDefaults.storageIssueLogKey) ?? []
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        defaults.set(entries, forKey: WidgetSharedDefaults.storageIssueLogKey)
    }

    private static func timestampString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

struct WidgetProjectSummary: Codable, Sendable {
    let id: UUID
    let name: String
    let status: String
    let progress: Double
    let todoCount: Int
}

struct WidgetExportData: Codable, Sendable {
    let projects: [WidgetProjectSummary]
    let pendingTodos: Int
    let materialStockCount: Int
    let lowStockCount: Int
    let missingReceiptCount: Int
    let priceSpikeCount: Int
    let backupOverdueCount: Int
    let backupLastSuccessAt: TimeInterval
    let backupReminderDays: Int
    let lastUpdatedAt: TimeInterval

    init(
        projects: [WidgetProjectSummary],
        pendingTodos: Int,
        materialStockCount: Int,
        lowStockCount: Int,
        missingReceiptCount: Int = 0,
        priceSpikeCount: Int = 0,
        backupOverdueCount: Int = 0,
        backupLastSuccessAt: TimeInterval = 0,
        backupReminderDays: Int = 0,
        lastUpdatedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.projects = projects
        self.pendingTodos = pendingTodos
        self.materialStockCount = materialStockCount
        self.lowStockCount = lowStockCount
        self.missingReceiptCount = missingReceiptCount
        self.priceSpikeCount = priceSpikeCount
        self.backupOverdueCount = backupOverdueCount
        self.backupLastSuccessAt = backupLastSuccessAt
        self.backupReminderDays = backupReminderDays
        self.lastUpdatedAt = lastUpdatedAt
    }

    enum CodingKeys: String, CodingKey {
        case projects
        case pendingTodos
        case materialStockCount
        case lowStockCount
        case missingReceiptCount
        case priceSpikeCount
        case backupOverdueCount
        case backupLastSuccessAt
        case backupReminderDays
        case lastUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decodeIfPresent([WidgetProjectSummary].self, forKey: .projects) ?? []
        pendingTodos = try container.decodeIfPresent(Int.self, forKey: .pendingTodos) ?? 0
        materialStockCount = try container.decodeIfPresent(Int.self, forKey: .materialStockCount) ?? 0
        lowStockCount = try container.decodeIfPresent(Int.self, forKey: .lowStockCount) ?? 0
        missingReceiptCount = try container.decodeIfPresent(Int.self, forKey: .missingReceiptCount) ?? 0
        priceSpikeCount = try container.decodeIfPresent(Int.self, forKey: .priceSpikeCount) ?? 0
        backupOverdueCount = try container.decodeIfPresent(Int.self, forKey: .backupOverdueCount) ?? 0
        backupLastSuccessAt = try container.decodeIfPresent(TimeInterval.self, forKey: .backupLastSuccessAt) ?? 0
        backupReminderDays = try container.decodeIfPresent(Int.self, forKey: .backupReminderDays) ?? 0
        lastUpdatedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .lastUpdatedAt) ?? 0
    }

    var lastUpdatedDate: Date? {
        guard lastUpdatedAt > 0 else { return nil }
        return Date(timeIntervalSince1970: lastUpdatedAt)
    }

    func refreshingTimeSensitiveRisks(at date: Date) -> Self {
        guard backupReminderDays > 0 else { return self }
        let overdue: Int
        if backupLastSuccessAt <= 0 {
            overdue = 1
        } else {
            let calendar = Calendar.current
            let start = calendar.startOfDay(for: Date(timeIntervalSince1970: backupLastSuccessAt))
            let today = calendar.startOfDay(for: date)
            let days = max(calendar.dateComponents([.day], from: start, to: today).day ?? 0, 0)
            overdue = days >= backupReminderDays ? 1 : 0
        }
        return Self(
            projects: projects,
            pendingTodos: pendingTodos,
            materialStockCount: materialStockCount,
            lowStockCount: lowStockCount,
            missingReceiptCount: missingReceiptCount,
            priceSpikeCount: priceSpikeCount,
            backupOverdueCount: overdue,
            backupLastSuccessAt: backupLastSuccessAt,
            backupReminderDays: backupReminderDays,
            lastUpdatedAt: lastUpdatedAt
        )
    }
}

struct WidgetDataHealthSnapshot: Codable, Equatable, Sendable {
    let appGroupReadable: Bool
    let lastUpdatedAt: Date?
    let projectCount: Int
    let pendingTodos: Int
}

struct WidgetBuilderProjectInput {
    let id: UUID
    let name: String
    let status: String
    let isActive: Bool
}

struct WidgetBuilderTodoInput {
    let projectId: UUID?
    let isDone: Bool
    let dueDate: String
}

struct WidgetBuilderTaskInput {
    let projectId: UUID
    let completion: Double
}

struct WidgetBuilderStockInput {
    let quantity: Decimal
}

enum WidgetProjectStatus: String {
    case active
    case paused
    case completed
    case settled
    case archived
    case unknown

    static func parse(_ raw: String) -> WidgetProjectStatus {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch text {
        case "进行中", "active", "in progress":
            return .active
        case "暂停", "paused":
            return .paused
        case "已完成", "completed", "done":
            return .completed
        case "已结算", "settled":
            return .settled
        case "已归档", "archived":
            return .archived
        default:
            return .unknown
        }
    }

}

enum WidgetDataBuilder {
    static func build(
        projects: [WidgetBuilderProjectInput],
        todos: [WidgetBuilderTodoInput],
        tasks: [WidgetBuilderTaskInput],
        stockLines: [WidgetBuilderStockInput],
        missingReceiptCount: Int = 0,
        priceSpikeCount: Int = 0,
        backupOverdueCount: Int = 0,
        backupLastSuccessAt: TimeInterval = 0,
        backupReminderDays: Int = 0,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> WidgetExportData {
        let activeProjects = projects.filter(\.isActive)
        let pendingTodosCount = todos.filter { !$0.isDone }.count
        let availableStockLineCount = stockLines.filter { $0.quantity > 0 }.count
        let negativeStockLineCount = stockLines.filter { $0.quantity < 0 }.count
        let sortedProjects = prioritizedProjects(activeProjects, todos: todos, tasks: tasks, now: now, calendar: calendar)

        return WidgetExportData(
            projects: Array(sortedProjects.prefix(5).map { $0.summary }),
            pendingTodos: pendingTodosCount,
            materialStockCount: availableStockLineCount,
            lowStockCount: negativeStockLineCount,
            missingReceiptCount: max(missingReceiptCount, 0),
            priceSpikeCount: max(priceSpikeCount, 0),
            backupOverdueCount: max(backupOverdueCount, 0),
            backupLastSuccessAt: backupLastSuccessAt,
            backupReminderDays: max(backupReminderDays, 0),
            lastUpdatedAt: now.timeIntervalSince1970
        )
    }
    private static func prioritizedProjects(
        _ activeProjects: [WidgetBuilderProjectInput], todos: [WidgetBuilderTodoInput],
        tasks: [WidgetBuilderTaskInput], now: Date, calendar: Calendar
    ) -> [(summary: WidgetProjectSummary, overdueTodos: Int)] {
        let today = calendar.startOfDay(for: now)
        let dateParser = WidgetDateParser(timeZone: calendar.timeZone)
        let tasksByProjectID = Dictionary(grouping: tasks, by: \.projectId)
        var pendingTodosByProjectID: [UUID: [WidgetBuilderTodoInput]] = [:]
        for todo in todos where !todo.isDone {
            guard let projectId = todo.projectId else { continue }
            pendingTodosByProjectID[projectId, default: []].append(todo)
        }
        return activeProjects
            .map { project -> (summary: WidgetProjectSummary, overdueTodos: Int) in
                let projectTasks = tasksByProjectID[project.id] ?? []
                let avgProgress: Double
                if projectTasks.isEmpty {
                    avgProgress = 0
                } else {
                    avgProgress = projectTasks.map(\.completion).reduce(0, +) / Double(projectTasks.count)
                }
                let pendingProjectTodos = pendingTodosByProjectID[project.id] ?? []
                let overdueTodos = pendingProjectTodos.filter { todo in
                    guard let dueDate = dateParser.date(from: todo.dueDate) else {
                        return false
                    }
                    return calendar.startOfDay(for: dueDate) < today
                }.count
                let summary = WidgetProjectSummary(
                    id: project.id,
                    name: project.name,
                    status: project.status,
                    progress: avgProgress,
                    todoCount: pendingProjectTodos.count
                )
                return (summary, overdueTodos)
            }
            .sorted { lhs, rhs in
                if lhs.overdueTodos != rhs.overdueTodos {
                    return lhs.overdueTodos > rhs.overdueTodos
                }
                if lhs.summary.todoCount != rhs.summary.todoCount {
                    return lhs.summary.todoCount > rhs.summary.todoCount
                }
                if lhs.summary.progress != rhs.summary.progress {
                    return lhs.summary.progress < rhs.summary.progress
                }
                return lhs.summary.name.localizedStandardCompare(rhs.summary.name) == .orderedAscending
            }
    }
}

// Keep a parser local to each build so every date in the risk calculation uses
// one time zone without mutating shared DateFormatter instances.
private struct WidgetDateParser {
    private let dateTimeFormatter: DateFormatter
    private let dateFormatter: DateFormatter

    init(timeZone: TimeZone) {
        dateTimeFormatter = Self.makeFormatter("yyyy-MM-dd HH:mm", timeZone: TimeZone(secondsFromGMT: 0)!)
        dateFormatter = Self.makeFormatter("yyyy-MM-dd", timeZone: timeZone)
    }

    func date(from text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasSuffix("Z"),
           let date = Self.makeFormatter("yyyy-MM-dd HH:mm:ss'Z'", timeZone: TimeZone(secondsFromGMT: 0)!).date(from: value) {
            return date
        }
        if let date = dateTimeFormatter.date(from: value) { return date }
        if let date = dateFormatter.date(from: value) { return date }
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601.date(from: value) { return date }
        iso8601.formatOptions = [.withInternetDateTime]
        return iso8601.date(from: value)
    }

    private static func makeFormatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
}
