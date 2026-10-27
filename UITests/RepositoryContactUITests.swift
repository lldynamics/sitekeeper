import XCTest

@MainActor
final class RepositoryContactUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPagingEditingRestartAndOriginalIsolation() {
        let app = launch(reset: true)
        openLauncher(app)
        app.buttons["repository-workspace-create"].tap()
        openContacts(app)
        XCTAssertTrue(app.staticTexts["候选联系人 000"].waitForExistence(timeout: 8))
        app.buttons["repository-page-next"].tap()
        XCTAssertTrue(app.staticTexts["第 2 页"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["候选联系人 052"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["repository-page-next"].isEnabled)
        app.buttons["repository-page-previous"].tap()
        tapAfterScrolling(app.staticTexts["候选联系人 000"], app: app)
        let phone = app.textFields["repository-contact-phone"]
        XCTAssertTrue(phone.waitForExistence(timeout: 5))
        replace("010-98765432", in: phone, app: app)
        XCTAssertTrue(app.staticTexts["保留主项目及 1 个其他项目关联"].exists)
        app.buttons["repository-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["010-98765432"].waitForExistence(timeout: 8))
        attach(app, "candidate-contact-edited")
        app.terminate()
        _ = launch(reset: false, app: app)
        openLauncher(app)
        let existing = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "repository-workspace-open-")).firstMatch
        XCTAssertTrue(existing.waitForExistence(timeout: 8))
        existing.tap()
        openContacts(app)
        XCTAssertTrue(app.staticTexts["010-98765432"].waitForExistence(timeout: 8))
        app.navigationBars["副本往来单位"].buttons["BackButton"].tap()
        app.navigationBars["副本施工日志"].buttons["BackButton"].tap()
        app.buttons["repository-workspace-close"].tap()
        app.buttons["repository-workspace-create"].tap()
        openContacts(app)
        tapAfterScrolling(app.staticTexts["候选联系人 000"], app: app)
        XCTAssertTrue(phone.waitForExistence(timeout: 5))
        XCTAssertEqual(phone.value as? String, "00000000000")
    }

    func testCreateSearchRoleAndAllProjectScope() {
        let app = launch(reset: true)
        openLauncher(app)
        app.buttons["repository-workspace-create"].tap()
        openContacts(app)
        app.buttons["repository-contact-create"].tap()
        let name = app.textFields["repository-contact-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["repository-editor-save"].isEnabled)
        replace("独立新增联系人", in: name, app: app)
        replace("独立新增单位", in: app.textFields["repository-contact-company"], app: app)
        replace("021-12345678", in: app.textFields["repository-contact-phone"], app: app)
        app.buttons["repository-editor-save"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("021-12345678\n")
        XCTAssertTrue(app.staticTexts["独立新增联系人"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["独立新增单位"].exists)
        attach(app, "candidate-contact-search")
        search.tap()
        search.buttons["清除文本"].tap()
        finishSearch(app)
        for _ in 0..<3 { app.swipeDown() }
        app.buttons["repository-contact-role-filter"].tap()
        app.buttons["供应商"].tap()
        XCTAssertTrue(app.staticTexts["候选联系人 000"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["独立新增联系人"].exists)
        XCTAssertFalse(app.buttons["repository-page-next"].isEnabled)
        app.navigationBars["副本往来单位"].buttons["BackButton"].tap()
        app.navigationBars["副本施工日志"].buttons["BackButton"].tap()
        tapAfterScrolling(app.buttons["repository-all-contacts-entry"], app: app)
        XCTAssertTrue(app.staticTexts["新增往来单位请先进入对应项目。"].waitForExistence(timeout: 5))
        let allSearch = app.searchFields.firstMatch
        allSearch.tap()
        allSearch.typeText("其他项目联系人\n")
        XCTAssertTrue(app.staticTexts["其他项目联系人"].waitForExistence(timeout: 8))
    }

    private func replace(_ value: String, in field: XCUIElement, app: XCUIApplication) {
        focus(field, app: app)
        let old = field.value as? String ?? ""
        let count = old == field.placeholderValue ? 0 : old.count
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + value)
        XCTAssertEqual(field.value as? String, value)
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

    private func dismissNumberPad(_ app: XCUIApplication) {
        let dismissRegion = app.otherElements["PopoverDismissRegion"]
        if dismissRegion.exists {
            dismissRegion.tap()
            XCTAssertTrue(dismissRegion.waitForNonExistence(timeout: 5))
        }
    }

    private func finishSearch(_ app: XCUIApplication) {
        let navigation = app.navigationBars["副本往来单位"]
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
        if reset { app.launchEnvironment.merge(["UITEST_RESET_STATE": "1", "UITEST_REPOSITORY_FIXTURE": "1", "UITEST_REPOSITORY_CONTACTS_FIXTURE": "1"]) { _, new in new } }
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

    private func openContacts(_ app: XCUIApplication) {
        let project = app.staticTexts["分页工程 052"]
        XCTAssertTrue(project.waitForExistence(timeout: 30))
        project.tap()
        let entry = app.buttons["repository-contacts-entry"]
        tapAfterScrolling(entry, app: app)
        XCTAssertTrue(app.buttons["repository-contact-create"].waitForExistence(timeout: 8))
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
