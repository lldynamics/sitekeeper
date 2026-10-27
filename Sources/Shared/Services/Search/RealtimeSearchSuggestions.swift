import Foundation
import SwiftUI

struct RealtimeSearchSuggestion: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Hashable, Sendable {
        case project
        case contact
        case supplier
        case material
        case method
        case file
        case drawing
        case log
        case todo
        case note
        case command
        case quote
        case financial

        var systemImage: String {
            switch self {
            case .project:
                return "building.2"
            case .contact:
                return "person.crop.rectangle.stack"
            case .supplier:
                return "person.2.badge.gearshape"
            case .material:
                return "shippingbox"
            case .method:
                return "hammer.fill"
            case .file:
                return "doc.text"
            case .drawing:
                return "doc.viewfinder"
            case .log:
                return "book.pages"
            case .todo:
                return "checklist"
            case .note:
                return "square.and.pencil"
            case .command:
                return "command.circle.fill"
            case .quote:
                return "doc.text"
            case .financial:
                return "receipt"
            }
        }

        var tintColor: Color {
            switch self {
            case .project:
                return .appPrimaryAction
            case .contact:
                return .appPeople
            case .supplier:
                return .appFinance
            case .material:
                return .appInventory
            case .method:
                return .appSuccess
            case .file:
                return .appDoc
            case .drawing:
                return .appPrimaryAction
            case .log:
                return .appSuccess
            case .todo:
                return .appWarning
            case .note:
                return .appPeople
            case .command:
                return .appPrimaryAction
            case .quote, .financial:
                return .appFinance
            }
        }

