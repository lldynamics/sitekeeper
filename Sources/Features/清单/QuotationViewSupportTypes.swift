import Foundation

enum QuoteStatusChip: CaseIterable, Hashable {
    case all
    case draft
    case sent
    case confirmed

    init(status: QuoteStatus?) {
        switch status {
        case .draft: self = .draft
        case .sent: self = .sent
        case .confirmed: self = .confirmed
        case nil: self = .all
        }
    }

    var status: QuoteStatus? {
        switch self {
        case .all: return nil
        case .draft: return .draft
        case .sent: return .sent
        case .confirmed: return .confirmed
        }
    }

    var title: String {
        switch self {
        case .all: return String(localized: "全部")
        case .draft: return String(localized: "草稿")
        case .sent: return String(localized: "已发送")
        case .confirmed: return String(localized: "已确认")
        }
    }
}

enum QuotationSheetRoute: String, Identifiable {
    case edit
    case generate
    case export

    var id: String { rawValue }
}
