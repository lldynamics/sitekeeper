import Foundation

enum ProjectDocumentRecommendationStage: String, CaseIterable, Codable, Sendable {
    case preConstruction
    case construction
    case acceptance

    var displayName: String {
        switch self {
        case .preConstruction:
            return String(localized: "开工前")
        case .construction:
            return String(localized: "施工中")
        case .acceptance:
            return String(localized: "验收阶段")
        }
    }

    var detailText: String {
        switch self {
        case .preConstruction:
            return String(localized: "优先准备技术方案、管理报审和开工资料。")
        case .construction:
            return String(localized: "重点跟进物资、测量、施工记录和试验资料。")
        case .acceptance:
            return String(localized: "集中补齐过程验收和竣工验收资料。")
        }
    }

    var recommendedCategories: [ProjectDocumentCategory] {
        switch self {
        case .preConstruction:
            return [.constructionTechnical, .constructionManagement]
        case .construction:
            return [.constructionMaterial, .constructionSurvey, .constructionRecord, .constructionTest]
        case .acceptance:
            return [.processAcceptance, .completionAcceptance]
        }
    }

    var recommendedCategoryText: String {
        recommendedCategories.map(\.displayName).joined(separator: "、")
    }
}

enum ProjectDocumentChecklistTemplatePreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case civil = "土建"
    case decoration = "装饰"
    case mechanicalElectrical = "机电"
    case fireProtection = "消防"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .civil:
            return String(localized: "土建")
        case .decoration:
            return String(localized: "装饰")
        case .mechanicalElectrical:
            return String(localized: "机电")
        case .fireProtection:
            return String(localized: "消防")
        }
    }

    var detailText: String {
        switch self {
        case .civil:
            return String(localized: "保留完整施工资料口径，适合土建主体和综合工程。")
        case .decoration:
            return String(localized: "弱化测量资料，重点保留材料、施工记录、试验和验收。")
        case .mechanicalElectrical:
            return String(localized: "突出物资、测量定位、施工记录、试验和验收资料。")
        case .fireProtection:
            return String(localized: "突出方案报审、材料进场、施工记录、试验和验收资料。")
        }
    }

    var categories: [ProjectDocumentCategory] {
        switch self {
        case .civil:
            return ProjectDocumentCategory.defaultConstructionArchiveRequirements
        case .decoration:
            return [
                .constructionTechnical,
                .constructionMaterial,
                .constructionRecord,
                .constructionTest,
                .constructionManagement,
                .processAcceptance,
                .completionAcceptance
            ]
        case .mechanicalElectrical:
            return [
                .constructionTechnical,
                .constructionMaterial,
                .constructionSurvey,
                .constructionRecord,
                .constructionTest,
                .processAcceptance,
                .completionAcceptance
            ]
        case .fireProtection:
            return [
                .constructionTechnical,
                .constructionMaterial,
                .constructionRecord,
                .constructionTest,
                .constructionManagement,
                .processAcceptance,
                .completionAcceptance
            ]
        }
    }

    var checklistTemplate: ProjectDocumentChecklistTemplate {
        ProjectDocumentChecklistTemplate(
            id: "preset-\(rawValue)",
            name: displayName,
            detailText: detailText,
            categories: ProjectDocumentCategory.normalizedConstructionArchiveRequirements(categories),
            source: .preset
        )
    }
}

struct ProjectDocumentChecklistTemplate: Identifiable, Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case preset
        case custom(UUID)
    }

    var id: String
    var name: String
    var detailText: String
    var categories: [ProjectDocumentCategory]
    var source: Source

    var categoryText: String {
        categories.map(\.displayName).joined(separator: "、")
    }

    static var builtInPresets: [ProjectDocumentChecklistTemplate] {
        ProjectDocumentChecklistTemplatePreset.allCases.map(\.checklistTemplate)
    }

    static func customTemplates(from templates: [ProjectTemplate]) -> [ProjectDocumentChecklistTemplate] {
        templates.compactMap { template in
            guard let categories = template.documentChecklistCategories else { return nil }
            return ProjectDocumentChecklistTemplate(
                id: "custom-\(template.id.uuidString)",
                name: template.name,
                detailText: String(format: String(localized: "%lld 类资料"), Int64(categories.count)),
                categories: categories,
                source: .custom(template.id)
            )
        }
    }
}

