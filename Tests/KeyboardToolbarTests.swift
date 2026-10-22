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
