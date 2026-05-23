import SwiftUI

extension DocumentArchiveChecklistItem {
    var tint: Color {
        if isMissing || returnedCount > 0 { return .appWarning }
        if actionCount > 0 { return .appPrimaryAction }
        return .appSuccess
    }
}

enum DocumentCategoryFilter: String, CaseIterable {
    case all
    case constructionArchive
    case constructionTechnical
    case constructionMaterial
    case constructionSurvey
    case constructionRecord
    case constructionTest
    case constructionManagement
    case processAcceptance
    case completionAcceptance
    case businessArchive
    case paymentRequest
    case contract
    case invoice
    case receipt
    case legacyConstruction
    case acceptance
    case other

    var displayName: String {
        switch self {
        case .all:
            return String(localized: "全部")
        case .constructionArchive:
            return String(localized: "全部施工资料")
        case .constructionTechnical:
            return String(localized: "施工技术")
        case .constructionMaterial:
            return String(localized: "施工物资")
        case .constructionSurvey:
            return String(localized: "施工测量")
        case .constructionRecord:
            return String(localized: "施工记录")
        case .constructionTest:
            return String(localized: "施工试验")
        case .constructionManagement:
            return String(localized: "施工管理")
        case .processAcceptance:
            return String(localized: "过程验收")
        case .completionAcceptance:
            return String(localized: "竣工验收")
        case .businessArchive:
            return String(localized: "商务/财务")
        case .paymentRequest:
            return String(localized: "请款资料")
        case .contract:
            return String(localized: "合同")
        case .invoice:
            return String(localized: "发票")
        case .receipt:
            return String(localized: "收据")
        case .legacyConstruction:
            return String(localized: "施工资料")
        case .acceptance:
            return String(localized: "验收资料")
        case .other:
            return String(localized: "其他资料")
        }
    }

    init(category: ProjectDocumentCategory) {
        switch category {
        case .constructionTechnical:
            self = .constructionTechnical
        case .constructionMaterial:
            self = .constructionMaterial
        case .constructionSurvey:
            self = .constructionSurvey
        case .constructionRecord:
            self = .constructionRecord
        case .constructionTest:
            self = .constructionTest
        case .constructionManagement:
            self = .constructionManagement
        case .processAcceptance:
            self = .processAcceptance
        case .completionAcceptance:
            self = .completionAcceptance
        case .invoice:
            self = .invoice
        case .receipt:
            self = .receipt
        case .paymentRequest:
            self = .paymentRequest
        case .contract:
            self = .contract
        case .acceptance:
            self = .acceptance
        case .other:
            self = .other
        case .construction:
            self = .legacyConstruction
        }
    }

    func matches(_ document: ProjectDocument) -> Bool {
        switch self {
        case .all:
            return true
        case .constructionArchive:
            return document.category.isConstructionArchive
        case .constructionTechnical:
            return document.category == .constructionTechnical
        case .constructionMaterial:
            return document.category == .constructionMaterial
        case .constructionSurvey:
            return document.category == .constructionSurvey
        case .constructionRecord:
            return document.category == .constructionRecord
        case .constructionTest:
            return document.category == .constructionTest
        case .constructionManagement:
            return document.category == .constructionManagement
        case .processAcceptance:
            return document.category == .processAcceptance
        case .completionAcceptance:
            return document.category == .completionAcceptance
        case .businessArchive:
            return document.category.isBusinessArchive
        case .paymentRequest:
            return document.category == .paymentRequest
        case .contract:
            return document.category == .contract
        case .invoice:
            return document.category == .invoice
        case .receipt:
            return document.category == .receipt
        case .legacyConstruction:
            return document.category == .construction
        case .acceptance:
            return document.category == .acceptance
        case .other:
            return document.category == .other
        }
    }
}

enum DocumentRelationFilter: String, CaseIterable {
    case all
    case linked
    case unlinked

    var displayName: String {
        switch self {
        case .all:
            return String(localized: "全部")
        case .linked:
            return String(localized: "已关联账目")
        case .unlinked:
            return String(localized: "未关联账目")
        }
    }

    func matches(_ document: ProjectDocument) -> Bool {
        switch self {
        case .all:
            return true
        case .linked:
            return document.linkedFinancialRecordId != nil
        case .unlinked:
            return document.linkedFinancialRecordId == nil
        }
    }
}

typealias DocumentFinancialMatch = ProjectDocumentMatchSuggestion
