import SwiftUI
import UIKit

extension View {
    // iOS 27's .keyboard toolbar builds an infinite fixed frame in InputAccessoryBar.
    // Keep the same controls in the page's keyboard-adjusted safe area instead.
    func appKeyboardToolbar<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        modifier(AppKeyboardToolbarModifier(bar: content()))
    }
}

struct KeyboardToolbarCancelAction {
    let title: String
    let perform: () -> Void
}

private struct KeyboardToolbarCancelActionKey: EnvironmentKey {
    static var defaultValue: KeyboardToolbarCancelAction? { nil }
}

extension EnvironmentValues {
    var keyboardToolbarCancelAction: KeyboardToolbarCancelAction? {
        get { self[KeyboardToolbarCancelActionKey.self] }
        set { self[KeyboardToolbarCancelActionKey.self] = newValue }
    }
}

private struct AppKeyboardToolbarModifier<Bar: View>: ViewModifier {
    @Environment(\.keyboardToolbarCancelAction) private var cancelAction
    let bar: Bar
    @State private var isPresented = false
    @State private var isActive = false
    @State private var isFloatingKeyboard = false
    @State private var placeBarAtTop = false
    @State private var placeCancelAtTrailing = false
    @State private var barLeadingAvoidance: CGFloat = 0
    @State private var barTrailingAvoidance: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .background {
                KeyboardToolbarScopeReader(isActive: isActive, onVisibilityChange: { visible in
                    if isPresented != visible { isPresented = visible }
                }, onPlacementChange: { floating, top, trailing, leadingInset, trailingInset in
                    if isFloatingKeyboard != floating { isFloatingKeyboard = floating }
                    if placeBarAtTop != top { placeBarAtTop = top }
                    if placeCancelAtTrailing != trailing { placeCancelAtTrailing = trailing }
                    if barLeadingAvoidance != leadingInset { barLeadingAvoidance = leadingInset }
                    if barTrailingAvoidance != trailingInset { barTrailingAvoidance = trailingInset }
                })
            }
            .safeAreaInset(edge: placeBarAtTop ? .top : .bottom, spacing: 0) {
                if isPresented {
                    HStack {
                        if isFloatingKeyboard, !placeCancelAtTrailing, let cancelAction {
                            Button(cancelAction.title, action: cancelAction.perform)
                                .accessibilityIdentifier("keyboard-cancel")
                        }
                        bar
                        if isFloatingKeyboard, placeCancelAtTrailing, let cancelAction {
                            Button(cancelAction.title, action: cancelAction.perform)
                                .accessibilityIdentifier("keyboard-cancel")
                        }
                    }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.leading, barLeadingAvoidance)
                        .padding(.trailing, barTrailingAvoidance)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .background(.bar)
                }
            }
            .onAppear { isActive = true }
            .onDisappear {
                isActive = false
                isPresented = false
                isFloatingKeyboard = false
                placeBarAtTop = false
                placeCancelAtTrailing = false
                barLeadingAvoidance = 0
                barTrailingAvoidance = 0
            }
    }
}

