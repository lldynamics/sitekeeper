import Foundation

struct ProjectDrawing: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var name: String
    var drawingNumber: String
    var discipline: String
    var floorArea: String
    var fileName: String
    var fileType: String
    var version: String
    var isCurrentVersion: Bool
    var issuedAt: String
    var receiver: String
    var relatedLogDate: String
    var linkedTodoIDs: [UUID]
    var linkedLogIDs: [UUID]
    var linkedDocumentIDs: [UUID]
    var issueStatus: DrawingIssueStatus
    var issueNote: String
    var fileAvailabilityStatus: ProjectDrawingFileAvailabilityStatus
    var fileAvailabilityCheckedAt: String
    var externalOpenFailureReason: String
    var externalOpenFailedAt: String
    var importedAt: String
    var note: String

    init(
        id: UUID = UUID(),
        projectId: UUID,
        name: String,
        drawingNumber: String = "",
        discipline: String = "",
        floorArea: String = "",
        fileName: String,
        fileType: String,
        version: String = "V1",
        isCurrentVersion: Bool = true,
        issuedAt: String = "",
        receiver: String = "",
        relatedLogDate: String = "",
        linkedTodoIDs: [UUID] = [],
        linkedLogIDs: [UUID] = [],
        linkedDocumentIDs: [UUID] = [],
        issueStatus: DrawingIssueStatus = .none,
        issueNote: String = "",
        fileAvailabilityStatus: ProjectDrawingFileAvailabilityStatus = .unknown,
        fileAvailabilityCheckedAt: String = "",
        externalOpenFailureReason: String = "",
        externalOpenFailedAt: String = "",
        importedAt: String = Formatters.now(),
        note: String = ""
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.drawingNumber = drawingNumber
        self.discipline = discipline
        self.floorArea = floorArea
        self.fileName = fileName
        self.fileType = fileType
        self.version = version
        self.isCurrentVersion = isCurrentVersion
        self.issuedAt = issuedAt
        self.receiver = receiver
        self.relatedLogDate = relatedLogDate
        self.linkedTodoIDs = linkedTodoIDs
        self.linkedLogIDs = linkedLogIDs
        self.linkedDocumentIDs = linkedDocumentIDs
        self.issueStatus = issueStatus
        self.issueNote = issueNote
        self.fileAvailabilityStatus = fileAvailabilityStatus
        self.fileAvailabilityCheckedAt = fileAvailabilityCheckedAt
        self.externalOpenFailureReason = externalOpenFailureReason
        self.externalOpenFailedAt = externalOpenFailedAt
        self.importedAt = importedAt
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, name, drawingNumber, discipline, floorArea, fileName, fileType, version, isCurrentVersion
        case issuedAt, receiver, relatedLogDate, linkedTodoIDs, linkedLogIDs, linkedDocumentIDs
        case issueStatus, issueNote, fileAvailabilityStatus, fileAvailabilityCheckedAt, externalOpenFailureReason, externalOpenFailedAt, importedAt, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        drawingNumber = try container.decodeIfPresent(String.self, forKey: .drawingNumber) ?? ""
        discipline = try container.decodeIfPresent(String.self, forKey: .discipline) ?? ""
        floorArea = try container.decodeIfPresent(String.self, forKey: .floorArea) ?? ""
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        fileType = try container.decodeIfPresent(String.self, forKey: .fileType) ?? ""
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "V1"
        isCurrentVersion = try container.decodeIfPresent(Bool.self, forKey: .isCurrentVersion) ?? true
        issuedAt = try container.decodeIfPresent(String.self, forKey: .issuedAt) ?? ""
        receiver = try container.decodeIfPresent(String.self, forKey: .receiver) ?? ""
        relatedLogDate = try container.decodeIfPresent(String.self, forKey: .relatedLogDate) ?? ""
        linkedTodoIDs = try container.decodeIfPresent([UUID].self, forKey: .linkedTodoIDs) ?? []
        linkedLogIDs = try container.decodeIfPresent([UUID].self, forKey: .linkedLogIDs) ?? []
        linkedDocumentIDs = try container.decodeIfPresent([UUID].self, forKey: .linkedDocumentIDs) ?? []
        issueStatus = try container.decodeStringEnum(
            DrawingIssueStatus.self,
            forKey: .issueStatus,
            default: .none
        )
        issueNote = try container.decodeIfPresent(String.self, forKey: .issueNote) ?? ""
        fileAvailabilityStatus = try container.decodeStringEnum(
            ProjectDrawingFileAvailabilityStatus.self,
            forKey: .fileAvailabilityStatus,
            default: .unknown
        )
        fileAvailabilityCheckedAt = try container.decodeIfPresent(String.self, forKey: .fileAvailabilityCheckedAt) ?? ""
        externalOpenFailureReason = try container.decodeIfPresent(String.self, forKey: .externalOpenFailureReason) ?? ""
        externalOpenFailedAt = try container.decodeIfPresent(String.self, forKey: .externalOpenFailedAt) ?? ""
        importedAt = try container.decodeIfPresent(String.self, forKey: .importedAt) ?? Formatters.now()
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    static let allowedFileExtensions: Set<String> = ["pdf", "dwg", "dxf"]
}

