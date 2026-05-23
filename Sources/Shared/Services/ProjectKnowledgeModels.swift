import Foundation
import CoreGraphics

enum QuickNoteAttachmentKind: String, CaseIterable, Codable, Sendable {
    case photo
    case video
    case audio
    case drawing
    case file

    var title: String {
        switch self {
        case .photo: return String(localized: "quick_note_attachment_kind_photo")
        case .video: return String(localized: "quick_note_attachment_kind_video")
        case .audio: return String(localized: "quick_note_attachment_kind_audio")
        case .drawing: return String(localized: "quick_note_attachment_kind_drawing")
        case .file: return String(localized: "quick_note_attachment_kind_file")
        }
    }

    var systemImage: String {
        switch self {
        case .photo: return "photo"
        case .video: return "video"
        case .audio: return "waveform"
        case .drawing: return "pencil.and.outline"
        case .file: return "paperclip"
        }
    }
}

struct QuickNoteAttachment: Identifiable, Codable, Sendable {
    var id = UUID()
    var kind: String
    var fileName: String
    var originalName: String
    var createdAt: String
    var durationSeconds: Double?

    init(
        id: UUID = UUID(),
        kind: QuickNoteAttachmentKind,
        fileName: String,
        originalName: String = "",
        createdAt: String = Formatters.now(),
        durationSeconds: Double? = nil
    ) {
        self.id = id
        self.kind = kind.rawValue
        self.fileName = fileName
        self.originalName = originalName
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
    }

    var attachmentKind: QuickNoteAttachmentKind {
        StringEnumFallback.value(kind, default: .photo)
    }

    var displayName: String {
        originalName.isEmpty ? fileName : originalName
    }
}

struct QuickNote: Identifiable, Codable, Sendable {
    var id = UUID()
    var title: String
    var content: String
    var projectId: UUID?
    var createdAt: String
    var updatedAt: String
    var attachments: [QuickNoteAttachment]

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String = "",
        projectId: UUID? = nil,
        createdAt: String = Formatters.now(),
        updatedAt: String = Formatters.now(),
        attachments: [QuickNoteAttachment] = []
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.projectId = projectId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case id, title, content, projectId, createdAt, updatedAt, attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? Formatters.now()
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
        attachments = try container.decodeIfPresent([QuickNoteAttachment].self, forKey: .attachments) ?? []
    }
}

struct MaterialPriceEntry: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    var specification: String
    var brand: String
    var unit: String
    var referencePrice: String
    var supplier: String
    var category: String
    var note: String
    var updatedAt: String

    init(
        id: UUID = UUID(),
        name: String = "",
        specification: String = "",
        brand: String = "",
        unit: String = "",
        referencePrice: String = "",
        supplier: String = "",
        category: String = "",
        note: String = "",
        updatedAt: String = Formatters.now()
    ) {
        self.id = id
        self.name = name
        self.specification = specification
        self.brand = brand
        self.unit = unit
        self.referencePrice = referencePrice
        self.supplier = supplier
        self.category = category
        self.note = note
        self.updatedAt = updatedAt
    }
}

struct UserMaterial: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    var specification: String
    var unit: String
    var category: String

    init(
        id: UUID = UUID(),
        name: String = "",
        specification: String = "",
        unit: String = "",
        category: String = ""
    ) {
        self.id = id
        self.name = name
        self.specification = specification
        self.unit = unit
        self.category = category
    }
}

struct SupplierProfile: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    var category: String
    var contact: String
    var phone: String
    var address: String
    var note: String
    var updatedAt: String

    init(
        id: UUID = UUID(),
        name: String = "",
        category: String = "",
        contact: String = "",
        phone: String = "",
        address: String = "",
        note: String = "",
        updatedAt: String = Formatters.now()
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.contact = contact
        self.phone = phone
        self.address = address
        self.note = note
        self.updatedAt = updatedAt
    }
}

struct ConstructionMethodKnowledgeLink: Identifiable, Codable, Hashable, Sendable {
    var title: String
    var href: String

    var id: String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedHref = href.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(normalizedTitle)|\(normalizedHref)"
    }

    init(title: String = "", href: String = "") {
        self.title = title
        self.href = href
    }
}

struct ConstructionMethod: Identifiable, Codable, Sendable {
    enum PublishStatus: String, CaseIterable, Codable, Sendable {
        case draft = "草稿"
        case published = "已发布"
        case deprecated = "已废止"

        var displayName: String {
            switch self {
            case .draft:
                return String(localized: "construction_method_publish_status_draft")
            case .published:
                return String(localized: "construction_method_publish_status_published")
            case .deprecated:
                return String(localized: "construction_method_publish_status_deprecated")
            }
        }
    }

    enum TutorialTextSize: String, CaseIterable, Codable, Sendable {
        case small
        case normal
        case large
        case extraLarge

