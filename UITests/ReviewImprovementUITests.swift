import XCTest
import UIKit

extension SitekeeperUITests {
    func testFileSearchOpensFileOnlyMatchAndKeepsIPadSelectionAfterRotation() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchApp(resetState: true, reviewRegressionFixture: true)
        tapPrimaryModule(app, name: "项目")
        XCTAssertTrue(app.staticTexts["Review Site A"].firstMatch.waitForExistence(timeout: 10))
        let browser = app.buttons["project-file-browser-entry"]
        XCTAssertTrue(browser.waitForExistence(timeout: 5))
        browser.tap()
        let search = app.textFields["搜索项目或资料文件"].firstMatch
        if UIDevice.current.userInterfaceIdiom == .pad, !search.exists {
            let sidebar = app.navigationBars["文件预览"].buttons["显示边栏"]
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
            sidebar.tap()
            let projectSidebar = app.navigationBars["文件分类"].buttons["显示边栏"]
            XCTAssertTrue(projectSidebar.waitForExistence(timeout: 5))
            projectSidebar.tap()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Acceptance")

        if UIDevice.current.userInterfaceIdiom == .pad {
            let result = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-file-result-")).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 10))
            result.tap()
            let selected = app.staticTexts["project-file-selected-title"]
            XCTAssertTrue(selected.waitForExistence(timeout: 5))
            XCTAssertEqual(selected.label, "Review Acceptance")
            XCUIDevice.shared.orientation = .landscapeLeft
            let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
            XCTAssertTrue(selected.isHittable)
            XCTAssertEqual(selected.label, "Review Acceptance")
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "File-only search selection iPad landscape"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            selected.tap()
            let preview = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-file-preview-")).firstMatch
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            preview.tap()
            assertPDFPreviewPagingAndClose(app)
        } else {
            let actions = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-file-actions-")).firstMatch
            XCTAssertTrue(actions.waitForExistence(timeout: 10))
            actions.tap()
            let preview = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "project-file-preview-")).firstMatch
            XCTAssertTrue(preview.waitForExistence(timeout: 10))
            preview.tap()
            assertPDFPreviewPagingAndClose(app)
            XCTAssertTrue(app.staticTexts["Review Acceptance"].firstMatch.waitForExistence(timeout: 5))
        }
    }

    private func assertPDFPreviewPagingAndClose(_ app: XCUIApplication) {
        let done = app.buttons["app-pdf-preview-close"]
        XCTAssertTrue(done.waitForExistence(timeout: 8))
        let page = app.staticTexts["pdf-preview-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertEqual(page.label, "1 / 2")
        XCTAssertFalse(app.buttons["pdf-preview-previous"].isEnabled)
        XCTAssertTrue(app.buttons["app-pdf-preview-share"].isEnabled)
        XCTAssertTrue(app.buttons["pdf-preview-search"].isEnabled)
        app.buttons["pdf-preview-next"].tap()
        let nextPage = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "2 / 2"), object: page)
        XCTAssertEqual(XCTWaiter.wait(for: [nextPage], timeout: 5), .completed)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .portrait
            let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.height > app.frame.width }, object: app)
            XCTAssertEqual(XCTWaiter.wait(for: [portrait], timeout: 5), .completed)
            XCTAssertEqual(page.label, "2 / 2")
            XCTAssertTrue(app.buttons["pdf-preview-search"].isHittable)
        }
        XCTAssertFalse(app.buttons["pdf-preview-next"].isEnabled)
        app.buttons["pdf-preview-previous"].tap()
        XCTAssertEqual(page.label, "1 / 2")
        attachScreenshot(app, named: "PDF preview with paging and share")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
    }

    func testQuotationKeyboardNavigationUsesVisibleFieldsForBothPriceModes() {
        let app = launchApp(resetState: true, reviewRegressionFixture: true)
        tapPrimaryModule(app, name: "工具箱")
        element(app, identifier: "预结算信息", scrollingAttempts: 12).tap()
        let more = app.buttons["更多操作"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        app.buttons["从材料/人工生成报价"].tap()
        let mode = app.buttons["quotation-material-price-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.tap()
        app.buttons["沿用材料单价（成本参考）"].tap()
        let labor = app.textFields["quotation-generate-labor-rate"]
        XCTAssertTrue(labor.waitForExistence(timeout: 5))
        labor.tap()
        XCTAssertTrue(app.buttons["keyboard-previous"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["keyboard-previous"].isEnabled)
        app.buttons["keyboard-next"].tap()
        XCTAssertTrue(app.buttons["keyboard-previous"].isEnabled)
        app.buttons["keyboard-previous"].tap()
        XCTAssertFalse(app.buttons["keyboard-previous"].isEnabled)
        app.buttons["keyboard-done"].tap()
        mode.tap()
        app.buttons["统一设置对外报价"].tap()
        let material = app.textFields["quotation-generate-material-price"]
        XCTAssertTrue(material.waitForExistence(timeout: 5))
        material.tap()
        XCTAssertTrue(app.buttons["keyboard-previous"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["keyboard-previous"].isEnabled)
        app.buttons["keyboard-next"].tap()
        XCTAssertTrue(app.buttons["keyboard-previous"].isEnabled)
        attachScreenshot(app, named: "Quotation visible-field keyboard navigation")
        app.buttons["keyboard-done"].tap()
        app.navigationBars["生成报价"].buttons["取消"].tap()
        XCTAssertFalse(app.buttons["keyboard-done"].exists)
    }

    func testMaterialLibraryRejectsZeroQuantityForSingleAndBatchAppend() {
        let app = launchApp(resetState: true, reviewRegressionFixture: true)
        tapPrimaryModule(app, name: "工具箱")
        element(app, identifier: "材料中心", scrollingAttempts: 12).tap()
        let library = app.segmentedControls.buttons["材料库"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        library.tap()
        let add = app.buttons["添加Review Copper到材料单"]
        XCTAssertTrue(waitForElementByScrollingDown(add, in: app, attempts: 20))
        add.tap()
        assertAppendQuantityValidation(app, identifier: "material-library-append-quantity")
        app.navigationBars.buttons["取消"].firstMatch.tap()

        let batch = app.buttons["material-library-batch-select"]
        XCTAssertTrue(batch.waitForExistence(timeout: 5))
        batch.tap()
        let material = app.staticTexts["Review Copper"].firstMatch
        XCTAssertTrue(material.waitForExistence(timeout: 5))
        material.tap()
        let append = app.buttons["material-library-batch-append"]
        XCTAssertTrue(append.isEnabled)
        append.tap()
        assertAppendQuantityValidation(app, identifier: "material-library-batch-quantity")
        app.navigationBars.buttons["取消"].firstMatch.tap()
    }

    private func assertAppendQuantityValidation(_ app: XCUIApplication, identifier: String) {
        let quantity = app.textFields[identifier]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        quantity.tap()
        quantity.typeText(XCUIKeyboardKey.delete.rawValue + "0")
        let save = app.buttons["business-form-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertFalse(save.isEnabled)
        quantity.typeText(XCUIKeyboardKey.delete.rawValue + "2")
        XCTAssertTrue(save.isEnabled)
        attachScreenshot(app, named: "Material quantity validation \(identifier)")
        app.buttons["keyboard-done"].tap()
    }
}
