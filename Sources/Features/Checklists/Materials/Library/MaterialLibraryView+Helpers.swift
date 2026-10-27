import SwiftUI

extension MaterialLibraryView {
    func materialKey(_ item: CommonMaterial) -> String {
        MaterialLibraryLogicHelpers.materialKey(item)
    }

    func legacyMaterialKey(_ item: CommonMaterial) -> String {
        MaterialLibraryLogicHelpers.legacyMaterialKey(item)
    }

    func materialKey(name: String, specification: String, unit: String) -> String {
        MaterialLibraryLogicHelpers.materialKey(name: name, specification: specification, unit: unit)
    }

    func legacyMaterialKey(name: String, specification: String, unit: String) -> String {
        MaterialLibraryLogicHelpers.legacyMaterialKey(name: name, specification: specification, unit: unit)
    }

    func isPresetHidden(_ item: CommonMaterial) -> Bool {
        MaterialLibraryLogicHelpers.isPresetHidden(item, hiddenPresetKeys: hiddenPresetKeys)
    }

    func normalizedCategory(_ value: String) -> String {
        MaterialLibraryLogicHelpers.normalizedCategory(value)
    }

    func matchesPriceFilter(_ entry: MaterialPriceEntry?) -> Bool {
        MaterialLibraryLogicHelpers.matchesPriceFilter(entry, priceFilter: priceFilter)
    }

    func matchesSearch<Item: Searchable>(_ item: Item, extraFields: [String]) -> Bool {
        MaterialLibraryLogicHelpers.matchesSearch(
            item: item,
            normalizedKeyword: normalizedSearchKeyword,
            extraFields: extraFields
        )
    }
}
