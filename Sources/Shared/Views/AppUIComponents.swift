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
            .font(.system(size: 17, weight: .semibold))
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

struct KeyboardNavigationToolbar<Field: Hashable>: ToolbarContent {
    let focusedField: FocusState<Field?>.Binding
    let fields: [Field]

    private var currentIndex: Int? {
        guard let value = focusedField.wrappedValue else { return nil }
        return fields.firstIndex(of: value)
    }

    private var canMovePrevious: Bool {
        guard let currentIndex else { return false }
        return currentIndex > 0
    }

    private var canMoveNext: Bool {
        guard let currentIndex else { return false }
        return currentIndex < fields.count - 1
    }

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Button(String(localized: "上一个")) {
                move(delta: -1)
            }
            .disabled(!canMovePrevious)

            Button(String(localized: "下一个")) {
                move(delta: 1)
            }
            .disabled(!canMoveNext)

            Spacer()

            Button(String(localized: "完成")) {
                focusedField.wrappedValue = nil
            }
        }
    }

    private func move(delta: Int) {
        guard let currentIndex else { return }
        let next = currentIndex + delta
        guard fields.indices.contains(next) else { return }
        focusedField.wrappedValue = fields[next]
    }
}

struct KeyboardDismissToolbar: ToolbarContent {
    let onDone: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button(String(localized: "完成"), action: onDone)
        }
    }
}

@MainActor
enum AppKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
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
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
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
                    .lineLimit(1)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !note.isEmpty {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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

struct OperationToastModifier: ViewModifier {
    @Binding var message: String?
    @State private var hideTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Text(message)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            Capsule().fill(Color.black.opacity(0.78))
                        )
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .onChange(of: message) { _, newValue in
                hideTask?.cancel()
                guard newValue != nil else { return }
                AppHaptics.success()
                hideTask = Task { @MainActor in
                    guard await DebouncedTask.wait(for: .milliseconds(1_600)) else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        message = nil
                    }
                }
            }
            .animation(.easeOut(duration: 0.2), value: message)
    }
}

extension View {
    func operationToast(message: Binding<String?>) -> some View {
        modifier(OperationToastModifier(message: message))
    }
}

struct FilterChipBar<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                    Button {
                        selection = option
                    } label: {
                        Text(title(option))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selection == option ? .white : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(selection == option ? Color.appPrimaryAction : Color(uiColor: .tertiarySystemGroupedBackground))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
