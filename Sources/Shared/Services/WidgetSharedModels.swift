import Foundation

struct WidgetProjectSummary: Codable {
    let id: UUID
    let name: String
    let status: String
    let progress: Double
    let todoCount: Int
}

struct WidgetExportData: Codable {
    let projects: [WidgetProjectSummary]
    let pendingTodos: Int
    let materialStockCount: Int
    let lowStockCount: Int
    let lastUpdatedAt: TimeInterval

    init(
        projects: [WidgetProjectSummary],
        pendingTodos: Int,
        materialStockCount: Int,
        lowStockCount: Int,
        lastUpdatedAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.projects = projects
        self.pendingTodos = pendingTodos
        self.materialStockCount = materialStockCount
        self.lowStockCount = lowStockCount
        self.lastUpdatedAt = lastUpdatedAt
    }

    enum CodingKeys: String, CodingKey {
        case projects
        case pendingTodos
        case materialStockCount
        case lowStockCount
        case lastUpdatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projects = try container.decodeIfPresent([WidgetProjectSummary].self, forKey: .projects) ?? []
        pendingTodos = try container.decodeIfPresent(Int.self, forKey: .pendingTodos) ?? 0
        materialStockCount = try container.decodeIfPresent(Int.self, forKey: .materialStockCount) ?? 0
        lowStockCount = try container.decodeIfPresent(Int.self, forKey: .lowStockCount) ?? 0
        lastUpdatedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .lastUpdatedAt) ?? 0
    }

    var lastUpdatedDate: Date? {
        guard lastUpdatedAt > 0 else { return nil }
        return Date(timeIntervalSince1970: lastUpdatedAt)
    }
}

struct WidgetDataHealthSnapshot {
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
    let quantity: Double
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

    var isCompleted: Bool {
        self == .completed
    }

    var displayName: String {
        switch self {
        case .active:
            return String(localized: "widget_project_status_active")
        case .paused:
            return String(localized: "widget_project_status_paused")
        case .completed:
            return String(localized: "widget_project_status_completed")
        case .settled:
            return String(localized: "widget_project_status_settled")
        case .archived:
            return String(localized: "widget_project_status_archived")
        case .unknown:
            return String(localized: "widget_project_status_unknown")
        }
    }
}

enum WidgetDataBuilder {
    static func build(
        projects: [WidgetBuilderProjectInput],
        todos: [WidgetBuilderTodoInput],
        tasks: [WidgetBuilderTaskInput],
        stockLines: [WidgetBuilderStockInput],
        now: Date = Date()
    ) -> WidgetExportData {
        let activeProjects = projects.filter(\.isActive)
        let pendingTodosCount = todos.filter { !$0.isDone }.count
        let availableStockLineCount = stockLines.filter { $0.quantity > 0 }.count
        let negativeStockLineCount = stockLines.filter { $0.quantity < 0 }.count
        let today = Calendar.current.startOfDay(for: now)
        let tasksByProjectID = Dictionary(grouping: tasks, by: \.projectId)
        var pendingTodosByProjectID: [UUID: [WidgetBuilderTodoInput]] = [:]
        for todo in todos where !todo.isDone {
            guard let projectId = todo.projectId else { continue }
            pendingTodosByProjectID[projectId, default: []].append(todo)
        }
        let sortedProjects = activeProjects
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
                    guard let dueDate = parseWidgetDate(todo.dueDate) else {
                        return false
                    }
                    return Calendar.current.startOfDay(for: dueDate) < today
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

        return WidgetExportData(
            projects: Array(sortedProjects.prefix(5).map { $0.summary }),
            pendingTodos: pendingTodosCount,
            materialStockCount: availableStockLineCount,
            lowStockCount: negativeStockLineCount,
            lastUpdatedAt: now.timeIntervalSince1970
        )
    }

    private static func parseWidgetDate(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let date = WidgetDateParser.dateTime.date(from: value) { return date }
        return WidgetDateParser.date.date(from: value)
    }
}

private enum WidgetDateParser {
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
