import XCTest
import UIKit

@MainActor
final class SitekeeperUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }
}

extension SitekeeperUITests {
    var shouldWriteAppStoreScreenshots: Bool {
        let value = ProcessInfo.processInfo.environment["UITEST_CAPTURE_APP_STORE_SCREENSHOTS"]?.lowercased()
        return value == "1" || value == "true" || value == "yes"
            || FileManager.default.fileExists(atPath: screenshotCaptureFlagURL.path)
    }

    private var screenshotCaptureFlagURL: URL {
        screenshotRootDirectory.deletingLastPathComponent()
            .appendingPathComponent(".capture-app-store-screenshots")
    }

    var shouldRunExtendedScenarios: Bool {
        let value = ProcessInfo.processInfo.environment["UITEST_RUN_EXTENDED_SCENARIOS"]?.lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    private var screenshotRootDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("AppStoreShots", isDirectory: true)
    }

    private var screenshotOutputDirectory: URL {
        let environmentFamily = ProcessInfo.processInfo.environment["UITEST_SCREENSHOT_DEVICE_FAMILY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceFamily = environmentFamily?.isEmpty == false
            ? environmentFamily!
            : (UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")
        return screenshotRootDirectory.appendingPathComponent(deviceFamily, isDirectory: true)
    }

    func prepareScreenshotDirectory() {
        guard shouldWriteAppStoreScreenshots else { return }
        let manager = FileManager.default
        let directory = screenshotOutputDirectory
        if manager.fileExists(atPath: directory.path) {
            try? manager.removeItem(at: directory)
        }
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func saveScreenshot(_ app: XCUIApplication, named name: String, line: UInt = #line) {
        guard shouldWriteAppStoreScreenshots else { return }
        let url = screenshotOutputDirectory.appendingPathComponent("\(name).png")
        do {
            try FileManager.default.createDirectory(at: screenshotOutputDirectory, withIntermediateDirectories: true)
            try XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        } catch {
            XCTFail("截图保存失败: \(error.localizedDescription)", line: line)
        }
    }

    func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    func launchApp(
        skipOnboarding: Bool = true,
        resetState: Bool = false,
        enableBackupPreview: Bool = false,
        allowClearWithoutBackup: Bool = false,
        backupRoundTripSlot: String? = nil,
        dynamicTypeSize: String? = nil,
        languageCode: String = "zh-Hans"
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ui-testing", "-languageCode", languageCode, "-AppleLanguages", "(\(languageCode))"]
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
        if allowClearWithoutBackup {
            app.launchArguments += ["-uitest-allow-clear-without-backup"]
            app.launchEnvironment["UITEST_ALLOW_CLEAR_WITHOUT_BACKUP"] = "1"
        }
        if let backupRoundTripSlot {
            app.launchEnvironment["UITEST_BACKUP_ROUNDTRIP"] = "1"
            app.launchEnvironment["UITEST_BACKUP_ROUNDTRIP_SLOT"] = backupRoundTripSlot
        }
        if let dynamicTypeSize {
            app.launchArguments += ["-uitest-dynamic-type-size", dynamicTypeSize]
            app.launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] = dynamicTypeSize
        }
        app.launch()
        return app
    }

    func tapPrimaryModule(_ app: XCUIApplication, name: String) {
        let tabIdentifier: String? = switch name {
        case "工作台": "house.fill"
        case "项目": "building.2.fill"
        case "工具箱": "books.vertical.fill"
        case "随手记": "square.and.pencil"
        case "我的": "person.circle"
        default: nil
        }

        if let tabIdentifier,
           app.tabBars.buttons[tabIdentifier].waitForExistence(timeout: 2) {
            app.tabBars.buttons[tabIdentifier].tap()
            return
        }

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

    func waitForPrimaryModule(_ app: XCUIApplication, name: String, timeout: TimeInterval = 5) -> Bool {
        if app.tabBars.buttons[name].waitForExistence(timeout: timeout) {
            return true
        }
        if app.buttons[name].waitForExistence(timeout: timeout) {
            return true
        }
        return app.staticTexts[name].waitForExistence(timeout: timeout)
    }

    func button(
        _ app: XCUIApplication,
        identifier: String,
        scrollingAttempts: Int = 4
    ) -> XCUIElement {
        let button = app.buttons[identifier]
        if button.waitForExistence(timeout: 2), button.isHittable {
            return button
        }

        for attempt in 0..<scrollingAttempts {
            performSearchScroll(app, attempt: attempt)

            if button.waitForExistence(timeout: 1), button.isHittable {
                break
            }
        }
        return button
    }

    func element(
        _ app: XCUIApplication,
        identifier: String,
        scrollingAttempts: Int = 6
    ) -> XCUIElement {
        let match = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if match.waitForExistence(timeout: 2), match.isHittable {
            return match
        }

        for attempt in 0..<scrollingAttempts {
            performSearchScroll(app, attempt: attempt)

            if match.waitForExistence(timeout: 1), match.isHittable {
                break
            }
        }
        return match
    }

    private func performSearchScroll(_ app: XCUIApplication, attempt: Int) {
        let shouldSwipeUp = attempt % 2 == 0
        let table = app.tables.firstMatch
        let scrollView = app.scrollViews.firstMatch
        let collectionView = app.collectionViews.firstMatch

        if table.exists, !table.frame.isEmpty {
            shouldSwipeUp ? table.swipeUp() : table.swipeDown()
            return
        }

        if scrollView.exists, !scrollView.frame.isEmpty {
            shouldSwipeUp ? scrollView.swipeUp() : scrollView.swipeDown()
            return
        }
        if collectionView.exists, !collectionView.frame.isEmpty {
            shouldSwipeUp ? collectionView.swipeUp() : collectionView.swipeDown()
            return
        }
        shouldSwipeUp ? app.swipeUp() : app.swipeDown()
    }

    func waitForElementByScrollingDown(
        _ element: XCUIElement,
        in container: XCUIElement,
        attempts: Int = 12,
        timeoutPerAttempt: TimeInterval = 1
    ) -> Bool {
        if element.waitForExistence(timeout: timeoutPerAttempt) {
            return true
        }

        for _ in 0..<attempts {
            container.swipeUp()

            if element.waitForExistence(timeout: timeoutPerAttempt) {
                return true
            }
        }
        return false
    }

    func openDataSafetyCenter(_ app: XCUIApplication) {
        for attempt in 0..<3 {
            tapPrimaryModule(app, name: "我的")

            if app.navigationBars["我的"].waitForExistence(timeout: 2) {
                let dataEntry = button(app, identifier: "profile-data-management-link", scrollingAttempts: 8)
                if dataEntry.waitForExistence(timeout: 4), dataEntry.isHittable {
                    dataEntry.tap()
                    if app.navigationBars["数据安全中心"].waitForExistence(timeout: 10) {
                        return
                    }
                }

                let dataLabel = app.staticTexts["数据管理"]
                if dataLabel.waitForExistence(timeout: 2), dataLabel.isHittable {
                    dataLabel.tap()
                    if app.navigationBars["数据安全中心"].waitForExistence(timeout: 10) {
                        return
                    }
                }
            }

            // AXXXL 字号下 tab 切换偶发失效，补一次明确点击 profile 图标。
            let profileTabByIdentifier = app.buttons["person.circle"]
            if profileTabByIdentifier.waitForExistence(timeout: 1), profileTabByIdentifier.isHittable {
                profileTabByIdentifier.tap()
            }

            if attempt == 2 {
                break
            }
        }

        XCTFail("Unable to open profile data management entry")
    }

    func openSampleDataImportConfirmation(_ app: XCUIApplication) {
        openDataSafetyCenter(app)

        let directImportButton = app.buttons["data-management-import-sample-data"]
        if directImportButton.waitForExistence(timeout: 2), directImportButton.isHittable {
            directImportButton.tap()
        } else {
            let actionMenu = app.buttons["data-management-actions-menu"]
            XCTAssertTrue(actionMenu.waitForExistence(timeout: 5))
            actionMenu.tap()
            let importButton = app.buttons["导入测试数据"]
            XCTAssertTrue(importButton.waitForExistence(timeout: 5))
            importButton.tap()
        }

        XCTAssertTrue(app.alerts["恢复测试数据？"].waitForExistence(timeout: 5))
    }

    func importSampleDataThroughUI(_ app: XCUIApplication) {
        openSampleDataImportConfirmation(app)
        app.alerts["恢复测试数据？"].buttons["清空并导入"].tap()
        XCTAssertTrue(app.staticTexts["已恢复测试数据"].waitForExistence(timeout: 8))
    }

    func ensureDashboardBusinessMetricsVisible(_ app: XCUIApplication) {
        let metricId = "dashboard-business-receivable-aging"
        let metric = app.descendants(matching: .any).matching(identifier: metricId).firstMatch
        if metric.waitForExistence(timeout: 1) {
            return
        }

        let moreOverviewButton = app.buttons["更多概况"]
        if moreOverviewButton.waitForExistence(timeout: 2), moreOverviewButton.isHittable {
            moreOverviewButton.tap()
            _ = metric.waitForExistence(timeout: 3)
            return
        }

        let moreOverviewText = app.staticTexts["更多概况"]
        if moreOverviewText.waitForExistence(timeout: 2), moreOverviewText.isHittable {
            moreOverviewText.tap()
            _ = metric.waitForExistence(timeout: 3)
        }
    }

    @discardableResult
    func openImportedProject(
        _ app: XCUIApplication,
        preferredName: String = "阳光花园 3# 楼"
    ) -> String {
        let preferredProject = app.staticTexts[preferredName]
        if preferredProject.waitForExistence(timeout: 6) {
            preferredProject.tap()
            return preferredName
        }

        let rowButton = app.buttons["project-list-row"].firstMatch
        if rowButton.waitForExistence(timeout: 4), rowButton.isHittable {
            rowButton.tap()
        } else {
            let firstCollectionCell = app.collectionViews.cells.firstMatch
            if firstCollectionCell.waitForExistence(timeout: 4), firstCollectionCell.isHittable {
                firstCollectionCell.tap()
            } else {
                let firstTableCell = app.tables.cells.firstMatch
                if firstTableCell.waitForExistence(timeout: 4), firstTableCell.isHittable {
                    firstTableCell.tap()
                } else {
                    XCTFail("Unable to open any project row after sample import")
                }
            }
        }

        let navigationBar = app.navigationBars.firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: 6))
        return navigationBar.identifier
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
        app.tabBars.buttons["随手记"].tap()

        XCTAssertTrue(app.navigationBars["随手记"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["发送随手记"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["从相册添加媒体"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["拍照添加"].exists)
        XCTAssertTrue(app.buttons["录制语音"].exists)
        XCTAssertTrue(app.buttons["quick-note-add-drawing"].exists)
        XCTAssertTrue(app.buttons["导入文件附件"].exists)
    }

    func testQuickNoteCompactComposerCanOpenDrawingBoard() {
        let app = launchApp()
        app.tabBars.buttons["随手记"].tap()

        let drawingButton = app.buttons["quick-note-add-drawing"]
        XCTAssertTrue(drawingButton.waitForExistence(timeout: 5))
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
        let app = launchApp(resetState: true)
        app.tabBars.buttons["项目"].tap()

        let browserButton = app.buttons["project-file-browser-entry"]
        XCTAssertTrue(browserButton.waitForExistence(timeout: 5))
        browserButton.tap()

        XCTAssertTrue(app.navigationBars["项目资料"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["暂无项目资料"].waitForExistence(timeout: 5))
    }

    func testClearLocalDataFlowRequiresConfirmationPhrase() {
        let app = launchApp(resetState: true, allowClearWithoutBackup: true)
        app.tabBars.buttons["我的"].tap()

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
        app.buttons["取消"].tap()
    }

    func testBackupOverwriteImportShowsSecondConfirmation() {
        let app = launchApp(resetState: true, enableBackupPreview: true)
        openDataSafetyCenter(app)

        let actionMenu = app.buttons["data-management-actions-menu"]
        XCTAssertTrue(actionMenu.waitForExistence(timeout: 5))
        actionMenu.tap()

        let previewButton = app.buttons["ui-test-backup-preview"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5))
        let confirmShortcutButton = app.buttons["ui-test-overwrite-confirm"]
        XCTAssertTrue(confirmShortcutButton.waitForExistence(timeout: 5))
        confirmShortcutButton.tap()

        let overwriteAlert = app.alerts["确认覆盖导入？"]
        XCTAssertTrue(overwriteAlert.waitForExistence(timeout: 5))
        overwriteAlert.buttons["取消"].tap()
    }

    func testProjectDeliveryGuideReachesExportActionWithSampleData() throws {
        try XCTSkipUnless(shouldRunExtendedScenarios, "Set UITEST_RUN_EXTENDED_SCENARIOS=1 to run project delivery sample-data scenario tests.")
        let app = launchApp(resetState: true)
        importSampleDataThroughUI(app)

        tapPrimaryModule(app, name: "项目")
        let openedProjectName = openImportedProject(app)
        XCTAssertFalse(openedProjectName.isEmpty)
        let moreMenu = app.buttons["project-detail-more-menu"]
        XCTAssertTrue(moreMenu.waitForExistence(timeout: 5))
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

        for item in cases {
            let metricEntry = element(app, identifier: item.buttonId, scrollingAttempts: 8)
            XCTAssertTrue(metricEntry.waitForExistence(timeout: 6), "Missing metric entry: \(item.buttonId)")
            XCTAssertTrue(metricEntry.isHittable, "Metric entry not hittable: \(item.buttonId)")
            metricEntry.tap()

            XCTAssertTrue(app.navigationBars["项目"].waitForExistence(timeout: 6))
            XCTAssertTrue(app.staticTexts[item.filterId].waitForExistence(timeout: 6), "Missing overview filter marker: \(item.filterId)")

            let backButton = app.navigationBars.buttons.firstMatch
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
        let dashboardBackButton = app.navigationBars.buttons.firstMatch
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
        XCTAssertTrue(app.navigationBars["项目资料"].waitForExistence(timeout: 5))
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

        app.buttons["工具箱"].tap()
        saveScreenshot(app, named: "screenshot2_database")

        app.buttons["随手记"].tap()
        saveScreenshot(app, named: "screenshot3_quicknote")
    }
}
