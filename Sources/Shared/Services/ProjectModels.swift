import Foundation

struct Project: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    var location: String
    var status: ProjectStatus
    var customerName: String
    var customerPhone: String
    var startDate: String
    var expectedEndDate: String
    var managerName: String
    @NonNegativeNumberText var contractAmount: String
    @NonNegativeNumberText var paidAmount: String
    var paymentStatus: PaymentStatus
    @NonNegativeNumberText var materialCost: String
    @NonNegativeNumberText var laborCost: String
    var requiredDocumentCategories: [ProjectDocumentCategory]

    init(
        id: UUID = UUID(),
        name: String,
        location: String,
        status: ProjectStatus = .active,
        customerName: String = "",
        customerPhone: String = "",
        startDate: String = "",
        expectedEndDate: String = "",
        managerName: String = "",
        contractAmount: String = "",
        paidAmount: String = "",
        paymentStatus: PaymentStatus = .unpaid,
        materialCost: String = "",
        laborCost: String = "",
        requiredDocumentCategories: [ProjectDocumentCategory] = ProjectDocumentCategory.defaultConstructionArchiveRequirements
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.status = status
        self.customerName = customerName
        self.customerPhone = customerPhone
        self.startDate = startDate
        self.expectedEndDate = expectedEndDate
        self.managerName = managerName
        self.contractAmount = contractAmount
        self.paidAmount = paidAmount
        self.paymentStatus = paymentStatus
        self.materialCost = materialCost
        self.laborCost = laborCost
        self.requiredDocumentCategories = ProjectDocumentCategory.normalizedConstructionArchiveRequirements(requiredDocumentCategories)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, location, status, customerName, customerPhone, startDate, expectedEndDate
        case managerName, contractAmount, paidAmount, paymentStatus, materialCost, laborCost, requiredDocumentCategories
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        status = try container.decodeStringEnum(ProjectStatus.self, forKey: .status, default: .active)
        customerName = try container.decodeIfPresent(String.self, forKey: .customerName) ?? ""
        customerPhone = try container.decodeIfPresent(String.self, forKey: .customerPhone) ?? ""
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate) ?? ""
        expectedEndDate = try container.decodeIfPresent(String.self, forKey: .expectedEndDate) ?? ""
        managerName = try container.decodeIfPresent(String.self, forKey: .managerName) ?? ""
        contractAmount = try container.decodeIfPresent(String.self, forKey: .contractAmount) ?? ""
        paidAmount = try container.decodeIfPresent(String.self, forKey: .paidAmount) ?? ""
        paymentStatus = try container.decodeStringEnum(PaymentStatus.self, forKey: .paymentStatus, default: .unpaid)
        materialCost = try container.decodeIfPresent(String.self, forKey: .materialCost) ?? ""
        laborCost = try container.decodeIfPresent(String.self, forKey: .laborCost) ?? ""
        requiredDocumentCategories = ProjectDocumentCategory.normalizedConstructionArchiveRequirements(
            try container.decodeIfPresent([ProjectDocumentCategory].self, forKey: .requiredDocumentCategories) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(location, forKey: .location)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(customerName, forKey: .customerName)
        try container.encode(customerPhone, forKey: .customerPhone)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(expectedEndDate, forKey: .expectedEndDate)
        try container.encode(managerName, forKey: .managerName)
        try container.encode(contractAmount, forKey: .contractAmount)
        try container.encode(paidAmount, forKey: .paidAmount)
        try container.encode(paymentStatus.rawValue, forKey: .paymentStatus)
        try container.encode(materialCost, forKey: .materialCost)
        try container.encode(laborCost, forKey: .laborCost)
        try container.encode(requiredDocumentCategories.map(\.rawValue), forKey: .requiredDocumentCategories)
    }
}

enum ProjectStatus: String, CaseIterable, Codable, Sendable {
    case active = "进行中"
    case paused = "暂停"
    case completed = "已完成"
    case settled = "已结算"
    case archived = "已归档"

