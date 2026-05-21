import Foundation
import SwiftUI

struct RealtimeSearchSuggestion: Identifiable, Hashable {
    enum Category: String, CaseIterable, Hashable {
        case project
        case contact
        case supplier
        case material
        case method
        case file
        case drawing
        case log
        case command

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
            case .command:
                return "command.circle.fill"
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
            case .command:
                return .appPrimaryAction
            }
        }

        var displayName: String {
            switch self {
            case .project:
                return String(localized: "项目")
            case .contact:
                return String(localized: "联系人")
            case .supplier:
                return String(localized: "供应商")
            case .material:
                return String(localized: "材料")
            case .method:
                return String(localized: "施工工艺")
            case .file:
                return String(localized: "资料文件")
            case .drawing:
                return String(localized: "图纸")
            case .log:
                return String(localized: "施工日志")
            case .command:
                return String(localized: "命令")
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

enum RealtimeSearchCommand: String, CaseIterable, Hashable {
    case newDailyLog = "new-daily-log"
    case attachReceipt = "attach-receipt"
    case exportDeliveryPackage = "export-delivery-package"
    case backupNow = "backup-now"
    case dataHealthCheck = "data-health-check"

    var suggestionId: String {
        "command-\(rawValue)"
    }

    var entityId: UUID {
        switch self {
        case .newDailyLog:
            return UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        case .attachReceipt:
            return UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        case .exportDeliveryPackage:
            return UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
        case .backupNow:
            return UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
        case .dataHealthCheck:
            return UUID(uuidString: "00000000-0000-4000-8000-000000000005")!
        }
    }

    var title: String {
        switch self {
        case .newDailyLog:
            return String(localized: "新建日志")
        case .attachReceipt:
            return String(localized: "补票据")
        case .exportDeliveryPackage:
            return String(localized: "导出交付包")
        case .backupNow:
            return String(localized: "立即备份")
        case .dataHealthCheck:
            return String(localized: "打开数据健康检查")
        }
    }

    var subtitle: String {
        switch self {
        case .newDailyLog:
            return String(localized: "打开施工日志并直接新建一条")
        case .attachReceipt:
            return String(localized: "进入缺票工程或当前工程补扫票据")
        case .exportDeliveryPackage:
            return String(localized: "打开交付向导或导出交付中心")
        case .backupNow:
            return String(localized: "进入数据安全中心生成本地或 iCloud 备份")
        case .dataHealthCheck:
            return String(localized: "扫描缺失文件、无效关联和孤立文件")
        }
    }

    var aliases: [String] {
        switch self {
        case .newDailyLog:
            return ["新建日志", "写日志", "施工日志", "日志", "daily log", "log"]
        case .attachReceipt:
            return ["补票据", "补票", "缺票", "票据", "发票", "收据", "receipt", "invoice"]
        case .exportDeliveryPackage:
            return ["导出交付包", "交付包", "导出交付", "项目交付", "交付", "delivery", "package", "export"]
        case .backupNow:
            return ["立即备份", "备份", "本地备份", "iCloud备份", "iCloud backup", "backup"]
        case .dataHealthCheck:
            return ["数据健康检查", "数据健康", "健康检查", "数据体检", "修复数据", "health", "check"]
        }
    }

    init?(suggestionId: String) {
        guard suggestionId.hasPrefix("command-") else { return nil }
        self.init(rawValue: String(suggestionId.dropFirst("command-".count)))
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
        limit: Int = 8
    ) -> [RealtimeSearchSuggestion] {
        let keyword = rawKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return [] }
        let cappedLimit = max(limit, 0)
        guard cappedLimit > 0 else { return [] }

        let projectNameByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
        var ranked: [RealtimeSearchSuggestion] = []
        ranked.reserveCapacity(min(cappedLimit * 4, 64))

        if categories.contains(.command) {
            for command in RealtimeSearchCommand.allCases {
                let fields = [command.title, command.subtitle] + command.aliases
                guard let score = matchScore(query: keyword, fields: fields) else { continue }
                ranked.append(
                    RealtimeSearchSuggestion(
                        id: command.suggestionId,
                        category: .command,
                        entityId: command.entityId,
                        title: command.title,
                        subtitle: command.subtitle,
                        score: score + 120
                    )
                )
            }
        }

        if categories.contains(.project) {
            for project in projects {
                let fields = [project.name, project.location, project.customerName, project.managerName]
                guard let score = matchScore(query: keyword, fields: fields) else { continue }
                let activeBoost = (project.status == .active || project.status == .paused) ? 20 : 0
                ranked.append(
                    RealtimeSearchSuggestion(
                        id: "project-\(project.id.uuidString)",
                        category: .project,
                        entityId: project.id,
                        title: normalizedTitle(project.name, fallback: String(localized: "未命名项目")),
                        subtitleParts: [project.status.displayName, project.location, project.customerName],
                        score: score + activeBoost
                    )
                )
            }
        }

        if categories.contains(.contact) {
            for contact in contacts {
                let projectName = projectNameByID[contact.projectId] ?? String(localized: "未知项目")
                let fields = [contact.name, contact.roleDisplayName, contact.company, contact.phone, contact.note, projectName]
                guard let score = matchScore(query: keyword, fields: fields) else { continue }
                ranked.append(
                    RealtimeSearchSuggestion(
                        id: "contact-\(contact.id.uuidString)",
                        category: .contact,
                        entityId: contact.id,
                        title: normalizedTitle(contact.name, fallback: String(localized: "未命名联系人")),
                        subtitleParts: [contact.roleDisplayName, contact.phone, projectName],
                        score: score + 10
                    )
                )
            }
        }

        if categories.contains(.supplier) {
            for supplier in suppliers {
                let fields = [supplier.name, supplier.category, supplier.contact, supplier.phone, supplier.note, supplier.address]
                guard let score = matchScore(query: keyword, fields: fields) else { continue }
                let phoneBoost = supplier.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 8
                ranked.append(
                    RealtimeSearchSuggestion(
                        id: "supplier-\(supplier.id.uuidString)",
                        category: .supplier,
                        entityId: supplier.id,
                        title: normalizedTitle(supplier.name, fallback: String(localized: "未命名供应商")),
                        subtitleParts: [supplier.category, supplier.contact, supplier.phone],
                        score: score + phoneBoost
                    )
                )
            }
        }

        if categories.contains(.material) {
            for item in materials {
                let fields = [item.name, item.specification, item.brand, item.supplier, item.category, item.referencePrice]
                guard let score = matchScore(query: keyword, fields: fields) else { continue }
                let priceBoost = item.referencePrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 8
                ranked.append(
                    RealtimeSearchSuggestion(
                        id: "material-\(item.id.uuidString)",
                        category: .material,
                        entityId: item.id,
                        title: normalizedTitle(item.name, fallback: String(localized: "未命名材料")),
                        subtitleParts: [item.specification, item.brand, item.supplier, item.category],
                        score: score + priceBoost
                    )
                )
            }
        }

        if categories.contains(.method) {
            for method in methods {
                let fields = [
                    method.title,
                    method.trade,
                    method.versionName,
                    method.steps,
                    method.qualityStandard,
                    method.safetyNotes,
                    method.tutorialBody
                ]
                guard let score = matchScore(query: keyword, fields: fields) else { continue }
                let statusBoost = method.publishStatus == .published ? 12 : 0
                ranked.append(
                    RealtimeSearchSuggestion(
                        id: "method-\(method.id.uuidString)",
                        category: .method,
                        entityId: method.id,
                        title: normalizedTitle(method.title, fallback: String(localized: "未命名工艺")),
                        subtitleParts: [method.trade, method.publishStatus.displayName, method.versionName],
                        score: score + statusBoost
                    )
                )
            }
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.category != rhs.category {
                    return lhs.category.rawValue < rhs.category.rawValue
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            .prefix(cappedLimit)
            .map { $0 }
    }

    private static func matchScore(query: String, fields: [String]) -> Int? {
        var bestScore = 0
        for field in fields {
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

    private static func normalizedTitle(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
