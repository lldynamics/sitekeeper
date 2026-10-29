import Testing
import UIKit
@testable import sitekeeper

@MainActor
@Suite(.serialized)
struct KeyboardToolbarTests {
    @Test func toolbarBelongsOnlyToThePageContainingTheFocusedInput() throws {
        let fixture = KeyboardToolbarWindowFixture()
        defer { fixture.close() }

        #expect(!fixture.scope.shouldPresentToolbar)
        #expect(fixture.localInput.becomeFirstResponder())
        #expect(fixture.scope.shouldPresentToolbar)

        #expect(fixture.otherInput.becomeFirstResponder())
        #expect(!fixture.scope.shouldPresentToolbar)

        #expect(fixture.localInput.becomeFirstResponder())
        #expect(fixture.scope.shouldPresentToolbar)
        fixture.scope.isScopeActive = false
        #expect(!fixture.scope.shouldPresentToolbar)
        fixture.scope.isScopeActive = true
        #expect(fixture.scope.shouldPresentToolbar)
        fixture.localInput.resignFirstResponder()
        #expect(!fixture.scope.shouldPresentToolbar)
    }

    @Test func leavingTheWindowAndReturningDoesNotReuseVisibility() throws {
        let fixture = KeyboardToolbarWindowFixture()
        defer { fixture.close() }
        #expect(fixture.localInput.becomeFirstResponder())
        #expect(fixture.scope.shouldPresentToolbar)

        fixture.scope.removeFromSuperview()
        #expect(!fixture.scope.shouldPresentToolbar)
        #expect(fixture.otherInput.becomeFirstResponder())
        fixture.localController.view.addSubview(fixture.scope)
        #expect(!fixture.scope.shouldPresentToolbar)
    }

    @Test func keyboardNotificationsResumeAfterReturningToTheWindow() async throws {
        let fixture = KeyboardToolbarWindowFixture()
        defer { fixture.close() }
        var lastVisibility: Bool?
        fixture.scope.onVisibilityChange = { lastVisibility = $0 }

        try #require(fixture.localInput.becomeFirstResponder())
        try await waitForVisibility(true) { lastVisibility }
        fixture.scope.removeFromSuperview()
        try await waitForVisibility(false) { lastVisibility }
        fixture.localController.view.addSubview(fixture.scope)
        try await waitForVisibility(true) { lastVisibility }

        // Changing this flag does not schedule a refresh. Only the notification
        // should make the reattached scope deliver the new visibility value.
        fixture.scope.isScopeActive = false
        NotificationCenter.default.post(
            name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
        try await waitForVisibility(false) { lastVisibility }
        fixture.scope.isScopeActive = true
        NotificationCenter.default.post(
            name: UITextField.textDidBeginEditingNotification, object: fixture.localInput
        )
        try await waitForVisibility(true) { lastVisibility }

        try #require(fixture.otherInput.becomeFirstResponder())
        try await waitForVisibility(false) { lastVisibility }
    }

    private func waitForVisibility(_ expected: Bool, read: () -> Bool?) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while read() != expected, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(read() == expected, "Keyboard visibility callback did not arrive within one second.")
    }

    @Test func pageCoveredByASheetDoesNotKeepItsKeyboardBar() async throws {
        let fixture = KeyboardToolbarWindowFixture()
        defer { fixture.close() }
        #expect(fixture.localInput.becomeFirstResponder())
        #expect(fixture.scope.shouldPresentToolbar)

        let sheet = UIViewController()
        sheet.modalPresentationStyle = .pageSheet
        let input = UITextField(frame: CGRect(x: 20, y: 20, width: 160, height: 44))
        sheet.view.addSubview(input)
        fixture.root.present(sheet, animated: false)
        #expect(fixture.root.presentedViewController === sheet)
        #expect(!fixture.scope.shouldPresentToolbar)
        try await waitForVisibility(true) {
            sheet.view.window === fixture.window && !sheet.isBeingPresented
        }

        #expect(input.becomeFirstResponder())
        #expect(!fixture.scope.shouldPresentToolbar)
        sheet.dismiss(animated: false)
    }

