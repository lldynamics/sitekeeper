import XCTest

extension SitekeeperUITests {
    func testQuickNotePDFPreviewSupportsSearchCloseAndReopen() {
        let app = launchApp(resetState: true, reviewRegressionFixture: true)
        tapPrimaryModule(app, name: "随手记")
        XCTAssertTrue(app.staticTexts["Review Preview Attachments"].waitForExistence(timeout: 10))
        let attachment = pdfAttachment(in: app, name: "Review Preview.pdf")
        attachment.tap()
        let page = app.staticTexts["pdf-preview-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        XCTAssertEqual(page.label, "1 / 2")
        app.buttons["pdf-preview-next"].tap()
        XCTAssertEqual(page.label, "2 / 2")
        app.buttons["pdf-preview-search"].tap()
        let find = app.descendants(matching: .any)["pdf-preview-search-input"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        find.tap()
        find.typeText("Page One\n")
        let results = app.staticTexts["pdf-preview-search-results"]
        XCTAssertTrue(results.waitForExistence(timeout: 5))
        XCTAssertEqual(results.label, "1 / 1")
        XCTAssertEqual(page.label, "1 / 2")
        attachScreenshot(app, named: "Quick note PDF text search")
        find.tap()
        find.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        find.typeText("NoSuchPDFMatch\n")
        XCTAssertEqual(results.label, "0 / 0")
        let close = app.buttons["quick-note-attachment-close"]
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(attachment.waitForExistence(timeout: 5))
        attachment.tap()
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        XCTAssertEqual(page.label, "1 / 2")
        app.buttons["quick-note-attachment-close"].tap()
    }

    func testCorruptPDFShowsFailureAndAnotherAttachmentStillOpens() {
        let app = launchApp(resetState: true, reviewRegressionFixture: true)
        tapPrimaryModule(app, name: "随手记")
        XCTAssertTrue(app.staticTexts["Review Preview Attachments"].waitForExistence(timeout: 10))
        pdfAttachment(in: app, name: "Review Broken.pdf").tap()
        let message = app.staticTexts["pdf-preview-error"]
        XCTAssertTrue(message.waitForExistence(timeout: 8))
        XCTAssertEqual(message.label, "无法预览 PDF，文件可能已丢失或损坏。")
        XCTAssertFalse(app.buttons["pdf-preview-search"].isEnabled)
        XCTAssertFalse(app.buttons["pdf-preview-next"].isEnabled)
        attachScreenshot(app, named: "Corrupt PDF failure state")
        app.buttons["quick-note-attachment-close"].tap()
        pdfAttachment(in: app, name: "Review Preview.pdf").tap()
        let page = app.staticTexts["pdf-preview-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        XCTAssertEqual(page.label, "1 / 2")
        app.buttons["quick-note-attachment-close"].tap()
    }

    private func pdfAttachment(in app: XCUIApplication, name: String) -> XCUIElement {
        let attachment = app.buttons.matching(NSPredicate(format: "value CONTAINS %@", name)).firstMatch
        XCTAssertTrue(attachment.waitForExistence(timeout: 5))
        return attachment
    }
}
