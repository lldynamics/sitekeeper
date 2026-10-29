import XCTest
import UIKit

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
        if let path = ProcessInfo.processInfo.environment["UITEST_SCREENSHOT_OUTPUT_DIRECTORY"],
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
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
        languageCode: String = "zh-Hans",
        reviewRegressionFixture: Bool = false,
        workflowOptimizationFixture: Bool = false,
        duoWorkflowFixture: Bool = false,
        duoScrollFixture: Bool = false
    ) -> XCUIApplication {
        if ProcessInfo.processInfo.environment["UITEST_REQUIRE_ANIMATIONS"] == "1" {
            let reducesMotion = UIAccessibility.isReduceMotionEnabled
            XCTAssertFalse(reducesMotion, "Animation regression requires Reduce Motion to be off")
        }
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
        if reviewRegressionFixture {
            app.launchEnvironment["UITEST_REVIEW_REGRESSION_FIXTURE"] = "1"
        }
        app.launchEnvironment["UITEST_WORKFLOW_OPTIMIZATION_FIXTURE"] = workflowOptimizationFixture ? "1" : "0"
        app.launchEnvironment["UITEST_DUO_WORKFLOW_FIXTURE"] = duoWorkflowFixture ? "1" : "0"
        app.launchEnvironment["UITEST_DUO_SCROLL_FIXTURE"] = duoScrollFixture ? "1" : "0"
        app.launch()
        return app
    }

    func tapPrimaryModule(_ app: XCUIApplication, name: String) {
        let moduleIDs = [
            "工作台": "dashboard", "Dashboard": "dashboard", "项目": "records", "Projects": "records",
            "工具箱": "checklist", "Toolbox": "checklist", "随手记": "quickNote", "Quick Notes": "quickNote",
            "我的": "profile", "My Profile": "profile"
        ]
        if let moduleID = moduleIDs[name] {
            let sidebarModule = app.buttons["primary-module-\(moduleID)"]
            if sidebarModule.exists, sidebarModule.isHittable {
                sidebarModule.tap()
                return
            }
        }

        let compactMenu = app.descendants(matching: .any)["primary-module-menu"].firstMatch
        if compactMenu.exists, compactMenu.isHittable {
            compactMenu.tap()
            let option = app.buttons[name].firstMatch
            guard option.waitForExistence(timeout: 3), option.isHittable else {
                XCTFail("Missing primary module in navigation menu: \(name)")
                return
            }
            option.tap()
            return
        }

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

    func dismissFloatingKeyboardPreview(_ app: XCUIApplication) {
        // iPad's floating keypad captures taps and hides the form's other fields.
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let keypad = app.popovers.keys["1"]
        guard keypad.waitForExistence(timeout: 2) else { return }
        let regions = app.otherElements.matching(identifier: "PopoverDismissRegion")
        guard let dismiss = regions.allElementsBoundByIndex.last(where: { $0.isHittable }) else {
            XCTFail("Floating keypad has no dismissal region")
            return
        }
        dismiss.tap()
        XCTAssertTrue(keypad.waitForNonExistence(timeout: 5))
    }

    func clearDataConfirmationAction(_ app: XCUIApplication, title: String) -> XCUIElement {
        let action = app.buttons[title]
        let form = app.scrollViews.containing(.textField, identifier: "确认删除数据").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        for _ in 0..<6 {
            var viewport = form.frame.intersection(app.frame)
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists, keyboard.frame.intersects(viewport) {
                viewport.size.height = max(0, min(viewport.maxY, keyboard.frame.minY) - viewport.minY)
            }
            // AX can mark a clipped button hittable when only its top edge is visible.
            if action.exists, action.isHittable, viewport.insetBy(dx: 0, dy: 8).contains(action.frame) {
                return action
            }
            XCTAssertGreaterThan(viewport.height, 40)
            // Keep the drag above the keyboard, which can cover most of an iPhone form.
            let start = form.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: viewport.midX - form.frame.minX,
                dy: viewport.minY - form.frame.minY + viewport.height * 0.65
            ))
            let distance = min(140, viewport.height * 0.35)
            let direction: CGFloat = action.exists && action.frame.maxY < viewport.minY ? 1 : -1
            let end = start.withOffset(CGVector(dx: 0, dy: distance * direction))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Clear-data action is not fully visible: \(title)")
        return action
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
        // Expand the search in both directions instead of bouncing between the
        // same two offsets, which cannot reveal a lazy row above the start.
        var remaining = attempt
        var distance = 1
        while remaining >= distance {
            remaining -= distance
            distance += 1
        }
        let shouldSwipeUp = !distance.isMultiple(of: 2)
        let candidates = app.tables.allElementsBoundByIndex
            + app.collectionViews.allElementsBoundByIndex + app.scrollViews.allElementsBoundByIndex
        // An iPad keyboard accessory can expose a 49-point horizontal scroll view.
        // Scroll the actual form instead of selecting the first scroll view by type.
        let visible = candidates.filter { $0.isHittable && $0.frame.height > 100 }
        let frontNavigation = app.navigationBars.allElementsBoundByIndex.last { $0.isHittable }
        let foreground = visible.filter { candidate in
            guard let navigation = frontNavigation else { return false }
            return abs(candidate.frame.minX - navigation.frame.minX) < 2
                && abs(candidate.frame.width - navigation.frame.width) < 2
        }
        let container = (foreground.isEmpty ? visible : foreground)
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        if let container {
            shouldSwipeUp ? container.swipeUp() : container.swipeDown()
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
        let backup = app.buttons["data-management-shortcut-backup"]
        if backup.exists && backup.isHittable { backup.tap() }

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
        XCTAssertTrue(app.alerts["恢复测试数据？"].waitForNonExistence(timeout: 10))
        // The success toast can expire while XCTest waits for animations to idle.
        // Verify durable imported records rather than that transient notification.
        tapPrimaryModule(app, name: "项目")
        XCTAssertTrue(app.staticTexts["阳光花园 3# 楼"].firstMatch.waitForExistence(timeout: 10))
    }

    func rotateAndWaitForSceneResize(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
        let window = app.windows.firstMatch
        let width = window.frame.width
        XCUIDevice.shared.orientation = orientation
        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            window.exists && abs(window.frame.width - width) > 40
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 8), .completed)
    }

    func attachInterfaceSnapshot(_ app: XCUIApplication, named name: String) {
        attachScreenshot(app, named: name)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + " hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
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
