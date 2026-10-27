import Foundation

struct ProjectPaymentInstallment: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var dueDate: BusinessDateValue
    var amount: MoneyValue
    var isRetention = false
}

struct ProjectPaymentPlan: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var direction: ProjectFinancialDirection
    var counterparty: String
    var installments: [ProjectPaymentInstallment]
    var isArchived = false
    var remindersEnabled = false
    var createdAt = BusinessDateValue.now()
}

struct ProjectPaymentAllocation: Codable, Equatable, Sendable {
    var planID: UUID
    var installmentID: UUID
}
