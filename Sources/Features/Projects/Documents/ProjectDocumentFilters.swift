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
            return AppLocalization.string("全部")
        case .constructionArchive:
            return AppLocalization.string("全部施工资料")
        case .constructionTechnical:
            return AppLocalization.string("施工技术")
        case .constructionMaterial:
            return AppLocalization.string("施工物资")
        case .constructionSurvey:
            return AppLocalization.string("施工测量")
        case .constructionRecord:
            return AppLocalization.string("施工记录")
        case .constructionTest:
            return AppLocalization.string("施工试验")
        case .constructionManagement:
            return AppLocalization.string("施工管理")
        case .processAcceptance:
            return AppLocalization.string("过程验收")
        case .completionAcceptance:
            return AppLocalization.string("竣工验收")
        case .businessArchive:
            return AppLocalization.string("商务/财务")
        case .paymentRequest:
            return AppLocalization.string("请款资料")
        case .contract:
            return AppLocalization.string("合同")
        case .invoice:
            return AppLocalization.string("发票")
        case .receipt:
            return AppLocalization.string("收据")
        case .legacyConstruction:
            return AppLocalization.string("施工资料")
        case .acceptance:
            return AppLocalization.string("验收资料")
        case .other:
            return AppLocalization.string("其他资料")
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
            return AppLocalization.string("全部")
        case .linked:
            return AppLocalization.string("已关联账目")
        case .unlinked:
            return AppLocalization.string("未关联账目")
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