        var displayName: String {
            switch self {
            case .small: return String(localized: "construction_method_tutorial_text_size_small")
            case .normal: return String(localized: "construction_method_tutorial_text_size_normal")
            case .large: return String(localized: "construction_method_tutorial_text_size_large")
            case .extraLarge: return String(localized: "construction_method_tutorial_text_size_extra_large")
            }
        }

        var scale: CGFloat {
            switch self {
            case .small: return 0.92
            case .normal: return 1.0
            case .large: return 1.12
            case .extraLarge: return 1.24
            }
        }
    }

    var id = UUID()
    var title: String
    var trade: String
    var versionName: String
    var publishStatus: PublishStatus
    var tutorialBody: String
    // Legacy compatibility only: editor no longer applies per-tutorial global text scaling.
    var tutorialTextSize: TutorialTextSize
    var tutorialAttachments: [QuickNoteAttachment]
    var procedureSteps: [String]
    var qualityChecklist: [String]
    var safetyChecklist: [String]
    var attachments: [QuickNoteAttachment]
    var sourceID: String
    var sourceURL: String
    var sourceVersion: String
    var sourceUpdatedAt: String
    var relatedStandards: [String]
    var relatedTemplates: [ConstructionMethodKnowledgeLink]
    var relatedArticles: [ConstructionMethodKnowledgeLink]
    var updatedAt: String

    init(
        id: UUID = UUID(),
        title: String = "",
        trade: String = "",
        versionName: String = "V1",
        publishStatus: PublishStatus = .draft,
        tutorialBody: String = "",
        tutorialTextSize: TutorialTextSize = .normal,
        tutorialAttachments: [QuickNoteAttachment] = [],
        steps: String = "",
        qualityStandard: String = "",
        safetyNotes: String = "",
        procedureSteps: [String] = [],
        qualityChecklist: [String] = [],
        safetyChecklist: [String] = [],
        attachments: [QuickNoteAttachment] = [],
        sourceID: String = "",
        sourceURL: String = "",
        sourceVersion: String = "",
        sourceUpdatedAt: String = "",
        relatedStandards: [String] = [],
        relatedTemplates: [ConstructionMethodKnowledgeLink] = [],
        relatedArticles: [ConstructionMethodKnowledgeLink] = [],
        updatedAt: String = Formatters.now()
    ) {
        self.id = id
        self.title = title
        self.trade = trade
        self.versionName = versionName
        self.publishStatus = publishStatus
        self.tutorialBody = tutorialBody
        self.tutorialTextSize = tutorialTextSize
        self.tutorialAttachments = tutorialAttachments
        self.procedureSteps = procedureSteps.isEmpty ? Self.parseLines(steps) : Self.normalizeList(procedureSteps)
        self.qualityChecklist = qualityChecklist.isEmpty ? Self.parseLines(qualityStandard) : Self.normalizeList(qualityChecklist)
        self.safetyChecklist = safetyChecklist.isEmpty ? Self.parseLines(safetyNotes) : Self.normalizeList(safetyChecklist)
        self.attachments = attachments
        self.sourceID = sourceID
        self.sourceURL = sourceURL
        self.sourceVersion = sourceVersion
        self.sourceUpdatedAt = sourceUpdatedAt
        self.relatedStandards = Self.normalizeList(relatedStandards)
        self.relatedTemplates = Self.normalizeLinks(relatedTemplates)
        self.relatedArticles = Self.normalizeLinks(relatedArticles)
        self.updatedAt = updatedAt
    }

    var steps: String {
        get { procedureSteps.joined(separator: "\n") }
        set { procedureSteps = Self.parseLines(newValue) }
    }

    var qualityStandard: String {
        get { qualityChecklist.joined(separator: "\n") }
        set { qualityChecklist = Self.parseLines(newValue) }
    }

    var safetyNotes: String {
        get { safetyChecklist.joined(separator: "\n") }
        set { safetyChecklist = Self.parseLines(newValue) }
    }

