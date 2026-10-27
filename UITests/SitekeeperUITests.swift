import XCTest
import UIKit

@MainActor
final class SitekeeperUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        if ProcessInfo.processInfo.environment["UITEST_REQUIRE_ANIMATIONS"] == "1" {
            XCTAssertNotEqual(ProcessInfo.processInfo.environment["UITEST_DISABLE_ANIMATIONS"], "1")
        }
    }
}

extension SitekeeperUITests {
    func testColdLaunchShowsPrimaryTabs() {
        let app = launchApp()
        for module in ["工作台", "项目", "工具箱", "随手记", "我的"] {
            XCTAssertTrue(waitForPrimaryModule(app, name: module), "Missing primary module: \(module)")
        }
    }

    func testBackupScreenShowsImportAndExportActions() {
        let app = launchApp(resetState: true)
        openDataSafetyCenter(app)

        let backupShortcut = app.buttons["data-management-shortcut-backup"]
        if backupShortcut.waitForExistence(timeout: 2), backupShortcut.isHittable {
            backupShortcut.tap()
        }

        let exportButton = app.buttons["导出完整备份 ZIP"]
        guard exportButton.waitForExistence(timeout: 6) else {
            attachScreenshot(app, named: "backup-export-action-missing")
            XCTFail("导出完整备份 ZIP 操作不可见")
            return
        }
        let importButton = app.buttons["导入备份 ZIP"]
        guard importButton.waitForExistence(timeout: 6) else {
            attachScreenshot(app, named: "backup-import-action-missing")
            XCTFail("导入备份 ZIP 操作不可见")
            return
        }
    }

