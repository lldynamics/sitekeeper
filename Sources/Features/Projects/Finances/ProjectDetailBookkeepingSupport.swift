import SwiftUI

struct BookCounterpartySummary: Identifiable {
    var id: String { name }
    let name: String
    let incomeAmount: MoneyValue
    let expenseAmount: MoneyValue
    let receivableAmount: MoneyValue
    let payableAmount: MoneyValue
    let unsettledCount: Int
    let missingReceiptCount: Int
    let match: BookCounterpartyMatch
    let kind: BookCounterpartyKind

    var netOutstandingAmount: MoneyValue { receivableAmount - payableAmount }
    var totalOutstandingAmount: MoneyValue { receivableAmount + payableAmount }
    var turnoverAmount: MoneyValue { incomeAmount + expenseAmount }
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
            return AppLocalization.string("供应商")
        case .team:
            return AppLocalization.string("班组")
        case .customer:
            return AppLocalization.string("客户")
        case .other:
            return AppLocalization.string("其他")
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
            return AppLocalization.string("全部")
        case .income:
            return AppLocalization.string("收入")
        case .expense:
            return AppLocalization.string("支出")
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
            return AppLocalization.string("全部")
        case .invoice:
            return AppLocalization.string("发票")
        case .receipt:
            return AppLocalization.string("收据")
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
            return AppLocalization.string("全部")
        case .attached:
            return AppLocalization.string("已附票据")
        case .unattached:
            return AppLocalization.string("未附票据")
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
            return AppLocalization.string("全部")
        case .activeWithDueDate:
            return AppLocalization.string("应收付")
        }
    }

    func matches(_ record: ProjectFinancialRecord) -> Bool {
        switch self {
        case .all:
            return true
        case .activeWithDueDate:
            return record.normalizedStatus == .active && !record.dueDate.isEmpty
        }
    }
}
