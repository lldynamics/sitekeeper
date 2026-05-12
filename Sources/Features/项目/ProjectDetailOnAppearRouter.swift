import Foundation

struct ProjectDetailOnAppearRouting {
    let shouldOpenFinancialAdd: Bool
    let shouldOpenDocumentScanSetup: Bool
    let shouldOpenDeliveryGuide: Bool
    let shouldConsumeFocusRequest: Bool
    let focusedItem: ProjectDetailFocusedItem?
}

enum ProjectDetailOnAppearRouter {
    static func resolve(
        autoOpenFinancialAdd: Bool,
        didAutoOpenFinancialAdd: Bool,
        autoOpenDocumentScanSetup: Bool,
        didAutoOpenDocumentScanSetup: Bool,
        autoOpenDeliveryGuide: Bool,
        didAutoOpenDeliveryGuide: Bool,
        focus: ProjectDetailFocus?,
        didOpenFocusedItem: Bool,
        financialRecords: [ProjectFinancialRecord],
        documents: [ProjectDocument],
        contacts: [ProjectContact]
    ) -> ProjectDetailOnAppearRouting {
        let shouldOpenFinancialAdd = autoOpenFinancialAdd && !didAutoOpenFinancialAdd
        let shouldOpenDocumentScanSetup = autoOpenDocumentScanSetup && !didAutoOpenDocumentScanSetup
        let shouldOpenDeliveryGuide = autoOpenDeliveryGuide && !didAutoOpenDeliveryGuide
        let shouldConsumeFocusRequest = focus != nil && !didOpenFocusedItem

        let focusedItem: ProjectDetailFocusedItem?
        if let focus, !didOpenFocusedItem {
            focusedItem = ProjectDetailFocusRouter.resolve(
                focus: focus,
                financialRecords: financialRecords,
                documents: documents,
                contacts: contacts
            )
        } else {
            focusedItem = nil
        }

        return ProjectDetailOnAppearRouting(
            shouldOpenFinancialAdd: shouldOpenFinancialAdd,
            shouldOpenDocumentScanSetup: shouldOpenDocumentScanSetup,
            shouldOpenDeliveryGuide: shouldOpenDeliveryGuide,
            shouldConsumeFocusRequest: shouldConsumeFocusRequest,
            focusedItem: focusedItem
        )
    }
}
