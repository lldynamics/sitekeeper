import Foundation

struct Project: Identifiable, Codable {
    var id = UUID()
    var name: String
    var location: String
    var status: String
    var customerName: String
    var customerPhone: String
    var startDate: String
    var expectedEndDate: String
    var managerName: String
    var contractAmount: String
    var paidAmount: String
    var paymentStatus: String
    var materialCost: String
    var laborCost: String

    init(
        id: UUID = UUID(),
        name: String,
        location: String,
        status: String,
        customerName: String = "",
        customerPhone: String = "",
        startDate: String = "",
        expectedEndDate: String = "",
        managerName: String = "",
        contractAmount: String = "",
        paidAmount: String = "",
        paymentStatus: String = PaymentStatus.unpaid.rawValue,
        materialCost: String = "",
        laborCost: String = ""
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
    }

    enum CodingKeys: String, CodingKey {
        case id, name, location, status, customerName, customerPhone, startDate, expectedEndDate
        case managerName, contractAmount, paidAmount, paymentStatus, materialCost, laborCost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? ProjectStatus.active.rawValue
        customerName = try container.decodeIfPresent(String.self, forKey: .customerName) ?? ""
        customerPhone = try container.decodeIfPresent(String.self, forKey: .customerPhone) ?? ""
        startDate = try container.decodeIfPresent(String.self, forKey: .startDate) ?? ""
        expectedEndDate = try container.decodeIfPresent(String.self, forKey: .expectedEndDate) ?? ""
        managerName = try container.decodeIfPresent(String.self, forKey: .managerName) ?? ""
        contractAmount = try container.decodeIfPresent(String.self, forKey: .contractAmount) ?? ""
        paidAmount = try container.decodeIfPresent(String.self, forKey: .paidAmount) ?? ""
        paymentStatus = try container.decodeIfPresent(String.self, forKey: .paymentStatus) ?? PaymentStatus.unpaid.rawValue
        materialCost = try container.decodeIfPresent(String.self, forKey: .materialCost) ?? ""
        laborCost = try container.decodeIfPresent(String.self, forKey: .laborCost) ?? ""
    }
}

enum ProjectStatus: String, CaseIterable, Codable {
    case active = "进行中"
    case paused = "暂停"
    case completed = "已完成"
    case settled = "已结算"
    case archived = "已归档"

    var displayName: String { rawValue }
}

struct DailyLog: Identifiable, Codable {
    var id = UUID()
    var date: String
    var weather: String
    var content: String
    var workers: String
    var photoFileName: String?
    var photos: [LogPhoto]
    var safety: String
    var materials: String
    var tomorrowPlan: String
    var qualityIssue: String
    var rectification: String
    var confirmer: String
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
        self.projectId = projectId
    }

    enum CodingKeys: String, CodingKey {
        case id, date, weather, content, workers, photoFileName, photos, safety, materials
        case tomorrowPlan, qualityIssue, rectification, confirmer, projectId
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
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
    }
}

struct LogPhoto: Identifiable, Codable {
    var id = UUID()
    var fileName: String
    var note: String
    var tag: String

    init(id: UUID = UUID(), fileName: String, note: String = "", tag: String = PhotoTag.general.rawValue) {
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
        tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? PhotoTag.general.rawValue
    }
}

struct SiteTodo: Identifiable, Codable {
    var id = UUID()
    var title: String
    var owner: String
    var dueDate: String
    var priority: String
    var issueType: String
    var rectificationBeforePhotoFileName: String?
    var rectificationAfterPhotoFileName: String?
    var isDone: Bool
    var completedAt: String?
    var note: String
    var projectId: UUID?

    init(
        id: UUID = UUID(),
        title: String,
        owner: String = "",
        dueDate: String = Formatters.date.string(from: Date()),
        priority: String = TodoPriority.medium.rawValue,
        issueType: String = TodoIssueType.general.rawValue,
        rectificationBeforePhotoFileName: String? = nil,
        rectificationAfterPhotoFileName: String? = nil,
        isDone: Bool = false,
        completedAt: String? = nil,
        note: String = "",
        projectId: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.owner = owner
        self.dueDate = dueDate
        self.priority = priority
        self.issueType = issueType
        self.rectificationBeforePhotoFileName = rectificationBeforePhotoFileName
        self.rectificationAfterPhotoFileName = rectificationAfterPhotoFileName
        self.isDone = isDone
        self.completedAt = completedAt
        self.note = note
        self.projectId = projectId
    }

