import XCTest

@MainActor
class RepositoryUITestCase: XCTestCase {
    func openLauncher(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["我的"]
        let profile = tab.exists ? tab : app.buttons["primary-module-profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()
        tapAfterScrolling(app.buttons["profile-settings-link"], app: app)
        tapAfterScrolling(app.buttons["repository-workspace-entry"], app: app)
        XCTAssertTrue(app.buttons["repository-workspace-create"].waitForExistence(timeout: 8))
    }

    func tapAfterScrolling(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable {
                element.tap()
                return
            }
            app.swipeUp()
        }
        XCTFail("Missing entry: \(element)")
    }

    func focus(_ field: XCUIElement, app: XCUIApplication, acceptsNumberPad: Bool = false) {
        // The iPad decimal keyboard preview owns accessibility focus and can
        // intercept the first tap on the next field. Dismiss it explicitly.
        dismissNumberPad(app)
        tapAfterScrolling(field, app: app)
        let focused = NSPredicate { _, _ in
            field.debugDescription.split(separator: "\n").first?.contains("Keyboard Focused") == true
                || (acceptsNumberPad && app.popovers.keys["1"].exists)
        }
        let ready = XCTNSPredicateExpectation(predicate: focused, object: field)
        if XCTWaiter.wait(for: [ready], timeout: 3) == .completed { return }
        field.tap()
        let retry = XCTNSPredicateExpectation(predicate: focused, object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [retry], timeout: 3), .completed, "Input did not focus: \(field.identifier)")
    }

    func enterNumber(_ value: String, into field: XCUIElement, app: XCUIApplication) {
        focus(field, app: app, acceptsNumberPad: true)
        let previous = field.value as? String ?? ""
        let count = previous == field.placeholderValue ? 0 : previous.count
        if app.popovers.keys["1"].exists {
            // Exercise the visible floating keypad rather than requiring a
            // full keyboard's focus flag from the underlying text field.
            for _ in 0..<count { app.popovers.keys["Delete"].tap() }
            for digit in value { app.popovers.keys[String(digit)].tap() }
        } else {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + value)
        }
        let entered = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [entered], timeout: 5), .completed, "Unexpected input: \(field.identifier)")
        dismissNumberPad(app)
    }

    func dismissNumberPad(_ app: XCUIApplication) {
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        if dismissRegion.exists {
            dismissRegion.tap()
            XCTAssertTrue(dismissRegion.waitForNonExistence(timeout: 5))
        }
    }
}