enum ProjectDocumentCategory: String, CaseIterable, Codable, Sendable {
    case paymentRequest = "请款资料"
    case construction = "施工资料"
    case constructionTechnical = "施工技术"
    case constructionMaterial = "施工物资"
    case constructionSurvey = "施工测量"
    case constructionRecord = "施工记录"
    case constructionTest = "施工试验"
    case constructionManagement = "施工管理"
    case processAcceptance = "过程验收"
    case completionAcceptance = "竣工验收"
    case invoice = "发票"
    case receipt = "收据"
    case contract = "合同"
    case acceptance = "验收资料"
    case other = "其他资料"

    var displayName: String { rawValue }

    static let defaultConstructionArchiveRequirements: [ProjectDocumentCategory] = [
        .constructionTechnical,
        .constructionMaterial,
        .constructionSurvey,
        .constructionRecord,
        .constructionTest,
        .constructionManagement,
        .processAcceptance,
        .completionAcceptance
    ]

    static func recommendedStage(
        for project: Project,
        progressTasks: [ProgressTask] = [],
        referenceDate: Date = Date()
    ) -> ProjectDocumentRecommendationStage {
        if project.status.isArchiveLike {
            return .acceptance
        }
        if !progressTasks.isEmpty {
            let averageProgress = progressTasks.reduce(0) { $0 + $1.clampedCompletion } / Double(progressTasks.count)
            if averageProgress >= 0.85 {
                return .acceptance
            }
            if averageProgress > 0 {
                return .construction
            }
        }
        if let startDate = Formatters.date.date(from: project.startDate) {
            let calendar = Calendar.current
            if calendar.startOfDay(for: startDate) <= calendar.startOfDay(for: referenceDate) {
                return .construction
            }
        }
        return .preConstruction
    }

    static func recommendedConstructionArchiveRequirements(
        for stage: ProjectDocumentRecommendationStage
    ) -> [ProjectDocumentCategory] {
        normalizedConstructionArchiveRequirements(stage.recommendedCategories)
    }

    static func documentChecklistTemplateCategory(from token: String) -> ProjectDocumentCategory? {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if let category = ProjectDocumentCategory(rawValue: normalized) {
            return category
        }
        switch normalized {
        case "construction_technical":
            return .constructionTechnical
        case "construction_material":
            return .constructionMaterial
        case "construction_survey":
            return .constructionSurvey
        case "construction_record":
            return .constructionRecord
        case "construction_test":
            return .constructionTest
        case "construction_management":
            return .constructionManagement
        case "process_acceptance":
            return .processAcceptance
        case "completion_acceptance":
            return .completionAcceptance
        default:
            return nil
        }
    }

    static func normalizedConstructionArchiveRequirements(
        _ categories: [ProjectDocumentCategory]
    ) -> [ProjectDocumentCategory] {
        let allowed = Set(defaultConstructionArchiveRequirements)
        var seen = Set<ProjectDocumentCategory>()
        var normalized: [ProjectDocumentCategory] = []
        for category in categories where allowed.contains(category) {
            guard seen.insert(category).inserted else { continue }
            normalized.append(category)
        }
        guard !normalized.isEmpty else {
            return defaultConstructionArchiveRequirements
        }
        let order = Dictionary(uniqueKeysWithValues: defaultConstructionArchiveRequirements.enumerated().map { ($0.element, $0.offset) })
        return normalized.sorted { lhs, rhs in
            (order[lhs] ?? Int.max) < (order[rhs] ?? Int.max)
        }
    }

    var isConstructionArchive: Bool {
        switch self {
        case .construction,
             .constructionTechnical,
             .constructionMaterial,
             .constructionSurvey,
             .constructionRecord,
             .constructionTest,
             .constructionManagement,
             .processAcceptance,
             .completionAcceptance,
             .acceptance:
            return true
        case .paymentRequest, .invoice, .receipt, .contract, .other:
            return false
        }
    }