    enum CodingKeys: String, CodingKey {
        case id, title, owner, dueDate, priority, issueType
        case rectificationBeforePhotoFileName, rectificationAfterPhotoFileName
        case isDone, completedAt, note, projectId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        owner = try container.decodeIfPresent(String.self, forKey: .owner) ?? ""
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate) ?? Formatters.date.string(from: Date())
        priority = try container.decodeIfPresent(String.self, forKey: .priority) ?? TodoPriority.medium.rawValue
        issueType = try container.decodeIfPresent(String.self, forKey: .issueType) ?? TodoIssueType.general.rawValue
        rectificationBeforePhotoFileName = try container.decodeIfPresent(String.self, forKey: .rectificationBeforePhotoFileName)
        rectificationAfterPhotoFileName = try container.decodeIfPresent(String.self, forKey: .rectificationAfterPhotoFileName)
        isDone = try container.decodeIfPresent(Bool.self, forKey: .isDone) ?? false
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
    }

    var isOverdue: Bool {
        guard !isDone, let due = Formatters.date.date(from: dueDate) else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }
}

struct HistoryRecord: Identifiable, Codable {
    var id = UUID()
    var tool: String
    var input: String
    var result: String
    var date: String
}

enum QuickNoteAttachmentKind: String, CaseIterable, Codable {
    case photo
    case video
    case audio
    case drawing
    case file

