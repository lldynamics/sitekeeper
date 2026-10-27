import SwiftUI

/// Decisions use the space inside the current scene/column, including the keyboard.
enum AppWorkspaceRules {
    static func permitsColumns(width: CGFloat, height: CGFloat, primary: CGFloat, secondary: CGFloat) -> Bool {
        width.isFinite && height.isFinite && width >= primary + secondary + 1 && height >= 240
    }
}

enum AppReviewPane: Hashable {
    case primary, secondary
}

private struct AppReviewPaneVisibilityKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var appReviewPaneIsVisible: Bool {
        get { self[AppReviewPaneVisibilityKey.self] }
        set { self[AppReviewPaneVisibilityKey.self] = newValue }
    }
}

/// Both panes stay mounted when the window folds, resizes or enters Split View.
/// Hiding a pane never recreates its editor, PDF controller, focus or scroll state.
struct AppReviewWorkspace<Primary: View, Secondary: View>: View {
    let primaryTitle: String
    let secondaryTitle: String
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary
    @State private var selectedPane: AppReviewPane
    @State private var prefersColumns = true
    @ScaledMetric(relativeTo: .body) private var primaryMinimum: CGFloat = 340
    @ScaledMetric(relativeTo: .body) private var secondaryMinimum: CGFloat = 300

    init(primaryTitle: String, secondaryTitle: String, initialPane: AppReviewPane = .primary,
         @ViewBuilder primary: @escaping () -> Primary, @ViewBuilder secondary: @escaping () -> Secondary) {
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.primary = primary
        self.secondary = secondary
        _selectedPane = State(initialValue: initialPane)
    }

    var body: some View {
        GeometryReader { geometry in
            let canSplit = AppWorkspaceRules.permitsColumns(
                width: geometry.size.width, height: geometry.size.height,
                primary: primaryMinimum, secondary: secondaryMinimum
            )
            let split = canSplit && prefersColumns
            VStack(spacing: 0) {
                controls(canSplit: canSplit, split: split)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                AppReviewPaneLayout(split: split, primaryMinimum: primaryMinimum, secondaryMinimum: secondaryMinimum) {
                    primary()
                        .environment(\.appReviewPaneIsVisible, split || selectedPane == .primary)
                        .accessibilityElement(children: .contain)
                        .opacity(split || selectedPane == .primary ? 1 : 0)
                        .allowsHitTesting(split || selectedPane == .primary)
                        .accessibilityHidden(!split && selectedPane != .primary)
                        .simultaneousGesture(TapGesture().onEnded { selectedPane = .primary })
                    secondary()
                        .environment(\.appReviewPaneIsVisible, split || selectedPane == .secondary)
                        .accessibilityElement(children: .contain)
                        .opacity(split || selectedPane == .secondary ? 1 : 0)
                        .allowsHitTesting(split || selectedPane == .secondary)
                        .accessibilityHidden(!split && selectedPane != .secondary)
                        .simultaneousGesture(TapGesture().onEnded { selectedPane = .secondary })
                }
                .clipped()
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(split ? "review-workspace-columns" : "review-workspace-single")
        }
    }

    @ViewBuilder
    private func controls(canSplit: Bool, split: Bool) -> some View {
        HStack {
            if split {
                Text(AppLocalization.string("并排查看"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(primaryTitle) { show(.primary) }
                Button(secondaryTitle) { show(.secondary) }
            } else {
                Picker(AppLocalization.string("查看内容"), selection: $selectedPane) {
                    Text(primaryTitle).tag(AppReviewPane.primary)
                    Text(secondaryTitle).tag(AppReviewPane.secondary)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("review-workspace-pane")
                if canSplit {
                    Button { prefersColumns = true } label: {
                        Label(AppLocalization.string("并排查看"), systemImage: "rectangle.split.2x1")
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }

    private func show(_ pane: AppReviewPane) {
        selectedPane = pane
        prefersColumns = false
    }
}

private struct AppReviewPaneLayout: Layout {
    let split: Bool
    let primaryMinimum: CGFloat
    let secondaryMinimum: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 320, height: 480))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        if split {
            let width = min(max(bounds.width * 0.54, primaryMinimum), bounds.width - secondaryMinimum - 1)
            subviews[0].place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: width, height: bounds.height))
            subviews[1].place(at: CGPoint(x: bounds.minX + width + 1, y: bounds.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width - width - 1, height: bounds.height))
        } else {
            for view in subviews {
                view.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
            }
        }
    }
}
