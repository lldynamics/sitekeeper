import Foundation

struct ProjectFinancialRecord: Identifiable, Codable, Sendable {
    var id = UUID()
    var projectId: UUID
    var date: BusinessDateValue
    var direction: ProjectFinancialDirection
    var category: ProjectFinancialCategory
    @NonNegativeDecimal var amount: MoneyValue
    var counterparty: String
    var invoiceNumber: String
    var linkedDocumentIds: [UUID]
    var status: ProjectFinancialStatus
    var dueDate: BusinessDateValue
    var reminderStatus: ProjectFinancialReminderStatus
    var note: String
    var origin: BusinessRecordOrigin?
    var paymentAllocation: ProjectPaymentAllocation?

    init(
        id: UUID = UUID(),
        projectId: UUID,
        date: BusinessDateValue = .now(),
        direction: ProjectFinancialDirection = .expense,
        category: ProjectFinancialCategory = ProjectFinancialDirection.expense.defaultCategory,
        amount: MoneyValue = .empty,
        counterparty: String = "",
        invoiceNumber: String = "",
        linkedDocumentIds: [UUID] = [],
        status: ProjectFinancialStatus = .active,
        dueDate: BusinessDateValue = .empty,
        reminderStatus: ProjectFinancialReminderStatus = .none,
        note: String = "",
        origin: BusinessRecordOrigin? = nil,
        paymentAllocation: ProjectPaymentAllocation? = nil
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
        self.origin = origin
        self.paymentAllocation = paymentAllocation
    }

    enum CodingKeys: String, CodingKey {
        case id, projectId, date, direction, category, amount, counterparty, invoiceNumber, linkedDocumentIds, linkedDocumentId, status, dueDate, reminderStatus, note, origin, paymentAllocation
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        projectId = try container.decode(UUID.self, forKey: .projectId)
        date = try container.decodeIfPresent(BusinessDateValue.self, forKey: .date) ?? .empty
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
        amount = try container.decodeIfPresent(MoneyValue.self, forKey: .amount) ?? .empty
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
        dueDate = try container.decodeIfPresent(BusinessDateValue.self, forKey: .dueDate) ?? .empty
        reminderStatus = try container.decodeStringEnum(
            ProjectFinancialReminderStatus.self,
            forKey: .reminderStatus,
            default: .none
        )
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        origin = try container.decodeIfPresent(BusinessRecordOrigin.self, forKey: .origin)
        paymentAllocation = try container.decodeIfPresent(ProjectPaymentAllocation.self, forKey: .paymentAllocation)
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
        try container.encodeIfPresent(origin, forKey: .origin)
        try container.encodeIfPresent(paymentAllocation, forKey: .paymentAllocation)
    }
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
        !dueDate.isEmpty && normalizedReminderStatus != .none
    }

    var isDueReminderOpen: Bool {
        hasDueReminder && normalizedReminderStatus != .done
    }

    var isDueReminderOverdue: Bool {
        guard isDueReminderOpen, let due = dueDate.date() else { return false }
        return due < Calendar.current.startOfDay(for: Date())
    }
}
