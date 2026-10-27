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
            .secondary
        default:
            tint
        }
    }

    var background: Color {
        switch self {
        case .neutral:
            Color(uiColor: .tertiarySystemGroupedBackground)
        default:
            tint.opacity(0.12)
        }
    }

    var strokeColor: Color {
        switch self {
        case .neutral:
            Color(uiColor: .separator).opacity(0.25)
        default:
            tint.opacity(0.24)
        }
    }
}

struct StatusChip: View {
    let text: String
    var tone: StatusChipTone = .neutral
    var compact: Bool = false
    var isProminent: Bool = false

    var body: some View {
        Text(text)
            .font((compact ? Font.caption2 : .caption).weight(.semibold))
            .foregroundStyle(isProminent ? .white : tone.foreground)
            .padding(.horizontal, compact ? 8 : AppSpacing.tight)
            .padding(.vertical, compact ? 4 : 5)
            .background(
                RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
                    .fill(isProminent ? tone.tint : tone.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
                    .stroke(isProminent ? tone.tint : tone.strokeColor, lineWidth: 0.5)
            )
    }
}