struct ProjectContact: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var relatedProjectIds: [UUID]
    var name: String
    var role: ProjectContactRole
    var company: String
    var phone: String
    var note: String

    init(
        id: UUID = UUID(),
        projectId: UUID,
        relatedProjectIds: [UUID] = [],
        name: String,
        role: ProjectContactRole = .owner,
        company: String = "",
        phone: String = "",
        note: String = ""
    ) {
        self.id = id
        self.projectId = projectId
        self.relatedProjectIds = Self.normalizedRelatedProjectIDs(relatedProjectIds, excluding: projectId)
        self.name = name
        self.role = role
        self.company = company
        self.phone = phone
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, relatedProjectIds, name, role, company, phone, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        relatedProjectIds = try container.decodeIfPresent([UUID].self, forKey: .relatedProjectIds) ?? []
        relatedProjectIds = Self.normalizedRelatedProjectIDs(relatedProjectIds, excluding: projectId)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        role = try container.decodeStringEnum(
            ProjectContactRole.self,
            forKey: .role,
            default: .owner
        )
        company = try container.decodeIfPresent(String.self, forKey: .company) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    var normalizedRole: ProjectContactRole {
        role
    }

    var roleDisplayName: String {
        normalizedRole.displayName
    }

    var allProjectIDs: [UUID] {
        [projectId] + relatedProjectIds.filter { $0 != projectId }
    }

    func isLinked(to projectID: UUID) -> Bool {
        projectId == projectID || relatedProjectIds.contains(projectID)
    }

    private static func normalizedRelatedProjectIDs(_ projectIDs: [UUID], excluding primaryProjectID: UUID) -> [UUID] {
        var seen = Set<UUID>()
        var results: [UUID] = []
        for id in projectIDs where id != primaryProjectID {
            if seen.insert(id).inserted {
                results.append(id)
            }
        }
        return results
    }
}

struct ProjectDocumentStatusHistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var fromStatus: ProjectDocumentSubmissionStatus
    var toStatus: ProjectDocumentSubmissionStatus
    var operatorName: String
    var changedAt: String
    var reason: String

    init(
        id: UUID = UUID(),
        fromStatus: ProjectDocumentSubmissionStatus,
        toStatus: ProjectDocumentSubmissionStatus,
        operatorName: String = "",
        changedAt: String = Formatters.now(),
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
        changedAt = try container.decodeIfPresent(String.self, forKey: .changedAt) ?? Formatters.now()
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }
}

enum ProjectDocumentVersionState: String, CaseIterable, Codable {
    case current = "当前版"
    case superseded = "已替换"
    case voided = "已作废"

    var displayName: String { rawValue }
}

struct ProjectDocument: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var title: String
    var category: ProjectDocumentCategory
    var fileName: String
    var fileType: String
    var pageCount: Int
    @NonNegativeNumberText var amount: String
    var linkedFinancialRecordId: UUID?
    var linkedConstructionMethodIDs: [UUID]
    var submissionStatus: ProjectDocumentSubmissionStatus
    var responsiblePerson: String
    var formedAt: String
    var archiveNumber: String
    var workSection: String
    var createdAt: String
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
        amount: String = "",
        linkedFinancialRecordId: UUID? = nil,
        linkedConstructionMethodIDs: [UUID] = [],
        submissionStatus: ProjectDocumentSubmissionStatus = .notSubmitted,
        responsiblePerson: String = "",
        formedAt: String = "",
        archiveNumber: String = "",
        workSection: String = "",
        createdAt: String = Formatters.now(),
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
        amount = try container.decodeIfPresent(String.self, forKey: .amount) ?? ""
        linkedFinancialRecordId = try container.decodeIfPresent(UUID.self, forKey: .linkedFinancialRecordId)
        linkedConstructionMethodIDs = try container.decodeIfPresent([UUID].self, forKey: .linkedConstructionMethodIDs) ?? []
        submissionStatus = try container.decodeStringEnum(
            ProjectDocumentSubmissionStatus.self,
            forKey: .submissionStatus,
            default: .notSubmitted
        )
        responsiblePerson = try container.decodeIfPresent(String.self, forKey: .responsiblePerson) ?? ""
        formedAt = try container.decodeIfPresent(String.self, forKey: .formedAt) ?? ""
        archiveNumber = try container.decodeIfPresent(String.self, forKey: .archiveNumber) ?? ""
        workSection = try container.decodeIfPresent(String.self, forKey: .workSection) ?? ""
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? Formatters.now()
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

enum ProjectDocumentSubmissionStatus: String, CaseIterable, Codable {
    case notSubmitted = "未报验"
    case pending = "待报验"
    case submitted = "已报验"
    case returned = "退回修改"
    case confirmed = "已确认"
    case archived = "已归档"

