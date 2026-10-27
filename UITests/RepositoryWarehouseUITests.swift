import XCTest

@MainActor
final class RepositoryWarehouseUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPagingEditingStockRestartAndOriginalIsolation() {
        let app = launch(reset: true)
        openLauncher(app)
        app.buttons["repository-workspace-create"].tap()
        openWarehouse(app)
        app.buttons["repository-page-next"].tap()
        XCTAssertTrue(app.staticTexts["第 2 页"].waitForExistence(timeout: 5))
        app.buttons["repository-page-next"].tap()
        XCTAssertTrue(app.staticTexts["第 3 页"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["repository-page-next"].isEnabled)
        app.buttons["repository-page-previous"].tap()
        XCTAssertTrue(app.staticTexts["第 2 页"].waitForExistence(timeout: 5))
        app.buttons["repository-page-previous"].tap()
        XCTAssertTrue(app.staticTexts["第 1 页"].waitForExistence(timeout: 5))
        app.buttons["repository-stock-entry"].tap()
        XCTAssertTrue(app.staticTexts["匹配库存材料 53 种"].waitForExistence(timeout: 8))
        app.buttons["repository-stock-next"].tap()
        XCTAssertTrue(app.staticTexts["第 2 页"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["repository-stock-next"].isEnabled)
        XCTAssertTrue(app.staticTexts["库存 2.00"].firstMatch.waitForExistence(timeout: 5))
        app.navigationBars["副本库存汇总"].buttons["BackButton"].tap()
        let newest = app.staticTexts["仓储材料 052"].firstMatch
        XCTAssertTrue(newest.waitForExistence(timeout: 5))
        newest.tap()
        let type = app.segmentedControls["repository-warehouse-type"]
        XCTAssertTrue(type.waitForExistence(timeout: 5))
        type.buttons["入库"].tap()
        app.buttons["repository-editor-save"].tap()
        XCTAssertTrue(app.buttons["repository-stock-entry"].waitForExistence(timeout: 8))
        app.buttons["repository-stock-entry"].tap()
        searchStock(app, "仓储材料 052", balance: "3.00")
        capture(app, "candidate-stock-after-edit")
        app.terminate()
        _ = launch(reset: false, app: app)
        openLauncher(app)
        let existing = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "repository-workspace-open-")).firstMatch
        XCTAssertTrue(existing.waitForExistence(timeout: 8))
        existing.tap()
        openWarehouse(app)
        app.buttons["repository-stock-entry"].tap()
        searchStock(app, "仓储材料 052", balance: "3.00")
        clearSearch(app)
        app.navigationBars["副本库存汇总"].buttons["BackButton"].tap()
        app.navigationBars["副本仓储流水"].buttons["BackButton"].tap()
        app.navigationBars["副本施工日志"].buttons["BackButton"].tap()
        app.buttons["repository-workspace-close"].tap()
        app.buttons["repository-workspace-create"].tap()
        openWarehouse(app)
        app.buttons["repository-stock-entry"].tap()
        searchStock(app, "仓储材料 052", balance: "2.00")
    }

    func testNewMovementValidationDirectionFilterAndNegativeInventory() {
        let app = launch(reset: true)
        openLauncher(app)
        app.buttons["repository-workspace-create"].tap()
        openWarehouse(app)
        app.buttons["repository-warehouse-create"].tap()
        let name = app.textFields["repository-warehouse-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        app.segmentedControls["repository-warehouse-type"].buttons["出库"].tap()
        name.tap()
        name.typeText("独立仓储新增")
        let unit = app.textFields["repository-warehouse-unit"]
        unit.tap()
        unit.typeText("卷")
        let quantity = app.textFields["repository-warehouse-quantity"]
        quantity.tap()
        quantity.typeText("0")
        XCTAssertTrue(app.staticTexts["repository-warehouse-quantity-error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["repository-editor-save"].isEnabled)
        quantity.typeText(XCUIKeyboardKey.delete.rawValue + "1.25")
        app.buttons["repository-editor-save"].tap()
        let filter = app.segmentedControls["repository-warehouse-type-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 8))
        filter.buttons["入库"].tap()
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("独立仓储新增")
        XCTAssertTrue(app.staticTexts["没有匹配记录"].waitForExistence(timeout: 5))
        search.typeText("\n")
        filter.buttons["出库"].tap()
        XCTAssertTrue(app.staticTexts["独立仓储新增"].waitForExistence(timeout: 5))
        clearSearch(app)
        app.buttons["repository-stock-entry"].tap()
        searchStock(app, "独立仓储新增", balance: "-1.25")
        XCTAssertTrue(app.staticTexts["负库存，请核对出入库记录。"].exists)
        capture(app, "candidate-stock-negative-quantity")
    }

    private func clearSearch(_ app: XCUIApplication) {
        let closeSearch = app.buttons["关闭"]
        if closeSearch.exists { closeSearch.tap() }
        else {
            let clearSearch = app.searchFields.firstMatch.buttons["清除文本"]
            XCTAssertTrue(clearSearch.waitForExistence(timeout: 5))
            clearSearch.tap()
        }
    }

    private func searchStock(_ app: XCUIApplication, _ text: String, balance: String) {
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        search.tap()
        search.typeText(text)
        XCTAssertTrue(app.staticTexts["匹配库存材料 1 种"].waitForExistence(timeout: 8))
        search.typeText("\n")
        XCTAssertTrue(app.staticTexts["库存 " + balance].waitForExistence(timeout: 8))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(reset: Bool, app: XCUIApplication = XCUIApplication()) -> XCUIApplication {
        app.launchArguments = ["-uitest-skip-onboarding", "-languageCode", "zh-Hans", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment = ["UITEST_SKIP_ONBOARDING": "1"]
        if reset { app.launchEnvironment.merge(["UITEST_RESET_STATE": "1", "UITEST_REPOSITORY_FIXTURE": "1", "UITEST_REPOSITORY_WAREHOUSE_FIXTURE": "1"]) { _, new in new } }
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

    private func openWarehouse(_ app: XCUIApplication) {
        let project = app.staticTexts["分页工程 052"]
        XCTAssertTrue(project.waitForExistence(timeout: 30))
        project.tap()
        let entry = app.buttons["repository-warehouse-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()
        XCTAssertTrue(app.buttons["repository-warehouse-create"].waitForExistence(timeout: 8))
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
