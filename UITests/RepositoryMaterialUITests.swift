import XCTest

@MainActor
final class RepositoryMaterialUITests: RepositoryUITestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testMaterialPagingEditRestartAndOriginalIsolation() {
        let app = launch(reset: true)
        openLauncher(app)
        app.buttons["repository-workspace-create"].tap()
        openMaterials(app)
        assertTotal(app, "26.50")
        app.buttons["repository-page-next"].tap()
        XCTAssertTrue(app.staticTexts["第 2 页"].waitForExistence(timeout: 5))
        assertTotal(app, "26.50")
        XCTAssertFalse(app.buttons["repository-page-next"].isEnabled)
        app.buttons["repository-page-previous"].tap()
        tapAfterScrolling(app.staticTexts["清单材料 052"], app: app)
        let price = app.textFields["repository-material-price"]
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        price.tap()
        price.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 3) + "0.4")
        app.buttons["repository-editor-save"].tap()
        assertTotal(app, "27.00")
        attachScreenshot(app, named: "candidate-materials-edited-total")
        app.terminate()
        _ = launch(reset: false, app: app)
        openLauncher(app)
        let existing = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "repository-workspace-open-")).firstMatch
        XCTAssertTrue(existing.waitForExistence(timeout: 8))
        existing.tap()
        openMaterials(app)
        assertTotal(app, "27.00")
        app.navigationBars["副本材料清单"].buttons["BackButton"].tap()
        app.navigationBars["副本施工日志"].buttons["BackButton"].tap()
        app.buttons["repository-workspace-close"].tap()
        app.buttons["repository-workspace-create"].tap()
        openMaterials(app)
        assertTotal(app, "26.50")
    }

    func testCreateValidationSearchStatusAndUnassignedMaterials() {
        let app = launch(reset: true)
        openLauncher(app)
        app.buttons["repository-workspace-create"].tap()
        openMaterials(app)
        app.buttons["repository-material-create"].tap()
        let name = app.textFields["repository-material-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("独立材料新增")
        let unit = app.textFields["repository-material-unit"]
        unit.tap()
        unit.typeText("米")
        let quantity = app.textFields["repository-material-quantity"]
        quantity.tap()
        XCTAssertFalse(app.buttons["repository-editor-save"].isEnabled)
        quantity.typeText("0")
        XCTAssertTrue(app.buttons["repository-editor-save"].isEnabled)
        quantity.typeText(".")
        XCTAssertFalse(app.buttons["repository-editor-save"].isEnabled)
        quantity.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "0.3")
        app.buttons["repository-editor-save"].tap()
        assertTotal(app, "金额待核对")
        app.swipeDown()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("独立材料新增\n")
        tapAfterScrolling(app.staticTexts["独立材料新增"], app: app)
        let price = app.textFields["repository-material-price"]
        price.tap()
        price.typeText("0.1")
        app.buttons["repository-editor-save"].tap()
        assertTotal(app, "0.03")
        attachScreenshot(app, named: "candidate-materials-filtered-total")
        let closeSearch = app.buttons["关闭"]
        if closeSearch.exists { closeSearch.tap() }
        else {
            let clearSearch = app.searchFields.firstMatch.buttons["清除文本"]
            XCTAssertTrue(clearSearch.waitForExistence(timeout: 5))
            clearSearch.tap()
        }
        assertTotal(app, "26.53")
        app.swipeDown()
        app.buttons["repository-material-status-filter"].tap()
        app.buttons["已进场"].tap()
        assertTotal(app, "0.50")
        app.navigationBars["副本材料清单"].buttons["BackButton"].tap()
        app.navigationBars["副本施工日志"].buttons["BackButton"].tap()
        tapAfterScrolling(app.buttons["repository-unassigned-material-entry"], app: app)
        assertTotal(app, "金额待核对")
        tapAfterScrolling(app.staticTexts["未关联材料"], app: app)
        XCTAssertTrue(app.textFields["repository-material-name"].waitForExistence(timeout: 5))
    }

    private func assertTotal(_ app: XCUIApplication, _ value: String) {
        let label = app.staticTexts["repository-material-total"]
        expectation(for: NSPredicate(format: "exists == true AND label == %@", "材料总额、" + value), evaluatedWith: label)
        waitForExpectations(timeout: 10)
    }

    private func launch(reset: Bool, app: XCUIApplication = XCUIApplication()) -> XCUIApplication {
        app.launchArguments = ["-uitest-skip-onboarding", "-languageCode", "zh-Hans", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment = ["UITEST_SKIP_ONBOARDING": "1"]
        if reset { app.launchEnvironment.merge(["UITEST_RESET_STATE": "1", "UITEST_REPOSITORY_FIXTURE": "1", "UITEST_REPOSITORY_MATERIAL_FIXTURE": "1"]) { _, new in new } }
        app.launch()
        return app
    }

    private func openMaterials(_ app: XCUIApplication) {
        let project = app.staticTexts["分页工程 052"]
        XCTAssertTrue(project.waitForExistence(timeout: 30))
        project.tap()
        let entry = app.buttons["repository-material-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        tapAfterScrolling(entry, app: app)
        XCTAssertTrue(app.buttons["repository-material-create"].waitForExistence(timeout: 8))
    }
}
