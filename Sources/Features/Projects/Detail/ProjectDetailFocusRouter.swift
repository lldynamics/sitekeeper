import Foundation

enum ProjectDetailFocus: Hashable {
    case financialRecord(UUID)
    case document(UUID)
    case contact(UUID)
    case drawing(UUID)
}

enum ProjectDetailFocusedItem {
    case financialRecord(ProjectFinancialRecord)
    case document(ProjectDocument)
    case contact(ProjectContact)
    case drawing(ProjectDrawing)

    var mode: ProjectDetailMode {
        switch self {
        case .financialRecord:
            return .finance
        case .document, .contact, .drawing:
            return .assets
        }
    }
}

enum ProjectDetailFocusRouter {
    static func resolve(
        focus: ProjectDetailFocus,
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument],
        contacts: [ProjectContact],
        drawings: [ProjectDrawing] = []
    ) -> ProjectDetailFocusedItem? {
        switch focus {
        case .financialRecord(let id):
            return financialRecords.first { $0.id == id }.map(ProjectDetailFocusedItem.financialRecord)
        case .document(let id):
            return documents.first { $0.id == id }.map(ProjectDetailFocusedItem.document)
        case .contact(let id):
            return contacts.first { $0.id == id }.map(ProjectDetailFocusedItem.contact)
        case .drawing(let id):
            return drawings.first { $0.id == id }.map(ProjectDetailFocusedItem.drawing)
        }
    }
}