        var displayName: String {
            switch self {
            case .project:
                return AppLocalization.string("项目")
            case .contact:
                return AppLocalization.string("联系人")
            case .supplier:
                return AppLocalization.string("供应商")
            case .material:
                return AppLocalization.string("材料")
            case .method:
                return AppLocalization.string("施工工艺")
            case .file:
                return AppLocalization.string("资料文件")
            case .drawing:
                return AppLocalization.string("图纸")
            case .log:
                return AppLocalization.string("施工日志")
            case .todo:
                return AppLocalization.string("现场待办")
            case .note:
                return AppLocalization.string("随手记")
            case .command:
                return AppLocalization.string("命令")
            case .quote:
                return AppLocalization.string("预结算信息")
            case .financial:
                return AppLocalization.string("财务记录")
            }
        }
    }

    let id: String
    let category: Category
    let entityId: UUID
    let title: String
    let subtitle: String
    let score: Int

    init(
        id: String,
        category: Category,
        entityId: UUID,
        title: String,
        subtitle: String,
        score: Int
    ) {
        self.id = id
        self.category = category
        self.entityId = entityId
        self.title = title
        self.subtitle = subtitle
        self.score = score
    }

    init(
        id: String,
        category: Category,
        entityId: UUID,
        title: String,
        subtitleParts: [String],
        score: Int
    ) {
        self.init(
            id: id,
            category: category,
            entityId: entityId,
            title: title,
            subtitle: Self.joinedSubtitle(subtitleParts),
            score: score
        )
    }

    static func joinedSubtitle(_ parts: [String]) -> String {
        parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

enum RealtimeSearchSuggestionBuilder {
    static func suggestions(
        keyword rawKeyword: String,
        categories: Set<RealtimeSearchSuggestion.Category> = Set(RealtimeSearchSuggestion.Category.allCases),
        projects: [Project] = [],
        contacts: [ProjectContact] = [],
        suppliers: [SupplierProfile] = [],
        materials: [MaterialPriceEntry] = [],
        methods: [ConstructionMethod] = [],
        logs: [DailyLog] = [],
        todos: [SiteTodo] = [],
        notes: [QuickNote] = [],
        quotes: [QuoteItem] = [],
        financialRecords: [ProjectFinancialRecord] = [],
        drawings: [ProjectDrawing] = [],
        documents: [ProjectDocument] = [],
        projectID: UUID? = nil,
        limit: Int = 8
    ) -> [RealtimeSearchSuggestion] {
        let keyword = rawKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty, !Task.isCancelled else { return [] }
        let cappedLimit = max(limit, 0)
        guard cappedLimit > 0 else { return [] }

        let projectNameByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
        var ranked = commandSuggestions(query: keyword, categories: categories)
        ranked += projectSuggestions(query: keyword, categories: categories, projects: categories.contains(.project) ? projects.filter { projectID == nil || $0.id == projectID } : [])
        ranked += contactSuggestions(query: keyword, categories: categories, contacts: categories.contains(.contact) ? contacts.filter { contact in
            guard let projectID else { return true }
            return contact.projectId == projectID || contact.relatedProjectIds.contains(projectID)
        } : [], projectNameByID: projectNameByID)
        ranked += supplierSuggestions(query: keyword, categories: categories, suppliers: projectID == nil ? suppliers : [])
        ranked += materialSuggestions(query: keyword, categories: categories, materials: projectID == nil ? materials : [])
        ranked += methodSuggestions(query: keyword, categories: categories, methods: projectID == nil ? methods : [])
        ranked += logSuggestions(query: keyword, categories: categories, logs: categories.contains(.log) ? logs.filter { projectID == nil || $0.projectId == projectID } : [], projectNameByID: projectNameByID)
        ranked += todoSuggestions(query: keyword, categories: categories, todos: categories.contains(.todo) ? todos.filter { projectID == nil || $0.projectId == projectID } : [], projectNameByID: projectNameByID)
        ranked += noteSuggestions(query: keyword, categories: categories, notes: categories.contains(.note) ? notes.filter { projectID == nil || $0.projectId == projectID } : [], projectNameByID: projectNameByID)
        ranked += businessSuggestions(query: keyword, categories: categories, quotes: quotes, financialRecords: financialRecords, drawings: drawings, documents: documents, projectID: projectID, projectNameByID: projectNameByID)

        return topSuggestions(ranked, limit: cappedLimit)
    }

    /// A bounded, ordered prefix using precisely the same total ordering as full sorting.
    /// For the dashboard's ten results this avoids sorting thousands of matching rows.
    static func topSuggestions(_ suggestions: [RealtimeSearchSuggestion], limit: Int) -> [RealtimeSearchSuggestion] {
        guard limit > 0 else { return [] }
        if limit > 64 { return Array(suggestions.sorted(by: ranksBefore).prefix(limit)) }
        var best: [RealtimeSearchSuggestion] = []
        best.reserveCapacity(min(limit, suggestions.count))
        for suggestion in suggestions {
            guard !Task.isCancelled else { return [] }
            if best.count == limit, let last = best.last, !ranksBefore(suggestion, last) { continue }
            let index = best.firstIndex { ranksBefore(suggestion, $0) } ?? best.endIndex
            best.insert(suggestion, at: index)
            if best.count > limit { best.removeLast() }
        }
        return best
    }

    static func ranksBefore(_ lhs: RealtimeSearchSuggestion, _ rhs: RealtimeSearchSuggestion) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.category != rhs.category { return lhs.category.rawValue < rhs.category.rawValue }
        let order = lhs.title.localizedStandardCompare(rhs.title)
        return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
    }

    private static func commandSuggestions(
        query: String,
        categories: Set<RealtimeSearchSuggestion.Category>
    ) -> [RealtimeSearchSuggestion] {
        guard categories.contains(.command) else { return [] }
        return RealtimeSearchCommand.allCases.compactMap { command in
            guard !Task.isCancelled else { return nil }
            guard let score = matchScore(query: query, fields: [command.title, command.subtitle] + command.aliases) else { return nil }
            return RealtimeSearchSuggestion(
                id: command.suggestionId,
                category: .command,
                entityId: command.entityId,
                title: command.title,
                subtitle: command.subtitle,
                score: score + 120
            )
        }
    }

    private static func projectSuggestions(
        query: String,
        categories: Set<RealtimeSearchSuggestion.Category>,
        projects: [Project]
    ) -> [RealtimeSearchSuggestion] {
        guard categories.contains(.project) else { return [] }
        return projects.compactMap { project in
            guard !Task.isCancelled else { return nil }
            let fields = [project.name, project.location, project.customerName, project.managerName]
            guard let score = matchScore(query: query, fields: fields) else { return nil }
            let activeBoost = project.status.isActiveOrPaused ? 20 : 0
            return RealtimeSearchSuggestion(
                id: "project-\(project.id.uuidString)", category: .project, entityId: project.id,
                title: normalizedTitle(project.name, fallback: AppLocalization.string("未命名项目")),
                subtitleParts: [project.status.displayName, project.location, project.customerName],
                score: score + activeBoost
            )
        }
    }

    private static func contactSuggestions(
        query: String,
        categories: Set<RealtimeSearchSuggestion.Category>,
        contacts: [ProjectContact],
        projectNameByID: [UUID: String]
    ) -> [RealtimeSearchSuggestion] {
        guard categories.contains(.contact) else { return [] }
        return contacts.compactMap { contact in
            guard !Task.isCancelled else { return nil }
            let projectName = projectNameByID[contact.projectId] ?? AppLocalization.string("未知项目")
            let fields = [contact.name, contact.roleDisplayName, contact.company, contact.phone, contact.note, projectName]
            guard let score = matchScore(query: query, fields: fields) else { return nil }
            return RealtimeSearchSuggestion(
                id: "contact-\(contact.id.uuidString)", category: .contact, entityId: contact.id,
                title: normalizedTitle(contact.name, fallback: AppLocalization.string("未命名联系人")),
                subtitleParts: [contact.roleDisplayName, contact.phone, projectName], score: score + 10
            )
        }
    }

    private static func supplierSuggestions(
        query: String,
        categories: Set<RealtimeSearchSuggestion.Category>,
        suppliers: [SupplierProfile]
    ) -> [RealtimeSearchSuggestion] {
        guard categories.contains(.supplier) else { return [] }
        return suppliers.compactMap { supplier in
            guard !Task.isCancelled else { return nil }
            let fields = [supplier.name, supplier.category, supplier.contact, supplier.phone, supplier.note, supplier.address]
            guard let score = matchScore(query: query, fields: fields) else { return nil }
            let phoneBoost = supplier.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 8
            return RealtimeSearchSuggestion(
                id: "supplier-\(supplier.id.uuidString)", category: .supplier, entityId: supplier.id,
                title: normalizedTitle(supplier.name, fallback: AppLocalization.string("未命名供应商")),
                subtitleParts: [supplier.category, supplier.contact, supplier.phone], score: score + phoneBoost
            )
        }
    }

    private static func materialSuggestions(
        query: String,
        categories: Set<RealtimeSearchSuggestion.Category>,
        materials: [MaterialPriceEntry]
    ) -> [RealtimeSearchSuggestion] {
        guard categories.contains(.material) else { return [] }
        return materials.compactMap { item in
            guard !Task.isCancelled else { return nil }
            let fields = [item.name, item.specification, item.brand, item.supplier, item.category, item.referencePrice.wireText]
            guard let score = matchScore(query: query, fields: fields) else { return nil }
            let priceBoost = item.referencePrice.isEmpty ? 0 : 8
            return RealtimeSearchSuggestion(
                id: "material-\(item.id.uuidString)", category: .material, entityId: item.id,
                title: normalizedTitle(item.name, fallback: AppLocalization.string("未命名材料")),
                subtitleParts: [item.specification, item.brand, item.supplier, item.category], score: score + priceBoost
            )
        }
    }

    private static func methodSuggestions(
        query: String,
        categories: Set<RealtimeSearchSuggestion.Category>,
        methods: [ConstructionMethod]
    ) -> [RealtimeSearchSuggestion] {
        guard categories.contains(.method) else { return [] }
        return methods.compactMap { method in
            guard !Task.isCancelled else { return nil }
            let fields = [
                method.title, method.trade, method.versionName, method.steps,
                method.qualityStandard, method.safetyNotes, method.tutorialBody
            ]
            guard let score = matchScore(query: query, fields: fields) else { return nil }
            let statusBoost = method.publishStatus == .published ? 12 : 0
            return RealtimeSearchSuggestion(
                id: "method-\(method.id.uuidString)", category: .method, entityId: method.id,
                title: normalizedTitle(method.title, fallback: AppLocalization.string("未命名工艺")),
                subtitleParts: [method.trade, method.publishStatus.displayName, method.versionName],
                score: score + statusBoost
            )
        }
    }

    private static func logSuggestions(
        query: String,
        categories: Set<RealtimeSearchSuggestion.Category>,
        logs: [DailyLog],
        projectNameByID: [UUID: String]
    ) -> [RealtimeSearchSuggestion] {
        guard categories.contains(.log) else { return [] }
        return logs.compactMap { log in
            guard !Task.isCancelled else { return nil }
            let projectName = log.projectId.flatMap { projectNameByID[$0] } ?? ""
            let fields = [log.date.storageText, log.weather, log.content, log.safety, log.materials, log.tomorrowPlan, projectName]
            guard let score = matchScore(query: query, fields: fields) else { return nil }
            return RealtimeSearchSuggestion(
                id: "log-\(log.id.uuidString)", category: .log, entityId: log.id,
                title: normalizedTitle(log.content, fallback: AppLocalization.string("施工日志")),
                subtitleParts: [log.date.storageText, projectName, log.weather], score: score + 8
            )
        }
    }

    private static func todoSuggestions(
        query: String,
        categories: Set<RealtimeSearchSuggestion.Category>,
        todos: [SiteTodo],
        projectNameByID: [UUID: String]
    ) -> [RealtimeSearchSuggestion] {
        guard categories.contains(.todo) else { return [] }
        return todos.compactMap { todo in
            guard !Task.isCancelled else { return nil }
            let projectName = todo.projectId.flatMap { projectNameByID[$0] } ?? ""
            let fields = [todo.title, todo.owner, todo.note, todo.dueDate.storageText, projectName]
            guard let score = matchScore(query: query, fields: fields) else { return nil }
            return RealtimeSearchSuggestion(
                id: "todo-\(todo.id.uuidString)", category: .todo, entityId: todo.id,
                title: normalizedTitle(todo.title, fallback: AppLocalization.string("现场待办")),
                subtitleParts: [todo.dueDate.storageText, projectName, todo.owner],
                score: score + (todo.isDone ? 0 : 14)
            )
        }
    }

    private static func noteSuggestions(
        query: String,
        categories: Set<RealtimeSearchSuggestion.Category>,
        notes: [QuickNote],
        projectNameByID: [UUID: String]
    ) -> [RealtimeSearchSuggestion] {
        guard categories.contains(.note) else { return [] }
        return notes.compactMap { note in
            guard !Task.isCancelled else { return nil }
            let projectName = note.projectId.flatMap { projectNameByID[$0] } ?? ""
            let fields = [note.title, note.content, note.createdAt.storageText, projectName]
            guard let score = matchScore(query: query, fields: fields) else { return nil }
            return RealtimeSearchSuggestion(
                id: "note-\(note.id.uuidString)", category: .note, entityId: note.id,
                title: normalizedTitle(note.title, fallback: AppLocalization.string("随手记")),
                subtitleParts: [projectName, Formatters.displayDateText(note.createdAt)], score: score + 6
            )
        }
    }

    static func matchScore(query: String, fields: [String]) -> Int? {
        var bestScore = 0
        for field in fields {
            guard !Task.isCancelled else { return nil }
            let normalized = field.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }
            if normalized == query {
                bestScore = max(bestScore, 300)
            } else if normalized.hasPrefix(query) {
                bestScore = max(bestScore, 220)
            } else if normalized.contains(query) {
                bestScore = max(bestScore, 140)
            }
        }
        return bestScore > 0 ? bestScore : nil
    }

    static func normalizedTitle(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
