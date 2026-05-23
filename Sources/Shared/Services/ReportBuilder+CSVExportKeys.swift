import Foundation

extension MaterialPurchaseStatus {
    var exportKey: String {
        switch self {
        case .notPurchased: "not_purchased"
        case .purchased: "purchased"
        case .arrived: "arrived"
        case .used: "used"
        }
    }
}

extension QuoteStatus {
    var exportKey: String {
        switch self {
        case .draft: "draft"
        case .sent: "sent"
        case .confirmed: "confirmed"
        }
    }
}

extension ProjectFinancialDirection {
    var exportKey: String {
        switch self {
        case .income: "income"
        case .expense: "expense"
        }
    }
}

extension ProjectFinancialCategory {
    var exportKey: String {
        switch self {
        case .collection: "collection"
        case .refund: "refund"
        case .reimbursement: "reimbursement"
        case .material: "material"
        case .labor: "labor"
        case .invoice: "invoice"
        case .receipt: "receipt"
        case .paymentRequest: "payment_request"
        case .other: "other"
        }
    }
}

extension ProjectFinancialStatus {
    var exportKey: String {
        switch self {
        case .active: "active"
        case .draft: "draft"
        case .archived: "archived"
        }
    }
}

extension ProjectFinancialReminderStatus {
    var exportKey: String {
        switch self {
        case .none: "none"
        case .pending: "pending"
        case .reminded: "reminded"
        case .done: "done"
        }
    }
}

extension ProjectDocumentCategory {
    var exportKey: String {
        switch self {
        case .paymentRequest: "payment_request"
        case .construction: "construction"
        case .constructionTechnical: "construction_technical"
        case .constructionMaterial: "construction_material"
        case .constructionSurvey: "construction_survey"
        case .constructionRecord: "construction_record"
        case .constructionTest: "construction_test"
        case .constructionManagement: "construction_management"
        case .processAcceptance: "process_acceptance"
        case .completionAcceptance: "completion_acceptance"
        case .invoice: "invoice"
        case .receipt: "receipt"
        case .contract: "contract"
        case .acceptance: "acceptance"
        case .other: "other"
        }
    }
}

extension ProjectContactRole {
    var exportKey: String {
        switch self {
        case .owner: "owner"
        case .customer: "customer"
        case .supervisor: "supervisor"
        case .supplier: "supplier"
        case .team: "team"
        case .other: "other"
        }
    }
}

extension ProjectDrawingFileAvailabilityStatus {
    var exportKey: String {
        rawValue
    }
}

extension DrawingIssueStatus {
    var exportKey: String {
        switch self {
        case .none: "none"
        case .open: "open"
        case .inProgress: "in_progress"
        case .closed: "closed"
        }
    }
}

extension TodoPriority {
    var exportKey: String {
        switch self {
        case .high: "high"
        case .medium: "medium"
        case .low: "low"
        }
    }
}

extension TodoIssueType {
    var exportKey: String {
        switch self {
        case .safety: "safety"
        case .quality: "quality"
        case .material: "material"
        case .schedule: "schedule"
        case .general: "general"
        }
    }
}

extension WarehouseMovementType {
    var exportKey: String {
        switch self {
        case .inbound: "inbound"
        case .outbound: "outbound"
        }
    }
}

extension ProjectDocumentSubmissionStatus {
    var exportKey: String {
        switch self {
        case .notSubmitted: "not_submitted"
        case .pending: "pending"
        case .submitted: "submitted"
        case .returned: "returned"
        case .confirmed: "confirmed"
        case .archived: "archived"
        }
    }
}

extension DocumentArchiveChecklistItem {
    var statusExportKey: String {
        if isMissing { return "missing" }
        if returnedCount > 0 { return "returned" }
        if actionCount > 0 { return "pending" }
        if archivedCount == documentCount { return "archived" }
        return "covered"
    }
}
