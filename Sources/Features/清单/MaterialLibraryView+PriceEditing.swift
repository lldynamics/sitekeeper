import SwiftUI

extension MaterialLibraryView {
    func openPriceEditSheet(
        name: String,
        spec: String,
        unit: String,
        category: String,
        entry: MaterialPriceEntry?
    ) {
        if let existing = entry {
            priceEditorContext = MaterialPriceEditorContext(existing: existing)
        } else {
            priceEditorContext = MaterialPriceEditorContext(
                name: name,
                specification: spec,
                unit: unit,
                category: category
            )
        }
    }

    func upsertMaterialPriceEntry(_ entry: MaterialPriceEntry) {
        store.upsertMaterialPriceEntry(entry)
        store.scheduleSave()
    }

    func handleAddMaterialSave(_ material: UserMaterial, price: String) {
        let key = materialKey(name: material.name, specification: material.specification, unit: material.unit)
        if !userMaterials.contains(where: { materialKey(name: $0.name, specification: $0.specification, unit: $0.unit) == key }) {
            store.appendUserMaterial(material)
        }
        if !price.isEmpty {
            let entry = MaterialPriceEntry(
                name: material.name,
                specification: material.specification,
                unit: material.unit,
                referencePrice: price,
                category: material.category
            )
            upsertMaterialPriceEntry(entry)
        }
        let displayName = material.specification.isEmpty ? material.name : "\(material.name) \(material.specification)"
        store.appendMaterialItem(
            MaterialItem(
                name: displayName,
                quantity: "1",
                unit: material.unit,
                unitPrice: price,
                specification: material.specification
            )
        )
        store.scheduleSave()
    }

    func handleDeletePriceEntry(_ entry: MaterialPriceEntry) {
        MaterialLibraryLogicHelpers.deleteMaterialPriceEntryWithUndo(
            entry,
            store: store,
            undoableDeletion: undoableDeletion,
            notice: $operationNotice
        )
    }
}
