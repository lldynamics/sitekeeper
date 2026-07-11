import Foundation

struct MaterialItem: Identifiable, Codable, Sendable {
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

struct MaterialSheetDraftItem: Identifiable, Codable, Sendable {
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

struct MaterialSheetDraft: Identifiable, Codable, Sendable {
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

struct QuoteItem: Identifiable, Codable, Sendable {
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

struct LaborRecord: Identifiable, Codable, Sendable {
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