    @Test func rotationUsesLocalBoundsAndNeverRequiresAGlobalKeyboardFrame() throws {
        let fixture = KeyboardToolbarWindowFixture()
        defer { fixture.close() }
        #expect(fixture.localInput.becomeFirstResponder())

        fixture.scope.bounds = CGRect(x: 0, y: 0, width: 320, height: 500)
        #expect(fixture.scope.shouldPresentToolbar)
        fixture.scope.bounds = CGRect(x: 0, y: 0, width: 700, height: 250)
        #expect(fixture.scope.shouldPresentToolbar)
        fixture.scope.bounds = .zero
        #expect(!fixture.scope.shouldPresentToolbar)
        fixture.scope.bounds = CGRect(x: 0, y: 0, width: 320, height: 500)
        #expect(fixture.scope.shouldPresentToolbar)
    }

    @Test func unusableLayoutFramesCannotPresentTheBar() {
        #expect(!KeyboardToolbarScopeView.hasUsableBounds(.zero))
        #expect(!KeyboardToolbarScopeView.hasUsableBounds(.null))
        #expect(!KeyboardToolbarScopeView.hasUsableBounds(.infinite))
        #expect(!KeyboardToolbarScopeView.hasUsableBounds(CGRect(x: 0, y: 0, width: -1, height: 44)))
        #expect(!KeyboardToolbarScopeView.hasUsableBounds(CGRect(x: 0, y: 0, width: CGFloat.nan, height: 44)))
        #expect(KeyboardToolbarScopeView.hasUsableBounds(CGRect(x: 0, y: 0, width: 320, height: 44)))
    }

    @Test func floatingKeyboardPlacementUsesWindowAndPageCoordinates() {
        let window = CGRect(x: 0, y: 0, width: 1032, height: 1376)
        let owner = CGRect(x: 226, y: 360, width: 580, height: 650)
        let page = CGRect(x: 226, y: 420, width: 580, height: 590)
        let lowerKeyboard = CGRect(x: 520, y: 940, width: 320, height: 260)
        let upperKeyboard = CGRect(x: 250, y: 340, width: 320, height: 260)
        let dockedKeyboard = CGRect(x: 0, y: 1050, width: 1032, height: 326)

        #expect(KeyboardToolbarScopeView.isFloatingKeyboard(lowerKeyboard, in: window))
        #expect(KeyboardToolbarScopeView.isFloatingKeyboard(upperKeyboard, in: window))
        #expect(!KeyboardToolbarScopeView.isFloatingKeyboard(dockedKeyboard, in: window))
        #expect(!KeyboardToolbarScopeView.isFloatingKeyboard(.null, in: window))
        #expect(KeyboardToolbarScopeView.shouldPlaceBarAtTop(keyboard: lowerKeyboard, page: page, owner: owner))
        #expect(!KeyboardToolbarScopeView.shouldPlaceBarAtTop(keyboard: upperKeyboard, page: page, owner: owner))
    }

