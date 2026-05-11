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
            return .orange
        case .destructive:
            return .red
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
            Button("上一个") {
                move(delta: -1)
            }
            .disabled(!canMovePrevious)

            Button("下一个") {
                move(delta: 1)
            }
            .disabled(!canMoveNext)

            Spacer()

            Button("完成") {
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
            Button("完成", action: onDone)
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

    static let appPrimaryAction = Color.orange
    static let appSuccess = Color.green
    static let appRisk = Color.red
    static let appFinance = Color.pink
    static let appDoc = Color.blue
    static let appInventory = Color.teal
    static let appPrimarySurface = Color.appDynamicTint(.systemOrange, lightOpacity: 0.16, darkOpacity: 0.30)
    static let appPrimarySurfaceSubtle = Color.appDynamicTint(.systemOrange, lightOpacity: 0.12, darkOpacity: 0.24)
    static let appRiskSurface = Color.appDynamicTint(.systemRed, lightOpacity: 0.14, darkOpacity: 0.28)
    static let appDocSurfaceSubtle = Color.appDynamicTint(.systemBlue, lightOpacity: 0.10, darkOpacity: 0.22)
    static let appSuccessSurfaceSubtle = Color.appDynamicTint(.systemGreen, lightOpacity: 0.12, darkOpacity: 0.24)
    static let appStrokeWarning = Color("StrokeWarning")
    static let appStrokeInfo = Color("StrokeInfo")
    static let appStrokeSuccess = Color("StrokeSuccess")
    static let appStrokeError = Color("StrokeError")
    static let appStrokeSecondary = Color("StrokeSecondary")
    static let appStrokeSeparator = Color("StrokeSeparator")
    static let appStrokeLightOverlay = Color("StrokeLightOverlay")
    static let appStrokeNeutral = Color("StrokeNeutral")
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
    var trailingColor: Color = .orange

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
