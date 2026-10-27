import XCTest
import UIKit

extension SitekeeperUITests {
    func testDrawingReferenceAndIssueRemainLinkedAfterSaveAndRestart() {
        var app = launchApp(resetState: true, duoWorkflowFixture: true)
        openDuoDrawingIssue(app)
        showReviewPane(app, title: "图纸")
        let page = app.staticTexts["pdf-preview-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["pdf-preview-next"].isHittable)
        app.buttons["pdf-preview-next"].tap()
        XCTAssertEqual(page.label, "2 / 3")
        app.buttons["drawing-reference-page"].tap()
        showReviewPane(app, title: "记录问题")
        let content = app.descendants(matching: .any)["drawing-issue-description"].firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        app.typeText("Duo linked inspection")
        if app.buttons["keyboard-done"].isHittable { app.buttons["keyboard-done"].tap() }
        let reference = element(app, identifier: "drawing-issue-page", scrollingAttempts: 8)
        XCTAssertEqual(reference.value as? String, "第 2 页")
        attachScreenshot(app, named: "Drawing reference and issue editor")
        app.buttons["drawing-issue-save"].tap()
        XCTAssertTrue(app.navigationBars["新建问题"].waitForNonExistence(timeout: 8))
        app.terminate()
        app = launchApp(duoWorkflowFixture: true)
        openDuoDrawingDetail(app)
        let savedNote = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Duo linked inspection")).firstMatch
        XCTAssertTrue(waitForElementByScrollingDown(savedNote, in: app, attempts: 10))
        XCTAssertTrue(savedNote.label.contains("DUO-PDF-001"))
        XCTAssertTrue(savedNote.label.contains("第 2 页"))
        attachScreenshot(app, named: "Drawing issue persisted with its source")
    }

    func testMaterialReviewUpdatesTotalAndPersistsEditedQuantity() {
        verifyMaterialReview(dynamicType: nil)
    }

    func testMaterialReviewRemainsUsableWithAccessibilityText() {
        verifyMaterialReview(dynamicType: "accessibility3")
    }

    func testDuoDrawingIssueSurvivesNativeFoldCycle() throws {
        try requireDuoFoldSession()
        let app = launchApp(resetState: true, duoWorkflowFixture: true)
        openDuoDrawingIssue(app)
        showReviewPane(app, title: "图纸")
        let page = app.staticTexts["pdf-preview-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        app.buttons["pdf-preview-next"].tap()
        XCTAssertEqual(page.label, "2 / 3")
        app.buttons["drawing-reference-page"].tap()
        showReviewPane(app, title: "记录问题")
        let content = app.descendants(matching: .any)["drawing-issue-description"].firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        app.typeText("Folded issue")
        let width = app.frame.width
        try waitForDuoResize(content, app: app, stage: "drawing-workspace-expand")
        XCTAssertEqual(content.value as? String, "Folded issue")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText(" expanded")
        try waitForDuoResize(content, app: app, stage: "drawing-workspace-fold", returningToWidth: width)
        XCTAssertEqual(content.value as? String, "Folded issue expanded")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText(" retained")
        XCTAssertEqual(content.value as? String, "Folded issue expanded retained")
        app.buttons["keyboard-done"].tap()
        showReviewPane(app, title: "图纸")
        XCTAssertEqual(page.label, "2 / 3")
        showReviewPane(app, title: "记录问题")
        let reference = element(app, identifier: "drawing-issue-page", scrollingAttempts: 8)
        XCTAssertEqual(reference.value as? String, "第 2 页")
        app.buttons["drawing-issue-save"].tap()
        XCTAssertTrue(app.navigationBars["新建问题"].waitForNonExistence(timeout: 8))
    }

    func testDuoMaterialQuantitySurvivesNativeFoldCycle() throws {
        try requireDuoFoldSession()
        let app = launchApp(resetState: true, duoWorkflowFixture: true)
        let quantity = openDuoMaterialQuantity(app)
        quantity.tap()
        app.typeText("5")
        let width = app.frame.width
        try waitForDuoResize(quantity, app: app, stage: "material-workspace-expand")
        XCTAssertEqual(quantity.value as? String, "25")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText("0")
        app.buttons["keyboard-done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["review-workspace-columns"].exists)
        XCTAssertTrue(app.buttons["material-sheet-more-menu"].isHittable)
        XCTAssertTrue(app.buttons["material-sheet-create"].isHittable)
        quantity.tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(quantity.isHittable)
        try waitForDuoResize(quantity, app: app, stage: "material-workspace-fold", returningToWidth: width)
        XCTAssertEqual(quantity.value as? String, "250")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText("0")
        XCTAssertEqual(quantity.value as? String, "2500")
        app.buttons["keyboard-done"].tap()
        showReviewPane(app, title: "核对明细")
        if !app.otherElements["review-workspace-columns"].exists { XCTAssertFalse(quantity.isHittable) }
        XCTAssertTrue(app.staticTexts["2500 m"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Material quantity and review survived native fold")
        XCTAssertTrue(app.buttons["material-sheet-create"].isHittable)
        let more = app.buttons["material-sheet-more-menu"]
        XCTAssertTrue(more.isHittable)
        more.tap()
        XCTAssertTrue(app.buttons["导出 PDF"].waitForExistence(timeout: 5))
    }

    private func verifyMaterialReview(dynamicType: String?) {
        var app = launchApp(resetState: true, dynamicTypeSize: dynamicType, duoWorkflowFixture: true)
        let quantity = openDuoMaterialQuantity(app)
        quantity.tap()
        app.typeText(XCUIKeyboardKey.delete.rawValue + "3")
        XCTAssertEqual(quantity.value as? String, "3")
        app.buttons["keyboard-done"].tap()
        showReviewPane(app, title: "核对明细")
        if !app.otherElements["review-workspace-columns"].exists { XCTAssertFalse(quantity.isHittable) }
        XCTAssertTrue(app.staticTexts["3 m"].waitForExistence(timeout: 5))
        let total = app.descendants(matching: .any)["material-review-total"].firstMatch
        XCTAssertTrue(total.isHittable)
        XCTAssertTrue(total.label.contains("42.50"), total.label)
        attachScreenshot(app, named: "Material review and sticky total \(dynamicType ?? "default")")
        app.terminate()
        app = launchApp(dynamicTypeSize: dynamicType, duoWorkflowFixture: true)
        XCTAssertEqual(openDuoMaterialQuantity(app).value as? String, "3")
    }

    private func openDuoMaterialQuantity(_ app: XCUIApplication) -> XCUIElement {
        tapPrimaryModule(app, name: "工具箱")
        element(app, identifier: "材料中心", scrollingAttempts: 12).tap()
        app.segmentedControls.buttons["材料单"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Duo Copper")).firstMatch
        XCTAssertTrue(waitForElementByScrollingDown(row, in: app, attempts: 12))
        row.tap()
        let field = app.textFields["material-quantity-71000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(waitForElementByScrollingDown(field, in: app, attempts: 8))
        return field
    }

    private func openDuoDrawingDetail(_ app: XCUIApplication) {
        tapPrimaryModule(app, name: "项目")
        XCTAssertTrue(app.staticTexts["Duo Workflow Site"].firstMatch.waitForExistence(timeout: 12))
        tapPrimaryModule(app, name: "工作台")
        let search = app.textFields["搜索项目、票号、报价、图纸或资料"]
        if !search.isHittable { app.swipeDown() }
        search.tap()
        search.typeText("DUO-PDF-001\n")
        let result = app.buttons["search-suggestion-drawing-71000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.tap()
        XCTAssertTrue(app.navigationBars["图纸详情"].waitForExistence(timeout: 8))
    }

    private func openDuoDrawingIssue(_ app: XCUIApplication) {
        openDuoDrawingDetail(app)
        element(app, identifier: "drawing-review-open", scrollingAttempts: 12).tap()
        XCTAssertTrue(app.navigationBars["新建问题"].waitForExistence(timeout: 8))
    }

    private func showReviewPane(_ app: XCUIApplication, title: String) {
        let selector = app.segmentedControls.containing(.button, identifier: title).firstMatch
        if selector.exists {
            let button = selector.buttons[title]
            XCTAssertTrue(button.isHittable)
            button.tap()
            XCTAssertTrue(button.isSelected)
        } else {
            XCTAssertTrue(app.otherElements["review-workspace-columns"].exists)
        }
    }
}
