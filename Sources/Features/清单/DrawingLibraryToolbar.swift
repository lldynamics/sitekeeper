import SwiftUI

struct DrawingLibraryToolbar: ToolbarContent {
    let onImport: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: onImport) {
                Image(systemName: "plus").visibleIconStyle()
            }
            .accessibilityLabel(String(localized: "导入图纸"))
        }
    }
}

struct DrawingAvailabilityFilterChip: View {
    let filter: DrawingAvailabilityFilter
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: filter.icon)
                Text(filter.title)
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.appDoc : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(
                format: String(localized: "%@，%lld 张图纸"),
                filter.title,
                Int64(count)
            )
        )
    }
}
