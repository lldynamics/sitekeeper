import Foundation

struct ProjectDetailRouteState {
    var mode: ProjectDetailMode
    var financeJumpFilter: ProjectFinanceJumpFilter = .none
    var drawingFilter: DrawingListFilter = .all
    var presentation: ProjectDetailPresentation?
    var editingRoute: ProjectDetailEditingRoute?
    var anchorRequest: ProjectDetailAnchorRequest?
    var documentScanCategory: ProjectDocumentCategory?
}

enum ProjectDetailEditingRoute: Identifiable {
    case material(MaterialItem)
    case quote(QuoteItem)
    case labor(LaborRecord)
    case progress(ProgressTask)

    var id: String {
        switch self {
        case .material(let item):
            return "material-\(item.id.uuidString)"
        case .quote(let item):
            return "quote-\(item.id.uuidString)"
        case .labor(let item):
            return "labor-\(item.id.uuidString)"
        case .progress(let item):
            return "progress-\(item.id.uuidString)"
        }
    }
}

enum ProjectDetailAnchor: String {
    case overview
    case records
    case assets
    case finance
    case timeline

    var scrollID: String { "project-detail-anchor-\(rawValue)" }

    var title: String {
        switch self {
        case .overview:
            return "概况"
        case .records:
            return "现场"
        case .assets:
            return "资料"
        case .finance:
            return "财务"
        case .timeline:
            return "时间线"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "rectangle.grid.2x2.fill"
        case .records:
            return "checklist.checked"
        case .assets:
            return "folder.fill"
        case .finance:
            return "yensign.circle.fill"
        case .timeline:
            return "timeline.selection"
        }
    }
}

struct ProjectDetailAnchorRequest: Identifiable {
    let id = UUID()
    let anchor: ProjectDetailAnchor
}

enum ProjectDetailPresentation: Identifiable, Equatable {
    case quickAdd(DetailSheet)
    case editProject
    case deliveryGuide
    case addContact
    case addFinancial
    case documentScanSetup
    case imagePicker

    var id: String {
        switch self {
        case .quickAdd(let sheet):
            return "quickAdd-\(sheet.rawValue)"
        case .editProject:
            return "editProject"
        case .deliveryGuide:
            return "deliveryGuide"
        case .addContact:
            return "addContact"
        case .addFinancial:
            return "addFinancial"
        case .documentScanSetup:
            return "documentScanSetup"
        case .imagePicker:
            return "imagePicker"
        }
    }
}
