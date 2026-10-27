import SwiftUI

extension MaterialSheetView {
    func materialItemRow(_ item: Binding<MaterialSheetItem>) -> some View {
        let itemID = item.wrappedValue.id
        let isExpanded = itemExpanded.contains(itemID)
        return MaterialSheetEditableItemRow(
            item: item,
            isExpanded: isExpanded,
            accessibilityLabel: MaterialSheetLogicHelpers.materialItemAccessibilityLabel(
                item.wrappedValue,
                isExpanded: isExpanded
            ),
            photoSelection: photoSelectionBinding(for: itemID),
            suggestedPrice: MaterialSheetLogicHelpers.suggestedUnitPrice(
                for: item.wrappedValue,
                entries: store.materialPriceEntries
            ),
            onToggleExpand: {
                toggleExpand(itemID)
            },
            onDelete: {
                requestDeleteSheetItems(ids: [itemID])
            }
        )
    }

    func toggleExpand(_ id: UUID) {
        if itemExpanded.contains(id) {
            itemExpanded.remove(id)
        } else {
            itemExpanded.insert(id)
        }
    }

    func librarySearchRow(entry: MaterialPriceEntry) -> some View {
        Button {
            addToSheet(name: entry.name, spec: entry.specification, unit: entry.unit, price: entry.referencePrice.wireText)
            searchText = ""
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    if !entry.specification.isEmpty {
                        Text(entry.specification).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                HStack(spacing: 4) {
                    if !entry.referencePrice.isEmpty {
                        Text("¥\(entry.referencePrice)").font(.caption).foregroundStyle(Color.appPrimaryAction)
                    }
                    Text(entry.unit).font(.caption).foregroundStyle(.secondary)
                    Text(AppLocalization.string("材料库"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.appPrimaryAction)
                    .font(.title3)
            }
        }
    }

    func presetSearchRow(material: CommonMaterial) -> some View {
        Button {
            addToSheet(name: material.name, spec: material.specification, unit: material.unit)
            searchText = ""
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(material.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                    Text(material.specification).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(material.unit).font(.caption).foregroundStyle(.secondary)
                    Text(AppLocalization.string("预置材料"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(Color.appPrimaryAction)
                    .font(.title3)
            }
        }
    }
}