    var isBusinessArchive: Bool {
        switch self {
        case .paymentRequest, .invoice, .receipt, .contract:
            return true
        case .construction,
             .constructionTechnical,
             .constructionMaterial,
             .constructionSurvey,
             .constructionRecord,
             .constructionTest,
             .constructionManagement,
             .processAcceptance,
             .completionAcceptance,
             .acceptance,
             .other:
            return false
        }
    }
}

struct DocumentArchiveChecklistSnapshot: Sendable {
    let requiredCategories: [ProjectDocumentCategory]
    let items: [DocumentArchiveChecklistItem]
    let legacyDocumentCount: Int

    init(
        documents: [ProjectDocument],
        requiredCategories: [ProjectDocumentCategory] = ProjectDocumentCategory.defaultConstructionArchiveRequirements
    ) {
        let normalizedCategories = ProjectDocumentCategory.normalizedConstructionArchiveRequirements(requiredCategories)
        self.requiredCategories = normalizedCategories
        items = normalizedCategories.map { category in
            let categoryDocuments = documents.filter { $0.category == category }
            return DocumentArchiveChecklistItem(category: category, documents: categoryDocuments)
        }
        legacyDocumentCount = documents.filter {
            $0.category == .construction || $0.category == .acceptance
        }.count
    }

    var requiredCount: Int { items.count }
    var coveredCount: Int { items.filter { !$0.isMissing }.count }
    var missingCount: Int { items.filter(\.isMissing).count }
    var actionCount: Int { items.reduce(0) { $0 + $1.actionCount } }
    var returnedDocumentCount: Int { items.reduce(0) { $0 + $1.returnedCount } }
    var archivedDocumentCount: Int { items.reduce(0) { $0 + $1.archivedCount } }
    var hasAttention: Bool { missingCount > 0 || actionCount > 0 || legacyDocumentCount > 0 }

    var statusLine: String {
        if !hasAttention {
            return String(localized: "清单完整")
        }
        var parts: [String] = []
        if missingCount > 0 {
            parts.append(String(format: String(localized: "缺 %lld 类"), Int64(missingCount)))
        }
        if actionCount > 0 {
            parts.append(String(format: String(localized: "待处理 %lld 份"), Int64(actionCount)))
        }
        if legacyDocumentCount > 0 {
            parts.append(String(format: String(localized: "待细分 %lld 份"), Int64(legacyDocumentCount)))
        }
        return DashboardSubtitleBuilder.joined(parts)
    }
}

struct DocumentArchiveChecklistItem: Identifiable, Sendable {
    let category: ProjectDocumentCategory
    let documentCount: Int
    let actionCount: Int
    let returnedCount: Int
    let archivedCount: Int

    var id: ProjectDocumentCategory { category }
    var isMissing: Bool { documentCount == 0 }

    init(category: ProjectDocumentCategory, documents: [ProjectDocument]) {
        self.category = category
        documentCount = documents.count
        actionCount = documents.filter(\.submissionStatus.requiresArchiveAttention).count
        returnedCount = documents.filter { $0.submissionStatus == .returned }.count
        archivedCount = documents.filter { $0.submissionStatus == .archived }.count
    }

    var statusText: String {
        if isMissing { return String(localized: "缺项") }
        if returnedCount > 0 { return String(localized: "退回") }
        if actionCount > 0 { return String(localized: "待处理") }
        if archivedCount == documentCount { return String(localized: "已归档") }
        return String(localized: "已覆盖")
    }

    var detailText: String {
        if isMissing {
            return String(localized: "暂无资料")
        }
        var parts = [String(format: String(localized: "%lld 份资料"), Int64(documentCount))]
        if actionCount > 0 {
            parts.append(String(format: String(localized: "待处理 %lld"), Int64(actionCount)))
        }
        if archivedCount > 0 {
            parts.append(String(format: String(localized: "已归档 %lld"), Int64(archivedCount)))
        }
        return DashboardSubtitleBuilder.joined(parts)
    }

    var systemImage: String {
        if isMissing { return "exclamationmark.circle" }
        if returnedCount > 0 { return "arrow.uturn.backward.circle" }
        if actionCount > 0 { return "clock.badge.exclamationmark" }
        return "checkmark.circle"
    }
}
