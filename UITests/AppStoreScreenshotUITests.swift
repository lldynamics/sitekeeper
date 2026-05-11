import XCTest

final class AppStoreScreenshotUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private var screenshotOutputDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AppStoreShots", isDirectory: true)
    }

    private func saveScreenshot(_ app: XCUIApplication, named name: String, line: UInt = #line) {
        let url = screenshotOutputDirectory.appendingPathComponent("\(name).png")
        do {
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        } catch {
            XCTFail("截图保存失败: \(error.localizedDescription)", line: line)
        }
    }

    private func launchApp(
        skipOnboarding: Bool = true,
        resetState: Bool = false
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
        app.launch()
        return app
    }

    func testCaptureAppStoreScreenshots() {
        let app = launchApp(skipOnboarding: true, resetState: true)

        // 等待工作台加载
        XCTAssertTrue(app.tabBars.buttons["工作台"].waitForExistence(timeout: 10))

        // 截图1：工作台首页
        saveScreenshot(app, named: "screenshot1_dashboard")

        // 截图2：计算工具页面（工具箱 tab）
        app.tabBars.buttons["工具箱"].tap()
        XCTAssertTrue(app.tabBars.buttons["工具箱"].isSelected)
        // 等待列表加载
        let listExists = app.collectionViews.firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(listExists)
        saveScreenshot(app, named: "screenshot2_database")

        // 截图3：随手记页面
        app.tabBars.buttons["随手记"].tap()
        let quickNoteNav = app.navigationBars["随手记"].waitForExistence(timeout: 5)
        XCTAssertTrue(quickNoteNav)
        saveScreenshot(app, named: "screenshot3_quicknote")
    }
}