    var title: String {
        switch self {
        case .photo: return "照片"
        case .video: return "视频"
        case .audio: return "语音"
        case .drawing: return "手绘"
        case .file: return "附件"
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

struct QuickNoteAttachment: Identifiable, Codable {
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
        QuickNoteAttachmentKind(rawValue: kind) ?? .photo
    }

    var displayName: String {
        originalName.isEmpty ? fileName : originalName
    }
}

struct QuickNote: Identifiable, Codable {
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

struct MaterialPriceEntry: Identifiable, Codable {
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

struct UserMaterial: Identifiable, Codable {
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

struct SupplierProfile: Identifiable, Codable {
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

struct ConstructionMethod: Identifiable, Codable {
    var id = UUID()
    var title: String
    var trade: String
    var steps: String
    var qualityStandard: String
    var safetyNotes: String
    var updatedAt: String

    init(
        id: UUID = UUID(),
        title: String = "",
        trade: String = "",
        steps: String = "",
        qualityStandard: String = "",
        safetyNotes: String = "",
        updatedAt: String = Formatters.now()
    ) {
        self.id = id
        self.title = title
        self.trade = trade
        self.steps = steps
        self.qualityStandard = qualityStandard
        self.safetyNotes = safetyNotes
        self.updatedAt = updatedAt
    }
}

struct ProjectTemplate: Identifiable, Codable {
    var id = UUID()
    var name: String
    var category: TemplateCategory
    var content: String
}

struct ProjectDrawing: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var name: String
    var fileName: String
    var fileType: String
    var version: String
    var isCurrentVersion: Bool
    var relatedLogDate: String
    var issueStatus: String
    var issueNote: String
    var importedAt: String
    var note: String

    init(
        id: UUID = UUID(),
        projectId: UUID,
        name: String,
        fileName: String,
        fileType: String,
        version: String = "V1",
        isCurrentVersion: Bool = true,
        relatedLogDate: String = "",
        issueStatus: String = DrawingIssueStatus.none.rawValue,
        issueNote: String = "",
        importedAt: String = Formatters.now(),
        note: String = ""
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.fileName = fileName
        self.fileType = fileType
        self.version = version
        self.isCurrentVersion = isCurrentVersion
        self.relatedLogDate = relatedLogDate
        self.issueStatus = issueStatus
        self.issueNote = issueNote
        self.importedAt = importedAt
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, name, fileName, fileType, version, isCurrentVersion, relatedLogDate, issueStatus, issueNote, importedAt, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "图纸"
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        fileType = try container.decodeIfPresent(String.self, forKey: .fileType) ?? ""
        version = try container.decodeIfPresent(String.self, forKey: .version) ?? "V1"
        isCurrentVersion = try container.decodeIfPresent(Bool.self, forKey: .isCurrentVersion) ?? true
        relatedLogDate = try container.decodeIfPresent(String.self, forKey: .relatedLogDate) ?? ""
        issueStatus = try container.decodeIfPresent(String.self, forKey: .issueStatus) ?? DrawingIssueStatus.none.rawValue
        issueNote = try container.decodeIfPresent(String.self, forKey: .issueNote) ?? ""
        importedAt = try container.decodeIfPresent(String.self, forKey: .importedAt) ?? Formatters.now()
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    static let allowedFileExtensions: Set<String> = ["pdf", "dwg", "dxf"]
}

struct ProjectContact: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var name: String
    var role: String
    var company: String
    var phone: String
    var note: String

    init(
        id: UUID = UUID(),
        projectId: UUID,
        name: String,
        role: String = ProjectContactRole.owner.rawValue,
        company: String = "",
        phone: String = "",
        note: String = ""
    ) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.role = role
        self.company = company
        self.phone = phone
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, name, role, company, phone, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ProjectContactRole.owner.rawValue
        company = try container.decodeIfPresent(String.self, forKey: .company) ?? ""
        phone = try container.decodeIfPresent(String.self, forKey: .phone) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

struct ProjectDocument: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var title: String
    var category: String
    var fileName: String
    var fileType: String
    var pageCount: Int
    var amount: String
    var linkedFinancialRecordId: UUID?
    var createdAt: String
    var note: String

    init(
        id: UUID = UUID(),
        projectId: UUID,
        title: String,
        category: String = ProjectDocumentCategory.construction.rawValue,
        fileName: String,
        fileType: String = "pdf",
        pageCount: Int = 1,
        amount: String = "",
        linkedFinancialRecordId: UUID? = nil,
        createdAt: String = Formatters.now(),
        note: String = ""
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
        self.createdAt = createdAt
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, title, category, fileName, fileType, pageCount, amount, linkedFinancialRecordId, createdAt, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "项目资料"
        category = try container.decodeIfPresent(String.self, forKey: .category) ?? ProjectDocumentCategory.construction.rawValue
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        fileType = try container.decodeIfPresent(String.self, forKey: .fileType) ?? "pdf"
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount) ?? 1
        amount = try container.decodeIfPresent(String.self, forKey: .amount) ?? ""
        linkedFinancialRecordId = try container.decodeIfPresent(UUID.self, forKey: .linkedFinancialRecordId)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? Formatters.now()
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

enum WarehouseMovementType: String, CaseIterable, Codable {
    case inbound = "入库"
    case outbound = "出库"

    var displayName: String { rawValue }

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
    var movementType: String
    var materialName: String
    var specification: String
    var unit: String
    var quantity: String
    var counterparty: String
    var handler: String
    var note: String
    var linkedDocumentIds: [UUID]
    var createdAt: String

    init(
        id: UUID = UUID(),
        projectId: UUID,
        date: String = Formatters.date.string(from: Date()),
        movementType: String = WarehouseMovementType.inbound.rawValue,
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
        movementType = try container.decodeIfPresent(String.self, forKey: .movementType) ?? WarehouseMovementType.inbound.rawValue
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

enum CircuitSupplyType: String, CaseIterable, Codable {
    case singlePhase = "单相回路"
    case threePhase = "三相回路"

    var displayName: String { rawValue }

    var defaultVoltage: String {
        switch self {
        case .singlePhase: return "220"
        case .threePhase: return "380"
        }
    }
}

struct LightingCircuitLoad: Identifiable, Codable {
    var id = UUID()
    var name: String
    var powerKW: String
}

struct LightingCircuitPlan: Identifiable, Codable {
    var id = UUID()
    var name: String
    var projectId: UUID?
    var supplyType: CircuitSupplyType
    var voltage: String
    var powerFactor: String
    var demandFactor: String
    var breakerFactor: String
    var wireFactor: String
    var isCopper: Bool
    var loads: [LightingCircuitLoad]
    var updatedAt: String
}

enum TemplateCategory: String, CaseIterable, Codable {
    case quotation = "报价模板"
    case dailyLog = "日志模板"
    case material = "材料模板"

    var displayName: String { rawValue }
}

enum DrawingIssueStatus: String, CaseIterable, Codable {
    case none = "无问题"
    case open = "待整改"
    case inProgress = "整改中"
    case closed = "已关闭"

    var displayName: String { rawValue }
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

enum ProjectDocumentCategory: String, CaseIterable, Codable {
    case paymentRequest = "请款资料"
    case construction = "施工资料"
    case invoice = "发票"
    case receipt = "收据"
    case contract = "合同"
    case acceptance = "验收资料"
    case other = "其他资料"

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
