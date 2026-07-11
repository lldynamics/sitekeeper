import Foundation

enum MaterialPurchaseStatus: String, CaseIterable, Codable, Sendable {
    case notPurchased = "未采购"
    case purchased = "已采购"
    case arrived = "已进场"
    case used = "已使用"

    var displayName: String { rawValue }
}

enum QuoteStatus: String, CaseIterable, Codable, Sendable {
    case draft = "草稿"
    case sent = "已发送"
    case confirmed = "已确认"

    var displayName: String { rawValue }
}

enum PaymentStatus: String, CaseIterable, Codable, Sendable {
    case unpaid = "未收款"
    case partial = "部分收款"
    case paid = "已收款"

    var displayName: String { rawValue }
}

enum ProjectFinancialDirection: String, CaseIterable, Codable, Sendable {
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

enum ProjectFinancialCategory: String, CaseIterable, Codable, Sendable {
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

enum ProjectFinancialStatus: String, CaseIterable, Codable, Sendable {
    case active = "正式"
    case draft = "草稿"
    case archived = "已归档"

    var displayName: String { rawValue }
}

enum ProjectFinancialReminderStatus: String, CaseIterable, Codable, Sendable {
    case none = "不提醒"
    case pending = "待提醒"
    case reminded = "已提醒"
    case done = "已处理"

    var displayName: String { rawValue }
}
