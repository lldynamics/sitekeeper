import SwiftUI

struct BookCounterpartySummary: Identifiable {
    var id: String { name }
    let name: String
    let incomeAmount: Double
    let expenseAmount: Double
    let receivableAmount: Double
    let payableAmount: Double
    let unsettledCount: Int
    let missingReceiptCount: Int
    let match: BookCounterpartyMatch
    let kind: BookCounterpartyKind

    var netOutstandingAmount: Double { receivableAmount - payableAmount }
    var totalOutstandingAmount: Double { receivableAmount + payableAmount }
    var turnoverAmount: Double { incomeAmount + expenseAmount }
}

struct BookCounterpartyMatch {
    let supplier: SupplierProfile?
    let contact: ProjectContact?

    static let none = BookCounterpartyMatch(supplier: nil, contact: nil)

    var isEmpty: Bool {
        supplier == nil && contact == nil
    }
}

enum BookCounterpartyKind {
    case supplier
    case team
    case customer
    case other

    var displayName: String {
        switch self {
        case .supplier:
            return String(localized: "供应商")
        case .team:
            return String(localized: "班组")
        case .customer:
            return String(localized: "客户")
        case .other:
            return String(localized: "其他")
        }
    }

    var tint: Color {
        switch self {
        case .supplier:
            return .appWarning
        case .team:
            return .appSuccess
        case .customer:
            return .appDoc
        case .other:
            return .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .supplier:
            return "building.2.fill"
        case .team:
            return "person.3.fill"
        case .customer:
            return "person.text.rectangle.fill"
        case .other:
            return "person.crop.circle.fill"
        }
    }
}

enum BookDirectionFilter: CaseIterable {
    case all
    case income
    case expense

    var displayName: String {
        switch self {
        case .all:
            return String(localized: "全部")
        case .income:
            return String(localized: "收入")
        case .expense:
            return String(localized: "支出")
        }
    }

    func matches(_ record: ProjectFinancialRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .income:
            return record.isIncomeDirection
        case .expense:
            return record.isExpenseDirection
        }
    }
}

enum BookCategoryFilter: CaseIterable {
    case all
    case invoice
    case receipt

    var displayName: String {
        switch self {
        case .all:
            return String(localized: "全部")
        case .invoice:
            return String(localized: "发票")
        case .receipt:
            return String(localized: "收据")
        }
    }

    func matches(_ record: ProjectFinancialRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .invoice:
            return record.category == .invoice
        case .receipt:
            return record.category == .receipt
        }
    }
}

enum BookAttachmentFilter: CaseIterable {
    case all
    case attached
    case unattached

    var displayName: String {
        switch self {
        case .all:
            return String(localized: "全部")
        case .attached:
            return String(localized: "已附票据")
        case .unattached:
            return String(localized: "未附票据")
        }
    }

    func matches(
        _ record: ProjectFinancialRecord,
        linkedDocuments: (ProjectFinancialRecord) -> [ProjectDocument]
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .attached:
            return !linkedDocuments(record).isEmpty
        case .unattached:
            return record.countsInBusinessMetrics && record.requiresAttachment && linkedDocuments(record).isEmpty
        }
    }
}

enum BookOutstandingFilter: CaseIterable {
    case all
    case activeWithDueDate

    var displayName: String {
        switch self {
        case .all:
            return String(localized: "全部")
        case .activeWithDueDate:
            return String(localized: "应收付")
        }
    }

    func matches(_ record: ProjectFinancialRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .activeWithDueDate:
            return record.normalizedStatus == .active && !record.dueDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