    var displayName: String { rawValue }
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

enum WarehouseMovementType: String, CaseIterable, Codable {
    case inbound = "入库"
    case outbound = "出库"

    var displayName: String {
        switch self {
        case .inbound:
            return String(localized: "warehouse_movement_type_inbound")
        case .outbound:
            return String(localized: "warehouse_movement_type_outbound")
        }
    }

    var sign: Double {
        switch self {
        case .inbound: return 1
        case .outbound: return -1
        }
    }

    var systemImage: String {
        switch self {
        case .inbound: return "tray.and.arrow.down.fill"
        case .outbound: return "tray.and.arrow.up.fill"
        }
    }
}

struct ProjectWarehouseMovement: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var date: String
    var movementType: WarehouseMovementType
    var materialName: String
    var specification: String
    var unit: String
    @NonNegativeNumberText var quantity: String
    var counterparty: String
    var handler: String
    var note: String
    var linkedDocumentIds: [UUID]
    var createdAt: String

    init(
        id: UUID = UUID(),
        projectId: UUID,
        date: String = Formatters.date.string(from: Date()),
        movementType: WarehouseMovementType = .inbound,
        materialName: String = "",
        specification: String = "",
        unit: String = "",
        quantity: String = "",
        counterparty: String = "",
        handler: String = "",
        note: String = "",
        linkedDocumentIds: [UUID] = [],
        createdAt: String = Formatters.now()
    ) {
        self.id = id
        self.projectId = projectId
        self.date = date
        self.movementType = movementType
        self.materialName = materialName
        self.specification = specification
        self.unit = unit
        self.quantity = quantity
        self.counterparty = counterparty
        self.handler = handler
        self.note = note
        self.linkedDocumentIds = linkedDocumentIds
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, date, movementType, materialName, specification, unit, quantity, counterparty, handler, note, linkedDocumentIds, createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? Formatters.date.string(from: Date())
        movementType = try container.decodeStringEnum(
            WarehouseMovementType.self,
            forKey: .movementType,
            default: .inbound
        )
        materialName = try container.decodeIfPresent(String.self, forKey: .materialName) ?? ""
        specification = try container.decodeIfPresent(String.self, forKey: .specification) ?? ""
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        quantity = try container.decodeIfPresent(String.self, forKey: .quantity) ?? ""
        counterparty = try container.decodeIfPresent(String.self, forKey: .counterparty) ?? ""
        handler = try container.decodeIfPresent(String.self, forKey: .handler) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        linkedDocumentIds = try container.decodeIfPresent([UUID].self, forKey: .linkedDocumentIds) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? Formatters.now()
    }

    var normalizedMovementType: WarehouseMovementType {
        movementType
    }
}

struct ProgressTask: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var title: String
    var startDate: String
    var dueDate: String
    var completion: Double
    var note: String

    var clampedCompletion: Double {
        min(max(completion, 0), 1)
    }
}

enum TemplateCategory: String, CaseIterable, Codable {
    case quotation = "报价模板"
    case dailyLog = "日志模板"
    case material = "材料模板"
    case projectDocumentChecklist = "资料清单模板"

    var displayName: String {
        switch self {
        case .quotation:
            return String(localized: "报价模板")
        case .dailyLog:
            return String(localized: "日志模板")
        case .material:
            return String(localized: "材料模板")
        case .projectDocumentChecklist:
            return String(localized: "资料清单模板")
        }
    }
}

enum DrawingIssueStatus: String, CaseIterable, Codable {
    case none = "无问题"
    case open = "待整改"
    case inProgress = "整改中"
    case closed = "已关闭"

    var displayName: String { rawValue }
}

enum ProjectDrawingFileAvailabilityStatus: String, CaseIterable, Codable {
    case unknown
    case available
    case missing

    var displayName: String {
        switch self {
        case .unknown:
            return String(localized: "原件未检查")
        case .available:
            return String(localized: "原件可用")
        case .missing:
            return String(localized: "原件缺失")
        }
    }
}

enum TodoPriority: String, CaseIterable, Codable {
    case high = "高"
    case medium = "中"
    case low = "低"

    var displayName: String { rawValue }
}

enum TodoIssueType: String, CaseIterable, Codable {
    case safety = "安全"
    case quality = "质量"
    case material = "材料"
    case schedule = "进度"
    case general = "其他"

    var displayName: String { rawValue }
}

enum ProjectContactRole: String, CaseIterable, Codable {
    case owner = "业主"
    case customer = "客户"
    case supervisor = "监理"
    case supplier = "供应商"
    case team = "班组"
    case other = "其他"

    var displayName: String { rawValue }
}

enum PhotoTag: String, CaseIterable, Codable {
    case general = "现场"
    case rectificationBefore = "整改前"
    case rectificationAfter = "整改后"
    case hiddenWork = "隐蔽工程"
    case materialArrival = "材料进场"
    case completionAcceptance = "完工验收"

    var displayName: String { rawValue }
}
