import Foundation

struct Project: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    var location: String
    var status: ProjectStatus
    var customerName: String
    var customerPhone: String
    var startDate: BusinessDateValue
    var expectedEndDate: BusinessDateValue
    var managerName: String
    @NonNegativeDecimal var contractAmount: MoneyValue
    @NonNegativeDecimal var paidAmount: MoneyValue
    var paymentStatus: PaymentStatus
    @NonNegativeDecimal var materialCost: MoneyValue
    @NonNegativeDecimal var laborCost: MoneyValue
    var requiredDocumentCategories: [ProjectDocumentCategory]
    var paymentPlans: [ProjectPaymentPlan]
    /// Independent change confirmations; never added to contract or receipts automatically.
    var changeOrders: [ProjectChangeOrder]
    /// Explicit reporting selection only; never changes the contract amount.
    var businessQuoteVersion: String?

    init(
        id: UUID = UUID(),
        name: String,
        location: String,
        status: ProjectStatus = .active,
        customerName: String = "",
        customerPhone: String = "",
        startDate: BusinessDateValue = .empty,
        expectedEndDate: BusinessDateValue = .empty,
        managerName: String = "",
        contractAmount: MoneyValue = .empty,
        paidAmount: MoneyValue = .empty,
        paymentStatus: PaymentStatus = .unpaid,
        materialCost: MoneyValue = .empty,
        laborCost: MoneyValue = .empty,
        requiredDocumentCategories: [ProjectDocumentCategory] = ProjectDocumentCategory.defaultConstructionArchiveRequirements,
        paymentPlans: [ProjectPaymentPlan] = [],
        changeOrders: [ProjectChangeOrder] = [],
        businessQuoteVersion: String? = nil
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
        self.paymentPlans = paymentPlans
        self.changeOrders = changeOrders
        self.businessQuoteVersion = businessQuoteVersion
    }

    enum CodingKeys: String, CodingKey {
        case id, name, location, status, customerName, customerPhone, startDate, expectedEndDate
        case managerName, contractAmount, paidAmount, paymentStatus, materialCost, laborCost, requiredDocumentCategories, paymentPlans, changeOrders
        case businessQuoteVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        status = try container.decodeStringEnum(ProjectStatus.self, forKey: .status, default: .active)
        customerName = try container.decodeIfPresent(String.self, forKey: .customerName) ?? ""
        customerPhone = try container.decodeIfPresent(String.self, forKey: .customerPhone) ?? ""
        startDate = try container.decodeIfPresent(BusinessDateValue.self, forKey: .startDate) ?? .empty
        expectedEndDate = try container.decodeIfPresent(BusinessDateValue.self, forKey: .expectedEndDate) ?? .empty
        managerName = try container.decodeIfPresent(String.self, forKey: .managerName) ?? ""
        contractAmount = try container.decodeIfPresent(MoneyValue.self, forKey: .contractAmount) ?? .empty
        paidAmount = try container.decodeIfPresent(MoneyValue.self, forKey: .paidAmount) ?? .empty
        paymentStatus = try container.decodeStringEnum(PaymentStatus.self, forKey: .paymentStatus, default: .unpaid)
        materialCost = try container.decodeIfPresent(MoneyValue.self, forKey: .materialCost) ?? .empty
        laborCost = try container.decodeIfPresent(MoneyValue.self, forKey: .laborCost) ?? .empty
        requiredDocumentCategories = ProjectDocumentCategory.normalizedConstructionArchiveRequirements(
            try container.decodeIfPresent([ProjectDocumentCategory].self, forKey: .requiredDocumentCategories) ?? []
        )
        paymentPlans = try container.decodeIfPresent([ProjectPaymentPlan].self, forKey: .paymentPlans) ?? []
        changeOrders = try container.decodeIfPresent([ProjectChangeOrder].self, forKey: .changeOrders) ?? []
        businessQuoteVersion = try container.decodeIfPresent(String.self, forKey: .businessQuoteVersion)
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
        if !paymentPlans.isEmpty { try container.encode(paymentPlans, forKey: .paymentPlans) }
        if !changeOrders.isEmpty { try container.encode(changeOrders, forKey: .changeOrders) }
        try container.encodeIfPresent(businessQuoteVersion, forKey: .businessQuoteVersion)
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
            return AppLocalization.string("project_status_active")
        case .paused:
            return AppLocalization.string("project_status_paused")
        case .completed:
            return AppLocalization.string("project_status_completed")
        case .settled:
            return AppLocalization.string("project_status_settled")
        case .archived:
            return AppLocalization.string("project_status_archived")
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
    var date: BusinessDateValue
    var weather: String
    var content: String
    @NonNegativeDecimal var workers: QuantityValue
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
        date: BusinessDateValue,
        weather: String,
        content: String,
        workers: QuantityValue,
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
        date = try container.decode(BusinessDateValue.self, forKey: .date)
        weather = try container.decode(String.self, forKey: .weather)
        content = try container.decode(String.self, forKey: .content)
        workers = try container.decodeIfPresent(QuantityValue.self, forKey: .workers) ?? .empty
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
    var sourcePhotoID: UUID?

    init(id: UUID = UUID(), fileName: String, note: String = "", tag: PhotoTag = .general, sourcePhotoID: UUID? = nil) {
        self.id = id
        self.fileName = fileName
        self.note = note
        self.tag = tag
        self.sourcePhotoID = sourcePhotoID
    }

    enum CodingKeys: String, CodingKey {
        case id, fileName, note, tag, sourcePhotoID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sourcePhotoID = try container.decodeIfPresent(UUID.self, forKey: .sourcePhotoID)
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
    var dueDate: BusinessDateValue
    var priority: TodoPriority
    var issueType: TodoIssueType
    var drawingIssueLocation: String
    var drawingIssueLayerOrPage: String
    var drawingIssueMeasurement: String
    var drawingIssueCloseEvidence: String
    var rectificationBeforePhotoFileName: String?
    var rectificationAfterPhotoFileName: String?
    var isDone: Bool
    var completedAt: BusinessDateValue?
    /// Nil preserves the original one-tap completion workflow for ordinary todos.
    var review: SiteTodoReview?
    var note: String
    var linkedConstructionMethodIDs: [UUID]
    var projectId: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        owner: String = "",
        dueDate: BusinessDateValue = .today(),
        priority: TodoPriority = .medium,
        issueType: TodoIssueType = .general,
        drawingIssueLocation: String = "",
        drawingIssueLayerOrPage: String = "",
        drawingIssueMeasurement: String = "",
        drawingIssueCloseEvidence: String = "",
        rectificationBeforePhotoFileName: String? = nil,
        rectificationAfterPhotoFileName: String? = nil,
        isDone: Bool = false,
        completedAt: BusinessDateValue? = nil,
        review: SiteTodoReview? = nil,
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
        self.review = review
        self.note = note
        self.linkedConstructionMethodIDs = linkedConstructionMethodIDs
        self.projectId = projectId
        normalizeReviewCompletion()
    }

    enum CodingKeys: String, CodingKey {
        case id, title, owner, dueDate, priority, issueType
        case drawingIssueLocation, drawingIssueLayerOrPage, drawingIssueMeasurement, drawingIssueCloseEvidence
        case rectificationBeforePhotoFileName, rectificationAfterPhotoFileName
        case isDone, completedAt, review, note, linkedConstructionMethodIDs, projectId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? ""
        dueDate = try container.decodeIfPresent(BusinessDateValue.self, forKey: .dueDate) ?? .empty
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
        completedAt = try container.decodeIfPresent(BusinessDateValue.self, forKey: .completedAt)
        review = try container.decodeIfPresent(SiteTodoReview.self, forKey: .review)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        linkedConstructionMethodIDs = try container.decodeIfPresent([UUID].self, forKey: .linkedConstructionMethodIDs) ?? []
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
        normalizeReviewCompletion()
    }

    var isOverdue: Bool {
        guard !isDone, let due = dueDate.date() else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }
}

struct HistoryRecord: Identifiable, Codable, Sendable {
    var id: UUID
    var tool: String
    var input: String
    var result: String
    var date: BusinessDateValue
    var projectId: UUID?

    init(
        id: UUID = UUID(),
        tool: String,
        input: String,
        result: String,
        date: BusinessDateValue,
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
        date = try container.decodeIfPresent(BusinessDateValue.self, forKey: .date) ?? .empty
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
    }
}
