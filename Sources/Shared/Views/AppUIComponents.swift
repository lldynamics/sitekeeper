import SwiftUI
import UIKit

enum AppSpacing {
    static let tight: CGFloat = 8
    static let normal: CGFloat = 12
    static let relaxed: CGFloat = 16
}

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

@MainActor
enum AppHaptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private static let notification = UINotificationFeedbackGenerator()

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light, intensity: CGFloat = 1) {
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .light:
            generator = lightImpact
        case .medium:
            generator = mediumImpact
        case .heavy:
            generator = heavyImpact
        default:
            generator = mediumImpact
        }
        generator.prepare()
        generator.impactOccurred(intensity: max(0, min(1, intensity)))
    }

    static func success() {
        notification.prepare()
        notification.notificationOccurred(.success)
    }

    static func warning() {
        notification.prepare()
        notification.notificationOccurred(.warning)
    }

    static func error() {
        notification.prepare()
        notification.notificationOccurred(.error)
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

enum AppSurfaceTone {
    case grouped
    case secondary
    case tertiary
    case materialThin
    case materialThick
    case tinted(Color)

    var fillStyle: AnyShapeStyle {
        switch self {
        case .grouped:
            AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground))
        case .secondary:
            AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
        case .tertiary:
            AnyShapeStyle(Color(uiColor: .tertiarySystemGroupedBackground))
        case .materialThin:
            AnyShapeStyle(.ultraThinMaterial)
        case .materialThick:
            AnyShapeStyle(.ultraThickMaterial)
        case .tinted(let color):
            AnyShapeStyle(color)
        }
    }
}

enum AppSurfaceShadow {
    case none
    case card
    case overlay

    var color: Color {
        switch self {
        case .none:
            .clear
        case .card:
            .black.opacity(0.06)
        case .overlay:
            .black.opacity(0.12)
        }
    }

    var radius: CGFloat {
        switch self {
        case .none:
            0
        case .card:
            6
        case .overlay:
            12
        }
    }

    var y: CGFloat {
        switch self {
        case .none:
            0
        case .card:
            2
        case .overlay:
            4
        }
    }
}

struct AppSurface<Content: View>: View {
    let tone: AppSurfaceTone
    var cornerRadius: CGFloat = 12
    var shadow: AppSurfaceShadow = .none
    var stroke: Color? = nil
    var strokeWidth: CGFloat = 0.5
    @ViewBuilder let content: Content

    init(
        tone: AppSurfaceTone = .grouped,
        cornerRadius: CGFloat = 12,
        shadow: AppSurfaceShadow = .none,
        stroke: Color? = nil,
        strokeWidth: CGFloat = 0.5,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.stroke = stroke
        self.strokeWidth = strokeWidth
        self.content = content()
    }

    var body: some View {
        content
            .background(backgroundShape)
            .overlay {
                if let stroke, strokeWidth > 0 {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(stroke, lineWidth: strokeWidth)
                }
            }
            .shadow(color: shadow.color, radius: shadow.radius, y: shadow.y)
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(tone.fillStyle)
    }
}

struct AppPanel<Content: View>: View {
    let tone: AppSurfaceTone
    var cornerRadius: CGFloat = 12
    var padding: CGFloat = AppSpacing.normal
    var shadow: AppSurfaceShadow = .none
    var stroke: Color? = nil
    @ViewBuilder let content: Content

    init(
        tone: AppSurfaceTone = .grouped,
        cornerRadius: CGFloat = 12,
        padding: CGFloat = AppSpacing.normal,
        shadow: AppSurfaceShadow = .none,
        stroke: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.shadow = shadow
        self.stroke = stroke
        self.content = content()
    }

    var body: some View {
        AppSurface(
            tone: tone,
            cornerRadius: cornerRadius,
            shadow: shadow,
            stroke: stroke
        ) {
            content
                .padding(padding)
        }
    }
}

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

