import Foundation

enum ProjectDetailFocusedItemApplier {
    static func apply(
        _ item: ProjectDetailFocusedItem,
        setFinancialRecord: (ProjectFinancialRecord) -> Void,
        setDocument: (ProjectDocument) -> Void,
        setContact: (ProjectContact) -> Void
    ) {
        switch item {
        case .financialRecord(let record):
            setFinancialRecord(record)
        case .document(let document):
            setDocument(document)
        case .contact(let contact):
            setContact(contact)
        }
    }
}
