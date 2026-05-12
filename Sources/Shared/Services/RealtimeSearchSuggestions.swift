import Foundation
import SwiftUI

struct RealtimeSearchSuggestion: Identifiable {
    enum Category: String, CaseIterable, Hashable {
        case project
        case contact
        case supplier
        case material
        case method

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
            }
        }
    }

    let id: String
    let category: Category
    let entityId: UUID
    let title: String
    let subtitle: String
    let score: Int
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

        if categories.contains(.project) {
            for project in projects {
                let fields = [project.name, project.location, project.customerName, project.managerName]
                guard let score = matchScore(query: keyword, fields: fields) else { continue }
                let subtitle = [project.status.displayName, project.location, project.customerName]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: " · ")
                let activeBoost = (project.status == .active || project.status == .paused) ? 20 : 0
                ranked.append(
                    RealtimeSearchSuggestion(
                        id: "project-\(project.id.uuidString)",
                        category: .project,
                        entityId: project.id,
                        title: normalizedTitle(project.name, fallback: String(localized: "未命名项目")),
                        subtitle: subtitle,
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
                let subtitle = [contact.roleDisplayName, contact.phone, projectName]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: " · ")
                ranked.append(
                    RealtimeSearchSuggestion(
                        id: "contact-\(contact.id.uuidString)",
                        category: .contact,
                        entityId: contact.id,
                        title: normalizedTitle(contact.name, fallback: String(localized: "未命名联系人")),
                        subtitle: subtitle,
                        score: score + 10
                    )
                )
            }
        }

        if categories.contains(.supplier) {
            for supplier in suppliers {
                let fields = [supplier.name, supplier.category, supplier.contact, supplier.phone, supplier.note, supplier.address]
                guard let score = matchScore(query: keyword, fields: fields) else { continue }
                let subtitle = [supplier.category, supplier.contact, supplier.phone]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: " · ")
                let phoneBoost = supplier.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 8
                ranked.append(
                    RealtimeSearchSuggestion(
                        id: "supplier-\(supplier.id.uuidString)",
                        category: .supplier,
                        entityId: supplier.id,
                        title: normalizedTitle(supplier.name, fallback: String(localized: "未命名供应商")),
                        subtitle: subtitle,
                        score: score + phoneBoost
                    )
                )
            }
        }

        if categories.contains(.material) {
            for item in materials {
                let fields = [item.name, item.specification, item.brand, item.supplier, item.category, item.referencePrice]
                guard let score = matchScore(query: keyword, fields: fields) else { continue }
                let subtitle = [item.specification, item.brand, item.supplier, item.category]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: " · ")
                let priceBoost = item.referencePrice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 8
                ranked.append(
                    RealtimeSearchSuggestion(
                        id: "material-\(item.id.uuidString)",
                        category: .material,
                        entityId: item.id,
                        title: normalizedTitle(item.name, fallback: String(localized: "未命名材料")),
                        subtitle: subtitle,
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
                let subtitle = [
                    method.trade,
                    method.publishStatus.displayName,
                    method.versionName
                ]
                    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    .joined(separator: " · ")
                let statusBoost = method.publishStatus == .published ? 12 : 0
                ranked.append(
                    RealtimeSearchSuggestion(
                        id: "method-\(method.id.uuidString)",
                        category: .method,
                        entityId: method.id,
                        title: normalizedTitle(method.title, fallback: String(localized: "未命名工艺")),
                        subtitle: subtitle,
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
