import Foundation

enum ProjectDetailFocus: Hashable {
    case financialRecord(UUID)
    case document(UUID)
    case contact(UUID)
}

enum ProjectDetailFocusedItem {
    case financialRecord(ProjectFinancialRecord)
    case document(ProjectDocument)
    case contact(ProjectContact)

    var mode: ProjectDetailMode {
        switch self {
        case .financialRecord:
            return .finance
        case .document, .contact:
            return .assets
        }
    }
}

enum ProjectDetailFocusRouter {
    static func resolve(
        focus: ProjectDetailFocus,
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument],
        contacts: [ProjectContact]
    ) -> ProjectDetailFocusedItem? {
        switch focus {
        case .financialRecord(let id):
            return financialRecords.first { $0.id == id }.map(ProjectDetailFocusedItem.financialRecord)
        case .document(let id):
            return documents.first { $0.id == id }.map(ProjectDetailFocusedItem.document)
        case .contact(let id):
            return contacts.first { $0.id == id }.map(ProjectDetailFocusedItem.contact)
        }
    }
}
