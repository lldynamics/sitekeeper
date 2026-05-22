import SwiftUI

extension MaterialLibraryView {
    func priceEntry(for item: CommonMaterial) -> MaterialPriceEntry? {
        priceEntryByKey[materialKey(item)]
    }

    func priceEntry(forUser item: UserMaterial) -> MaterialPriceEntry? {
        priceEntryByKey[materialKey(name: item.name, specification: item.specification, unit: item.unit)]
    }

    func presetMaterialRow(_ item: CommonMaterial) -> some View {
        let entry = priceEntry(for: item)
        let hasPrice = entry?.referencePrice.isEmpty == false
        let context = makeAppendContext(
            name: item.name,
            specification: item.specification,
            unit: item.unit,
            key: materialKey(item),
            priceEntry: entry
        )
        return materialRowContent(
            name: item.name,
            spec: item.specification,
            unit: item.unit,
            hasPrice: hasPrice,
            price: entry?.referencePrice,
            appendContext: context,
            onEdit: {
                openPriceEditSheet(
                    name: item.name,
                    spec: item.specification,
                    unit: item.unit,
                    category: item.category.rawValue,
                    entry: entry
                )
            },
            onAdd: {
                prepareAppendMaterial(context)
            }
        )
    }

    func userMaterialRow(_ item: UserMaterial) -> some View {
        let entry = priceEntry(forUser: item)
        let hasPrice = entry?.referencePrice.isEmpty == false
        let context = makeAppendContext(
            name: item.name,
            specification: item.specification,
            unit: item.unit,
            key: materialKey(name: item.name, specification: item.specification, unit: item.unit),
            priceEntry: entry
        )
        return materialRowContent(
            name: item.name,
            spec: item.specification,
            unit: item.unit,
            hasPrice: hasPrice,
            price: entry?.referencePrice,
            appendContext: context,
            onEdit: {
                openPriceEditSheet(
                    name: item.name,
                    spec: item.specification,
                    unit: item.unit,
                    category: item.category,
                    entry: entry
                )
            },
            onAdd: {
                prepareAppendMaterial(context)
            }
        )
    }

    func materialRowContent(
        name: String,
        spec: String,
        unit: String,
        hasPrice: Bool,
        price: String?,
        appendContext: PendingMaterialAppendContext,
        onEdit: @escaping () -> Void,
        onAdd: @escaping () -> Void
    ) -> some View {
        let isSelected = batchState.selectedMaterialContextsByKey[appendContext.key] != nil
        return MaterialLibraryMaterialRowContent(
            name: name,
            spec: spec,
            unit: unit,
            hasPrice: hasPrice,
            price: price,
            isBatchSelectionMode: batchState.isBatchSelectionMode,
            isSelected: isSelected,
            onEdit: onEdit,
            onAdd: onAdd,
            onToggleSelection: {
                toggleBatchMaterialSelection(appendContext)
            }
        )
    }

    func makeAppendContext(
        name: String,
        specification: String,
        unit: String,
        key: String,
        priceEntry: MaterialPriceEntry?
    ) -> PendingMaterialAppendContext {
        PendingMaterialAppendContext(
            name: name,
            specification: specification,
            unit: unit,
            key: key,
            defaultBrand: priceEntry?.brand ?? "",
            defaultSupplier: priceEntry?.supplier ?? "",
            defaultUnitPrice: priceEntry?.referencePrice ?? ""
        )
    }
}
