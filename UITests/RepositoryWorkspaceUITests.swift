import XCTest

@MainActor
final class RepositoryWorkspaceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPagingEditingAndReopeningCandidatePreservesOriginal() {
        let app = launch(reset: true, fixture: true)
        openLauncher(app)
        app.buttons["repository-workspace-create"].tap()
        let newestProject = app.staticTexts["分页工程 052"]
        XCTAssertTrue(newestProject.waitForExistence(timeout: 30))
        app.buttons["repository-page-next"].tap()
        XCTAssertTrue(app.staticTexts["第 2 页"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["repository-page-next"].isEnabled)
        app.buttons["repository-page-previous"].tap()
        XCTAssertTrue(newestProject.waitForExistence(timeout: 5))
        newestProject.tap()
        XCTAssertTrue(app.staticTexts["分页日志 101"].waitForExistence(timeout: 5))
        app.buttons["repository-page-next"].tap()
        XCTAssertTrue(app.staticTexts["第 2 页"].waitForExistence(timeout: 5))
        app.buttons["repository-page-next"].tap()
        XCTAssertTrue(app.staticTexts["第 3 页"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["repository-page-next"].isEnabled)
        app.buttons["repository-page-previous"].tap()
        XCTAssertTrue(app.staticTexts["第 2 页"].waitForExistence(timeout: 5))
        app.buttons["repository-page-previous"].tap()
        XCTAssertTrue(app.staticTexts["分页日志 101"].waitForExistence(timeout: 5))
        app.staticTexts["分页日志 101"].tap()
        let content = app.descendants(matching: .any)["repository-log-content"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        content.typeText(" 已修改")
        app.buttons["repository-editor-save"].tap()
        let modified = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "分页日志 101", "已修改")).firstMatch
        XCTAssertTrue(modified.waitForExistence(timeout: 8))
        let savedText = modified.label
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "candidate-log-page-after-save"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
        _ = launch(reset: false, fixture: false, app: app)
        openLauncher(app)
        let existing = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "repository-workspace-open-")).firstMatch
        XCTAssertTrue(existing.waitForExistence(timeout: 8))
        existing.tap()
        XCTAssertTrue(newestProject.waitForExistence(timeout: 8))
        newestProject.tap()
        XCTAssertTrue(app.staticTexts[savedText].waitForExistence(timeout: 5))
        app.navigationBars["副本施工日志"].buttons["BackButton"].tap()
        app.buttons["repository-workspace-close"].tap()
        // A new copy comes from original JSON, not from the edited candidate.
        app.buttons["repository-workspace-create"].tap()
        XCTAssertTrue(newestProject.waitForExistence(timeout: 30))
        newestProject.tap()
        XCTAssertTrue(app.staticTexts["分页日志 101"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[savedText].exists)
    }

    func testCreatesProjectAndLogAndSearchesCommittedChange() {
        let app = launch(reset: true, fixture: false)
        openLauncher(app)
        app.buttons["repository-workspace-create"].tap()
        XCTAssertTrue(app.buttons["repository-project-create"].waitForExistence(timeout: 20))
        app.buttons["repository-project-create"].tap()
        let name = app.textFields["repository-project-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("独立新项目")
        app.buttons["repository-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["独立新项目"].waitForExistence(timeout: 8))
        app.staticTexts["独立新项目"].tap()
        app.buttons["repository-log-create"].tap()
        let content = app.descendants(matching: .any)["repository-log-content"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        content.typeText("独立新日志")
        app.buttons["repository-editor-save"].tap()
        XCTAssertTrue(app.staticTexts["独立新日志"].waitForExistence(timeout: 8))
        app.swipeDown()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("不存在的内容")
        XCTAssertTrue(app.staticTexts["没有匹配记录"].waitForExistence(timeout: 5))
        let clear = search.buttons["清除文本"]
        XCTAssertTrue(clear.exists)
        clear.tap()
        XCTAssertTrue(app.staticTexts["独立新日志"].waitForExistence(timeout: 5))
    }

    private func launch(reset: Bool, fixture: Bool, app: XCUIApplication = XCUIApplication()) -> XCUIApplication {
        app.launchArguments = ["-uitest-skip-onboarding", "-languageCode", "zh-Hans", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment = ["UITEST_SKIP_ONBOARDING": "1"]
        if reset { app.launchEnvironment["UITEST_RESET_STATE"] = "1" }
        if fixture { app.launchEnvironment["UITEST_REPOSITORY_FIXTURE"] = "1" }
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

    private func tapAfterScrolling(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { element.tap()
            return }
            app.swipeUp()
        }
        XCTFail("Missing entry: \(element)")
    }
}
