import Foundation

struct MaterialItem: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    @NonNegativeDecimal var quantity: QuantityValue
    var unit: String
    @NonNegativeDecimal var unitPrice: MoneyValue
    var specification: String
    var brand: String
    var supplier: String
    var purchaseStatus: MaterialPurchaseStatus
    var arrivalDate: BusinessDateValue
    var projectId: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        quantity: QuantityValue,
        unit: String,
        unitPrice: MoneyValue = .empty,
        specification: String = "",
        brand: String = "",
        supplier: String = "",
        purchaseStatus: MaterialPurchaseStatus = .notPurchased,
        arrivalDate: BusinessDateValue = .empty,
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
        quantity = try container.decodeIfPresent(QuantityValue.self, forKey: .quantity) ?? .empty
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        unitPrice = try container.decodeIfPresent(MoneyValue.self, forKey: .unitPrice) ?? .empty
        specification = try container.decodeIfPresent(String.self, forKey: .specification) ?? ""
        brand = try container.decodeIfPresent(String.self, forKey: .brand) ?? ""
        supplier = try container.decodeIfPresent(String.self, forKey: .supplier) ?? ""
        purchaseStatus = try container.decodeStringEnum(
            MaterialPurchaseStatus.self,
            forKey: .purchaseStatus,
            default: .notPurchased
        )
        arrivalDate = try container.decodeIfPresent(BusinessDateValue.self, forKey: .arrivalDate) ?? .empty
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
    }
}

struct MaterialSheetDraftItem: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var specification: String
    var unit: String
    @NonNegativeDecimal var quantity: QuantityValue
    @NonNegativeDecimal var unitPrice: MoneyValue
    @NonNegativeDecimal var laborCost: MoneyValue
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
        quantity: QuantityValue = .empty,
        unitPrice: MoneyValue = .empty,
        laborCost: MoneyValue = .empty,
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
        quantity = try container.decodeIfPresent(QuantityValue.self, forKey: .quantity) ?? .empty
        unitPrice = try container.decodeIfPresent(MoneyValue.self, forKey: .unitPrice) ?? .empty
        laborCost = try container.decodeIfPresent(MoneyValue.self, forKey: .laborCost) ?? .empty
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
    var exportDate: BusinessDateValue
    var items: [MaterialSheetDraftItem]
    var createdAt: BusinessDateValue
    var updatedAt: BusinessDateValue

    init(
        id: UUID = UUID(),
        title: String = "",
        projectId: UUID? = nil,
        isArchived: Bool = false,
        exportProjectName: String = "",
        exportPreparer: String = "",
        exportDate: BusinessDateValue = .today(),
        items: [MaterialSheetDraftItem] = [],
        createdAt: BusinessDateValue = .now(),
        updatedAt: BusinessDateValue = .now()
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
        exportDate = try container.decodeIfPresent(BusinessDateValue.self, forKey: .exportDate) ?? .empty
        items = try container.decodeIfPresent([MaterialSheetDraftItem].self, forKey: .items) ?? []
        createdAt = try container.decodeIfPresent(BusinessDateValue.self, forKey: .createdAt) ?? .empty
        updatedAt = try container.decodeIfPresent(BusinessDateValue.self, forKey: .updatedAt) ?? .empty
    }
}

struct QuoteItem: Identifiable, Codable, Sendable {
    var id = UUID()
    var name: String
    @NonNegativeDecimal var unitPrice: MoneyValue
    @NonNegativeDecimal var quantity: QuantityValue
    var unit: String
    var notes: String
    @NonNegativeDecimal var taxRate: QuantityValue
    @NonNegativeDecimal var discountRate: QuantityValue
    var versionName: String
    var status: QuoteStatus
    var customerConfirmedDate: BusinessDateValue
    @NonNegativeDecimal var contractAmount: MoneyValue
    var projectId: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        unitPrice: MoneyValue,
        quantity: QuantityValue,
        unit: String,
        notes: String,
        taxRate: QuantityValue,
        discountRate: QuantityValue,
        versionName: String = "V1",
        status: QuoteStatus = .draft,
        customerConfirmedDate: BusinessDateValue = .empty,
        contractAmount: MoneyValue = .empty,
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
        unitPrice = try container.decodeIfPresent(MoneyValue.self, forKey: .unitPrice) ?? .empty
        quantity = try container.decodeIfPresent(QuantityValue.self, forKey: .quantity) ?? .empty
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        taxRate = try container.decodeIfPresent(QuantityValue.self, forKey: .taxRate) ?? .zero
        discountRate = try container.decodeIfPresent(QuantityValue.self, forKey: .discountRate) ?? .zero
        versionName = try container.decodeIfPresent(String.self, forKey: .versionName) ?? "V1"
        status = try container.decodeStringEnum(QuoteStatus.self, forKey: .status, default: .draft)
        customerConfirmedDate = try container.decodeIfPresent(BusinessDateValue.self, forKey: .customerConfirmedDate) ?? .empty
        contractAmount = try container.decodeIfPresent(MoneyValue.self, forKey: .contractAmount) ?? .empty
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
    }
}

enum LaborWorkloadUnit: String, Codable, CaseIterable, Sendable {
    case legacyUnspecified
    case hour
    case workday

    var displayName: String {
        switch self {
        case .legacyUnspecified:
            AppLocalization.string("待确认单位")
        case .hour:
            AppLocalization.string("工时")
        case .workday:
            AppLocalization.string("天")
        }
    }

    var quoteUnit: String? {
        switch self {
        case .legacyUnspecified:
            nil
        case .hour:
            AppLocalization.string("工时")
        case .workday:
            AppLocalization.string("工天")
        }
    }
}

struct LaborRecord: Identifiable, Codable, Sendable {
    var id = UUID()
    var date: BusinessDateValue
    @NonNegativeDecimal var workers: QuantityValue
    @NonNegativeDecimal var hours: QuantityValue
    @NonNegativeDecimal var unitRate: MoneyValue

    /// 历史字段名为 hours；实际语义由 workloadUnit 明确。
    var workloadUnit: LaborWorkloadUnit
    var days: QuantityValue { hours }
    var workType: String
    var teamName: String
    var isSettled: Bool
    var note: String
    var projectId: UUID?

    init(
        id: UUID = UUID(),
        date: BusinessDateValue,
        workers: QuantityValue,
        hours: QuantityValue,
        workloadUnit: LaborWorkloadUnit = .hour,
        unitRate: MoneyValue = .empty,
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
        self.workloadUnit = workloadUnit
        self.unitRate = unitRate
        self.workType = workType
        self.teamName = teamName
        self.isSettled = isSettled
        self.note = note
        self.projectId = projectId
    }

    enum CodingKeys: String, CodingKey {
        case id, date, workers, hours, workloadUnit, unitRate, workType, teamName, isSettled, note, projectId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(BusinessDateValue.self, forKey: .date)
        workers = try container.decodeIfPresent(QuantityValue.self, forKey: .workers) ?? .empty
        hours = try container.decodeIfPresent(QuantityValue.self, forKey: .hours) ?? .empty
        // 旧版本曾同时把工时与工天写进 hours，必须由用户确认后才能用于报价。
        workloadUnit = try container.decodeIfPresent(LaborWorkloadUnit.self, forKey: .workloadUnit) ?? .legacyUnspecified
        unitRate = try container.decodeIfPresent(MoneyValue.self, forKey: .unitRate) ?? .empty
        workType = try container.decodeIfPresent(String.self, forKey: .workType) ?? ""
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName) ?? ""
        isSettled = try container.decodeIfPresent(Bool.self, forKey: .isSettled) ?? false
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
    }
}
