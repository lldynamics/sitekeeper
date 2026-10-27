import Foundation

struct ProjectDocumentStatusHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var fromStatus: ProjectDocumentSubmissionStatus
    var toStatus: ProjectDocumentSubmissionStatus
    var operatorName: String
    var changedAt: BusinessDateValue
    var reason: String

    init(
        id: UUID = UUID(),
        fromStatus: ProjectDocumentSubmissionStatus,
        toStatus: ProjectDocumentSubmissionStatus,
        operatorName: String = "",
        changedAt: BusinessDateValue = .now(),
        reason: String = ""
    ) {
        self.id = id
        self.fromStatus = fromStatus
        self.toStatus = toStatus
        self.operatorName = operatorName
        self.changedAt = changedAt
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case id, fromStatus, toStatus, operatorName, changedAt, reason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fromStatus = try container.decodeStringEnum(
            ProjectDocumentSubmissionStatus.self,
            forKey: .fromStatus,
            default: .notSubmitted
        )
        toStatus = try container.decodeStringEnum(
            ProjectDocumentSubmissionStatus.self,
            forKey: .toStatus,
            default: .notSubmitted
        )
        operatorName = try container.decodeIfPresent(String.self, forKey: .operatorName) ?? ""
        changedAt = try container.decodeIfPresent(BusinessDateValue.self, forKey: .changedAt) ?? .empty
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }
}

enum ProjectDocumentVersionState: String, CaseIterable, Codable, Sendable {
    case current = "当前版"
    case superseded = "已替换"
    case voided = "已作废"

    var displayName: String { AppLocalization.string(String.LocalizationValue(rawValue)) }
}

struct ProjectDocument: Identifiable, Codable, Sendable {
    var id = UUID()
    var projectId: UUID
    var title: String
    var category: ProjectDocumentCategory
    var fileName: String
    var fileType: String
    var pageCount: Int
    @NonNegativeDecimal var amount: MoneyValue
    var linkedFinancialRecordId: UUID?
    var linkedConstructionMethodIDs: [UUID]
    var submissionStatus: ProjectDocumentSubmissionStatus
    var responsiblePerson: String
    var formedAt: BusinessDateValue
    var archiveNumber: String
    var workSection: String
    var createdAt: BusinessDateValue
    var note: String
    var statusHistory: [ProjectDocumentStatusHistoryEntry]
    var versionNumber: Int
    var versionState: ProjectDocumentVersionState
    var replacesDocumentId: UUID?
    var replacedByDocumentId: UUID?

    init(
        id: UUID = UUID(),
        projectId: UUID,
        title: String,
        category: ProjectDocumentCategory = .constructionRecord,
        fileName: String,
        fileType: String = "pdf",
        pageCount: Int = 1,
        amount: MoneyValue = .empty,
        linkedFinancialRecordId: UUID? = nil,
        linkedConstructionMethodIDs: [UUID] = [],
        submissionStatus: ProjectDocumentSubmissionStatus = .notSubmitted,
        responsiblePerson: String = "",
        formedAt: BusinessDateValue = .empty,
        archiveNumber: String = "",
        workSection: String = "",
        createdAt: BusinessDateValue = .now(),
        note: String = "",
        statusHistory: [ProjectDocumentStatusHistoryEntry] = [],
        versionNumber: Int = 1,
        versionState: ProjectDocumentVersionState = .current,
        replacesDocumentId: UUID? = nil,
        replacedByDocumentId: UUID? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.category = category
        self.fileName = fileName
        self.fileType = fileType
        self.pageCount = pageCount
        self.amount = amount
        self.linkedFinancialRecordId = linkedFinancialRecordId
        self.linkedConstructionMethodIDs = linkedConstructionMethodIDs
        self.submissionStatus = submissionStatus
        self.responsiblePerson = responsiblePerson
        self.formedAt = formedAt
        self.archiveNumber = archiveNumber
        self.workSection = workSection
        self.createdAt = createdAt
        self.note = note
        self.statusHistory = statusHistory
        self.versionNumber = max(1, versionNumber)
        self.versionState = versionState
        self.replacesDocumentId = replacesDocumentId == id ? nil : replacesDocumentId
        self.replacedByDocumentId = replacedByDocumentId == id ? nil : replacedByDocumentId
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, title, category, fileName, fileType, pageCount, amount, linkedFinancialRecordId, linkedConstructionMethodIDs, submissionStatus, responsiblePerson, formedAt, archiveNumber, workSection, createdAt, note, statusHistory, versionNumber, versionState, replacesDocumentId, replacedByDocumentId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        category = try container.decodeStringEnum(
            ProjectDocumentCategory.self,
            forKey: .category,
            default: .construction
        )
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        fileType = try container.decodeIfPresent(String.self, forKey: .fileType) ?? "pdf"
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount) ?? 1
        amount = try container.decodeIfPresent(MoneyValue.self, forKey: .amount) ?? .empty
        linkedFinancialRecordId = try container.decodeIfPresent(UUID.self, forKey: .linkedFinancialRecordId)
        linkedConstructionMethodIDs = try container.decodeIfPresent([UUID].self, forKey: .linkedConstructionMethodIDs) ?? []
        submissionStatus = try container.decodeStringEnum(
            ProjectDocumentSubmissionStatus.self,
            forKey: .submissionStatus,
            default: .notSubmitted
        )
        responsiblePerson = try container.decodeIfPresent(String.self, forKey: .responsiblePerson) ?? ""
        formedAt = try container.decodeIfPresent(BusinessDateValue.self, forKey: .formedAt) ?? .empty
        archiveNumber = try container.decodeIfPresent(String.self, forKey: .archiveNumber) ?? ""
        workSection = try container.decodeIfPresent(String.self, forKey: .workSection) ?? ""
        createdAt = try container.decodeIfPresent(BusinessDateValue.self, forKey: .createdAt) ?? .empty
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        statusHistory = try container.decodeIfPresent([ProjectDocumentStatusHistoryEntry].self, forKey: .statusHistory) ?? []
        versionNumber = max(1, try container.decodeIfPresent(Int.self, forKey: .versionNumber) ?? 1)
        versionState = try container.decodeStringEnum(
            ProjectDocumentVersionState.self,
            forKey: .versionState,
            default: .current
        )
        replacesDocumentId = try container.decodeIfPresent(UUID.self, forKey: .replacesDocumentId)
        replacedByDocumentId = try container.decodeIfPresent(UUID.self, forKey: .replacedByDocumentId)
        if replacesDocumentId == id {
            replacesDocumentId = nil
        }
        if replacedByDocumentId == id {
            replacedByDocumentId = nil
        }
    }
}