    var displayName: String {
        switch self {
        case .active:
            return String(localized: "project_status_active")
        case .paused:
            return String(localized: "project_status_paused")
        case .completed:
            return String(localized: "project_status_completed")
        case .settled:
            return String(localized: "project_status_settled")
        case .archived:
            return String(localized: "project_status_archived")
        }
    }

    var isActiveOrPaused: Bool {
        self == .active || self == .paused
    }

    var isArchiveLike: Bool {
        self == .completed || self == .settled || self == .archived
    }
}

struct DailyLog: Identifiable, Codable, Sendable {
    var id = UUID()
    var date: String
    var weather: String
    var content: String
    @NonNegativeNumberText var workers: String
    var photoFileName: String?
    var photos: [LogPhoto]
    var safety: String
    var materials: String
    var tomorrowPlan: String
    var qualityIssue: String
    var rectification: String
    var confirmer: String
    var linkedConstructionMethodIDs: [UUID]
    var projectId: UUID?

    init(
        id: UUID = UUID(),
        date: String,
        weather: String,
        content: String,
        workers: String,
        photoFileName: String? = nil,
        photos: [LogPhoto] = [],
        safety: String = "",
        materials: String = "",
        tomorrowPlan: String = "",
        qualityIssue: String = "",
        rectification: String = "",
        confirmer: String = "",
        linkedConstructionMethodIDs: [UUID] = [],
        projectId: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.weather = weather
        self.content = content
        self.workers = workers
        self.photoFileName = photoFileName
        self.photos = photos
        self.safety = safety
        self.materials = materials
        self.tomorrowPlan = tomorrowPlan
        self.qualityIssue = qualityIssue
        self.rectification = rectification
        self.confirmer = confirmer
        self.linkedConstructionMethodIDs = linkedConstructionMethodIDs
        self.projectId = projectId
    }

    enum CodingKeys: String, CodingKey {
        case id, date, weather, content, workers, photoFileName, photos, safety, materials
        case tomorrowPlan, qualityIssue, rectification, confirmer, linkedConstructionMethodIDs, projectId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(String.self, forKey: .date)
        weather = try container.decode(String.self, forKey: .weather)
        content = try container.decode(String.self, forKey: .content)
        workers = try container.decode(String.self, forKey: .workers)
        photoFileName = try container.decodeIfPresent(String.self, forKey: .photoFileName)
        photos = try container.decodeIfPresent([LogPhoto].self, forKey: .photos) ?? []
        safety = try container.decodeIfPresent(String.self, forKey: .safety) ?? ""
        materials = try container.decodeIfPresent(String.self, forKey: .materials) ?? ""
        tomorrowPlan = try container.decodeIfPresent(String.self, forKey: .tomorrowPlan) ?? ""
        qualityIssue = try container.decodeIfPresent(String.self, forKey: .qualityIssue) ?? ""
        rectification = try container.decodeIfPresent(String.self, forKey: .rectification) ?? ""
        confirmer = try container.decodeIfPresent(String.self, forKey: .confirmer) ?? ""
        linkedConstructionMethodIDs = try container.decodeIfPresent([UUID].self, forKey: .linkedConstructionMethodIDs) ?? []
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
    }
}

struct LogPhoto: Identifiable, Codable, Sendable {
    var id = UUID()
    var fileName: String
    var note: String
    var tag: PhotoTag

    init(id: UUID = UUID(), fileName: String, note: String = "", tag: PhotoTag = .general) {
        self.id = id
        self.fileName = fileName
        self.note = note
        self.tag = tag
    }

    enum CodingKeys: String, CodingKey {
        case id, fileName, note, tag
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fileName = try container.decode(String.self, forKey: .fileName)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        tag = try container.decodeStringEnum(
            PhotoTag.self,
            forKey: .tag,
            default: .general
        )
    }
}

