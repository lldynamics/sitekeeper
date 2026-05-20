import Foundation

struct MaterialItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    @NonNegativeNumberText var quantity: String
    var unit: String
    @NonNegativeNumberText var unitPrice: String
    var specification: String
    var brand: String
    var supplier: String
    var purchaseStatus: MaterialPurchaseStatus
    var arrivalDate: String
    var projectId: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        quantity: String,
        unit: String,
        unitPrice: String = "",
        specification: String = "",
        brand: String = "",
        supplier: String = "",
        purchaseStatus: MaterialPurchaseStatus = .notPurchased,
        arrivalDate: String = "",
        projectId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.specification = specification
        self.brand = brand
        self.supplier = supplier
        self.purchaseStatus = purchaseStatus
        self.arrivalDate = arrivalDate
        self.projectId = projectId
    }

    enum CodingKeys: String, CodingKey {
        case id, name, quantity, unit, unitPrice, specification, brand, supplier, purchaseStatus, arrivalDate, projectId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        quantity = try container.decodeIfPresent(String.self, forKey: .quantity) ?? ""
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        unitPrice = try container.decodeIfPresent(String.self, forKey: .unitPrice) ?? ""
        specification = try container.decodeIfPresent(String.self, forKey: .specification) ?? ""
        brand = try container.decodeIfPresent(String.self, forKey: .brand) ?? ""
        supplier = try container.decodeIfPresent(String.self, forKey: .supplier) ?? ""
        purchaseStatus = try container.decodeStringEnum(
            MaterialPurchaseStatus.self,
            forKey: .purchaseStatus,
            default: .notPurchased
        )
        arrivalDate = try container.decodeIfPresent(String.self, forKey: .arrivalDate) ?? ""
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
    }
}

struct MaterialSheetDraftItem: Identifiable, Codable {
    var id: UUID
    var name: String
    var specification: String
    var unit: String
    @NonNegativeNumberText var quantity: String
    @NonNegativeNumberText var unitPrice: String
    @NonNegativeNumberText var laborCost: String
    var supplier: String
    var usageLocation: String
    var note: String
    var attachmentData: Data?
    var attachmentFileName: String?

    init(
        id: UUID = UUID(),
        name: String,
        specification: String = "",
        unit: String = "",
        quantity: String = "",
        unitPrice: String = "",
        laborCost: String = "",
        supplier: String = "",
        usageLocation: String = "",
        note: String = "",
        attachmentData: Data? = nil,
        attachmentFileName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.specification = specification
        self.unit = unit
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.laborCost = laborCost
        self.supplier = supplier
        self.usageLocation = usageLocation
        self.note = note
        self.attachmentData = attachmentData
        self.attachmentFileName = attachmentFileName
    }

    enum CodingKeys: String, CodingKey {
        case id, name, specification, unit, quantity, unitPrice
        case laborCost, supplier, usageLocation, note
        case attachmentData, attachmentFileName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        specification = try container.decodeIfPresent(String.self, forKey: .specification) ?? ""
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        quantity = try container.decodeIfPresent(String.self, forKey: .quantity) ?? ""
        unitPrice = try container.decodeIfPresent(String.self, forKey: .unitPrice) ?? ""
        laborCost = try container.decodeIfPresent(String.self, forKey: .laborCost) ?? ""
        supplier = try container.decodeIfPresent(String.self, forKey: .supplier) ?? ""
        usageLocation = try container.decodeIfPresent(String.self, forKey: .usageLocation) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        attachmentData = try container.decodeIfPresent(Data.self, forKey: .attachmentData)
        attachmentFileName = try container.decodeIfPresent(String.self, forKey: .attachmentFileName)
    }
}

struct MaterialSheetDraft: Identifiable, Codable {
    var id: UUID
    var title: String
    var projectId: UUID?
    var isArchived: Bool
    var exportProjectName: String
    var exportPreparer: String
    var exportDate: String
    var items: [MaterialSheetDraftItem]
    var createdAt: String
    var updatedAt: String

