import SwiftUI
import UIKit

enum AppSpacing {
    static let tight: CGFloat = 8
    static let normal: CGFloat = 12
    static let relaxed: CGFloat = 16
}

/// The expanded phone workspace follows its container, never a device name or screen size.
/// iPad keeps its independently selected layouts.
enum ExpandedPhoneWorkspaceLayout {
    static func isAvailable(width: CGFloat, minimumWidth: CGFloat = 820) -> Bool {
        UIDevice.current.userInterfaceIdiom == .phone && width >= max(820, minimumWidth)
    }

    /// One track width for every expanded-phone workspace, based on the root container.
    static func sidebarWidth(containerWidth: CGFloat, minimumWorkspaceWidth: CGFloat = 820) -> CGFloat {
        guard containerWidth.isFinite, containerWidth > 0 else { return 0 }
        let minimumWidth = minimumWorkspaceWidth.isFinite ? max(820, minimumWorkspaceWidth) : 820
        let scale = minimumWidth / 820
        return min(containerWidth, min(460 * scale, max(320 * scale, containerWidth * 0.42)))
    }
}

private struct ExpandedPhoneWorkspaceWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var expandedPhoneWorkspaceWidth: CGFloat {
        get { self[ExpandedPhoneWorkspaceWidthKey.self] }
        set { self[ExpandedPhoneWorkspaceWidthKey.self] = newValue }
    }
}

/// Native indicators appear only when the system has scrollable content to indicate.
/// Interior panes use their own boundaries rather than the root navigation rail's inset.
struct ExpandedPhoneSidebarScrollModifier: ViewModifier {
    let isExpanded: Bool

    func body(content: Content) -> some View {
        content
            .scrollIndicators(isExpanded ? .visible : .automatic)
            .contentMargins(.horizontal, isExpanded ? 0 : nil, for: .scrollContent)
            .contentMargins(.horizontal, isExpanded ? 0 : nil, for: .scrollIndicators)
            .scrollContentBackground(isExpanded ? .hidden : .automatic)
            .background(isExpanded ? Color(.secondarySystemGroupedBackground) : Color.clear, ignoresSafeAreaEdges: [])
            .modifier(ExpandedPhoneScrollEdgeModifier(isExpanded: isExpanded))
    }
}

struct ExpandedPhoneScrollEdgeModifier: ViewModifier {
    let isExpanded: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Opaque pane backgrounds already separate these regions. Disable both axes
            // of the system edge fade, not only its horizontal part.
            content.scrollEdgeEffectHidden(isExpanded, for: .all)
        } else {
            content
        }
    }
}

/// A clean, standard column boundary matching system separator tone.
struct ExpandedPhoneColumnDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(uiColor: .separator).opacity(0.45))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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
    static var appMutedSurface: Color { Color.appDynamicTint(AppTheme.current.palette.peopleUIColor, lightOpacity: 0.12, darkOpacity: 0.25) }
    // MARK: - 桥接别名（兼容旧名称，逐步迁移）

    static var appPeachSurfaceSubtle: Color { appPrimarySurfaceSubtle }

    static let appStrokeWarning = Color("StrokeWarning")
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var minimumDetailsWidth: CGFloat = 180
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

            if dynamicTypeSize.isAccessibilitySize {
                stackedDetails
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        details.frame(minWidth: minimumDetailsWidth, maxWidth: .infinity, alignment: .leading)
                        trailingText
                            .fixedSize(horizontal: true, vertical: true)
                            .multilineTextAlignment(.trailing)
                    }
                    stackedDetails
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(accessibilityValueText)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !meta.isEmpty {
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !note.isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .appListSecondaryTextLayout()
            }
        }
    }

    private var stackedDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            details
            trailingText
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var trailingText: some View {
        if !trailing.isEmpty {
            Text(trailing)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(trailingColor)
        }
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
