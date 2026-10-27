import Foundation

struct ProjectDrawing: Identifiable, Codable, Sendable {
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
    var issuedAt: BusinessDateValue
    var receiver: String
    var relatedLogDate: BusinessDateValue
    var linkedTodoIDs: [UUID]
    var linkedLogIDs: [UUID]
    var linkedDocumentIDs: [UUID]
    var issueStatus: DrawingIssueStatus
    var issueNote: String
    var fileAvailabilityStatus: ProjectDrawingFileAvailabilityStatus
    var fileAvailabilityCheckedAt: BusinessDateValue
    var externalOpenFailureReason: String
    var externalOpenFailedAt: BusinessDateValue
    var importedAt: BusinessDateValue
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
        issuedAt: BusinessDateValue = .empty,
        receiver: String = "",
        relatedLogDate: BusinessDateValue = .empty,
        linkedTodoIDs: [UUID] = [],
        linkedLogIDs: [UUID] = [],
        linkedDocumentIDs: [UUID] = [],
        issueStatus: DrawingIssueStatus = .none,
        issueNote: String = "",
        fileAvailabilityStatus: ProjectDrawingFileAvailabilityStatus = .unknown,
        fileAvailabilityCheckedAt: BusinessDateValue = .empty,
        externalOpenFailureReason: String = "",
        externalOpenFailedAt: BusinessDateValue = .empty,
        importedAt: BusinessDateValue = .now(),
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
        issuedAt = try container.decodeIfPresent(BusinessDateValue.self, forKey: .issuedAt) ?? .empty
        receiver = try container.decodeIfPresent(String.self, forKey: .receiver) ?? ""
        relatedLogDate = try container.decodeIfPresent(BusinessDateValue.self, forKey: .relatedLogDate) ?? .empty
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
        fileAvailabilityCheckedAt = try container.decodeIfPresent(BusinessDateValue.self, forKey: .fileAvailabilityCheckedAt) ?? .empty
        externalOpenFailureReason = try container.decodeIfPresent(String.self, forKey: .externalOpenFailureReason) ?? ""
        externalOpenFailedAt = try container.decodeIfPresent(BusinessDateValue.self, forKey: .externalOpenFailedAt) ?? .empty
        importedAt = try container.decodeIfPresent(BusinessDateValue.self, forKey: .importedAt) ?? .empty
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    static let allowedFileExtensions: Set<String> = ["pdf", "dwg", "dxf"]
}

enum DrawingIssueStatus: String, CaseIterable, Codable, Sendable {
    case none = "无问题"
    case open = "待整改"
    case inProgress = "整改中"
    case closed = "已关闭"

    var displayName: String { AppLocalization.string(String.LocalizationValue(rawValue)) }
}

enum ProjectDrawingFileAvailabilityStatus: String, CaseIterable, Codable, Sendable {
    case unknown
    case available
    case missing

    var displayName: String {
        switch self {
        case .unknown:
            return AppLocalization.string("原件未检查")
        case .available:
            return AppLocalization.string("原件可用")
        case .missing:
            return AppLocalization.string("原件缺失")
        }
    }
}