    enum CodingKeys: String, CodingKey {
        case id, title, trade, versionName, publishStatus, tutorialBody, tutorialTextSize, tutorialAttachments
        case steps, qualityStandard, safetyNotes
        case procedureSteps, qualityChecklist, safetyChecklist
        case attachments, sourceID, sourceURL, sourceVersion, sourceUpdatedAt
        case relatedStandards, relatedTemplates, relatedArticles
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        trade = try container.decodeIfPresent(String.self, forKey: .trade) ?? ""
        versionName = try container.decodeIfPresent(String.self, forKey: .versionName) ?? "V1"
        publishStatus = try container.decodeIfPresent(PublishStatus.self, forKey: .publishStatus) ?? .draft
        tutorialBody = try container.decodeIfPresent(String.self, forKey: .tutorialBody) ?? ""
        tutorialTextSize = try container.decodeIfPresent(TutorialTextSize.self, forKey: .tutorialTextSize) ?? .normal
        tutorialAttachments = try container.decodeIfPresent([QuickNoteAttachment].self, forKey: .tutorialAttachments) ?? []
        let legacySteps = try container.decodeIfPresent(String.self, forKey: .steps) ?? ""
        let legacyQuality = try container.decodeIfPresent(String.self, forKey: .qualityStandard) ?? ""
        let legacySafety = try container.decodeIfPresent(String.self, forKey: .safetyNotes) ?? ""
        procedureSteps = Self.normalizeList(try container.decodeIfPresent([String].self, forKey: .procedureSteps) ?? Self.parseLines(legacySteps))
        qualityChecklist = Self.normalizeList(try container.decodeIfPresent([String].self, forKey: .qualityChecklist) ?? Self.parseLines(legacyQuality))
        safetyChecklist = Self.normalizeList(try container.decodeIfPresent([String].self, forKey: .safetyChecklist) ?? Self.parseLines(legacySafety))
        attachments = try container.decodeIfPresent([QuickNoteAttachment].self, forKey: .attachments) ?? []
        sourceID = try container.decodeIfPresent(String.self, forKey: .sourceID) ?? ""
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL) ?? ""
        sourceVersion = try container.decodeIfPresent(String.self, forKey: .sourceVersion) ?? ""
        sourceUpdatedAt = try container.decodeIfPresent(String.self, forKey: .sourceUpdatedAt) ?? ""
        relatedStandards = Self.normalizeList(
            try container.decodeIfPresent([String].self, forKey: .relatedStandards) ?? []
        )
        relatedTemplates = Self.normalizeLinks(
            try container.decodeIfPresent([ConstructionMethodKnowledgeLink].self, forKey: .relatedTemplates) ?? []
        )
        relatedArticles = Self.normalizeLinks(
            try container.decodeIfPresent([ConstructionMethodKnowledgeLink].self, forKey: .relatedArticles) ?? []
        )
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? Formatters.now()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(trade, forKey: .trade)
        try container.encode(versionName, forKey: .versionName)
        try container.encode(publishStatus, forKey: .publishStatus)
        try container.encode(tutorialBody, forKey: .tutorialBody)
        // Keep decoding legacy fields, but stop writing them for new data.
        try container.encode(tutorialAttachments, forKey: .tutorialAttachments)
        try container.encode(procedureSteps, forKey: .procedureSteps)
        try container.encode(qualityChecklist, forKey: .qualityChecklist)
        try container.encode(safetyChecklist, forKey: .safetyChecklist)
        try container.encode(attachments, forKey: .attachments)
        try container.encode(sourceID, forKey: .sourceID)
        try container.encode(sourceURL, forKey: .sourceURL)
        try container.encode(sourceVersion, forKey: .sourceVersion)
        try container.encode(sourceUpdatedAt, forKey: .sourceUpdatedAt)
        try container.encode(relatedStandards, forKey: .relatedStandards)
        try container.encode(relatedTemplates, forKey: .relatedTemplates)
        try container.encode(relatedArticles, forKey: .relatedArticles)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private static func parseLines(_ raw: String) -> [String] {
        raw
            .split(whereSeparator: \.isNewline)
            .map { item in
                item.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"^\d+[\.\、\)]\s*"#, with: "", options: .regularExpression)
            }
            .filter { !$0.isEmpty }
    }

    private static func normalizeList(_ list: [String]) -> [String] {
        list
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizeLinks(_ links: [ConstructionMethodKnowledgeLink]) -> [ConstructionMethodKnowledgeLink] {
        var seen = Set<String>()
        var normalized: [ConstructionMethodKnowledgeLink] = []
        for link in links {
            let title = link.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let href = link.href.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !href.isEmpty else { continue }
            let displayTitle = title.isEmpty ? href : title
            let dedupeKey = "\(displayTitle)|\(href)"
            guard seen.insert(dedupeKey).inserted else { continue }
            normalized.append(ConstructionMethodKnowledgeLink(title: displayTitle, href: href))
        }
        return normalized
    }
}

struct ProjectTemplate: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    var category: TemplateCategory
    var content: String
}

extension ProjectTemplate {
    private static let documentChecklistContentHeader = "sitekeeper_document_checklist_template_v1"

    static func documentChecklistTemplate(
        id: UUID = UUID(),
        name: String,
        categories: [ProjectDocumentCategory]
    ) -> ProjectTemplate {
        ProjectTemplate(
            id: id,
            name: name,
            category: .projectDocumentChecklist,
            content: documentChecklistContent(categories: categories)
        )
    }

    var documentChecklistCategories: [ProjectDocumentCategory]? {
        guard category == .projectDocumentChecklist else { return nil }
        let categories = content
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != Self.documentChecklistContentHeader }
            .compactMap(ProjectDocumentCategory.documentChecklistTemplateCategory(from:))
        guard !categories.isEmpty else { return nil }
        return ProjectDocumentCategory.normalizedConstructionArchiveRequirements(categories)
    }

    private static func documentChecklistContent(categories: [ProjectDocumentCategory]) -> String {
        let normalizedCategories = ProjectDocumentCategory.normalizedConstructionArchiveRequirements(categories)
        return ([documentChecklistContentHeader] + normalizedCategories.map(\.rawValue)).joined(separator: "\n")
    }
}
