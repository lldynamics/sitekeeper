import SwiftUI
import UIKit

extension View {
    // iOS 27's .keyboard toolbar builds an infinite fixed frame in InputAccessoryBar.
    // Keep the same controls in the page's keyboard-adjusted safe area instead.
    func appKeyboardToolbar<Bar: View>(@ViewBuilder content: () -> Bar) -> some View {
        modifier(AppKeyboardToolbarModifier(bar: content()))
    }
}

private struct AppKeyboardToolbarModifier<Bar: View>: ViewModifier {
    let bar: Bar
    @State private var isPresented = false
    @State private var isActive = false

    func body(content: Content) -> some View {
        content
            .background {
                KeyboardToolbarScopeReader(isActive: isActive) { visible in
                    if isPresented != visible { isPresented = visible }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isPresented {
                    bar
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                        .background(.bar)
                }
            }
            .onAppear { isActive = true }
            .onDisappear {
                isActive = false
                isPresented = false
            }
    }
}

private struct KeyboardToolbarScopeReader: UIViewRepresentable {
    let isActive: Bool
    let onVisibilityChange: (Bool) -> Void

    func makeUIView(context: Context) -> KeyboardToolbarScopeView {
        let view = KeyboardToolbarScopeView()
        view.isScopeActive = isActive
        view.onVisibilityChange = onVisibilityChange
        return view
    }

    func updateUIView(_ uiView: KeyboardToolbarScopeView, context: Context) {
        uiView.onVisibilityChange = onVisibilityChange
        uiView.isScopeActive = isActive
        uiView.scheduleVisibilityUpdate()
    }

    static func dismantleUIView(_ uiView: KeyboardToolbarScopeView, coordinator: ()) {
        uiView.stopObserving()
        uiView.onVisibilityChange = nil
    }
}

// Scope the bar to its hosting page, not an application-wide keyboard-visible flag.
// System safe areas position it above docked keyboards; floating/hardware keyboards
// retain an accessible Done action at the page bottom while this page owns focus.
@MainActor
final class KeyboardToolbarScopeView: UIView {
    var onVisibilityChange: ((Bool) -> Void)?
    var isScopeActive = true
    private var observers: [NSObjectProtocol] = []
    private var updateScheduled = false
    private var lastPageSize = CGSize.zero

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        stopObserving()
        if window != nil {
            let names: [Notification.Name] = [
                UITextField.textDidBeginEditingNotification, UITextField.textDidEndEditingNotification,
                UITextView.textDidBeginEditingNotification, UITextView.textDidEndEditingNotification,
                UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidChangeFrameNotification,
                UIResponder.keyboardDidHideNotification, UIWindow.didBecomeKeyNotification,
                UIWindow.didResignKeyNotification
            ]
            observers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.scheduleVisibilityUpdate() }
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
            self.onVisibilityChange?(self.shouldPresentToolbar)
            if resized { self.keepFocusedInputVisible() }
        }
    }

    private func keepFocusedInputVisible() {
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
                let page = convert(bounds, to: scroll)
                let visible = scroll.bounds.inset(by: scroll.adjustedContentInset).intersection(safe).intersection(page)
                let input = responder.convert(target, to: scroll).insetBy(dx: 0, dy: -12)
                if Self.hasUsableBounds(visible), Self.hasUsableBounds(input) {
                    let delta = input.minY < visible.minY ? input.minY - visible.minY
                        : max(0, input.maxY - visible.maxY)
                    let lower = -scroll.adjustedContentInset.top
                    let upper = max(lower, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                    let offset = min(max(scroll.contentOffset.y + delta, lower), upper)
                    if abs(offset - scroll.contentOffset.y) > 0.5 {
                        scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
                    }
                }
            }
            ancestor = view.superview
        }
    }

    var shouldPresentToolbar: Bool {
        guard isScopeActive, let window, window.isKeyWindow,
              Self.hasUsableBounds(bounds), !isHidden,
              let owner = Self.viewController(containing: self),
              let responder = Self.firstResponder(in: window),
              Self.viewController(containing: responder) === owner else { return false }
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
