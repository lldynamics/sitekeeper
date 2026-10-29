import SwiftUI

extension ProjectDetailContainer {
    func handleOnAppear(snapshot: ProjectDetailSnapshot) {
        let routing = ProjectDetailOnAppearRouter.resolve(
            autoOpenFinancialAdd: autoOpenFinancialAdd,
            didAutoOpenFinancialAdd: didAutoOpenFinancialAdd,
            autoOpenDocumentScanSetup: autoOpenDocumentScanSetup,
            didAutoOpenDocumentScanSetup: didAutoOpenDocumentScanSetup,
            autoOpenDeliveryGuide: autoOpenDeliveryGuide,
            didAutoOpenDeliveryGuide: didAutoOpenDeliveryGuide,
            focus: focus,
            didOpenFocusedItem: didOpenFocusedItem,
            financialRecords: snapshot.relatedFinancialRecords,
            documents: snapshot.relatedDocuments,
            contacts: snapshot.relatedContacts,
            drawings: snapshot.relatedDrawings
        )
        if routing.shouldOpenFinancialAdd {
            didAutoOpenFinancialAdd = true
            openMode(.finance, prefersInlineSections: usesSingleCanvasLayoutOnPad, isUserInitiated: false)
            routeState.presentation = .addFinancial
        }
        if routing.shouldOpenDocumentScanSetup {
            didAutoOpenDocumentScanSetup = true
            openMode(.assets, prefersInlineSections: usesSingleCanvasLayoutOnPad, isUserInitiated: false)
            routeState.presentation = .documentScanSetup
        }
        if routing.shouldOpenDeliveryGuide {
            didAutoOpenDeliveryGuide = true
            openMode(.overview, prefersInlineSections: usesSingleCanvasLayoutOnPad, isUserInitiated: false)
            routeState.presentation = .deliveryGuide
        }
        if routing.shouldConsumeFocusRequest {
            didOpenFocusedItem = true
            guard let focusedItem = routing.focusedItem else { return }
            openMode(focusedItem.mode, prefersInlineSections: usesSingleCanvasLayoutOnPad, isUserInitiated: false)
            Task { @MainActor in
                ProjectDetailFocusedItemApplier.apply(
                    focusedItem,
                    setFinancialRecord: { financeState.editingFinancialRecord = $0 },
                    setDocument: { assetState.editingDocument = $0 },
                    setContact: { assetState.editingContact = $0 },
                    setDrawing: { assetState.editingDrawing = $0 }
                )
            }
        }
    }
}