    func testDataSafetyCenterShowsRiskFirstReleasePaths() {
        let app = launchApp(resetState: true)
        openDataSafetyCenter(app)

        XCTAssertTrue(app.staticTexts["数据安全状态"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["data-management-shortcut-backup"].exists)
        XCTAssertTrue(app.buttons["data-management-shortcut-health"].exists)
        XCTAssertTrue(app.buttons["data-management-shortcut-storage"].exists)
        XCTAssertTrue(app.buttons["data-management-shortcut-export"].exists)

        app.buttons["data-management-shortcut-health"].tap()
        XCTAssertTrue(app.staticTexts["健康概览"].waitForExistence(timeout: 5))

        app.buttons["data-management-shortcut-storage"].tap()
        XCTAssertTrue(app.buttons["存储清理"].waitForExistence(timeout: 5))

        app.buttons["data-management-shortcut-export"].tap()
        XCTAssertTrue(app.staticTexts["导出交付"].waitForExistence(timeout: 5))
    }

    func testSampleDataImportEntryShowsRestoreConfirmation() throws {
        try XCTSkipUnless(shouldRunExtendedScenarios, "Set UITEST_RUN_EXTENDED_SCENARIOS=1 to run sample import scenario tests.")
        let app = launchApp(resetState: true)
        openSampleDataImportConfirmation(app)
        app.alerts["恢复测试数据？"].buttons["取消"].tap()
    }

    func testQuickNoteComposerShowsMediaAndAttachmentActions() {
        let app = launchApp()
        tapPrimaryModule(app, name: "随手记")

        XCTAssertTrue(app.navigationBars["随手记"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quick-note-publish"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quick-note-project-selector"].exists)
        XCTAssertTrue(app.buttons["拍照添加"].exists)
        XCTAssertTrue(app.buttons["录制语音"].exists)
        if !app.buttons["从相册添加媒体"].isHittable {
            let more = app.buttons["quick-note-more-tools"]
            XCTAssertTrue(more.waitForExistence(timeout: 5))
            more.tap()
        }
        XCTAssertTrue(app.buttons["从相册添加媒体"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["quick-note-add-drawing"].exists)
        XCTAssertTrue(app.buttons["导入文件附件"].exists)
    }

    func testQuickNoteCompactComposerCanOpenDrawingBoard() {
        let app = launchApp()
        tapPrimaryModule(app, name: "随手记")

        let drawingButton = app.buttons["quick-note-add-drawing"]
        if !drawingButton.isHittable {
            let more = app.buttons["quick-note-more-tools"]
            XCTAssertTrue(more.waitForExistence(timeout: 5))
            more.tap()
        }
        XCTAssertTrue(drawingButton.waitForExistence(timeout: 5))
        XCTAssertTrue(drawingButton.isHittable)
        drawingButton.tap()

        XCTAssertTrue(app.navigationBars["手绘"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["quick-note-drawing-save"].isEnabled)
        XCTAssertFalse(app.buttons["quick-note-drawing-clear"].isEnabled)
        app.buttons["quick-note-drawing-cancel"].tap()
        XCTAssertTrue(app.navigationBars["手绘"].waitForNonExistence(timeout: 5))
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

    func testFirstLaunchOnboardingCanBeDeferred() {
        let app = launchApp(skipOnboarding: false, resetState: true)

        XCTAssertTrue(app.navigationBars["首次设置"].waitForExistence(timeout: 5))
        let skipButton = app.buttons["onboarding-skip"]
        XCTAssertTrue(skipButton.waitForExistence(timeout: 5))
        skipButton.tap()

        XCTAssertTrue(app.navigationBars["首次设置"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForPrimaryModule(app, name: "工作台"))
    }

    func testProjectFileBrowserEntryOpensList() {
        let orientations: [UIDeviceOrientation] = UIDevice.current.userInterfaceIdiom == .pad
            ? [.portrait, .landscapeLeft] : [.portrait]
        defer { XCUIDevice.shared.orientation = .portrait }
        for orientation in orientations {
            XCUIDevice.shared.orientation = orientation
            assertProjectFileBrowserEntryOpensList()
        }
    }

    private func assertProjectFileBrowserEntryOpensList() {
        let app = launchApp(resetState: true)
        tapPrimaryModule(app, name: "项目")

        let browserButton = app.buttons["project-file-browser-entry"]
        XCTAssertTrue(browserButton.waitForExistence(timeout: 5))
        browserButton.tap()

        if UIDevice.current.userInterfaceIdiom == .pad {
            let preview = app.navigationBars["文件预览"]
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["请选择文件"].waitForExistence(timeout: 5))
            let projects = app.navigationBars["项目资料"]
            for _ in 0..<2 {
                if projects.exists, projects.isHittable { break }
                let categorySidebar = app.navigationBars.matching(identifier: "文件分类")
                    .buttons["显示边栏"].firstMatch
                let previewSidebar = app.navigationBars.matching(identifier: "文件预览")
                    .buttons["显示边栏"].firstMatch
                let sidebar = categorySidebar.exists ? categorySidebar : previewSidebar
                XCTAssertTrue(sidebar.waitForExistence(timeout: 5), app.debugDescription)
                XCTAssertTrue(sidebar.isHittable)
                sidebar.tap()
            }
            XCTAssertTrue(projects.waitForExistence(timeout: 5))
            XCTAssertTrue(projects.isHittable)
            let empty = app.staticTexts["暂无项目"]
            XCTAssertTrue(empty.waitForExistence(timeout: 5))
            XCTAssertTrue(empty.isHittable)
        } else {
            XCTAssertTrue(app.navigationBars["项目资料"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["暂无项目资料"].waitForExistence(timeout: 5))
        }
    }

    func testClearLocalDataFlowRequiresConfirmationPhrase() {
        let app = launchApp(resetState: true, allowClearWithoutBackup: true)
        tapPrimaryModule(app, name: "我的")

        let settingsEntry = button(app, identifier: "profile-settings-link")
        XCTAssertTrue(settingsEntry.waitForExistence(timeout: 5))
        settingsEntry.tap()

        let clearButton = app.buttons["清空本机全部数据（需先备份）"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5))
        clearButton.tap()

        let continueButton = app.buttons["继续清空"]
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
        clearDataConfirmationAction(app, title: "取消").tap()
        XCTAssertTrue(phraseField.waitForNonExistence(timeout: 5))
    }

    func testBackupOverwriteImportShowsSecondConfirmation() {
        let app = launchApp(resetState: true, enableBackupPreview: true)
        openDataSafetyCenter(app)

        let actionMenu = app.buttons["data-management-actions-menu"]
        XCTAssertTrue(actionMenu.waitForExistence(timeout: 5))
        actionMenu.tap()

        let previewButtons = app.buttons.matching(identifier: "ui-test-backup-preview")
        XCTAssertTrue(previewButtons.firstMatch.waitForExistence(timeout: 5))
        let confirmations = app.buttons.matching(identifier: "ui-test-overwrite-confirm")
        XCTAssertTrue(confirmations.firstMatch.waitForExistence(timeout: 5))
        // The wide page also exposes this debug action inline. The open menu
        // owns the hittable instance; its covered page counterpart is retained.
        let confirmShortcutButton = confirmations.allElementsBoundByIndex.first(where: { $0.isHittable })
        XCTAssertNotNil(confirmShortcutButton)
        confirmShortcutButton?.tap()

        let overwriteAlert = app.alerts["确认覆盖导入？"]
        XCTAssertTrue(overwriteAlert.waitForExistence(timeout: 5))
        overwriteAlert.buttons["取消"].tap()
    }

    func testProjectDeliveryGuideReachesExportActionWithSampleData() throws {
        try XCTSkipUnless(shouldRunExtendedScenarios, "Set UITEST_RUN_EXTENDED_SCENARIOS=1 to run project delivery sample-data scenario tests.")
        let orientations: [UIDeviceOrientation] = UIDevice.current.userInterfaceIdiom == .pad
            ? [.portrait, .landscapeLeft] : [.portrait]
        defer { XCUIDevice.shared.orientation = .portrait }
        for orientation in orientations {
            XCUIDevice.shared.orientation = orientation
            let app = launchApp(resetState: true)
            importSampleDataThroughUI(app)
            tapPrimaryModule(app, name: "项目")
            let openedProjectName = openImportedProject(app)
            XCTAssertFalse(openedProjectName.isEmpty)
            XCTAssertTrue(app.navigationBars[openedProjectName].waitForExistence(timeout: 5))
            let moreMenu = app.buttons["project-detail-more-menu"]
            let moreMenuExists = moreMenu.waitForExistence(timeout: 5)
            if !moreMenuExists { attachInterfaceSnapshot(app, named: "Delivery menu missing") }
            XCTAssertTrue(moreMenuExists)
            moreMenu.tap()
            let deliveryGuideButton = app.buttons["打开交付向导"]
            XCTAssertTrue(deliveryGuideButton.waitForExistence(timeout: 5))
            deliveryGuideButton.tap()
            XCTAssertTrue(app.navigationBars["完工交付向导"].waitForExistence(timeout: 5))
            let exportButton = app.buttons["project-delivery-export-package"]
            XCTAssertTrue(
                waitForElementByScrollingDown(exportButton, in: app, attempts: 14, timeoutPerAttempt: 1),
                "Unable to locate project-delivery-export-package in guide"
            )
        }
    }

    func testSwitchingFromSettingsToToolboxRefreshesDetail() {
        let app = launchApp(resetState: true)

        tapPrimaryModule(app, name: "我的")
        let settingsEntry = button(app, identifier: "profile-settings-link")
        XCTAssertTrue(settingsEntry.waitForExistence(timeout: 5))
        settingsEntry.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))

        tapPrimaryModule(app, name: "工具箱")
        XCTAssertTrue(app.navigationBars["工程工具箱"].waitForExistence(timeout: 5))
    }

    func testDashboardBusinessMetricsOpenProjectListOverviewFilters() throws {
        try XCTSkipUnless(shouldRunExtendedScenarios, "Set UITEST_RUN_EXTENDED_SCENARIOS=1 to run dashboard business metric drilldown tests.")
        let app = launchApp(resetState: true)
        importSampleDataThroughUI(app)

        tapPrimaryModule(app, name: "工作台")
        let dashboardReady =
            app.navigationBars["今日工作台"].waitForExistence(timeout: 4)
            || app.navigationBars["工作台"].waitForExistence(timeout: 2)
            || element(app, identifier: "dashboard-business-receivable-aging", scrollingAttempts: 4).waitForExistence(timeout: 2)
        XCTAssertTrue(dashboardReady, "Dashboard did not become ready after switching to 工作台")
        ensureDashboardBusinessMetricsVisible(app)
        let metricsVisible = app.descendants(matching: .any)
            .matching(identifier: "dashboard-business-receivable-aging")
            .firstMatch
            .waitForExistence(timeout: 2)
        try XCTSkipIf(!metricsVisible, "Current sample fixture has no active project business metrics to click through")

        let cases: [(buttonId: String, filterId: String)] = [
            ("dashboard-business-receivable-aging", "project-list-overview-filter-receivableAging"),
            ("dashboard-business-recent-collection", "project-list-overview-filter-recentCollection"),
            ("dashboard-business-cost-anomaly", "project-list-overview-filter-costAnomaly"),
            ("dashboard-business-profit-risk", "project-list-overview-filter-lowMarginRisk")
        ]

        for item in cases + cases {
            let metricEntry = element(app, identifier: item.buttonId, scrollingAttempts: 8)
            XCTAssertTrue(metricEntry.waitForExistence(timeout: 6), "Missing metric entry: \(item.buttonId)")
            XCTAssertTrue(metricEntry.isHittable, "Metric entry not hittable: \(item.buttonId)")
            XCTAssertGreaterThanOrEqual(metricEntry.frame.height, 44, "Metric tap areas must not overlap adjacent rows")
            if item.buttonId == "dashboard-business-cost-anomaly" {
                attachInterfaceSnapshot(app, named: "Before cost anomaly drilldown")
            }
            metricEntry.tap()

            XCTAssertTrue(app.navigationBars["项目"].waitForExistence(timeout: 6))
            let filterExists = app.staticTexts[item.filterId].waitForExistence(timeout: 6)
            if !filterExists { attachInterfaceSnapshot(app, named: "Overview filter missing: \(item.filterId)") }
            XCTAssertTrue(filterExists, "Missing overview filter marker: \(item.filterId)")

            let backButton = app.navigationBars["项目"].buttons["BackButton"]
            XCTAssertTrue(backButton.waitForExistence(timeout: 6))
            backButton.tap()
            let returnedToDashboard =
                app.navigationBars["今日工作台"].waitForExistence(timeout: 4)
                || app.navigationBars["工作台"].waitForExistence(timeout: 2)
                || element(app, identifier: "dashboard-business-receivable-aging", scrollingAttempts: 4).waitForExistence(timeout: 2)
            XCTAssertTrue(returnedToDashboard, "Failed to return to dashboard after tapping back")
            ensureDashboardBusinessMetricsVisible(app)
        }
    }

    func testAccessibilityAXXXLCoreFlowsRemainOperable() {
        let app = launchApp(resetState: true, dynamicTypeSize: "accessibility5")

        XCTAssertTrue(app.navigationBars["今日工作台"].waitForExistence(timeout: 8))
        let emptyProjectCallToAction = button(app, identifier: "dashboard-empty-active-projects", scrollingAttempts: 3)
        XCTAssertTrue(emptyProjectCallToAction.isHittable)
        emptyProjectCallToAction.tap()
        XCTAssertTrue(app.navigationBars["项目"].waitForExistence(timeout: 5))
        let dashboardBackButton = app.navigationBars["项目"].buttons["BackButton"]
        XCTAssertTrue(dashboardBackButton.waitForExistence(timeout: 3))
        dashboardBackButton.tap()
        XCTAssertTrue(app.navigationBars["今日工作台"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "axxxl-dashboard")

        tapPrimaryModule(app, name: "项目")
        let projectSurfaceReady =
            app.buttons["project-file-browser-entry"].waitForExistence(timeout: 6)
            || app.navigationBars["项目"].waitForExistence(timeout: 2)
            || app.buttons["新建项目"].waitForExistence(timeout: 2)
            || app.staticTexts["新建项目"].waitForExistence(timeout: 2)
        XCTAssertTrue(projectSurfaceReady)
        let statusMenu = button(app, identifier: "project-status-filter-menu", scrollingAttempts: 3)
        XCTAssertTrue(statusMenu.isHittable)
        statusMenu.tap()
        let activeStatus = app.buttons["进行中"]
        XCTAssertTrue(activeStatus.waitForExistence(timeout: 3))
        activeStatus.tap()
        XCTAssertEqual(statusMenu.value as? String, "进行中")
        attachScreenshot(app, named: "axxxl-project-list")

        tapPrimaryModule(app, name: "我的")
        let profileReady =
            app.navigationBars["我的"].waitForExistence(timeout: 4)
            || app.buttons["profile-data-management-link"].waitForExistence(timeout: 4)
            || app.buttons["profile-settings-link"].waitForExistence(timeout: 4)
        XCTAssertTrue(profileReady, "AXXXL profile module did not present core entries")
        let editUserName = button(app, identifier: "profile-edit-username", scrollingAttempts: 2)
        XCTAssertTrue(editUserName.isHittable)
        editUserName.tap()
        let userNameField = app.textFields["profile-username-input"]
        XCTAssertTrue(userNameField.waitForExistence(timeout: 4))
        userNameField.tap()
        userNameField.typeText("超大字体用户")
        let saveUserName = app.buttons["profile-username-save"]
        XCTAssertTrue(saveUserName.isHittable)
        saveUserName.tap()
        XCTAssertTrue(app.staticTexts["超大字体用户"].waitForExistence(timeout: 4))
        attachScreenshot(app, named: "axxxl-profile")
    }

    func testCaptureFeaturedAppStoreScreenshots() throws {
        try XCTSkipUnless(shouldWriteAppStoreScreenshots, "Set UITEST_CAPTURE_APP_STORE_SCREENSHOTS=1 to run App Store screenshot capture tests.")
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

        let importApp = launchApp(resetState: true, enableBackupPreview: true)
        XCTAssertTrue(waitForPrimaryModule(importApp, name: "工作台"))
        importSampleDataThroughUI(importApp)
        importApp.terminate()

        let app = launchApp(resetState: false, enableBackupPreview: true)
        XCTAssertTrue(waitForPrimaryModule(app, name: "工作台"))
        saveScreenshot(app, named: "03-dashboard")

        tapPrimaryModule(app, name: "项目")
        XCTAssertTrue(app.buttons["project-file-browser-entry"].waitForExistence(timeout: 5))
        saveScreenshot(app, named: "04-project-home")

        app.buttons["project-file-browser-entry"].tap()
        let browserTitle = UIDevice.current.userInterfaceIdiom == .pad ? "文件预览" : "项目资料"
        XCTAssertTrue(app.navigationBars[browserTitle].waitForExistence(timeout: 5))
        saveScreenshot(app, named: "05-project-files")

        tapPrimaryModule(app, name: "工具箱")
        XCTAssertTrue(waitForPrimaryModule(app, name: "工具箱"))
        saveScreenshot(app, named: "06-database")

        tapPrimaryModule(app, name: "随手记")
        XCTAssertTrue(app.navigationBars["随手记"].waitForExistence(timeout: 5))
        saveScreenshot(app, named: "07-quick-note")

        tapPrimaryModule(app, name: "我的")
        let backupEntry = app.buttons["profile-data-management-link"]
        XCTAssertTrue(backupEntry.waitForExistence(timeout: 5))
        saveScreenshot(app, named: "08-profile")

        backupEntry.tap()
        XCTAssertTrue(app.navigationBars["数据安全中心"].waitForExistence(timeout: 5))
        saveScreenshot(app, named: "09-backup")
    }

    func testCaptureThreeAppStoreScreenshots() throws {
        try XCTSkipUnless(shouldWriteAppStoreScreenshots, "Set UITEST_CAPTURE_APP_STORE_SCREENSHOTS=1 to run App Store screenshot capture tests.")
        let app = launchApp(skipOnboarding: true, resetState: true)
        XCTAssertTrue(app.navigationBars["今日工作台"].waitForExistence(timeout: 20))
        saveScreenshot(app, named: "screenshot1_dashboard")

        tapPrimaryModule(app, name: "工具箱")
        XCTAssertTrue(app.navigationBars["工程工具箱"].waitForExistence(timeout: 5))
        saveScreenshot(app, named: "screenshot2_database")

        tapPrimaryModule(app, name: "随手记")
        XCTAssertTrue(app.navigationBars["随手记"].waitForExistence(timeout: 5))
        saveScreenshot(app, named: "screenshot3_quicknote")
    }
}