    @Test func floatingKeyboardKeepsToolbarControlsOnTheUncoveredSide() {
        let owner = CGRect(x: 226, y: 50, width: 580, height: 550)
        let page = CGRect(x: 226, y: 100, width: 580, height: 450)
        let left = KeyboardToolbarScopeView.horizontalToolbarAvoidance(
            keyboard: CGRect(x: 7, y: 81, width: 320, height: 223), page: page, owner: owner)
        #expect(left.leading == 109 && left.trailing == 0)
        let right = KeyboardToolbarScopeView.horizontalToolbarAvoidance(
            keyboard: CGRect(x: 700, y: 81, width: 320, height: 223), page: page, owner: owner)
        #expect(right.leading == 0 && right.trailing == 114)
        let outside = KeyboardToolbarScopeView.horizontalToolbarAvoidance(
            keyboard: CGRect(x: 0, y: 900, width: 320, height: 223), page: page, owner: owner)
        #expect(outside.leading == 0 && outside.trailing == 0)
        let narrow = CGRect(x: 226, y: 100, width: 150, height: 450)
        let insufficient = KeyboardToolbarScopeView.horizontalToolbarAvoidance(
            keyboard: CGRect(x: 7, y: 81, width: 320, height: 223), page: narrow, owner: owner)
        #expect(insufficient.leading == 0 && insufficient.trailing == 0)
        #expect(KeyboardToolbarScopeView.cancelShouldBeTrailing(
            keyboard: CGRect(x: 361, y: 80, width: 320, height: 227), page: page))
        #expect(!KeyboardToolbarScopeView.cancelShouldBeTrailing(
            keyboard: CGRect(x: 700, y: 81, width: 320, height: 223), page: page))
    }

    @Test func floatingKeyboardScrollAvoidanceKeepsTheCaretInTheVisiblePage() {
        let visible = CGRect(x: 0, y: 0, width: 500, height: 500)
        let input = CGRect(x: 200, y: 240, width: 10, height: 30)
        let keyboard = CGRect(x: 100, y: 200, width: 300, height: 200)
        let delta = KeyboardToolbarScopeView.unobscuredScrollDelta(
            input: input, visible: visible, keyboard: keyboard,
            currentOffset: 100, lower: 0, upper: 600, proposed: 0
        )
        let shifted = input.offsetBy(dx: 0, dy: -delta)
        #expect(delta == 82)
        #expect(visible.contains(shifted))
        #expect(!shifted.intersects(keyboard))

        let noOverlap = keyboard.offsetBy(dx: 500, dy: 0)
        #expect(KeyboardToolbarScopeView.unobscuredScrollDelta(
            input: input, visible: visible, keyboard: noOverlap,
            currentOffset: 100, lower: 0, upper: 600, proposed: 0
        ) == 0)
        #expect(KeyboardToolbarScopeView.unobscuredScrollDelta(
            input: input, visible: visible, keyboard: visible,
            currentOffset: 100, lower: 0, upper: 600, proposed: 0
        ) == 0, "Do not force an invalid offset when the keyboard covers the entire page.")
    }

    @Test func resizingKeepsTheFocusedCaretBelowThePageChromeWithoutRefocusing() async throws {
        let fixture = KeyboardToolbarWindowFixture()
        defer { fixture.close() }
        let scroll = UIScrollView(frame: fixture.localController.view.bounds)
        scroll.contentSize = CGSize(width: 400, height: 1000)
        fixture.localController.view.insertSubview(scroll, at: 0)
        fixture.localInput.frame = CGRect(x: 20, y: 500, width: 240, height: 44)
        fixture.localInput.text = "Retained draft"
        scroll.addSubview(fixture.localInput)
        try #require(fixture.localInput.becomeFirstResponder())
        var visible: Bool?
        fixture.scope.onVisibilityChange = { visible = $0 }
        fixture.scope.scheduleVisibilityUpdate()
        try await waitForVisibility(true) { visible }

        // The retained content offset puts the caret behind the resized page's top bar.
        scroll.contentOffset.y = 520
        fixture.scope.frame = CGRect(x: 0, y: 60, width: 400, height: 240)
        fixture.scope.scheduleVisibilityUpdate()
        try await waitForVisibility(true) {
            guard let selection = fixture.localInput.selectedTextRange else { return false }
            let caret = fixture.localInput.caretRect(for: selection.end)
            return fixture.localInput.convert(caret, to: fixture.localController.view).minY >= 60
        }
        #expect(fixture.localInput.isFirstResponder)
        #expect(fixture.localInput.text == "Retained draft")
    }
}

@MainActor
private final class KeyboardToolbarWindowFixture {
    let window: UIWindow
    let root = UIViewController()
    let localController = UIViewController()
    let otherController = UIViewController()
    let scope = KeyboardToolbarScopeView()
    let localInput = UITextField(frame: CGRect(x: 20, y: 20, width: 160, height: 44))
    let otherInput = UITextField(frame: CGRect(x: 20, y: 20, width: 160, height: 44))
    private let previousKeyWindow: UIWindow?

    init() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        previousKeyWindow = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
        if let scene = previousKeyWindow?.windowScene ?? scenes.first {
            window = UIWindow(windowScene: scene)
        } else {
            window = UIWindow(frame: .zero)
        }
        window.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        window.rootViewController = root
        attach(localController, frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        attach(otherController, frame: CGRect(x: 400, y: 0, width: 400, height: 600))
        scope.frame = localController.view.bounds
        localController.view.addSubview(scope)
        localController.view.addSubview(localInput)
        otherController.view.addSubview(otherInput)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
    }

    func close() {
        root.dismiss(animated: false)
        window.endEditing(true)
        scope.stopObserving()
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
    }

    private func attach(_ controller: UIViewController, frame: CGRect) {
        root.addChild(controller)
        controller.view.frame = frame
        root.view.addSubview(controller.view)
        controller.didMove(toParent: root)
    }
}
