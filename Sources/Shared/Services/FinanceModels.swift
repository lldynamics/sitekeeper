import Foundation

struct MaterialItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var quantity: String
    var unit: String
    var unitPrice: String
    var specification: String
    var brand: String
    var supplier: String
    var purchaseStatus: String
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
        purchaseStatus: String = MaterialPurchaseStatus.notPurchased.rawValue,
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
        purchaseStatus = try container.decodeIfPresent(String.self, forKey: .purchaseStatus) ?? MaterialPurchaseStatus.notPurchased.rawValue
        arrivalDate = try container.decodeIfPresent(String.self, forKey: .arrivalDate) ?? ""
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
    }
}

struct QuoteItem: Identifiable, Codable {
    var id = UUID()
    var name: String
    var unitPrice: String
    var quantity: String
    var unit: String
    var notes: String
    var taxRate: String
    var discountRate: String
    var versionName: String
    var status: String
    var customerConfirmedDate: String
    var contractAmount: String
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
        status: String = QuoteStatus.draft.rawValue,
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
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? QuoteStatus.draft.rawValue
        customerConfirmedDate = try container.decodeIfPresent(String.self, forKey: .customerConfirmedDate) ?? ""
        contractAmount = try container.decodeIfPresent(String.self, forKey: .contractAmount) ?? ""
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
    }
}

struct LaborRecord: Identifiable, Codable {
    var id = UUID()
    var date: String
    var workers: String
    var hours: String
    var unitRate: String
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

struct PaymentRecord: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var date: String
    var amount: String
    var method: String
    var note: String
    var isInvoiced: Bool

    init(
        id: UUID = UUID(),
        projectId: UUID,
        date: String,
        amount: String,
        method: String = PaymentMethod.bankTransfer.rawValue,
        note: String = "",
        isInvoiced: Bool = false
    ) {
        self.id = id
        self.projectId = projectId
        self.date = date
        self.amount = amount
        self.method = method
        self.note = note
        self.isInvoiced = isInvoiced
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, date, amount, method, note, isInvoiced
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? Formatters.date.string(from: Date())
        amount = try container.decodeIfPresent(String.self, forKey: .amount) ?? ""
        method = try container.decodeIfPresent(String.self, forKey: .method) ?? PaymentMethod.bankTransfer.rawValue
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        isInvoiced = try container.decodeIfPresent(Bool.self, forKey: .isInvoiced) ?? false
    }
}

struct ProjectFinancialRecord: Identifiable, Codable {
    var id = UUID()
    var projectId: UUID
    var date: String
    var direction: String
    var category: String
    var amount: String
    var counterparty: String
    var invoiceNumber: String
    var linkedDocumentIds: [UUID]
    var note: String

    init(
        id: UUID = UUID(),
        projectId: UUID,
        date: String = Formatters.date.string(from: Date()),
        direction: String = ProjectFinancialDirection.expense.rawValue,
        category: String = ProjectFinancialDirection.expense.defaultCategory.rawValue,
        amount: String = "",
        counterparty: String = "",
        invoiceNumber: String = "",
        linkedDocumentIds: [UUID] = [],
        note: String = ""
    ) {
        self.id = id
        self.projectId = projectId
        self.date = date
        self.direction = direction
        self.category = category
        self.amount = amount
        self.counterparty = counterparty
        self.invoiceNumber = invoiceNumber
        self.linkedDocumentIds = linkedDocumentIds
        self.note = note
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, date, direction, category, amount, counterparty, invoiceNumber, linkedDocumentIds, linkedDocumentId, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        date = try container.decodeIfPresent(String.self, forKey: .date) ?? Formatters.date.string(from: Date())
        let decodedDirection = ProjectFinancialDirection(rawValue: try container.decodeIfPresent(String.self, forKey: .direction) ?? "") ?? .expense
        direction = decodedDirection.rawValue
        let decodedCategory = try container.decodeIfPresent(String.self, forKey: .category) ?? decodedDirection.defaultCategory.rawValue
        category = ProjectFinancialCategory.normalized(rawValue: decodedCategory, for: decodedDirection).rawValue
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

enum PaymentMethod: String, CaseIterable, Codable {
    case bankTransfer = "转账"
    case cash = "现金"
    case wechat = "微信"
    case alipay = "支付宝"
    case other = "其他"

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
        normalized(ProjectFinancialCategory(rawValue: rawValue) ?? direction.defaultCategory, for: direction)
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

extension ProjectFinancialRecord {
    var normalizedDirection: ProjectFinancialDirection {
        ProjectFinancialDirection(rawValue: direction) ?? .expense
    }

    var normalizedCategory: ProjectFinancialCategory {
        ProjectFinancialCategory.normalized(rawValue: category, for: normalizedDirection)
    }

    var requiresAttachment: Bool {
        normalizedCategory.requiresAttachment
    }
}