    init(
        id: UUID = UUID(),
        title: String = "",
        projectId: UUID? = nil,
        isArchived: Bool = false,
        exportProjectName: String = "",
        exportPreparer: String = "",
        exportDate: String = Formatters.date.string(from: Date()),
        items: [MaterialSheetDraftItem] = [],
        createdAt: String = Formatters.now(),
        updatedAt: String = Formatters.now()
    ) {
        self.id = id
        self.title = title
        self.projectId = projectId
        self.isArchived = isArchived
        self.exportProjectName = exportProjectName
        self.exportPreparer = exportPreparer
        self.exportDate = exportDate
        self.items = items
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, title, projectId, isArchived
        case exportProjectName, exportPreparer, exportDate, items
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        exportProjectName = try container.decodeIfPresent(String.self, forKey: .exportProjectName) ?? ""
        exportPreparer = try container.decodeIfPresent(String.self, forKey: .exportPreparer) ?? ""
        exportDate = try container.decodeIfPresent(String.self, forKey: .exportDate) ?? Formatters.date.string(from: Date())
        items = try container.decodeIfPresent([MaterialSheetDraftItem].self, forKey: .items) ?? []
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? Formatters.now()
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? Formatters.now()
    }
}

struct QuoteItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    @NonNegativeNumberText var unitPrice: String
    @NonNegativeNumberText var quantity: String
    var unit: String
    var notes: String
    @NonNegativeNumberText var taxRate: String
    @NonNegativeNumberText var discountRate: String
    var versionName: String
    var status: QuoteStatus
    var customerConfirmedDate: String
    @NonNegativeNumberText var contractAmount: String
    var projectId: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        unitPrice: String,
        quantity: String,
        unit: String,
        notes: String,
        taxRate: String,
        discountRate: String,
        versionName: String = "V1",
        status: QuoteStatus = .draft,
        customerConfirmedDate: String = "",
        contractAmount: String = "",
        projectId: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.unitPrice = unitPrice
        self.quantity = quantity
        self.unit = unit
        self.notes = notes
        self.taxRate = taxRate
        self.discountRate = discountRate
        self.versionName = versionName
        self.status = status
        self.customerConfirmedDate = customerConfirmedDate
        self.contractAmount = contractAmount
        self.projectId = projectId
    }

    enum CodingKeys: String, CodingKey {
        case id, name, unitPrice, quantity, unit, notes, taxRate, discountRate
        case versionName, status, customerConfirmedDate, contractAmount, projectId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        unitPrice = try container.decodeIfPresent(String.self, forKey: .unitPrice) ?? ""
        quantity = try container.decodeIfPresent(String.self, forKey: .quantity) ?? ""
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        taxRate = try container.decodeIfPresent(String.self, forKey: .taxRate) ?? "0"
        discountRate = try container.decodeIfPresent(String.self, forKey: .discountRate) ?? "0"
        versionName = try container.decodeIfPresent(String.self, forKey: .versionName) ?? "V1"
        status = try container.decodeStringEnum(QuoteStatus.self, forKey: .status, default: .draft)
        customerConfirmedDate = try container.decodeIfPresent(String.self, forKey: .customerConfirmedDate) ?? ""
        contractAmount = try container.decodeIfPresent(String.self, forKey: .contractAmount) ?? ""
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
    }
}

struct LaborRecord: Identifiable, Codable {
    var id = UUID()
    var date: String
    @NonNegativeNumberText var workers: String
    @NonNegativeNumberText var hours: String
    @NonNegativeNumberText var unitRate: String

    /// UI 展示用，等价于 hours（工天）
    var days: String { hours }
    var workType: String
    var teamName: String
    var isSettled: Bool
    var note: String
    var projectId: UUID?

    init(
        id: UUID = UUID(),
        date: String,
        workers: String,
        hours: String,
        unitRate: String = "",
        workType: String = "",
        teamName: String = "",
        isSettled: Bool = false,
        note: String,
        projectId: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.workers = workers
        self.hours = hours
        self.unitRate = unitRate
        self.workType = workType
        self.teamName = teamName
        self.isSettled = isSettled
        self.note = note
        self.projectId = projectId
    }

