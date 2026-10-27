import SwiftUI

struct MaterialLibraryFilterBar: View {
    let selectedCategory: String?
    let availableCategories: [String]
    let priceFilter: MaterialPriceFilter
    let onSelectCategory: (String?) -> Void
    let onSelectPriceFilter: (MaterialPriceFilter) -> Void
    let onOpenCategoryManager: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                CategoryChip(
                    title: AppLocalization.string("materials.library.category.all"),
                    isSelected: selectedCategory == nil
                ) {
                    onSelectCategory(nil)
                }
                ForEach(availableCategories, id: \.self) { category in
                    CategoryChip(
                        title: category,
                        isSelected: selectedCategory == category
                    ) {
                        onSelectCategory(category)
                    }
                }
                ForEach(MaterialPriceFilter.allCases, id: \.self) { item in
                    CategoryChip(title: item.title, isSelected: priceFilter == item) {
                        onSelectPriceFilter(item)
                    }
                }
                Button(action: onOpenCategoryManager) {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.caption)
                        Text(AppLocalization.string("materials.library.categoryManagement.title"))
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.appPrimarySurfaceSubtle)
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalization.string("materials.library.categoryManagement.title"))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct CategoryChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.appPrimaryAction : Color(uiColor: .tertiarySystemGroupedBackground))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
