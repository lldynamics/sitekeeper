import XCTest

final class SitekeeperUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var screenshotOutputDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AppStoreShots", isDirectory: true)
    }

    private func prepareScreenshotDirectory() {
        let manager = FileManager.default
        let directory = screenshotOutputDirectory
        if manager.fileExists(atPath: directory.path) {
            try? manager.removeItem(at: directory)
        }
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func saveScreenshot(_ app: XCUIApplication, named name: String, line: UInt = #line) {
        let url = screenshotOutputDirectory.appendingPathComponent("\(name).png")
        do {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        } catch {
            XCTFail("截图保存失败: \(error.localizedDescription)", line: line)
        }
    }

    @discardableResult
    private func launchApp(
        skipOnboarding: Bool = true,
        resetState: Bool = false,
        enableBackupPreview: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        if skipOnboarding {
            app.launchArguments += ["-uitest-skip-onboarding"]
            app.launchEnvironment["UITEST_SKIP_ONBOARDING"] = "1"
        }
        if resetState {
            app.launchArguments += ["-uitest-reset-state"]
            app.launchEnvironment["UITEST_RESET_STATE"] = "1"
        }
        if enableBackupPreview {
            app.launchArguments += ["-uitest-backup-preview"]
            app.launchEnvironment["UITEST_BACKUP_PREVIEW"] = "1"
        }
        app.launch()
        return app
    }

    private func tapPrimaryModule(_ app: XCUIApplication, name: String) {
        let tabButton = app.tabBars.buttons[name]
        if tabButton.waitForExistence(timeout: 2) {
            tabButton.tap()
            return
        }

        let sidebarButton = app.buttons[name]
        if sidebarButton.waitForExistence(timeout: 2) {
            sidebarButton.tap()
            return
        }

        let sidebarText = app.staticTexts[name]
        if sidebarText.waitForExistence(timeout: 2) {
            sidebarText.tap()
        }
    }

    func testColdLaunchShowsPrimaryTabs() {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.buttons["工作台"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["项目"].exists)
        XCTAssertTrue(app.tabBars.buttons["工具箱"].exists)
        XCTAssertTrue(app.tabBars.buttons["随手记"].exists)
        XCTAssertTrue(app.tabBars.buttons["我的"].exists)
    }

    func testBackupScreenShowsImportAndExportActions() {
        let app = launchApp()
        app.tabBars.buttons["我的"].tap()

        let backupEntry = app.cells.containing(.staticText, identifier: "数据备份").firstMatch
        XCTAssertTrue(backupEntry.waitForExistence(timeout: 5))
        backupEntry.tap()

        XCTAssertTrue(app.buttons["导出完整备份 ZIP"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["导入备份 ZIP"].exists)
    }

    func testQuickNoteComposerShowsMediaAndAttachmentActions() {
        let app = launchApp()
        app.tabBars.buttons["随手记"].tap()

        XCTAssertTrue(app.navigationBars["随手记"].waitForExistence(timeout: 5))
        app.buttons["发布"].tap()

        XCTAssertTrue(app.navigationBars["发布随手记"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["媒体"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["附件"].exists)
        app.buttons["关闭"].tap()
    }

    func testFirstLaunchOnboardingCanOpenProjectComposer() {
        let app = launchApp(skipOnboarding: false, resetState: true)

        XCTAssertTrue(app.navigationBars["首次设置"].waitForExistence(timeout: 5))
        let createButton = app.buttons.containing(.staticText, identifier: "新建项目").firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))

        createButton.tap()

        XCTAssertTrue(app.navigationBars["项目"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["新建工程"].waitForExistence(timeout: 5))
    }

    func testProjectFileBrowserEntryOpensList() {
        let app = launchApp(resetState: true)
        app.tabBars.buttons["项目"].tap()

        let browserButton = app.buttons["项目文件浏览"]
        XCTAssertTrue(browserButton.waitForExistence(timeout: 5))
        browserButton.tap()

        XCTAssertTrue(app.navigationBars["项目文件"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["暂无项目文件"].waitForExistence(timeout: 5))
    }

    func testClearLocalDataFlowRequiresConfirmationPhrase() {
        let app = launchApp(resetState: true)
        app.tabBars.buttons["我的"].tap()

        let settingsEntry = app.cells.containing(.staticText, identifier: "设置").firstMatch
        XCTAssertTrue(settingsEntry.waitForExistence(timeout: 5))
        settingsEntry.tap()

        let clearButton = app.buttons["清空本机全部数据（不可恢复）"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        clearButton.tap()

        let continueButton = app.buttons["继续"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.tap()

        let confirmationTitle = app.staticTexts["即将清空本机全部数据"]
        XCTAssertTrue(confirmationTitle.waitForExistence(timeout: 5))

        let confirmClearButton = app.buttons["确认清空"]
        XCTAssertTrue(confirmClearButton.exists)
        XCTAssertFalse(confirmClearButton.isEnabled)

        let phraseField = app.textFields["确认删除数据"]
        XCTAssertTrue(phraseField.waitForExistence(timeout: 5))
        phraseField.tap()
        phraseField.typeText("确认删除数据")

        XCTAssertTrue(confirmClearButton.isEnabled)
        app.buttons["取消"].tap()
    }

    func testBackupOverwriteImportShowsSecondConfirmation() {
        let app = launchApp(resetState: true, enableBackupPreview: true)
        app.tabBars.buttons["我的"].tap()

        let backupEntry = app.cells.containing(.staticText, identifier: "数据备份").firstMatch
        XCTAssertTrue(backupEntry.waitForExistence(timeout: 5))
        backupEntry.tap()

        let previewButton = app.buttons["UI测试：模拟覆盖导入预览"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5))
        let confirmShortcutButton = app.buttons["UI测试：触发覆盖二次确认"]
        XCTAssertTrue(confirmShortcutButton.waitForExistence(timeout: 5))
        confirmShortcutButton.tap()

        let overwriteAlert = app.alerts["确认覆盖导入？"]
        XCTAssertTrue(overwriteAlert.waitForExistence(timeout: 5))
        overwriteAlert.buttons["取消"].tap()
    }

    func testSwitchingFromSettingsToToolboxRefreshesDetail() {
        let app = launchApp(resetState: true)

        tapPrimaryModule(app, name: "我的")
        let settingsEntry = app.cells.containing(.staticText, identifier: "设置").firstMatch
        XCTAssertTrue(settingsEntry.waitForExistence(timeout: 5))
        settingsEntry.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))

        tapPrimaryModule(app, name: "工具箱")
        XCTAssertTrue(app.navigationBars["工程工具箱"].waitForExistence(timeout: 5))
    }

    func testCaptureFeaturedAppStoreScreenshots() {
        prepareScreenshotDirectory()

        let onboardingApp = launchApp(skipOnboarding: false, resetState: true, enableBackupPreview: true)
        XCTAssertTrue(onboardingApp.navigationBars["首次设置"].waitForExistence(timeout: 6))
        saveScreenshot(onboardingApp, named: "01-onboarding")

        let createButton = onboardingApp.buttons.containing(.staticText, identifier: "新建项目").firstMatch
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()
        let composerReady = onboardingApp.navigationBars["新建工程"].waitForExistence(timeout: 8)
            || onboardingApp.navigationBars["项目"].waitForExistence(timeout: 2)
        XCTAssertTrue(composerReady)
        saveScreenshot(onboardingApp, named: "02-project-composer")
        onboardingApp.terminate()

        let app = launchApp(resetState: false, enableBackupPreview: true)
        XCTAssertTrue(app.tabBars.buttons["工作台"].waitForExistence(timeout: 5))
        saveScreenshot(app, named: "03-dashboard")

        app.tabBars.buttons["项目"].tap()
        XCTAssertTrue(app.buttons["项目文件浏览"].waitForExistence(timeout: 5))
        saveScreenshot(app, named: "04-project-home")

        app.buttons["项目文件浏览"].tap()
        XCTAssertTrue(app.navigationBars["项目文件"].waitForExistence(timeout: 5))
        saveScreenshot(app, named: "05-project-files")
        app.navigationBars.buttons.firstMatch.tap()

        app.tabBars.buttons["工具箱"].tap()
        XCTAssertTrue(app.tabBars.buttons["工具箱"].isSelected)
        saveScreenshot(app, named: "06-database")

        app.tabBars.buttons["随手记"].tap()
        XCTAssertTrue(app.navigationBars["随手记"].waitForExistence(timeout: 5))
        saveScreenshot(app, named: "07-quick-note")

        app.tabBars.buttons["我的"].tap()
        let backupEntry = app.cells.containing(.staticText, identifier: "数据备份").firstMatch
        XCTAssertTrue(backupEntry.waitForExistence(timeout: 5))
        saveScreenshot(app, named: "08-profile")

        backupEntry.tap()
        XCTAssertTrue(app.navigationBars["数据备份"].waitForExistence(timeout: 5))
        saveScreenshot(app, named: "09-backup")
    }

    func testCaptureThreeAppStoreScreenshots() {
        let app = launchApp(skipOnboarding: true, resetState: true)
        XCTAssertTrue(app.navigationBars["今日工作台"].waitForExistence(timeout: 20))
        saveScreenshot(app, named: "screenshot1_dashboard")

        app.buttons["工具箱"].tap()
        saveScreenshot(app, named: "screenshot2_database")

        app.buttons["随手记"].tap()
        saveScreenshot(app, named: "screenshot3_quicknote")
    }
}
