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

struct AppBusinessEditForm<Content: View>: View {
    let title: String
    var cancelTitle: String = String(localized: "取消")
    var primaryActionTitle: String = String(localized: "保存")
    var isPrimaryActionDisabled = false
    let onCancel: () -> Void
    let onPrimaryAction: () -> Void
    @ViewBuilder let content: Content

    init(
        title: String,
        cancelTitle: String = String(localized: "取消"),
        primaryActionTitle: String = String(localized: "保存"),
        isPrimaryActionDisabled: Bool = false,
        onCancel: @escaping () -> Void,
        onPrimaryAction: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.cancelTitle = cancelTitle
        self.primaryActionTitle = primaryActionTitle
        self.isPrimaryActionDisabled = isPrimaryActionDisabled
        self.onCancel = onCancel
        self.onPrimaryAction = onPrimaryAction
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(cancelTitle, action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(primaryActionTitle, action: onPrimaryAction)
                            .disabled(isPrimaryActionDisabled)
                    }
                }
        }
    }
}

struct AppBusinessFormValidationSection: View {
    let messages: [String]

    var body: some View {
        if !messages.isEmpty {
            Section(String(localized: "表单问题")) {
                ForEach(messages, id: \.self) { message in
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.appWarning)
                }
            }
        }
    }
}

struct AppBusinessFormDestructiveActionSection: View {
    let title: String
    var systemImage: String = "trash"
    let action: () -> Void

    var body: some View {
        Section {
            Button(role: .destructive, action: action) {
                Label(title, systemImage: systemImage)
            }
        }
    }
}

extension View {
    func appListPrimaryTextLayout(lines: Int = 2) -> some View {
        lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
    }