extension Color {
    init(light: UIColor, dark: UIColor) {
        self = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static func appDynamicTint(_ base: UIColor, lightOpacity: CGFloat, darkOpacity: CGFloat) -> Color {
        Color(light: base.withAlphaComponent(lightOpacity), dark: base.withAlphaComponent(darkOpacity))
    }

    // MARK: 动态主题色

    static var appPrimaryAction: Color { AppTheme.current.palette.primary }
    static var appSuccess: Color { AppTheme.current.palette.success }
    static var appWarning: Color { AppTheme.current.palette.warning }
    static var appRisk: Color { AppTheme.current.palette.risk }
    static var appDoc: Color { AppTheme.current.palette.doc }
    static var appPrimarySurface: Color { Color.appDynamicTint(AppTheme.current.palette.primaryUIColor, lightOpacity: 0.14, darkOpacity: 0.28) }
    static var appPrimarySurfaceSubtle: Color { Color.appDynamicTint(AppTheme.current.palette.primaryUIColor, lightOpacity: 0.08, darkOpacity: 0.20) }
    static var appRiskSurface: Color { Color.appDynamicTint(AppTheme.current.palette.riskUIColor, lightOpacity: 0.14, darkOpacity: 0.28) }
    static var appDocSurfaceSubtle: Color { Color.appDynamicTint(AppTheme.current.palette.docUIColor, lightOpacity: 0.10, darkOpacity: 0.22) }
    static var appSuccessSurfaceSubtle: Color { Color.appDynamicTint(AppTheme.current.palette.successUIColor, lightOpacity: 0.10, darkOpacity: 0.22) }
    static var appWillowSurfaceSubtle: Color { appSuccessSurfaceSubtle }

    // MARK: - 新维度色（按功能域独立）

    static var appFinance: Color { AppTheme.current.palette.finance }
    static var appInventory: Color { AppTheme.current.palette.inventory }
    static var appPeople: Color { AppTheme.current.palette.people }
    static var appMuted: Color { AppTheme.current.palette.people }
    static var appJournal: Color { AppTheme.current.palette.journal }
    static var appPhoto: Color { AppTheme.current.palette.photo }
    static var appCalculations: Color { AppTheme.current.palette.calculations }
    static var appQuotation: Color { AppTheme.current.palette.quotation }
    static var appFinanceSurface: Color { Color.appDynamicTint(AppTheme.current.palette.financeUIColor, lightOpacity: 0.12, darkOpacity: 0.25) }
    static var appInventorySurface: Color { Color.appDynamicTint(AppTheme.current.palette.inventoryUIColor, lightOpacity: 0.12, darkOpacity: 0.25) }
    static var appPeopleSurface: Color { Color.appDynamicTint(AppTheme.current.palette.peopleUIColor, lightOpacity: 0.12, darkOpacity: 0.25) }
    static var appMutedSurface: Color { Color.appDynamicTint(AppTheme.current.palette.peopleUIColor, lightOpacity: 0.12, darkOpacity: 0.25) }
    static var appJournalSurface: Color { Color.appDynamicTint(AppTheme.current.palette.journalUIColor, lightOpacity: 0.12, darkOpacity: 0.25) }
    static var appPhotoSurface: Color { Color.appDynamicTint(AppTheme.current.palette.photoUIColor, lightOpacity: 0.12, darkOpacity: 0.25) }
    static var appCalculationsSurface: Color { Color.appDynamicTint(AppTheme.current.palette.calculationsUIColor, lightOpacity: 0.12, darkOpacity: 0.25) }
    static var appQuotationSurface: Color { Color.appDynamicTint(AppTheme.current.palette.quotationUIColor, lightOpacity: 0.12, darkOpacity: 0.25) }

    // MARK: - 桥接别名（兼容旧名称，逐步迁移）

    static var appPeach: Color { appPrimaryAction }
    static var appPeachSurface: Color { appPrimarySurface }
    static var appPeachSurfaceSubtle: Color { appPrimarySurfaceSubtle }

    static let appStrokeWarning = Color("StrokeWarning")
    static let appStrokeInfo = Color("StrokeInfo")
    static let appStrokeSuccess = Color("StrokeSuccess")
    static let appStrokeError = Color("StrokeError")
    static let appStrokeSecondary = Color("StrokeSecondary")
    static let appStrokeSeparator = Color("StrokeSeparator")
    static let appStrokeLightOverlay = Color("StrokeLightOverlay")
    static let appStrokeNeutral = Color("StrokeNeutral")
}

// MARK: - ShapeStyle 桥接（允许 .appRisk / .appWarning 等不加 Color. 前缀）

extension ShapeStyle where Self == Color {
    static var appPrimaryAction: Color { Color.appPrimaryAction }
    static var appSuccess: Color { Color.appSuccess }
    static var appWarning: Color { Color.appWarning }
    static var appRisk: Color { Color.appRisk }
    static var appDoc: Color { Color.appDoc }
    static var appFinance: Color { Color.appFinance }
    static var appInventory: Color { Color.appInventory }
    static var appPeople: Color { Color.appPeople }
    static var appJournal: Color { Color.appJournal }
    static var appPhoto: Color { Color.appPhoto }
    static var appCalculations: Color { Color.appCalculations }
    static var appQuotation: Color { Color.appQuotation }
}

struct ProjectContextStrip: View {
    let title: String
    let projects: [Project]
    @Binding var selectedProjectId: UUID?
    var emptyText: String = "全部项目"

    private var currentProjectName: String {
        guard let selectedProjectId,
              let project = projects.first(where: { $0.id == selectedProjectId }) else {
            return emptyText
        }
        return project.name
    }

    var body: some View {
        Menu {
            Button(emptyText) {
                selectedProjectId = nil
            }
            Divider()
            ForEach(projects) { project in
                Button {
                    selectedProjectId = project.id
                } label: {
                    if selectedProjectId == project.id {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Label(title, systemImage: "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(currentProjectName)
                    .font(.subheadline.weight(.semibold))
                    .appListPrimaryTextLayout()
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background {
                AppSurface(tone: .grouped, cornerRadius: 10) {
                    Color.clear
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct BusinessRecordRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let meta: String
    let note: String
    let trailing: String
    var trailingColor: Color = .appPrimaryAction

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 18, height: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .appListPrimaryTextLayout()
                if !meta.isEmpty {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .appListSecondaryTextLayout()
                }
                if !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .appListSecondaryTextLayout()
                }
            }

            Spacer(minLength: 8)

            if !trailing.isEmpty {
                Text(trailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(trailingColor)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(accessibilityValueText)
    }

    private var accessibilityLabelText: String {
        var parts: [String] = [title]
        if !meta.isEmpty { parts.append(meta) }
        if !note.isEmpty { parts.append(note) }
        return parts.joined(separator: "，")
    }

    private var accessibilityValueText: String {
        trailing.isEmpty ? "无补充信息" : trailing
    }
}