    enum CodingKeys: String, CodingKey {
        case id, date, workers, hours, unitRate, workType, teamName, isSettled, note, projectId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(String.self, forKey: .date)
        workers = try container.decodeIfPresent(String.self, forKey: .workers) ?? ""
        hours = try container.decodeIfPresent(String.self, forKey: .hours) ?? ""
        unitRate = try container.decodeIfPresent(String.self, forKey: .unitRate) ?? ""
        workType = try container.decodeIfPresent(String.self, forKey: .workType) ?? ""
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName) ?? ""
        isSettled = try container.decodeIfPresent(Bool.self, forKey: .isSettled) ?? false
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
    }
}

struct ProjectFinancialRecord: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var date: String
    var direction: ProjectFinancialDirection
    var category: ProjectFinancialCategory
    @NonNegativeNumberText var amount: String
    var counterparty: String
    var invoiceNumber: String
    var linkedDocumentIds: [UUID]
    var status: ProjectFinancialStatus
    var dueDate: String
    var reminderStatus: ProjectFinancialReminderStatus
    var note: String

    init(
        id: UUID = UUID(),
        projectId: UUID,
        date: String = Formatters.now(),
        direction: ProjectFinancialDirection = .expense,
        category: ProjectFinancialCategory = ProjectFinancialDirection.expense.defaultCategory,
        amount: String = "",
        counterparty: String = "",
        invoiceNumber: String = "",
        linkedDocumentIds: [UUID] = [],
        status: ProjectFinancialStatus = .active,
        dueDate: String = "",
        reminderStatus: ProjectFinancialReminderStatus = .none,
        note: String = ""
    ) {
        self.id = id
        self.projectId = projectId
        self.date = date
        self.direction = direction
        self.category = ProjectFinancialCategory.normalized(category, for: direction)
        self.amount = amount
        self.counterparty = counterparty
        self.invoiceNumber = invoiceNumber
        self.linkedDocumentIds = linkedDocumentIds
        self.status = status
        self.dueDate = dueDate
        self.reminderStatus = reminderStatus
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, date, direction, category, amount, counterparty, invoiceNumber, linkedDocumentIds, linkedDocumentId, status, dueDate, reminderStatus, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? Formatters.now()
        let decodedDirection = try container.decodeStringEnum(
            ProjectFinancialDirection.self,
            forKey: .direction,
            default: .expense
        )
        direction = decodedDirection
        let decodedCategory = try container.decodeStringEnum(
            ProjectFinancialCategory.self,
            forKey: .category,
            default: decodedDirection.defaultCategory
        )
        category = ProjectFinancialCategory.normalized(decodedCategory, for: decodedDirection)
        amount = try container.decodeIfPresent(String.self, forKey: .amount) ?? ""
        counterparty = try container.decodeIfPresent(String.self, forKey: .counterparty) ?? ""
        invoiceNumber = try container.decodeIfPresent(String.self, forKey: .invoiceNumber) ?? ""
        if let ids = try container.decodeIfPresent([UUID].self, forKey: .linkedDocumentIds) {
            linkedDocumentIds = ids
        } else if let id = try container.decodeIfPresent(UUID.self, forKey: .linkedDocumentId) {
            linkedDocumentIds = [id]
        } else {
            linkedDocumentIds = []
        }
        status = try container.decodeStringEnum(ProjectFinancialStatus.self, forKey: .status, default: .active)
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate) ?? ""
        reminderStatus = try container.decodeStringEnum(
            ProjectFinancialReminderStatus.self,
            forKey: .reminderStatus,
            default: .none
        )
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(projectId, forKey: .projectId)
        try container.encode(date, forKey: .date)
        try container.encode(direction, forKey: .direction)
        try container.encode(category, forKey: .category)
        try container.encode(amount, forKey: .amount)
        try container.encode(counterparty, forKey: .counterparty)
        try container.encode(invoiceNumber, forKey: .invoiceNumber)
        try container.encode(linkedDocumentIds, forKey: .linkedDocumentIds)
        try container.encode(status, forKey: .status)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(reminderStatus, forKey: .reminderStatus)
        try container.encode(note, forKey: .note)
    }
}