    func appListSecondaryTextLayout(lines: Int = 2) -> some View {
        lineLimit(lines)
            .fixedSize(horizontal: false, vertical: true)
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

enum InlineNoticeTone {
    case info
    case success
    case warning
    case error

    var icon: String {
        switch self {
        case .info:
            "info.circle.fill"
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .error:
            "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .info:
            .appPrimaryAction
        case .success:
            .appSuccess
        case .warning:
            .appWarning
        case .error:
            .appRisk
        }
    }

    var background: Color {
        switch self {
        case .info:
            .appPrimarySurfaceSubtle
        case .success:
            .appSuccessSurfaceSubtle
        case .warning:
            .appDynamicTint(AppTheme.current.palette.warningUIColor, lightOpacity: 0.12, darkOpacity: 0.24)
        case .error:
            .appRiskSurface
        }
    }
}

struct InlineNotice: View {
    let title: String
    var message: String? = nil
    var tone: InlineNoticeTone = .info

    var body: some View {
        AppPanel(
            tone: .tinted(tone.background),
            cornerRadius: 10,
            padding: AppSpacing.normal,
            stroke: tone.tint.opacity(0.18)
        ) {
            HStack(alignment: .top, spacing: AppSpacing.tight) {
                Image(systemName: tone.icon)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tone.tint)
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let message, !message.isEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct DataSafetyStatusItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    var tone: StatusChipTone = .neutral
}

struct DataSafetyStatusStrip: View {
    let items: [DataSafetyStatusItem]

    var body: some View {
        AppPanel(
            tone: .grouped,
            cornerRadius: 12,
            padding: AppSpacing.normal,
            stroke: Color.appStrokeSecondary.opacity(0.45)
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 132), alignment: .topLeading)],
                alignment: .leading,
                spacing: AppSpacing.normal
            ) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        StatusChip(text: item.title, tone: item.tone, compact: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct AdaptiveListDetailLayout<Compact: View, Sidebar: View, Detail: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var forceSplit: Bool? = nil
    var visibility: NavigationSplitViewVisibility = .all
    @ViewBuilder let compact: () -> Compact
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let detail: () -> Detail

    init(
        forceSplit: Bool? = nil,
        visibility: NavigationSplitViewVisibility = .all,
        @ViewBuilder compact: @escaping () -> Compact,
        @ViewBuilder sidebar: @escaping () -> Sidebar,
        @ViewBuilder detail: @escaping () -> Detail
    ) {
        self.forceSplit = forceSplit
        self.visibility = visibility
        self.compact = compact
        self.sidebar = sidebar
        self.detail = detail
    }

    private var usesSplitLayout: Bool {
        if let forceSplit {
            return forceSplit
        }
        return UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if usesSplitLayout {
                NavigationSplitView(columnVisibility: .constant(visibility)) {
                    sidebar()
                } detail: {
                    detail()
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                compact()
            }
        }
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

struct OperationToastNotice: Identifiable {
    let id = UUID()
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var autoDismissDuration: Duration = .milliseconds(1_600)

    static func info(_ message: String) -> OperationToastNotice {
        OperationToastNotice(message: message)
    }
}

private struct OperationToastBanner: View {
    let notice: OperationToastNotice
    var actionOverride: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(notice.message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let actionTitle = notice.actionTitle {
                Button(actionTitle) {
                    actionOverride?() ?? notice.action?()
                }
                .font(.caption.weight(.bold))
                .buttonStyle(.plain)
                .foregroundStyle(Color.appWarning)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Color.black.opacity(0.78))
        )
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct UndoableDeletionAuditContext {
    let summary: String
    var detail: String = ""
    var source: String = ""
}

extension UndoableDeletionAuditContext {
    init(_ context: DataStoreDeletionAuditContext) {
        self.init(summary: context.summary, detail: context.detail, source: context.source)
    }
}

@MainActor
final class UndoableDeletionCoordinator {
    private var pendingCommitTask: Task<Void, Never>?
    private var pendingCommit: (() -> Void)?
    private let delay: Duration

    init(delay: Duration = .seconds(4)) {
        self.delay = delay
    }

    func queue(
        notice: Binding<OperationToastNotice?>,
        message: String,
        undoMessage: String = String(localized: "已撤销删除"),
        actionTitle: String = String(localized: "撤销"),
        commit: @escaping () -> Void,
        undo: @escaping () -> Void,
        audit: UndoableDeletionAuditContext? = nil
    ) {
        flushPendingCommit()

        if let audit {
            OperationAuditLog.record(
                action: .delete,
                outcome: .started,
                summary: audit.summary,
                detail: audit.detail,
                source: audit.source
            )
        }

        pendingCommit = {
            commit()
            if let audit {
                OperationAuditLog.record(
                    action: .delete,
                    outcome: .succeeded,
                    summary: audit.summary,
                    detail: audit.detail,
                    source: audit.source
                )
            }
        }

        let delay = delay
        pendingCommitTask = Task { @MainActor [weak self] in
            guard await DebouncedTask.wait(for: delay) else { return }
            self?.commitPending()
        }

        notice.wrappedValue = OperationToastNotice(
            message: message,
            actionTitle: actionTitle,
            action: { [weak self] in
                self?.cancelPendingCommit()
                undo()
                if let audit {
                    OperationAuditLog.record(
                        action: .delete,
                        outcome: .cancelled,
                        summary: audit.summary,
                        detail: audit.detail,
                        source: audit.source
                    )
                }
                notice.wrappedValue = .info(undoMessage)
            },
            autoDismissDuration: delay
        )
    }

    func flushPendingCommit() {
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        let commit = pendingCommit
        pendingCommit = nil
        commit?()
    }

    func cancelPendingCommit() {
        pendingCommitTask?.cancel()
        pendingCommitTask = nil
        pendingCommit = nil
    }

    private func commitPending() {
        let commit = pendingCommit
        pendingCommit = nil
        pendingCommitTask = nil
        commit?()
    }

    static func restoringItems<Item: Identifiable>(
        snapshot: [Item],
        current: [Item],
        deletedIDs: Set<Item.ID>
    ) -> [Item] where Item.ID: Hashable {
        let snapshotIDs = Set(snapshot.map(\.id))
        var currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for item in snapshot where deletedIDs.contains(item.id) {
            currentByID[item.id] = item
        }
        let newItems = current.filter { !snapshotIDs.contains($0.id) }
        let restoredSnapshotItems = snapshot.compactMap { currentByID[$0.id] }
        return newItems + restoredSnapshotItems
    }
}

struct OperationToastNoticeModifier: ViewModifier {
    @Binding var notice: OperationToastNotice?
    var onDismiss: (() -> Void)? = nil
    @State private var hideTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let notice {
                    OperationToastBanner(
                        notice: notice,
                        actionOverride: {
                            hideTask?.cancel()
                            withAnimation(.easeOut(duration: 0.2)) {
                                self.notice = nil
                            }
                            onDismiss?()
                            notice.action?()
                        }
                    )
                }
            }
            .onChange(of: notice?.id) { _, newID in
                hideTask?.cancel()
                guard newID != nil else {
                    onDismiss?()
                    return
                }
                AppHaptics.success()
                let duration = notice?.autoDismissDuration ?? .milliseconds(1_600)
                hideTask = Task { @MainActor in
                    guard await DebouncedTask.wait(for: duration) else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        notice = nil
                    }
                    onDismiss?()
                }
            }
            .animation(.easeOut(duration: 0.2), value: notice?.id)
    }
}

private struct OperationToastMessageBridgeModifier: ViewModifier {
    @Binding var message: String?
    @State private var notice: OperationToastNotice?

    func body(content: Content) -> some View {
        content
            .modifier(OperationToastNoticeModifier(
                notice: $notice,
                onDismiss: {
                    message = nil
                }
            ))
            .onChange(of: message) { _, newValue in
                guard let newValue, !newValue.isEmpty else {
                    notice = nil
                    return
                }
                notice = .info(newValue)
            }
            .onAppear {
                if let message, !message.isEmpty {
                    notice = .info(message)
                }
            }
    }
}

extension View {
    func operationToast(message: Binding<String?>) -> some View {
        modifier(OperationToastMessageBridgeModifier(message: message))
    }

    func operationToast(notice: Binding<OperationToastNotice?>) -> some View {
        modifier(OperationToastNoticeModifier(notice: notice))
    }
}

struct AppActionableEmptyState<Action: View>: View {
    let title: String
    let systemImage: String
    let message: Text
    @ViewBuilder let action: Action

    init(
        title: String,
        systemImage: String,
        message: String,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = Text(message)
        self.action = action()
    }

    init(
        title: String,
        systemImage: String,
        message: Text,
        @ViewBuilder action: () -> Action
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.action = action()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.tight) {
            HStack(alignment: .top, spacing: AppSpacing.tight) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.appPrimaryAction)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    message
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            action
        }
        .padding(.vertical, 4)
    }
}

extension AppActionableEmptyState where Action == EmptyView {
    init(
        title: String,
        systemImage: String,
        message: String
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = Text(message)
        self.action = EmptyView()
    }

    init(
        title: String,
        systemImage: String,
        message: Text
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.action = EmptyView()
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
