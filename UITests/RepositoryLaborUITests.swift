import XCTest

@MainActor
final class RepositoryLaborUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPagingEditRestartAndOriginalIsolation() {
        let app = launch(reset: true)
        openLauncher(app)
        app.buttons["repository-workspace-create"].tap()
        openLabor(app)
        assertTotal(app, "1060.00")
        app.buttons["repository-page-next"].tap()
        XCTAssertTrue(app.staticTexts["第 2 页"].waitForExistence(timeout: 5))
        assertTotal(app, "1060.00")
        XCTAssertFalse(app.buttons["repository-page-next"].isEnabled)
        app.buttons["repository-page-previous"].tap()
        tapAfterScrolling(app.staticTexts["候选人工 052"], app: app)
        let rate = app.textFields["repository-labor-rate"]
        XCTAssertTrue(rate.waitForExistence(timeout: 5))
        enterNumber("20", into: rate, app: app)
        app.buttons["repository-editor-save"].tap()
        assertTotal(app, "1080.00")
        for _ in 0..<3 { app.swipeDown() }
        app.buttons["repository-labor-unit-filter"].tap()
        app.buttons["天"].tap()
        assertTotal(app, "40.00")
        attach(app, "candidate-labor-workday-summary")
        app.terminate()
        _ = launch(reset: false, app: app)
        openLauncher(app)
        let existing = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "repository-workspace-open-")).firstMatch
        XCTAssertTrue(existing.waitForExistence(timeout: 8))
        existing.tap()
        openLabor(app)
        assertTotal(app, "1080.00")
        app.navigationBars["副本人工记录"].buttons["BackButton"].tap()
        app.navigationBars["副本施工日志"].buttons["BackButton"].tap()
        app.buttons["repository-workspace-close"].tap()
        app.buttons["repository-workspace-create"].tap()
        openLabor(app)
        assertTotal(app, "1060.00")
    }

    func testCreateExactAmountSearchSettlementAndUnassigned() {
        let app = launch(reset: true)
        openLauncher(app)
        app.buttons["repository-workspace-create"].tap()
        openLabor(app)
        app.buttons["repository-labor-create"].tap()
        let team = app.textFields["repository-labor-team"]
        XCTAssertTrue(team.waitForExistence(timeout: 5))
        focus(team, app: app)
        team.typeText("独立人工新增")
        enterNumber("2", into: app.textFields["repository-labor-workers"], app: app)
        XCTAssertFalse(app.buttons["repository-editor-save"].isEnabled)
        enterNumber("0.3", into: app.textFields["repository-labor-hours"], app: app)
        enterNumber("0.1", into: app.textFields["repository-labor-rate"], app: app)
        app.buttons["repository-editor-save"].tap()
        assertTotal(app, "1060.06")
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("独立人工新增\n")
        assertTotal(app, "0.06")
        attach(app, "candidate-labor-exact-amount")
        search.tap()
        let clear = search.buttons["清除文本"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        finishSearch(app)
        assertTotal(app, "1060.06")
        for _ in 0..<3 { app.swipeDown() }
        app.buttons["repository-labor-settled-filter"].tap()
        app.buttons["已结算"].tap()
        assertTotal(app, "20.00")
        app.navigationBars["副本人工记录"].buttons["BackButton"].tap()
        app.navigationBars["副本施工日志"].buttons["BackButton"].tap()
        tapAfterScrolling(app.buttons["repository-unassigned-labor-entry"], app: app)
        assertTotal(app, "5.00")
    }

    private func assertTotal(_ app: XCUIApplication, _ value: String) {
        let label = app.staticTexts["repository-labor-total"]
        if !label.exists { app.swipeUp() }
        expectation(for: NSPredicate(format: "exists == true AND label == %@", "合计人工费、" + value), evaluatedWith: label)
        waitForExpectations(timeout: 10)
    }

    private func focus(_ field: XCUIElement, app: XCUIApplication, acceptsNumberPad: Bool = false) {
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

    private func enterNumber(_ value: String, into field: XCUIElement, app: XCUIApplication) {
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

    private func dismissNumberPad(_ app: XCUIApplication) {
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        if dismissRegion.exists {
            dismissRegion.tap()
            XCTAssertTrue(dismissRegion.waitForNonExistence(timeout: 5))
        }
    }

    private func finishSearch(_ app: XCUIApplication) {
        let navigation = app.navigationBars["副本人工记录"]
        // Compact search replaces the navigation bar; regular-width search
        // keeps it visible and may have no dismiss button at all.
        if !navigation.waitForExistence(timeout: 1) {
            let close = app.buttons["关闭"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            close.tap()
        }
        XCTAssertTrue(navigation.waitForExistence(timeout: 5))
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    private func launch(reset: Bool, app: XCUIApplication = XCUIApplication()) -> XCUIApplication {
        app.launchArguments = ["-uitest-skip-onboarding", "-languageCode", "zh-Hans", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment = ["UITEST_SKIP_ONBOARDING": "1"]
        if reset { app.launchEnvironment.merge(["UITEST_RESET_STATE": "1", "UITEST_REPOSITORY_FIXTURE": "1", "UITEST_REPOSITORY_LABOR_FIXTURE": "1"]) { _, new in new } }
        app.launch()
        return app
    }

    private func openLauncher(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["我的"]
        let profile = tab.exists ? tab : app.buttons["primary-module-profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 10))
        profile.tap()
        tapAfterScrolling(app.buttons["profile-settings-link"], app: app)
        tapAfterScrolling(app.buttons["repository-workspace-entry"], app: app)
        XCTAssertTrue(app.buttons["repository-workspace-create"].waitForExistence(timeout: 8))
    }

    private func openLabor(_ app: XCUIApplication) {
        let project = app.staticTexts["分页工程 052"]
        XCTAssertTrue(project.waitForExistence(timeout: 30))
        project.tap()
        let entry = app.buttons["repository-labor-entry"]
        tapAfterScrolling(entry, app: app)
        XCTAssertTrue(app.buttons["repository-labor-create"].waitForExistence(timeout: 8))
    }

    private func tapAfterScrolling(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { element.tap()
            return }
            app.swipeUp()
        }
        XCTFail("Missing entry: \(element)")
    }
}
