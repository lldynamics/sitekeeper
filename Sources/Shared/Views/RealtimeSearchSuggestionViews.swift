import SwiftUI

struct RealtimeSearchSuggestionRow: View {
    let suggestion: RealtimeSearchSuggestion
    var showsCategoryBadge = true
    var showsChevron = true
    var rowPadding = EdgeInsets(top: AppSpacing.tight, leading: AppSpacing.normal, bottom: AppSpacing.tight, trailing: AppSpacing.normal)

    var body: some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: suggestion.category.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(suggestion.category.tintColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(suggestion.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if showsCategoryBadge {
                        Text(suggestion.category.displayName)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(suggestion.category.tintColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(suggestion.category.tintColor.opacity(0.12), in: Capsule())
                    }
                }
                if !suggestion.subtitle.isEmpty {
                    Text(suggestion.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(rowPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct RealtimeSearchSuggestionInlineList: View {
    let suggestions: [RealtimeSearchSuggestion]
    let onSelect: (RealtimeSearchSuggestion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    RealtimeSearchSuggestionRow(
                        suggestion: suggestion,
                        showsCategoryBadge: true,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                if index < suggestions.count - 1 {
                    Divider()
                        .padding(.leading, AppSpacing.normal + 20 + AppSpacing.tight)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.normal - 2, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

struct RealtimeSearchSuggestionMenuRow: View {
    let suggestion: RealtimeSearchSuggestion

    var body: some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: suggestion.category.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(suggestion.category.tintColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.title)
                    .font(.subheadline.weight(.semibold))
                if !suggestion.subtitle.isEmpty {
                    Text(suggestion.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
