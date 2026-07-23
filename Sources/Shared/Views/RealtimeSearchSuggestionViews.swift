import SwiftUI

struct InlineSearchPanel: View {
    @Binding var text: String
    let prompt: String
    var suggestions: [RealtimeSearchSuggestion] = []
    var emptyStateText: String = String(localized: "未找到匹配内容")
    var materialTone: AppSurfaceTone = .materialThin
    let onSelectSuggestion: (RealtimeSearchSuggestion) -> Void

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSearchKeyword: Bool {
        !trimmedText.isEmpty
    }

    var body: some View {
        AppPanel(
            tone: materialTone,
            cornerRadius: AppSpacing.normal - 2,
            padding: 0
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: AppSpacing.tight + 2) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(prompt, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                    if hasSearchKeyword {
                        Button {
                            text = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "清空搜索"))
                    }
                }
                .padding(AppSpacing.normal)

                if hasSearchKeyword {
                    Divider()
                        .padding(.horizontal, AppSpacing.normal)
                    if suggestions.isEmpty {
                        InlineSearchEmptyState(
                            keyword: trimmedText,
                            message: emptyStateText
                        )
                    } else {
                        RealtimeSearchSuggestionInlineList(
                            suggestions: suggestions,
                            onSelect: onSelectSuggestion,
                            useEmbeddedBackground: false
                        )
                    }
                }
            }
        }
    }
}

struct InlineSearchEmptyState: View {
    let keyword: String
    let message: String

    var body: some View {
        ContentUnavailableView.search(text: keyword)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppSpacing.normal)
            .padding(.vertical, AppSpacing.tight)
            .overlay(alignment: .bottom) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, AppSpacing.tight)
            }
    }
}

struct RealtimeSearchSuggestionRow: View {
    let suggestion: RealtimeSearchSuggestion
    var showsChevron = true
    var rowPadding = EdgeInsets(top: AppSpacing.tight, leading: AppSpacing.normal, bottom: AppSpacing.tight, trailing: AppSpacing.normal)

    var body: some View {
        HStack(spacing: AppSpacing.tight) {
            Image(systemName: suggestion.category.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(suggestion.category.tintColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
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
    var useEmbeddedBackground = true

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                Button {
                    onSelect(suggestion)
                } label: {
                    RealtimeSearchSuggestionRow(
                        suggestion: suggestion,
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
        .background(backgroundView)
    }

    @ViewBuilder
    private var backgroundView: some View {
        if useEmbeddedBackground {
            RoundedRectangle(cornerRadius: AppSpacing.normal - 2, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        }
    }
}