private struct KeyboardToolbarScopeReader: UIViewRepresentable {
    let isActive: Bool
    let onVisibilityChange: (Bool) -> Void
    let onPlacementChange: (Bool, Bool, Bool, CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> KeyboardToolbarScopeView {
        let view = KeyboardToolbarScopeView()
        view.isScopeActive = isActive
        view.onVisibilityChange = onVisibilityChange
        view.onPlacementChange = onPlacementChange
        return view
    }

    func updateUIView(_ uiView: KeyboardToolbarScopeView, context: Context) {
        uiView.onVisibilityChange = onVisibilityChange
        uiView.onPlacementChange = onPlacementChange
        uiView.isScopeActive = isActive
        uiView.scheduleVisibilityUpdate()
    }

    static func dismantleUIView(_ uiView: KeyboardToolbarScopeView, coordinator: ()) {
        uiView.stopObserving()
        uiView.onVisibilityChange = nil
        uiView.onPlacementChange = nil
    }
}

// Scope the bar to its hosting page, not an application-wide keyboard-visible flag.
// Track the keyboard in window coordinates, then choose a free edge of this page.
@MainActor
final class KeyboardToolbarScopeView: UIView {
    var onVisibilityChange: ((Bool) -> Void)?
    var onPlacementChange: ((Bool, Bool, Bool, CGFloat, CGFloat) -> Void)?
    var isScopeActive = true
    private var observers: [NSObjectProtocol] = []
    private var updateScheduled = false
    private var lastPageSize = CGSize.zero
    private var keyboardEndFrame: CGRect?
    private var keyboardTracker: KeyboardFrameTrackingView?
    private var lastFloatingFrame: CGRect?
    private weak var lastFocusedResponder: UIView?

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        stopObserving()
        if let window {
            if window.traitCollection.userInterfaceIdiom == .pad {
                let tracker = KeyboardFrameTrackingView(frame: window.bounds)
                tracker.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                tracker.onLayoutChange = { [weak self] in self?.scheduleVisibilityUpdate() }
                window.addSubview(tracker)
                keyboardTracker = tracker
            }
            let names: [Notification.Name] = [
                UITextField.textDidBeginEditingNotification, UITextField.textDidEndEditingNotification,
                UITextView.textDidBeginEditingNotification, UITextView.textDidEndEditingNotification,
                UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidChangeFrameNotification,
                UIResponder.keyboardDidHideNotification, UIWindow.didBecomeKeyNotification,
                UIWindow.didResignKeyNotification
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                    let keyboardFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if name == UIResponder.keyboardDidHideNotification {
                            self.keyboardEndFrame = nil
                        } else if let keyboardFrame {
                            self.keyboardEndFrame = keyboardFrame
                        }
                        self.scheduleVisibilityUpdate()
                    }
                }
            }
        }
        scheduleVisibilityUpdate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleVisibilityUpdate()
    }

    func stopObserving() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        keyboardTracker?.removeFromSuperview()
        keyboardTracker = nil
        lastFloatingFrame = nil
        lastFocusedResponder = nil
    }

    func scheduleVisibilityUpdate() {
        guard !updateScheduled else { return }
        updateScheduled = true
        // Editing-end can precede editing-begin while using Next. Re-read focus after
        // UIKit completes the change, and avoid changing SwiftUI state during layout.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            let resized = self.lastPageSize != .zero && self.lastPageSize != self.bounds.size
            self.lastPageSize = self.bounds.size
            let belongsToPage = self.shouldPresentToolbar
            self.onVisibilityChange?(belongsToPage)
            let focusedResponder = belongsToPage ? self.window.flatMap { Self.firstResponder(in: $0) } : nil
            let focusChanged = self.lastFocusedResponder !== focusedResponder
            self.lastFocusedResponder = focusedResponder
            let floatingFrame = self.window.flatMap { self.floatingKeyboardFrame(in: $0) }
            let keyboardMoved = self.lastFloatingFrame != floatingFrame
            self.lastFloatingFrame = floatingFrame
            let placement = self.keyboardPlacement(floatingFrame: floatingFrame)
            self.onPlacementChange?(placement.isFloating, placement.atTop, placement.cancelAtTrailing,
                                    placement.leadingInset, placement.trailingInset)
            if resized || keyboardMoved || (focusChanged && floatingFrame != nil) {
                self.keepFocusedInputVisible(floatingFrame: floatingFrame)
            }
        }
    }

    private func floatingKeyboardFrame(in window: UIWindow) -> CGRect? {
        guard window.traitCollection.userInterfaceIdiom == .pad else { return nil }
        let frame: CGRect
        if let keyboardTracker {
            let guideFrame = keyboardTracker.convert(keyboardTracker.keyboardLayoutGuide.layoutFrame, to: window)
            // The guide returns the bottom safe area when the keyboard is hidden
            // or lies outside this window. Never revive a stale notification then.
            guard Self.hasUsableBounds(guideFrame),
                  guideFrame.height > window.safeAreaInsets.bottom + 1 else { return nil }
            frame = guideFrame
        } else if let screen = window.windowScene?.screen, let keyboardEndFrame {
            frame = window.convert(keyboardEndFrame, from: screen.coordinateSpace)
        } else {
            return nil
        }
        return Self.isFloatingKeyboard(frame, in: window.bounds) ? frame : nil
    }

    private func keyboardPlacement(floatingFrame: CGRect?) -> (isFloating: Bool, atTop: Bool, cancelAtTrailing: Bool, leadingInset: CGFloat, trailingInset: CGFloat) {
        guard let window, let frame = floatingFrame,
              let owner = Self.viewController(containing: self) else { return (false, false, false, 0, 0) }
        let ownerFrame = owner.view.convert(owner.view.bounds, to: window)
        let page = Self.hasUsableBounds(bounds) ? convert(bounds, to: window) : ownerFrame
        guard Self.hasUsableBounds(page), Self.hasUsableBounds(ownerFrame) else { return (true, true, false, 0, 0) }
        let insets = Self.horizontalToolbarAvoidance(keyboard: frame, page: page, owner: ownerFrame)
        return (true, Self.shouldPlaceBarAtTop(keyboard: frame, page: page, owner: ownerFrame),
                Self.cancelShouldBeTrailing(keyboard: frame, page: page), insets.leading, insets.trailing)
    }

    static func cancelShouldBeTrailing(keyboard: CGRect, page: CGRect) -> Bool {
        guard hasUsableBounds(keyboard), hasUsableBounds(page) else { return false }
        let leftSpace = keyboard.minX - page.minX
        let rightSpace = page.maxX - keyboard.maxX
        // With the keyboard in the middle, keep previous/next on the left and
        // done/cancel on the right when both groups have room.
        if leftSpace >= 120 && rightSpace >= 96 { return true }
        return keyboard.midX < page.midX
    }

    static func horizontalToolbarAvoidance(keyboard: CGRect, page: CGRect, owner: CGRect) -> (leading: CGFloat, trailing: CGFloat) {
        guard hasUsableBounds(keyboard), hasUsableBounds(page), hasUsableBounds(owner) else { return (0, 0) }
        let pageArea = CGRect(x: page.minX, y: owner.minY, width: page.width, height: owner.height)
        guard keyboard.intersects(pageArea) else { return (0, 0) }
        // On a short window the system can place the inset bar beside the keyboard
        // even after choosing the other vertical edge. Move its controls to the
        // free side when that side still fits the navigation and cancel actions.
        let leading = max(0, keyboard.maxX - page.minX + 8)
        let trailing = max(0, page.maxX - keyboard.minX + 8)
        let minimumWidth: CGFloat = 240
        if keyboard.midX < page.midX, page.width - leading >= minimumWidth { return (leading, 0) }
        if keyboard.midX >= page.midX, page.width - trailing >= minimumWidth { return (0, trailing) }
        return (0, 0)
    }

    static func shouldPlaceBarAtTop(keyboard: CGRect, page: CGRect, owner: CGRect) -> Bool {
        guard hasUsableBounds(keyboard), hasUsableBounds(page), hasUsableBounds(owner) else { return true }
        // Anchor the exclusion zone to the hosting page, not the Form: the Form
        // itself moves when the inset changes, which could make the bar oscillate.
        let topArea = CGRect(x: page.minX, y: owner.minY,
                             width: page.width, height: min(owner.height, 160))
        return !keyboard.intersects(topArea)
    }

    static func isFloatingKeyboard(_ frame: CGRect, in window: CGRect) -> Bool {
        hasUsableBounds(frame) && hasUsableBounds(window) && frame.intersects(window)
            && frame.width < window.width * 0.8
    }

    private func keepFocusedInputVisible(floatingFrame: CGRect?) {
        guard shouldPresentToolbar, let window,
              let owner = Self.viewController(containing: self),
              let responder = Self.firstResponder(in: window) else { return }
        owner.view.layoutIfNeeded()
        var target = responder.bounds
        if let input = responder as? UITextInput, let selection = input.selectedTextRange {
            let caret = input.caretRect(for: selection.end)
            if Self.hasUsableBounds(caret) { target = caret }
        }
        var ancestor = responder.superview
        while let view = ancestor, view !== owner.view.superview {
            if let scroll = view as? UIScrollView, scroll.isScrollEnabled {
                let safe = owner.view.convert(owner.view.safeAreaLayoutGuide.layoutFrame, to: scroll)
                let page = Self.hasUsableBounds(bounds) ? convert(bounds, to: scroll)
                    : owner.view.convert(owner.view.bounds, to: scroll)
                let visible = scroll.bounds.inset(by: scroll.adjustedContentInset).intersection(safe).intersection(page)
                let input = responder.convert(target, to: scroll).insetBy(dx: 0, dy: -12)
                if Self.hasUsableBounds(visible), Self.hasUsableBounds(input) {
                    var delta = input.minY < visible.minY ? input.minY - visible.minY
                        : max(0, input.maxY - visible.maxY)
                    let lower = -scroll.adjustedContentInset.top
                    let upper = max(lower, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    if let floatingFrame {
                        let keyboard = scroll.convert(floatingFrame, from: window)
                        delta = Self.unobscuredScrollDelta(input: input, visible: visible, keyboard: keyboard,
                                                          currentOffset: scroll.contentOffset.y, lower: lower,
                                                          upper: upper, proposed: delta)
                    }
                    let offset = min(max(scroll.contentOffset.y + delta, lower), upper)
                    if abs(offset - scroll.contentOffset.y) > 0.5 {
                        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
                    }
                }
            }
            ancestor = view.superview
        }
    }

    static func unobscuredScrollDelta(input: CGRect, visible: CGRect, keyboard: CGRect,
                                      currentOffset: CGFloat, lower: CGFloat, upper: CGFloat,
                                      proposed: CGFloat) -> CGFloat {
        let adjustedInput = input.offsetBy(dx: 0, dy: -proposed)
        guard hasUsableBounds(input), hasUsableBounds(visible), hasUsableBounds(keyboard),
              adjustedInput.intersects(keyboard) else { return proposed }
        let above = proposed + adjustedInput.maxY - keyboard.minY + 12
        let below = proposed + adjustedInput.minY - keyboard.maxY - 12
        let candidates = [above, below].filter { candidate in
            let offset = currentOffset + candidate
            let shifted = input.offsetBy(dx: 0, dy: -candidate)
            return offset >= lower && offset <= upper
                && visible.contains(shifted) && !shifted.intersects(keyboard)
        }
        return candidates.min(by: { abs($0) < abs($1) }) ?? proposed
    }

    var shouldPresentToolbar: Bool {
        guard isScopeActive, let window, window.isKeyWindow,
              !isHidden, let owner = Self.viewController(containing: self),
              let responder = Self.firstResponder(in: window),
              Self.viewController(containing: responder) === owner else { return false }
        // A floating keyboard can temporarily collapse the Form's background
        // reader to zero height while its hosting page and focused field remain
        // active. Keep scope validation tied to that page in this case only.
        guard Self.hasUsableBounds(bounds)
                || (floatingKeyboardFrame(in: window) != nil && Self.hasUsableBounds(owner.view.bounds)) else { return false }
        var controller: UIViewController? = owner
        while let current = controller {
            if current.isBeingDismissed || current.presentedViewController != nil { return false }
            controller = current.parent
        }
        return true
    }

    static func hasUsableBounds(_ bounds: CGRect) -> Bool {
        !bounds.isNull && !bounds.isInfinite
            && bounds.origin.x.isFinite && bounds.origin.y.isFinite
            && bounds.size.width.isFinite && bounds.size.height.isFinite
            && bounds.size.width > 0 && bounds.size.height > 0
    }

    private static func viewController(containing view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }

    private static func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for child in view.subviews {
            if let responder = firstResponder(in: child) { return responder }
        }
        return nil
    }
}

// This full-window, non-interactive view keeps the layout guide in the same
// coordinate space as a floating keyboard, even when a form is a small sheet.
@MainActor
private final class KeyboardFrameTrackingView: UIView {
    var onLayoutChange: (() -> Void)?
    private let probe = KeyboardFrameProbeView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        backgroundColor = .clear
        keyboardLayoutGuide.followsUndockedKeyboard = true
        probe.translatesAutoresizingMaskIntoConstraints = false
        probe.onFrameChange = { [weak self] in self?.onLayoutChange?() }
        addSubview(probe)
        NSLayoutConstraint.activate([
            probe.leadingAnchor.constraint(equalTo: keyboardLayoutGuide.leadingAnchor),
            probe.trailingAnchor.constraint(equalTo: keyboardLayoutGuide.trailingAnchor),
            probe.topAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
            probe.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayoutChange?()
    }
}

@MainActor
private final class KeyboardFrameProbeView: UIView {
    var onFrameChange: (() -> Void)?

    override var frame: CGRect {
        didSet {
            if frame != oldValue { onFrameChange?() }
        }
    }
}
