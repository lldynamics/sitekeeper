import XCTest

@MainActor
final class RepositoryFinancialUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFinancialPagingStatusEditRestartAndOriginalIsolation() {
        let app = launch(reset: true)
        openLauncher(app)
        app.buttons["repository-workspace-create"].tap()
        openFinance(app)
        assertAmount(app, "income", "5.00")
        assertAmount(app, "expense", "0.60")
        assertAmount(app, "balance", "4.40")
        app.buttons["repository-page-next"].tap()
        XCTAssertTrue(app.staticTexts["第 2 页"].waitForExistence(timeout: 5))
        assertAmount(app, "income", "5.00")
        XCTAssertFalse(app.buttons["repository-page-next"].isEnabled)
        app.buttons["repository-page-previous"].tap()
        let newest = app.staticTexts["财务流水 052"]
        tapAfterScrolling(newest, app: app)
        let status = app.buttons["repository-finance-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        status.tap()
        app.buttons["草稿"].tap()
        app.buttons["repository-editor-save"].tap()
        assertAmount(app, "expense", "0.40")
        assertAmount(app, "balance", "4.60")
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "candidate-finance-after-status-save"
        image.lifetime = .keepAlways
        add(image)
        app.terminate()
        _ = launch(reset: false, app: app)
        openLauncher(app)
        let existing = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "repository-workspace-open-")).firstMatch
        XCTAssertTrue(existing.waitForExistence(timeout: 8))
        existing.tap()
        openFinance(app)
        assertAmount(app, "expense", "0.40")
        app.navigationBars["副本财务记录"].buttons["BackButton"].tap()
        app.navigationBars["副本施工日志"].buttons["BackButton"].tap()
        app.buttons["repository-workspace-close"].tap()
        app.buttons["repository-workspace-create"].tap()
        openFinance(app)
        assertAmount(app, "expense", "0.60")
    }

    func testCreateValidAmountSearchAndDirectionFilter() {
        let app = launch(reset: true)
        openLauncher(app)
        app.buttons["repository-workspace-create"].tap()
        openFinance(app)
        app.buttons["repository-finance-create"].tap()
        let amount = app.textFields["repository-finance-amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["repository-editor-save"].isEnabled)
        amount.tap()
        amount.typeText("0")
        XCTAssertTrue(app.staticTexts["repository-finance-amount-error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["repository-editor-save"].isEnabled)
        amount.typeText(XCUIKeyboardKey.delete.rawValue + "12.34")
        let counterparty = app.textFields["repository-finance-counterparty"]
        tapAfterScrolling(counterparty, app: app)
        counterparty.typeText("独立财务新增")
        app.buttons["repository-editor-save"].tap()
        assertAmount(app, "expense", "12.94")
        app.segmentedControls["repository-finance-direction-filter"].buttons["收入"].tap()
        assertAmount(app, "income", "5.00")
        assertAmount(app, "expense", "0.00")
        app.segmentedControls["repository-finance-direction-filter"].buttons["全部收支"].tap()
        app.swipeDown()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("独立财务新增")
        assertAmount(app, "expense", "12.34")
        XCTAssertTrue(app.staticTexts["共 1 条，正式记录 1 条"].exists)
        search.typeText("\n")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["独立财务新增"].waitForExistence(timeout: 5))
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "candidate-finance-filtered-summary"
        image.lifetime = .keepAlways
        add(image)
    }

    private func assertAmount(_ app: XCUIApplication, _ field: String, _ value: String) {
        let label = app.staticTexts["repository-finance-summary-\(field)"]
        let title = ["income": "正式收入", "expense": "正式支出", "balance": "收支差额"][field]!
        let predicate = NSPredicate(format: "exists == true AND label == %@", title + "、" + value)
        expectation(for: predicate, evaluatedWith: label)
        waitForExpectations(timeout: 10)
    }

    private func launch(reset: Bool, app: XCUIApplication = XCUIApplication()) -> XCUIApplication {
        app.launchArguments = ["-uitest-skip-onboarding", "-languageCode", "zh-Hans", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment = ["UITEST_SKIP_ONBOARDING": "1"]
        if reset { app.launchEnvironment.merge(["UITEST_RESET_STATE": "1", "UITEST_REPOSITORY_FIXTURE": "1", "UITEST_REPOSITORY_FINANCE_FIXTURE": "1"]) { _, new in new } }
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

    private func openFinance(_ app: XCUIApplication) {
        let project = app.staticTexts["分页工程 052"]
        XCTAssertTrue(project.waitForExistence(timeout: 30))
        project.tap()
        let entry = app.buttons["repository-finance-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()
        XCTAssertTrue(app.buttons["repository-finance-create"].waitForExistence(timeout: 8))
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
