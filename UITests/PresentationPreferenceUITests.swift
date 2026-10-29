import XCTest
import UIKit

extension SitekeeperUITests {
    func testIPadFloatingKeyboardMovementKeepsNavigationAccessible() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SITEKEEPER_IPAD_KEYBOARD"] == "1",
                          "Requires a dedicated iPad with the software keyboard enabled.")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .portrait
        let app = launchApp()
        tapPrimaryModule(app, name: "工具箱")
        element(app, identifier: "人工记录", scrollingAttempts: 10).tap()
        app.buttons["labor-add-record"].tap()
        let workers = element(app, identifier: "labor-workers-input")
        workers.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8))
        let deviceScreen = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let keyboardOnscreen = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            // In an iPad window the docked keyboard can be visible outside the app's frame.
            keyboard.frame.intersection(deviceScreen.frame).height > 50
        }, object: nil)
        guard XCTWaiter.wait(for: [keyboardOnscreen], timeout: 20) == .completed else {
            XCTFail("The software keyboard must be visible before testing movement.")
            return
        }
        if keyboard.frame.width >= app.frame.width * 0.8 {
            keyboard.pinch(withScale: 0.4, velocity: -1)
        }
        XCTAssertLessThan(keyboard.frame.width, app.frame.width * 0.8,
                          "The movement check requires the floating keyboard.")
        let firstPosition = keyboard.frame.midX < app.frame.midX
            ? ("lower right", CGVector(dx: 0.85, dy: 0.85))
            : ("upper left", CGVector(dx: 0.15, dy: 0.30))
        for (name, destination) in [
            firstPosition,
            ("upper center", CGVector(dx: 0.50, dy: 0.40)),
            ("upper left", CGVector(dx: 0.15, dy: 0.30))
        ] {
            let before = keyboard.frame
            keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.15))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: destination))
            attachScreenshot(app, named: "floating keyboard \(name)")
            XCTAssertNotEqual(keyboard.frame.origin, before.origin, "Keyboard must move to \(name).")
            let next = app.buttons["keyboard-next"]
            XCTAssertTrue(next.exists && next.isHittable, "Next must be accessible at \(name).")
            XCTAssertFalse(next.frame.intersects(keyboard.frame), "Next must not be covered at \(name).")
            next.tap()
            let previous = app.buttons["keyboard-previous"]
            XCTAssertTrue(previous.isEnabled && previous.isHittable, "Previous must work at \(name).")
            XCTAssertFalse(previous.frame.intersects(keyboard.frame), "Previous must not be covered at \(name).")
            attachScreenshot(app, named: "floating keyboard settled \(name)")
            let duration = app.textFields["labor-duration-input"]
            XCTAssertTrue(duration.waitForExistence(timeout: 5))
            XCTAssertTrue(next.isHittable, "The next numeric field must keep navigation reachable at \(name).")
            let keyboardBeforeFocusChange = keyboard.frame
            next.tap()
            let rate = app.textFields["labor-rate-input"]
            XCTAssertTrue(rate.waitForExistence(timeout: 5))
            let keyboardSettled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                keyboard.frame.width > 100 && keyboard.frame.height > 100
                    && abs(keyboard.frame.minX - keyboardBeforeFocusChange.minX) <= 1
                    && abs(keyboard.frame.minY - keyboardBeforeFocusChange.minY) <= 1
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [keyboardSettled], timeout: 5), .completed,
                           "This check requires the floating keyboard to stay in place after focus changes.")
            XCTAssertEqual(keyboard.frame.minX, keyboardBeforeFocusChange.minX, accuracy: 1,
                           "This check requires a stationary floating keyboard during focus change.")
            XCTAssertEqual(keyboard.frame.minY, keyboardBeforeFocusChange.minY, accuracy: 1,
                           "This check requires a stationary floating keyboard during focus change.")
            let unobscuredRate = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                // SwiftUI exposes the whole labeled row as the text field frame.
                // Its numeric text and caret are right aligned within that row.
                let inputPoint = CGPoint(x: rate.frame.maxX - min(20, rate.frame.width / 2), y: rate.frame.midY)
                return rate.isHittable && rate.frame.height > 0 && !keyboard.frame.contains(inputPoint)
            }, object: nil)
            let rateResult = XCTWaiter.wait(for: [unobscuredRate], timeout: 5)
            if rateResult != .completed {
                print("Rate frame: \(rate.frame), hittable: \(rate.isHittable), keyboard frame: \(keyboard.frame)")
                attachScreenshot(app, named: "floating keyboard rate field \(name)")
            }
            XCTAssertEqual(rateResult, .completed,
                           "The newly focused rate field must be reachable outside the floating keyboard at \(name).")
            let previousRate = rate.value as? String ?? ""
            keyboard.keys["1"].tap()
            XCTAssertNotEqual(rate.value as? String ?? "", previousRate,
                              "The visible rate input must accept numeric input at \(name).")
            previous.tap()
            previous.tap()
            if name == "upper center" {
                let done = app.buttons["keyboard-done"]
                XCTAssertTrue(done.exists && done.isHittable)
                done.tap()
                XCTAssertTrue(keyboard.waitForNonExistence(timeout: 5))
                workers.tap()
                XCTAssertTrue(keyboard.waitForExistence(timeout: 8))
            }
        }
        let cancel = app.buttons["keyboard-cancel"]
        XCTAssertTrue(cancel.exists && cancel.isHittable, "Cancel must remain reachable while the keyboard floats.")
        cancel.tap()
        XCTAssertFalse(app.buttons["keyboard-next"].exists)
    }

    func testIPadFloatingKeyboardAllowsTodoInput() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SITEKEEPER_IPAD_KEYBOARD"] == "1",
                          "Requires a dedicated iPad with the software keyboard enabled.")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .portrait
        let app = launchApp()
        let addTodo = app.buttons["加待办"].firstMatch
        XCTAssertTrue(addTodo.waitForExistence(timeout: 10))
        addTodo.tap()
        let note = app.descendants(matching: .any)["todo-draft-note"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        note.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8))
        if keyboard.frame.width >= app.frame.width * 0.8 {
            keyboard.pinch(withScale: 0.4, velocity: -1)
        }
        attachScreenshot(app, named: "iPad floating keyboard")
        XCTAssertLessThan(keyboard.frame.width, app.frame.width * 0.8,
                          "The system keyboard must actually be floating.")
        let original = note.value as? String ?? ""
        keyboard.keys["q"].tap()
        XCTAssertNotEqual(note.value as? String ?? "", original,
                          "The floating keyboard must enter text into the focused note.")
    }

    func testIPadFloatingKeyboardTodoCancelPreservesDraft() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SITEKEEPER_IPAD_KEYBOARD"] == "1",
                          "Requires a dedicated iPad with the software keyboard enabled.")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .portrait
        let app = launchApp()
        let addTodo = app.buttons["加待办"].firstMatch
        XCTAssertTrue(addTodo.waitForExistence(timeout: 10))
        addTodo.tap()
        let note = app.descendants(matching: .any)["todo-draft-note"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        note.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8))
        guard keyboard.frame.intersection(app.frame).height > 50 else {
            XCTFail("The software keyboard must be visible before testing movement.")
            return
        }
        if keyboard.frame.width >= app.frame.width * 0.8 {
            keyboard.pinch(withScale: 0.4, velocity: -1)
        }
        XCTAssertLessThan(keyboard.frame.width, app.frame.width * 0.8)
        let draft = note.value as? String ?? ""
        if keyboard.frame.midX < app.frame.midX * 1.3 || keyboard.frame.midY < app.frame.midY {
            keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.15))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.85)))
        }
        let before = keyboard.frame
        keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.15))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.30)))
        XCTAssertNotEqual(keyboard.frame.origin, before.origin)
        let cancel = app.buttons["keyboard-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5) && cancel.isHittable)
        cancel.tap()
        XCTAssertTrue(note.waitForNonExistence(timeout: 5))
        app.buttons["新建待办"].firstMatch.tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertEqual(note.value as? String ?? "", draft, "Cancel must preserve the existing todo draft.")
    }

    func testIPadFloatingKeyboardLaborNavigation() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SITEKEEPER_IPAD_KEYBOARD"] == "1",
                          "Requires a dedicated iPad with the software keyboard enabled.")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchApp()
        tapPrimaryModule(app, name: "工具箱")
        element(app, identifier: "人工记录", scrollingAttempts: 10).tap()
        let add = app.buttons["labor-add-record"]
        XCTAssertTrue(add.waitForExistence(timeout: 8))
        add.tap()
        let workers = element(app, identifier: "labor-workers-input")
        workers.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8))
        if keyboard.frame.width >= app.frame.width * 0.8 {
            keyboard.pinch(withScale: 0.4, velocity: -1)
        }
        XCTAssertLessThan(keyboard.frame.width, app.frame.width * 0.8)
        let next = app.buttons["keyboard-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        attachScreenshot(app, named: "iPad labor floating keyboard before navigation")
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertTrue(app.buttons["keyboard-previous"].isEnabled)
        attachScreenshot(app, named: "iPad labor floating keyboard")
        let done = app.buttons["keyboard-done"]
        XCTAssertTrue(done.isHittable)
        done.tap()
        app.navigationBars.buttons["取消"].firstMatch.tap()
    }

    func testIPadFloatingKeyboardQuotationNavigation() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SITEKEEPER_IPAD_KEYBOARD"] == "1",
                          "Requires a dedicated iPad with the software keyboard enabled.")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .portrait
        let app = launchApp()
        tapPrimaryModule(app, name: "工具箱")
        element(app, identifier: "预结算信息", scrollingAttempts: 12).tap()
        let more = app.buttons["更多操作"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 8))
        more.tap()
        app.buttons["从材料/人工生成报价"].tap()
        let mode = app.buttons["quotation-material-price-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.tap()
        app.buttons["统一设置对外报价"].tap()
        let price = app.textFields["quotation-generate-material-price"]
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        price.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8))
        if keyboard.frame.width >= app.frame.width * 0.8 {
            keyboard.pinch(withScale: 0.4, velocity: -1)
        }
        XCTAssertLessThan(keyboard.frame.width, app.frame.width * 0.8)
        let original = price.value as? String ?? ""
        keyboard.keys["1"].tap()
        XCTAssertNotEqual(price.value as? String ?? "", original)
        let next = app.buttons["keyboard-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isHittable)
        next.tap()
        XCTAssertTrue(app.buttons["keyboard-previous"].isEnabled)
        attachScreenshot(app, named: "iPad quotation floating keyboard")
        let done = app.buttons["keyboard-done"]
        XCTAssertTrue(done.isHittable)
        done.tap()
        app.navigationBars["生成报价"].buttons["取消"].tap()
    }

    func testIPadFloatingKeyboardQuotationCancelAfterMove() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SITEKEEPER_IPAD_KEYBOARD"] == "1",
                          "Requires a dedicated iPad with the software keyboard enabled.")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .portrait
        let app = launchApp()
        tapPrimaryModule(app, name: "工具箱")
        element(app, identifier: "预结算信息", scrollingAttempts: 12).tap()
        app.buttons["更多操作"].firstMatch.tap()
        app.buttons["从材料/人工生成报价"].tap()
        let mode = app.buttons["quotation-material-price-mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.tap()
        app.buttons["统一设置对外报价"].tap()
        let price = app.textFields["quotation-generate-material-price"]
        XCTAssertTrue(price.waitForExistence(timeout: 5))
        price.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8))
        guard keyboard.frame.intersection(app.frame).height > 50 else {
            XCTFail("The software keyboard must be visible before testing movement.")
            return
        }
        if keyboard.frame.width >= app.frame.width * 0.8 {
            keyboard.pinch(withScale: 0.4, velocity: -1)
        }
        XCTAssertLessThan(keyboard.frame.width, app.frame.width * 0.8)
        if keyboard.frame.midX > app.frame.midX * 0.7 && keyboard.frame.midX < app.frame.midX * 1.3 {
            keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.15))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.85)))
        }
        let before = keyboard.frame
        keyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.15))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.40)))
        XCTAssertNotEqual(keyboard.frame.origin, before.origin)
        let next = app.buttons["keyboard-next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5) && next.isHittable)
        next.tap()
        XCTAssertTrue(app.buttons["keyboard-previous"].isEnabled)
        let cancel = app.buttons["keyboard-cancel"]
        XCTAssertTrue(cancel.exists && cancel.isHittable)
        cancel.tap()
        XCTAssertTrue(price.waitForNonExistence(timeout: 5))
    }

    func testIPadTodoNoteStaysAboveSoftwareKeyboard() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SITEKEEPER_IPAD_KEYBOARD"] == "1",
                          "Requires a dedicated iPad with the software keyboard enabled.")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchApp()
        let addTodo = app.buttons["加待办"].firstMatch
        XCTAssertTrue(addTodo.waitForExistence(timeout: 10))
        addTodo.tap()
        let note = app.descendants(matching: .any)["todo-draft-note"].firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 8))
        note.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), "Software keyboard must be visible for this check.")
        if keyboard.frame.width < app.frame.width * 0.8 {
            keyboard.pinch(withScale: 4, velocity: 2)
        }
        XCTAssertGreaterThanOrEqual(keyboard.frame.width, app.frame.width * 0.8,
                                    "This check requires the full docked keyboard.")
        let positioned = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            note.frame.height > 0 && note.frame.maxY <= keyboard.frame.minY + 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [positioned], timeout: 5), .completed,
                       "The focused note must be fully above the keyboard.")
        keyboard.keys["q"].tap()
        XCTAssertTrue((note.value as? String ?? "").contains("q"),
                      "Typing on the software keyboard must reach the focused note.")
        attachScreenshot(app, named: "iPad todo note above software keyboard")
    }

    func testIPadLandscapeQuickActionsAreFullyVisible() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SITEKEEPER_IPAD_LAYOUT"] == "1",
                          "Requires a dedicated iPad simulator and synthetic repository fixture.")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-uitest-skip-onboarding", "-languageCode", "zh-Hans",
                               "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment["UITEST_REPOSITORY_FIXTURE"] = "1"
        app.launch()

        let header = app.scrollViews["dashboard-ipad-header-scroll"]
        XCTAssertTrue(header.waitForExistence(timeout: 15))
        for title in ["写日志", "加待办", "拍照片", "记账"] {
            let action = app.buttons[title].firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 5))
            XCTAssertTrue(action.isHittable, "Quick action must be reachable: \(title)")
            XCTAssertTrue(header.frame.contains(action.frame),
                          "Quick action must not be clipped by the header: \(title)")
        }
        attachScreenshot(app, named: "iPad landscape quick actions")
    }

    func testIPadAccessibilityNavigationKeepsModulesReachable() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SITEKEEPER_IPAD_LAYOUT"] == "1",
                          "Requires the dedicated wide iPad simulator.")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .portrait
        let app = launchApp(dynamicTypeSize: "accessibility5")
        for id in ["dashboard", "records", "checklist", "quickNote", "profile"] {
            let button = app.buttons["primary-module-\(id)"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            XCTAssertTrue(button.isHittable, "Navigation module must remain reachable: \(id)")
        }
        tapPrimaryModule(app, name: "工具箱")
        XCTAssertTrue(app.staticTexts["工程工具箱"].firstMatch.waitForExistence(timeout: 8))
        tapPrimaryModule(app, name: "工作台")
        XCTAssertTrue(app.buttons["primary-module-dashboard"].isSelected)
        attachScreenshot(app, named: "iPad maximum text size navigation")
    }

    func testIPadDashboardRemindersAndIndependentPanesRemainUsable() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SITEKEEPER_IPAD_LAYOUT"] == "1",
                          "Requires the dedicated wide iPad simulator and synthetic repository fixture.")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }

        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-uitest-skip-onboarding", "-languageCode", "zh-Hans",
                               "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment["UITEST_REPOSITORY_FIXTURE"] = "1"
        app.launchEnvironment["UITEST_REPOSITORY_FINANCE_FIXTURE"] = "1"
        app.launchEnvironment["UITEST_REPOSITORY_WAREHOUSE_FIXTURE"] = "1"
        app.launchEnvironment["UITEST_REPOSITORY_MATERIAL_FIXTURE"] = "1"
        app.launchEnvironment["UITEST_REPOSITORY_QUOTE_FIXTURE"] = "1"
        app.launch()

        let toggle = app.buttons["dashboard-risk-expansion-toggle"]
        let timeline = app.scrollViews["dashboard-ipad-timeline-scroll"]
        let overview = app.scrollViews["dashboard-ipad-overview-scroll"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15))
        XCTAssertTrue(toggle.isHittable, "Reminders must fit inside the visible iPad workspace.")
        XCTAssertTrue(timeline.waitForExistence(timeout: 5))
        XCTAssertTrue(overview.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(timeline.frame.height, 150)
        XCTAssertGreaterThan(overview.frame.height, 150)

        let core = app.staticTexts["经营核心"].firstMatch
        let insights = app.staticTexts["经营洞察"].firstMatch
        XCTAssertTrue(core.waitForExistence(timeout: 5))
        XCTAssertTrue(insights.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(insights.frame.minY, core.frame.maxY,
                             "Narrow overview columns must stack the business cards.")

        toggle.tap()
        XCTAssertTrue(app.buttons["dashboard-risk-missingReceipt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard-risk-missingTodayLog"].exists)

        let firstActivity = timeline.buttons.firstMatch
        XCTAssertTrue(firstActivity.waitForExistence(timeout: 5))
        let initialActivityY = firstActivity.frame.minY
        let todo = app.buttons["今日待办"].firstMatch
        XCTAssertTrue(todo.isHittable)
        let initialTodoY = todo.frame.minY
        timeline.swipeUp()
        XCTAssertLessThan(firstActivity.frame.minY, initialActivityY - 20)
        XCTAssertEqual(todo.frame.minY, initialTodoY, accuracy: 2,
                       "Scrolling the timeline must not move the overview pane.")
        XCTAssertTrue(toggle.isHittable)

        rotateAndWaitForSceneResize(app, to: .landscapeLeft)
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.value as? String, "已展开")
        XCTAssertTrue(timeline.isHittable)
        XCTAssertTrue(overview.isHittable)
        attachScreenshot(app, named: "iPad dashboard reminders and independent panes")
    }
}

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

    func testIPadRepeatedProjectDetailSectionJumps() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SITEKEEPER_DEMO_DETAIL_NAV"] == "1",
                          "Requires the dedicated iPad with the existing synthetic demonstration project.")
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .portrait
        let app = launchApp()
        tapPrimaryModule(app, name: "项目")
        let project = app.buttons.matching(identifier: "project-list-row")
            .matching(NSPredicate(format: "label CONTAINS %@", "青禾社区配套工程（演示）")).firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 10))
        project.tap()

        let picker = app.segmentedControls["项目详情焦点"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        let identifiedList = app.collectionViews["project-detail-list"]
        let list = identifiedList.exists ? identifiedList : app.collectionViews["project-workspace-detail"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))

        func assertVisible(_ anchor: String, label: String) {
            let header = app.staticTexts["project-detail-section-\(anchor)"]
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                header.isHittable && header.frame.height > 0
                    && header.frame.intersects(list.frame)
                    && header.frame.midY > picker.frame.maxY
            }, object: nil)
            let result = XCTWaiter.wait(for: [visible], timeout: 8)
            if result != .completed { attachScreenshot(app, named: "Section jump failed \(label)") }
            XCTAssertEqual(result, .completed, "Expected the \(label) section to be visible")
        }

        func manuallyReturnToOverview() {
            let overview = app.staticTexts["project-detail-section-overview"]
            for _ in 0..<20 where !overview.isHittable {
                list.swipeDown(velocity: .fast)
            }
            assertVisible("overview", label: "overview after manual scroll")
            let overviewSelected = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "selected == true"), object: picker.buttons["概览"]
            )
            XCTAssertEqual(XCTWaiter.wait(for: [overviewSelected], timeout: 5), .completed)
        }

        picker.buttons["成本"].tap()
        assertVisible("finance", label: "first cost selection")
        attachScreenshot(app, named: "First cost selection")
        manuallyReturnToOverview()
        attachScreenshot(app, named: "Manually returned to overview")
        picker.buttons["成本"].tap()
        assertVisible("finance", label: "repeated cost selection")
        attachScreenshot(app, named: "Repeated cost selection")

        picker.buttons["现场"].tap()
        assertVisible("records", label: "first site selection")
        manuallyReturnToOverview()
        picker.buttons["现场"].tap()
        assertVisible("records", label: "repeated site selection")
        attachScreenshot(app, named: "Repeated site selection")
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
