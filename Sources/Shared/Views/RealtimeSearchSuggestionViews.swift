import SwiftUI

struct InlineSearchPanel<TrailingContent: View>: View {
    @Binding var text: String
    let prompt: String
    var suggestions: [RealtimeSearchSuggestion] = []
    var emptyStateText: String = AppLocalization.string("未找到匹配内容")
    var materialTone: AppSurfaceTone = .grouped
    var shadow: AppSurfaceShadow = .card
    var trailingContent: TrailingContent
    let onSelectSuggestion: (RealtimeSearchSuggestion) -> Void

    init(
        text: Binding<String>,
        prompt: String,
        suggestions: [RealtimeSearchSuggestion] = [],
        emptyStateText: String = AppLocalization.string("未找到匹配内容"),
        materialTone: AppSurfaceTone = .grouped,
        shadow: AppSurfaceShadow = .card,
        @ViewBuilder trailingContent: () -> TrailingContent,
        onSelectSuggestion: @escaping (RealtimeSearchSuggestion) -> Void
    ) {
        self._text = text
        self.prompt = prompt
        self.suggestions = suggestions
        self.emptyStateText = emptyStateText
        self.materialTone = materialTone
        self.shadow = shadow
        self.trailingContent = trailingContent()
        self.onSelectSuggestion = onSelectSuggestion
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasSearchKeyword: Bool {
        !trimmedText.isEmpty
    }

    var body: some View {
        AppPanel(
            tone: materialTone,
            cornerRadius: 14,
            padding: 0,
            shadow: shadow,
            stroke: AppSurfaceDefaults.stroke
        ) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: AppSpacing.tight + 2) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(prompt, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                    trailingContent
                    if hasSearchKeyword {
                        Button {
                            text = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppLocalization.string("清空搜索"))
                    }
                }
                .padding(.horizontal, AppSpacing.normal)
                .padding(.vertical, AppSpacing.tight + 3)

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

extension InlineSearchPanel where TrailingContent == EmptyView {
    init(
        text: Binding<String>,
        prompt: String,
        suggestions: [RealtimeSearchSuggestion] = [],
        emptyStateText: String = AppLocalization.string("未找到匹配内容"),
        materialTone: AppSurfaceTone = .grouped,
        onSelectSuggestion: @escaping (RealtimeSearchSuggestion) -> Void
    ) {
        self.init(
            text: text,
            prompt: prompt,
            suggestions: suggestions,
            emptyStateText: emptyStateText,
            materialTone: materialTone,
            trailingContent: { EmptyView() },
            onSelectSuggestion: onSelectSuggestion
        )
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
                .accessibilityIdentifier("search-suggestion-\(suggestion.id)")

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