enum MaterialPurchaseStatus: String, CaseIterable, Codable {
    case notPurchased = "未采购"
    case purchased = "已采购"
    case arrived = "已进场"
    case used = "已使用"

    var displayName: String { rawValue }
}

enum QuoteStatus: String, CaseIterable, Codable {
    case draft = "草稿"
    case sent = "已发送"
    case confirmed = "已确认"

    var displayName: String { rawValue }
}

enum PaymentStatus: String, CaseIterable, Codable {
    case unpaid = "未收款"
    case partial = "部分收款"
    case paid = "已收款"

    var displayName: String { rawValue }
}

enum ProjectFinancialDirection: String, CaseIterable, Codable {
    case income = "收入"
    case expense = "支出"

    var displayName: String { rawValue }

    var allowedCategories: [ProjectFinancialCategory] {
        switch self {
        case .income:
            return [.collection, .receipt, .paymentRequest, .refund, .other]
        case .expense:
            return [.material, .labor, .reimbursement, .invoice, .receipt, .refund, .other]
        }
    }

    var defaultCategory: ProjectFinancialCategory {
        allowedCategories.first ?? .other
    }

    func supports(_ category: ProjectFinancialCategory) -> Bool {
        allowedCategories.contains(category)
    }
}

enum ProjectFinancialCategory: String, CaseIterable, Codable {
    case collection = "收款"
    case refund = "退款"
    case reimbursement = "报销"
    case material = "材料"
    case labor = "人工"
    case invoice = "发票"
    case receipt = "收据"
    case paymentRequest = "请款"
    case other = "其他"

    var displayName: String { rawValue }

    static func allowed(for direction: ProjectFinancialDirection) -> [ProjectFinancialCategory] {
        direction.allowedCategories
    }

    static func normalized(_ category: ProjectFinancialCategory, for direction: ProjectFinancialDirection) -> ProjectFinancialCategory {
        direction.supports(category) ? category : direction.defaultCategory
    }

    static func normalized(rawValue: String, for direction: ProjectFinancialDirection) -> ProjectFinancialCategory {
        normalized(StringEnumFallback.value(rawValue, default: direction.defaultCategory), for: direction)
    }

    var requiresAttachment: Bool {
        switch self {
        case .material, .labor, .reimbursement, .invoice, .receipt:
            return true
        case .collection, .paymentRequest, .refund, .other:
            return false
        }
    }
}

enum ProjectFinancialStatus: String, CaseIterable, Codable {
    case active = "正式"
    case draft = "草稿"
    case archived = "已归档"

    var displayName: String { rawValue }
}

enum ProjectFinancialReminderStatus: String, CaseIterable, Codable {
    case none = "不提醒"
    case pending = "待提醒"
    case reminded = "已提醒"
    case done = "已处理"

    var displayName: String { rawValue }
}

extension ProjectFinancialRecord {
    var normalizedDirection: ProjectFinancialDirection {
        direction
    }

    var isIncomeDirection: Bool {
        normalizedDirection == .income
    }

    var isExpenseDirection: Bool {
        normalizedDirection == .expense
    }

    func matchesDirection(_ direction: ProjectFinancialDirection) -> Bool {
        normalizedDirection == direction
    }

    var normalizedCategory: ProjectFinancialCategory {
        category
    }

    var requiresAttachment: Bool {
        normalizedCategory.requiresAttachment
    }

    var normalizedStatus: ProjectFinancialStatus {
        status
    }

    var normalizedReminderStatus: ProjectFinancialReminderStatus {
        reminderStatus
    }

    var countsInBusinessMetrics: Bool {
        normalizedStatus == .active
    }

    var isCollectionIncome: Bool {
        normalizedDirection == .income && (normalizedCategory == .collection || normalizedCategory == .receipt)
    }

    var hasDueReminder: Bool {
        !dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && normalizedReminderStatus != .none
    }

    var isDueReminderOpen: Bool {
        hasDueReminder && normalizedReminderStatus != .done
    }

    var isDueReminderOverdue: Bool {
        guard isDueReminderOpen, let due = Formatters.date.date(from: dueDate) else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }
}