struct SiteTodo: Identifiable, Codable, Sendable {
    var id = UUID()
    var title: String
    var owner: String
    var dueDate: String
    var priority: TodoPriority
    var issueType: TodoIssueType
    var drawingIssueLocation: String
    var drawingIssueLayerOrPage: String
    var drawingIssueMeasurement: String
    var drawingIssueCloseEvidence: String
    var rectificationBeforePhotoFileName: String?
    var rectificationAfterPhotoFileName: String?
    var isDone: Bool
    var completedAt: String?
    var note: String
    var linkedConstructionMethodIDs: [UUID]
    var projectId: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        owner: String = "",
        dueDate: String = Formatters.date.string(from: Date()),
        priority: TodoPriority = .medium,
        issueType: TodoIssueType = .general,
        drawingIssueLocation: String = "",
        drawingIssueLayerOrPage: String = "",
        drawingIssueMeasurement: String = "",
        drawingIssueCloseEvidence: String = "",
        rectificationBeforePhotoFileName: String? = nil,
        rectificationAfterPhotoFileName: String? = nil,
        isDone: Bool = false,
        completedAt: String? = nil,
        note: String = "",
        linkedConstructionMethodIDs: [UUID] = [],
        projectId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.owner = owner
        self.dueDate = dueDate
        self.priority = priority
        self.issueType = issueType
        self.drawingIssueLocation = drawingIssueLocation
        self.drawingIssueLayerOrPage = drawingIssueLayerOrPage
        self.drawingIssueMeasurement = drawingIssueMeasurement
        self.drawingIssueCloseEvidence = drawingIssueCloseEvidence
        self.rectificationBeforePhotoFileName = rectificationBeforePhotoFileName
        self.rectificationAfterPhotoFileName = rectificationAfterPhotoFileName
        self.isDone = isDone
        self.completedAt = completedAt
        self.note = note
        self.linkedConstructionMethodIDs = linkedConstructionMethodIDs
        self.projectId = projectId
    }

    enum CodingKeys: String, CodingKey {
        case id, title, owner, dueDate, priority, issueType
        case drawingIssueLocation, drawingIssueLayerOrPage, drawingIssueMeasurement, drawingIssueCloseEvidence
        case rectificationBeforePhotoFileName, rectificationAfterPhotoFileName
        case isDone, completedAt, note, linkedConstructionMethodIDs, projectId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? ""
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate) ?? Formatters.date.string(from: Date())
        priority = try container.decodeStringEnum(
            TodoPriority.self,
            forKey: .priority,
            default: .medium
        )
        issueType = try container.decodeStringEnum(
            TodoIssueType.self,
            forKey: .issueType,
            default: .general
        )
        drawingIssueLocation = try container.decodeIfPresent(String.self, forKey: .drawingIssueLocation) ?? ""
        drawingIssueLayerOrPage = try container.decodeIfPresent(String.self, forKey: .drawingIssueLayerOrPage) ?? ""
        drawingIssueMeasurement = try container.decodeIfPresent(String.self, forKey: .drawingIssueMeasurement) ?? ""
        drawingIssueCloseEvidence = try container.decodeIfPresent(String.self, forKey: .drawingIssueCloseEvidence) ?? ""
        rectificationBeforePhotoFileName = try container.decodeIfPresent(String.self, forKey: .rectificationBeforePhotoFileName)
        rectificationAfterPhotoFileName = try container.decodeIfPresent(String.self, forKey: .rectificationAfterPhotoFileName)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        linkedConstructionMethodIDs = try container.decodeIfPresent([UUID].self, forKey: .linkedConstructionMethodIDs) ?? []
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
    }

    var isOverdue: Bool {
        guard !isDone, let due = Formatters.date.date(from: dueDate) else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }
}

struct HistoryRecord: Identifiable, Codable, Sendable {
    var id: UUID
    var tool: String
    var input: String
    var result: String
    var date: String
    var projectId: UUID?

    init(
        id: UUID = UUID(),
        tool: String,
        input: String,
        result: String,
        date: String,
        projectId: UUID? = nil
    ) {
        self.id = id
        self.tool = tool
        self.input = input
        self.result = result
        self.date = date
        self.projectId = projectId
    }

    enum CodingKeys: String, CodingKey {
        case id, tool, input, result, date, projectId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        tool = try container.decodeIfPresent(String.self, forKey: .tool) ?? ""
        input = try container.decodeIfPresent(String.self, forKey: .input) ?? ""
        result = try container.decodeIfPresent(String.self, forKey: .result) ?? ""
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? Formatters.now()
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
    }
}
