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

    func testPDFSearchKeepsQueryResultsAndKeyboardAcrossRotation() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchApp(resetState: true, reviewRegressionFixture: true)
        tapPrimaryModule(app, name: "随手记")
        pdfAttachment(in: app, name: "Review Preview.pdf").tap()
        let page = app.staticTexts["pdf-preview-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        app.buttons["pdf-preview-search"].tap()
        let find = app.descendants(matching: .any)["pdf-preview-search-input"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        find.tap()
        find.typeText("Page One\n")
        let results = app.staticTexts["pdf-preview-search-results"]
        XCTAssertEqual(results.label, "1 / 1")
        find.tap()
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            rotateAndVerifySupportedSceneGeometry(app, to: orientation)
            XCTAssertEqual(find.value as? String, "Page One")
            XCTAssertEqual(results.label, "1 / 1")
            XCTAssertEqual(page.label, "1 / 2")
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            attachScreenshot(app, named: "PDF query and page retained after device orientation change")
        }
        find.tap()
        find.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        find.typeText("NoSuchPDFMatch\n")
        XCTAssertEqual(results.label, "0 / 0")
        let close = app.buttons["quick-note-attachment-close"]
        XCTAssertTrue(close.isHittable)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        pdfAttachment(in: app, name: "Review Preview.pdf").tap()
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        XCTAssertEqual(page.label, "1 / 2")
        app.buttons["quick-note-attachment-close"].tap()
    }

    func testDuoPDFSearchSurvivesNativeFoldCycle() throws {
        try requireDuoFoldSession()
        let app = launchApp(resetState: true, reviewRegressionFixture: true)
        tapPrimaryModule(app, name: "随手记")
        pdfAttachment(in: app, name: "Review Preview.pdf").tap()
        let page = app.staticTexts["pdf-preview-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        app.buttons["pdf-preview-search"].tap()
        let find = app.descendants(matching: .any)["pdf-preview-search-input"]
        XCTAssertTrue(find.waitForExistence(timeout: 5))
        find.tap()
        find.typeText("Page One\n")
        let results = app.staticTexts["pdf-preview-search-results"]
        XCTAssertEqual(results.label, "1 / 1")
        find.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let foldedWidth = app.frame.width
        try waitForDuoResize(find, app: app, stage: "pdf-expand")
        XCTAssertEqual(find.value as? String, "Page One")
        XCTAssertEqual(results.label, "1 / 1")
        XCTAssertEqual(page.label, "1 / 2")
        assertDuoPDFTypingWithoutRefocus(find, app: app)
        try waitForDuoResize(find, app: app, stage: "pdf-fold", returningToWidth: foldedWidth)
        XCTAssertEqual(find.value as? String, "Page One")
        XCTAssertEqual(results.label, "1 / 1")
        XCTAssertEqual(page.label, "1 / 2")
        assertDuoPDFTypingWithoutRefocus(find, app: app)
        app.typeText("NoSuchPDFMatch\n")
        XCTAssertEqual(results.label, "0 / 0")
        XCTAssertTrue(app.buttons["quick-note-attachment-close"].isHittable)
        app.buttons["quick-note-attachment-close"].tap()
        pdfAttachment(in: app, name: "Review Preview.pdf").tap()
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        XCTAssertEqual(page.label, "1 / 2")
    }

    private func assertDuoPDFTypingWithoutRefocus(_ find: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText("x")
        let value = find.value as? String ?? ""
        XCTAssertEqual(value.count, "Page One".count + 1)
        XCTAssertEqual(value.filter { $0 != "x" }, "Page One")
        app.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(find.value as? String, "Page One")
        // Editing invalidates search matches. Submit again before checking the next fold.
        app.typeText("\n")
        XCTAssertEqual(app.staticTexts["pdf-preview-search-results"].label, "1 / 1")
        find.tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
    }

    private func pdfAttachment(in app: XCUIApplication, name: String) -> XCUIElement {
        let attachment = app.buttons.matching(NSPredicate(format: "value CONTAINS %@", name)).firstMatch
        XCTAssertTrue(attachment.waitForExistence(timeout: 5))
        return attachment
    }
}
