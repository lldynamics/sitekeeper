import XCTest
import UIKit

extension SitekeeperUITests {
    func testLanguageSwitchUpdatesGlobalNavigationWithoutRestart() {
        let app = launchPresentationApp()
        tapPrimaryModule(app, name: "我的")
        app.segmentedControls["profile-language-picker"].buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["My Profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["App language updated."].exists)

        tapPrimaryModule(app, name: "Dashboard")
        XCTAssertTrue(app.navigationBars["Today's Dashboard"].waitForExistence(timeout: 5))
        tapPrimaryModule(app, name: "Toolbox")
        XCTAssertTrue(app.staticTexts["Watermark Camera"].firstMatch.waitForExistence(timeout: 5))
        tapPrimaryModule(app, name: "Projects")
        XCTAssertTrue(app.buttons["project-create-open"].waitForExistence(timeout: 5))
        app.buttons["project-create-open"].tap()
        XCTAssertTrue(app.textFields["project-create-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.exists)
        app.buttons["Cancel"].firstMatch.tap()

        tapPrimaryModule(app, name: "My Profile")
        app.segmentedControls["profile-language-picker"].buttons["中文"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        tapPrimaryModule(app, name: "工作台")
        XCTAssertTrue(app.navigationBars["今日工作台"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Language switched twice without relaunch")
    }

    func testIPadProjectWorkspaceKeepsGlobalModuleSidebar() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchPresentationApp()
        tapPrimaryModule(app, name: "项目")
        XCTAssertTrue(app.buttons["project-create-open"].waitForExistence(timeout: 5))
        for tab in ["工作台", "项目", "工具箱", "随手记", "我的"] {
            XCTAssertTrue(app.buttons[tab].firstMatch.isHittable, "Global module missing: \(tab)")
        }
        XCTAssertFalse(app.buttons["project-workspace-modules"].exists)
        attachScreenshot(app, named: "iPad global sidebar with project list and detail")
        tapPrimaryModule(app, name: "工作台")
        XCTAssertTrue(app.navigationBars["今日工作台"].waitForExistence(timeout: 5))
    }

    func testThemeSwitchKeepsNavigationUsable() {
        let app = launchPresentationApp()
        tapPrimaryModule(app, name: "我的")
        app.buttons["profile-theme-picker"].tap()
        app.buttons["晴空蓝"].firstMatch.tap()
        tapPrimaryModule(app, name: "工作台")
        XCTAssertTrue(app.navigationBars["今日工作台"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Dashboard sky blue theme")
        tapPrimaryModule(app, name: "我的")
        app.buttons["profile-theme-picker"].tap()
        app.buttons["暖橙"].firstMatch.tap()
        tapPrimaryModule(app, name: "工作台")
        XCTAssertTrue(app.navigationBars["今日工作台"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Dashboard warm amber theme")
    }

    func testIPadProjectSelectionAndDraftSurviveRotation() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchPresentationApp()
        tapPrimaryModule(app, name: "项目")
        app.buttons["project-create-open"].tap()
        let field = app.textFields["project-create-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Three Column Project")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Three Column Project")
        app.buttons["project-create-submit"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        app.staticTexts["Three Column Project"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Three Column Project"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.navigationBars["Three Column Project"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Selected project in three columns after rotation")
        tapPrimaryModule(app, name: "工作台")
        tapPrimaryModule(app, name: "项目")
        XCTAssertTrue(app.navigationBars["Three Column Project"].waitForExistence(timeout: 5))
    }

    private func launchPresentationApp() -> XCUIApplication {
        let app = XCUIApplication()
        // A -languageCode launch override would mask writes from the actual picker.
        app.launchArguments = ["-uitest-skip-onboarding", "-uitest-reset-state", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        return app
    }

    func testIPadProjectDetailHasNoBlankCardsAndSectionJumpsWork() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchApp(resetState: true, reviewRegressionFixture: true)
        tapPrimaryModule(app, name: "项目")
        let project = app.staticTexts["Review Site A"].firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()
        let list = app.collectionViews["project-workspace-detail"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        assertVisibleProjectCardsHaveContent(list)

        let picker = app.segmentedControls["项目详情焦点"]
        XCTAssertTrue(picker.exists)
        for (title, anchor) in [("现场", "records"), ("资料", "assets"), ("成本", "finance"),
                                ("时间线", "timeline"), ("概览", "overview")] {
            picker.buttons[title].tap()
            let header = app.staticTexts["project-detail-section-\(anchor)"]
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: header)
            let jumpResult = XCTWaiter.wait(for: [visible], timeout: 8)
            if jumpResult != .completed { attachInterfaceSnapshot(app, named: "Section jump failed: \(title)") }
            XCTAssertEqual(jumpResult, .completed, "Section jump failed: \(title)")
            assertVisibleProjectCardsHaveContent(list)
        }

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "iPad detail without blank anchor cards"
        attachment.lifetime = .keepAlways
        add(attachment)
        if ProcessInfo.processInfo.environment["UITEST_NATIVE_CAPTURE_WINDOW"] == "1" {
            FileHandle.standardOutput.write(Data("SITEKEEPER_STABLE_RAW_READY\n".utf8))
            let captureWindow = expectation(description: "Keep project detail foreground for raw capture")
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { captureWindow.fulfill() }
            wait(for: [captureWindow], timeout: 15)
        }
    }

    private func assertVisibleProjectCardsHaveContent(_ list: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let cells = list.cells.allElementsBoundByIndex.filter {
            $0.frame.height >= 30 && $0.frame.width > 100 && $0.frame.intersects(list.frame)
        }
        XCTAssertFalse(cells.isEmpty, "Expected visible content cards", file: file, line: line)
        let contentTypes: [XCUIElement.ElementType] = [.staticText, .button, .image, .textField, .textView, .picker, .switch]
        for cell in cells {
            let hasContent = !cell.label.isEmpty || contentTypes.contains { cell.descendants(matching: $0).count > 0 }
            XCTAssertTrue(hasContent, "Empty visible project card at \(cell.frame)", file: file, line: line)
        }
    }
}

extension SitekeeperUITests {
    @MainActor
    func rotateAndVerifySupportedSceneGeometry(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            rotateAndWaitForSceneResize(app, to: orientation)
            return
        }
        // The app intentionally supports portrait only on iPhone. Rotating the
        // device must keep that scene geometry while callers verify editor state.
        let window = app.windows.firstMatch
        let before = window.frame
        XCTAssertLessThan(before.width, before.height)
        XCUIDevice.shared.orientation = orientation
        XCTAssertEqual(XCUIDevice.shared.orientation, orientation)
        let after = window.frame
        XCTAssertEqual(after.width, before.width, accuracy: 1)
        XCTAssertEqual(after.height, before.height, accuracy: 1)
        XCTAssertLessThan(after.width, after.height)
        let evidence = XCTAttachment(string: "Requested device orientation: \(orientation.rawValue); actual: \(XCUIDevice.shared.orientation.rawValue); scene before: \(before); after: \(after)")
        evidence.name = "iPhone portrait lock during device orientation change"
        evidence.lifetime = .keepAlways
        add(evidence)
    }
}
