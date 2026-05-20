import Foundation

struct MaterialSheetItem: Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var specification: String
    var unit: String
    var quantity: String
    var unitPrice: String
    var laborCost: String = ""
    var supplier: String = ""
    var usageLocation: String = ""
    var note: String = ""
    var attachmentData: Data?
    var attachmentFileName: String?

    var hasAttachment: Bool { attachmentData != nil }
    var isExpanded: Bool = false
}

extension MaterialSheetItem {
    init(draftItem: MaterialSheetDraftItem) {
        self.init(
            id: draftItem.id,
            name: draftItem.name,
            specification: draftItem.specification,
            unit: draftItem.unit,
            quantity: draftItem.quantity,
            unitPrice: draftItem.unitPrice,
            laborCost: draftItem.laborCost,
            supplier: draftItem.supplier,
            usageLocation: draftItem.usageLocation,
            note: draftItem.note,
            attachmentData: draftItem.attachmentData,
            attachmentFileName: draftItem.attachmentFileName,
            isExpanded: false
        )
    }

    var draftItem: MaterialSheetDraftItem {
        MaterialSheetDraftItem(
            id: id,
            name: name,
            specification: specification,
            unit: unit,
            quantity: quantity,
            unitPrice: unitPrice,
            laborCost: laborCost,
            supplier: supplier,
            usageLocation: usageLocation,
            note: note,
            attachmentData: attachmentData,
            attachmentFileName: attachmentFileName
        )
    }
}

struct MaterialSheetExportOptions {
    var showPrice = true
    var showLabor = false
    var showSupplier = false
    var showLocation = true
    var showNote = false
}
