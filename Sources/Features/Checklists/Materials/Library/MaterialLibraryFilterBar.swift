import SwiftUI

struct MaterialLibraryFilterBar: View {
    let selectedCategory: String?
    let availableCategories: [String]
    let priceFilter: MaterialPriceFilter
    let onSelectCategory: (String?) -> Void
    let onSelectPriceFilter: (MaterialPriceFilter) -> Void
    let onOpenCategoryManager: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    priceFilterMenu
                    categoryManagerButton
                }
                .fixedSize(horizontal: true, vertical: false)

                VStack(alignment: .leading, spacing: 4) {
                    priceFilterMenu
                    categoryManagerButton
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 4)

            categoryChips
        }
    }

    private var categoryChips: some View {
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
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppLocalization.string("分类"))
    }

    private var priceFilterMenu: some View {
        Menu {
            ForEach(MaterialPriceFilter.allCases, id: \.self) { item in
                Button {
                    onSelectPriceFilter(item)
                } label: {
                    if priceFilter == item {
                        Label(item.title, systemImage: "checkmark")
                    } else {
                        Text(item.title)
                    }
                }
                .accessibilityAddTraits(priceFilter == item ? .isSelected : [])
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                Text(AppLocalization.string("materials.library.priceFilter.title"))
                Text(priceFilter.title)
                    .foregroundStyle(Color.appPrimaryAction)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
            .font(.caption.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(priceFilter == .all ? Color.appPrimarySurfaceSubtle : Color.appPrimaryAction.opacity(0.14))
            .foregroundStyle(.primary)
            .clipShape(Capsule())
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(AppLocalization.string("materials.library.priceFilter.title"))
        .accessibilityValue(priceFilter.title)
        .accessibilityIdentifier("material-library-price-filter")
    }

    private var categoryManagerButton: some View {
        Button(action: onOpenCategoryManager) {
            Label(AppLocalization.string("materials.library.categoryManagement.title"), systemImage: "folder.badge.gearshape")
                .font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.appPrimarySurfaceSubtle)
                .foregroundStyle(.primary)
                .clipShape(Capsule())
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalization.string("materials.library.categoryManagement.title"))
        .accessibilityIdentifier("material-library-category-management")
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
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
