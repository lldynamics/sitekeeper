import SwiftUI

struct DataManagementShortcutCardModel: Identifiable {
    let id: String
    let target: DataManagementView.DataSafetySecondaryTarget
    let title: String
    let subtitle: String
    let icon: String
    let tone: StatusChipTone
    let isSelected: Bool
}

struct DataManagementSecondaryFlowShortcutGrid: View {
    let usesWideLayout: Bool
    let usesCompactRow: Bool
    let cards: [DataManagementShortcutCardModel]
    let onSelect: (DataManagementView.DataSafetySecondaryTarget) -> Void

    init(
        usesWideLayout: Bool,
        cards: [DataManagementShortcutCardModel],
        onSelect: @escaping (DataManagementView.DataSafetySecondaryTarget) -> Void,
        usesCompactRow: Bool? = nil
    ) {
        self.usesWideLayout = usesWideLayout
        self.usesCompactRow = usesCompactRow ?? !usesWideLayout
        self.cards = cards
        self.onSelect = onSelect
    }

    var body: some View {
        if usesCompactRow {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.tight) {
                    ForEach(cards) { card in
                        compactShortcutButton(card)
                    }
                }
                .padding(.horizontal)
            }
            .scrollClipDisabled()
        } else {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: usesWideLayout ? 154 : 134), spacing: AppSpacing.tight)],
                alignment: .leading,
                spacing: AppSpacing.tight
            ) {
                ForEach(cards) { card in
                    shortcutCardButton(card)
                }
            }
            .padding(.horizontal)
        }
    }

    private func shortcutCardButton(_ card: DataManagementShortcutCardModel) -> some View {
        Button {
            onSelect(card.target)
        } label: {
            AppPanel(
                tone: card.isSelected ? selectedCardTone(for: card.tone) : .grouped,
                cornerRadius: 10,
                padding: 10,
                stroke: card.isSelected ? card.tone.tint.opacity(0.3) : Color.appStrokeSecondary.opacity(0.35)
            ) {
                HStack(alignment: .top, spacing: AppSpacing.tight) {
                    Image(systemName: card.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(card.tone.tint)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(card.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(card.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(card.title)
        .accessibilityHint(card.subtitle)
        .accessibilityIdentifier("data-management-shortcut-\(card.id)")
    }

    private func compactShortcutButton(_ card: DataManagementShortcutCardModel) -> some View {
        Button {
            onSelect(card.target)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: card.icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(card.tone.tint)
                    .frame(width: 16, height: 16)
                Text(card.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background {
                Capsule()
                    .fill(card.isSelected ? card.tone.tint.opacity(0.14) : Color(uiColor: .secondarySystemGroupedBackground))
            }
            .overlay {
                Capsule()
                    .stroke(card.isSelected ? card.tone.tint.opacity(0.35) : Color.appStrokeSecondary.opacity(0.35), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(card.title)
        .accessibilityHint(card.subtitle)
        .accessibilityIdentifier("data-management-shortcut-\(card.id)")
    }

    private func selectedCardTone(for tone: StatusChipTone) -> AppSurfaceTone {
        switch tone {
        case .success:
            return .tinted(Color.appSuccessSurfaceSubtle)
        case .warning:
            return .tinted(Color.appWarning.opacity(0.12))
        case .risk:
            return .tinted(Color.appRiskSurface)
        case .doc:
            return .tinted(Color.appDocSurfaceSubtle)
        case .primary:
            return .tinted(Color.appPrimarySurfaceSubtle)
        default:
            return .grouped
        }
    }
}