extension ProjectDocument {
    var normalizedVersionNumber: Int {
        max(1, versionNumber)
    }

    var versionLabel: String {
        "V\(normalizedVersionNumber)"
    }

    var versionDisplayText: String {
        switch versionState {
        case .current:
            return versionLabel
        case .superseded, .voided:
            return DashboardSubtitleBuilder.versionState(versionLabel, state: versionState.displayName)
        }
    }
}

enum ProjectDocumentSubmissionStatus: String, CaseIterable, Codable, Sendable {
    case notSubmitted = "未报验"
    case pending = "待报验"
    case submitted = "已报验"
    case returned = "退回修改"
    case confirmed = "已确认"
    case archived = "已归档"

    var displayName: String { AppLocalization.string(String.LocalizationValue(rawValue)) }
}

extension ProjectDocumentSubmissionStatus {
    var requiresArchiveAttention: Bool {
        switch self {
        case .notSubmitted, .pending, .returned:
            return true
        case .submitted, .confirmed, .archived:
            return false
        }
    }
}

struct ProgressTask: Identifiable, Codable, Sendable {
    var id = UUID()
    var projectId: UUID
    var title: String
    var startDate: BusinessDateValue
    var dueDate: BusinessDateValue
    var completion: Double
    var note: String

    init(id: UUID = UUID(), projectId: UUID, title: String, startDate: BusinessDateValue, dueDate: BusinessDateValue, completion: Double, note: String) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.startDate = startDate
        self.dueDate = dueDate
        self.completion = completion
        self.note = note
    }

    var clampedCompletion: Double {
        min(max(completion, 0), 1)
    }
}

enum TemplateCategory: String, CaseIterable, Codable, Sendable {
    case quotation = "报价模板"
    case dailyLog = "日志模板"
    case material = "材料模板"
    case projectDocumentChecklist = "资料清单模板"

    var displayName: String {
        switch self {
        case .quotation:
            return AppLocalization.string("报价模板")
        case .dailyLog:
            return AppLocalization.string("日志模板")
        case .material:
            return AppLocalization.string("材料模板")
        case .projectDocumentChecklist:
            return AppLocalization.string("资料清单模板")
        }
    }
}

enum TodoPriority: String, CaseIterable, Codable, Sendable {
    case high = "高"
    case medium = "中"
    case low = "低"

    var displayName: String { AppLocalization.string(String.LocalizationValue(rawValue)) }
}

enum TodoIssueType: String, CaseIterable, Codable, Sendable {
    case safety = "安全"
    case quality = "质量"
    case material = "材料"
    case schedule = "进度"
    case general = "其他"

    var displayName: String { AppLocalization.string(String.LocalizationValue(rawValue)) }
}

enum PhotoTag: String, CaseIterable, Codable, Sendable {
    case general = "现场"
    case rectificationBefore = "整改前"
    case rectificationAfter = "整改后"
    case hiddenWork = "隐蔽工程"
    case materialArrival = "材料进场"
    case completionAcceptance = "完工验收"

    var displayName: String { AppLocalization.string(String.LocalizationValue(rawValue)) }
}
