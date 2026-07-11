import SwiftUI

enum StatusChipTone: Equatable {
    case neutral
    case primary
    case success
    case warning
    case risk
    case doc
    case finance

    var tint: Color {
        switch self {
        case .neutral:
            .secondary
        case .primary:
            .appPrimaryAction
        case .success:
            .appSuccess
        case .warning:
            .appWarning
        case .risk:
            .appRisk
        case .doc:
            .appDoc
        case .finance:
            .appFinance
        }
    }

    var foreground: Color {
        switch self {
        case .neutral:
            .primary
        default:
            .white
        }
    }

    var background: Color {
        switch self {
        case .neutral:
            Color(uiColor: .secondarySystemGroupedBackground)
        default:
            tint
        }
    }
}

struct StatusChip: View {
    let text: String
    var tone: StatusChipTone = .neutral
    var compact: Bool = false

    var body: some View {
        Text(text)
            .font((compact ? Font.caption2 : .caption).weight(.semibold))
            .foregroundStyle(tone.foreground)
            .padding(.horizontal, compact ? 8 : AppSpacing.tight)
            .padding(.vertical, compact ? 4 : 5)
            .background(
                RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
                    .fill(tone.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
                    .stroke(tone.tint.opacity(tone == .neutral ? 0.18 : 1), lineWidth: 0.5)
            )
    }
}
