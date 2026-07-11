import SwiftUI

enum AppIconButtonTone {
    case normal
    case primary
    case destructive

    var iconColor: Color {
        switch self {
        case .normal:
            return .primary
        case .primary:
            return .appPrimaryAction
        case .destructive:
            return .appRisk
        }
    }

    var backgroundColor: Color {
        switch self {
        case .normal:
            return Color(uiColor: .secondarySystemGroupedBackground)
        case .primary:
            return .appPrimarySurface
        case .destructive:
            return .appRiskSurface
        }
    }
}

struct AppIconButtonStyle: ButtonStyle {
    let tone: AppIconButtonTone

    init(tone: AppIconButtonTone = .normal) {
        self.tone = tone
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tone.iconColor)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(tone.backgroundColor)
                    .opacity(configuration.isPressed ? 0.45 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AppIconButtonStyle {
    static func appIcon(tone: AppIconButtonTone = .normal) -> AppIconButtonStyle {
        AppIconButtonStyle(tone: tone)
    }
}

struct AppProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    let tint: Color

    init(tint: Color = .appPrimaryAction) {
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 38)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isEnabled ? tint : Color(uiColor: .tertiarySystemFill))
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == AppProminentButtonStyle {
    static func appProminent(tint: Color = .appPrimaryAction) -> AppProminentButtonStyle {
        AppProminentButtonStyle(tint: tint)
    }
}
