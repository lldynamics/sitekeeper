import XCTest
import UIKit

extension SitekeeperUITests {
    func testProjectKeyboardToolbarNavigatesFieldsAndSurvivesRotation() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchApp(skipOnboarding: false, resetState: true)
        enterProjectNameUsingKeyboardToolbar(app)
        enterProjectAmountsUsingKeyboardNavigation(app)
        submitProjectAfterKeyboardInput(app)
    }

    private func enterProjectNameUsingKeyboardToolbar(_ app: XCUIApplication) {
        let create = app.buttons["onboarding-create-project"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()

        let name = app.textFields["project-create-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        app.typeText("Keyboard Navigation Project")
        dismissKeyboardUsingToolbar(app)
        XCTAssertEqual(name.value as? String, "Keyboard Navigation Project")
    }

    private func enterProjectAmountsUsingKeyboardNavigation(_ app: XCUIApplication) {
        let form = app.descendants(matching: .any).matching(identifier: "project-create-form").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        let contract = app.textFields["project-create-contract-amount"]
        revealKeyboardTestField(contract, in: form)
        contract.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["keyboard-previous"].isEnabled)
        app.typeText("12000")
        XCTAssertEqual(contract.value as? String, "12000")

        // iPhone supports portrait only; iPad must keep the focused field through rotation.
        if UIDevice.current.userInterfaceIdiom == .pad {
            rotateKeyboardTestApp(app, to: .landscapeLeft)
        }

        tapKeyboardToolbarButton(app, identifier: "keyboard-next")
        app.typeText("2000")
        let paid = app.textFields["project-create-paid-amount"]
        XCTAssertEqual(paid.value as? String, "2000")

        // Leave material cost empty, then navigate backwards into it to verify both directions.
        tapKeyboardToolbarButton(app, identifier: "keyboard-next")
        tapKeyboardToolbarButton(app, identifier: "keyboard-next")
        app.typeText("4000")
        let labor = app.textFields["project-create-labor-cost"]
        XCTAssertEqual(labor.value as? String, "4000")
        XCTAssertFalse(app.buttons["keyboard-next"].isEnabled)

        tapKeyboardToolbarButton(app, identifier: "keyboard-previous")
        app.typeText("3000")
        let material = app.textFields["project-create-material-cost"]
        XCTAssertEqual(material.value as? String, "3000")
        if UIDevice.current.userInterfaceIdiom == .pad {
            rotateKeyboardTestApp(app, to: .portrait)
        }
        dismissKeyboardUsingToolbar(app)
    }

    private func submitProjectAfterKeyboardInput(_ app: XCUIApplication) {
        for (identifier, expectedValue) in [
            ("project-create-contract-amount", "12000"),
            ("project-create-paid-amount", "2000"),
            ("project-create-material-cost", "3000"),
            ("project-create-labor-cost", "4000")
        ] {
            XCTAssertEqual(app.textFields[identifier].value as? String, expectedValue)
        }
        app.buttons["project-create-submit"].tap()
        XCTAssertTrue(app.navigationBars["新建工程"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Keyboard Navigation Project"].firstMatch.waitForExistence(timeout: 5))
    }

    func testCalculatorKeyboardDoneDismissesAndAllowsFurtherInput() {
        XCUIDevice.shared.orientation = .portrait
        let app = launchApp(resetState: true)
        tapPrimaryModule(app, name: "工具箱")
        let calculators = element(app, identifier: "快速计算", scrollingAttempts: 8)
        XCTAssertTrue(calculators.isHittable)
        calculators.tap()
        let electrical = app.buttons["电气"]
        XCTAssertTrue(electrical.waitForExistence(timeout: 5))
        electrical.tap()
        let currentCalculator = app.staticTexts["电流计算"].firstMatch
        XCTAssertTrue(currentCalculator.waitForExistence(timeout: 5))
        currentCalculator.tap()
        XCTAssertTrue(app.navigationBars["电流计算"].waitForExistence(timeout: 5))

        let power = app.textFields["例如 10"]
        XCTAssertTrue(power.waitForExistence(timeout: 5))
        power.tap()
        app.typeText("12")
        dismissKeyboardUsingToolbar(app)
        XCTAssertEqual(power.value as? String, "12")

        let voltage = app.textFields["220"]
        XCTAssertTrue(voltage.isHittable)
        voltage.doubleTap()
        app.typeText("380")
        dismissKeyboardUsingToolbar(app)
        XCTAssertEqual(voltage.value as? String, "380")
        XCTAssertEqual(power.value as? String, "12")
    }

    func testCalculatorInputsResetOnReentryAndHistoryRequiresExplicitSave() {
        let app = launchApp(resetState: true)
        tapPrimaryModule(app, name: "工具箱")
        element(app, identifier: "快速计算", scrollingAttempts: 8).tap()
        app.buttons["电气"].tap()
        app.staticTexts["电流计算"].firstMatch.tap()
        let power = app.textFields["例如 10"]
        XCTAssertTrue(power.waitForExistence(timeout: 5))
        power.tap()
        app.typeText("12")
        dismissKeyboardUsingToolbar(app)
        app.buttons["计算"].tap()
        let saveHistory = element(app, identifier: "calculator-save-history", scrollingAttempts: 8)
        XCTAssertTrue(saveHistory.isEnabled)
        app.buttons["calculator-open-history"].tap()
        XCTAssertTrue(app.staticTexts["还没有计算历史"].waitForExistence(timeout: 5))
        app.navigationBars["历史计算"].buttons.element(boundBy: 0).tap()
        saveHistory.tap()
        XCTAssertFalse(saveHistory.isEnabled)
        app.buttons["calculator-open-history"].tap()
        let inputs = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "输入: 12"))
        XCTAssertTrue(inputs.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(inputs.count, 1)
        app.navigationBars["历史计算"].buttons.element(boundBy: 0).tap()
        app.navigationBars["电流计算"].buttons.element(boundBy: 0).tap()
        app.staticTexts["电流计算"].firstMatch.tap()
        XCTAssertTrue(power.waitForExistence(timeout: 5))
        XCTAssertEqual(power.value as? String, "例如 10")
        power.tap()
        app.typeText("99")
        dismissKeyboardUsingToolbar(app)
        app.terminate()
        let restarted = launchApp()
        tapPrimaryModule(restarted, name: "工具箱")
        element(restarted, identifier: "快速计算", scrollingAttempts: 8).tap()
        restarted.buttons["电气"].tap()
        restarted.staticTexts["电流计算"].firstMatch.tap()
        XCTAssertTrue(restarted.textFields["例如 10"].waitForExistence(timeout: 5))
        XCTAssertEqual(restarted.textFields["例如 10"].value as? String, "例如 10")
        attachScreenshot(restarted, named: "Calculator inputs reset after reentry and restart")
    }

    func testCalculatorDraftGenerationRequiresProjectSelectionAndReview() {
        let app = launchApp(resetState: true)
        let projectName = "Calculator Draft Target"
        tapPrimaryModule(app, name: "项目")
        let create = app.buttons["project-create-open"]
        XCTAssertTrue(create.waitForExistence(timeout: 8))
        create.tap()
        let projectNameField = app.textFields["project-create-name"]
        XCTAssertTrue(projectNameField.waitForExistence(timeout: 5))
        projectNameField.tap()
        projectNameField.typeText(projectName)
        app.buttons["project-create-submit"].tap()
        XCTAssertTrue(projectNameField.waitForNonExistence(timeout: 8))

        tapPrimaryModule(app, name: "工具箱")
        element(app, identifier: "快速计算", scrollingAttempts: 8).tap()
        app.buttons["电气"].tap()
        app.staticTexts["电流计算"].firstMatch.tap()
        let power = app.textFields["例如 10"]
        XCTAssertTrue(power.waitForExistence(timeout: 5))
        power.tap()
        app.typeText("12")
        dismissKeyboardUsingToolbar(app)
        app.buttons["计算"].tap()

        let material = element(app, identifier: "calculator-generate-material", scrollingAttempts: 10)
        XCTAssertTrue(material.exists)
        XCTAssertFalse(material.isEnabled, "Even a single project must be selected explicitly")
        let quote = app.buttons["calculator-generate-quote"]
        XCTAssertFalse(quote.isEnabled)
        let picker = element(app, identifier: "calculator-project-picker", scrollingAttempts: 10)
        picker.tap()
        app.buttons[projectName].tap()
        XCTAssertEqual(picker.value as? String, projectName)

        material.tap()
        XCTAssertTrue(app.navigationBars["核对材料单草稿"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[projectName].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["calculator-draft-review-notice"].exists)
        XCTAssertTrue(app.buttons["business-form-save"].isEnabled)
        attachScreenshot(app, named: "Calculator material draft target and pending quantity unit price review")
        app.navigationBars["核对材料单草稿"].buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["核对材料单草稿"].waitForNonExistence(timeout: 5))

        quote.tap()
        XCTAssertTrue(app.navigationBars["核对报价项"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[projectName].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["calculator-draft-review-notice"].exists)
        app.navigationBars["核对报价项"].buttons["取消"].tap()
        XCTAssertTrue(app.navigationBars["核对报价项"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(quote.isEnabled)
    }

    func testQuickNoteKeyboardDonePreservesDraft() {
        let app = launchApp(resetState: true)
        tapPrimaryModule(app, name: "随手记")
        let input = app.textViews["quick-note-content-input"].exists
            ? app.textViews["quick-note-content-input"]
            : app.textFields["quick-note-content-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        app.typeText("Keyboard draft")
        attachScreenshot(app, named: "Quick note keyboard toolbar")
        dismissKeyboardUsingToolbar(app)
        XCTAssertEqual(input.value as? String, "Keyboard draft")
        XCTAssertTrue(app.buttons["发送随手记"].isHittable)
    }

    func testLaborSheetKeyboardToolbarStaysWithinTheForm() {
        let app = launchApp(resetState: true)
        tapPrimaryModule(app, name: "工具箱")
        element(app, identifier: "人工记录", scrollingAttempts: 10).tap()
        let add = app.buttons["labor-add-record"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let workType = app.textFields["labor-work-type-input"]
        XCTAssertTrue(workType.waitForExistence(timeout: 5))
        workType.tap()
        app.typeText("Keyboard Crew")
        dismissKeyboardUsingToolbar(app)

        let workers = element(app, identifier: "labor-workers-input")
        XCTAssertTrue(workers.isHittable)
        workers.tap()
        tapKeyboardToolbarButton(app, identifier: "keyboard-next")
        XCTAssertTrue(app.buttons["keyboard-previous"].isEnabled)
        dismissKeyboardUsingToolbar(app)
        workers.tap()
        XCTAssertTrue(app.buttons["keyboard-done"].waitForExistence(timeout: 5))
        dismissFloatingKeyboardPreview(app)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.navigationBars.buttons["取消"].tap()
        XCTAssertTrue(workType.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["keyboard-done"].exists)
        add.tap()
        XCTAssertTrue(workType.waitForExistence(timeout: 5))
        workType.tap()
        dismissKeyboardUsingToolbar(app)
        app.navigationBars.buttons["取消"].tap()
    }

    private func dismissKeyboardUsingToolbar(_ app: XCUIApplication) {
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Keyboard toolbar before dismissal")
        tapKeyboardToolbarButton(app, identifier: "keyboard-done")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }

    func tapKeyboardToolbarButton(_ app: XCUIApplication, identifier: String) {
        dismissFloatingKeyboardPreview(app)
        let control = app.buttons[identifier]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        XCTAssertTrue(control.isEnabled)
        if UIDevice.current.userInterfaceIdiom == .pad,
           !control.isHittable, app.frame.contains(CGPoint(x: control.frame.midX, y: control.frame.midY)) {
            // iPad's decimal keypad popover can intercept the first tap on the
            // visible toolbar. Dismiss that layer before navigating or finishing input.
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if identifier == "keyboard-done", app.keyboards.firstMatch.waitForNonExistence(timeout: 2) { return }
            let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: control)
            XCTAssertEqual(XCTWaiter.wait(for: [hittable], timeout: 3), .completed)
        }
        XCTAssertTrue(control.isHittable)
        control.tap()
    }

    private func revealKeyboardTestField(_ field: XCUIElement, in form: XCUIElement) {
        for _ in 0..<16 {
            if field.exists, field.isHittable { return }
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let end = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("The project amount field did not become visible after scrolling.")
    }

    private func rotateKeyboardTestApp(_ app: XCUIApplication, to orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let expectedLandscape = orientation.isLandscape
        let rotation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let frame = app.frame
                return expectedLandscape ? frame.width > frame.height : frame.height > frame.width
            },
            object: app
        )
        XCTAssertEqual(XCTWaiter.wait(for: [rotation], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["keyboard-done"].waitForExistence(timeout: 5))
        dismissFloatingKeyboardPreview(app)
        XCTAssertTrue(app.buttons["keyboard-done"].isHittable)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Keyboard toolbar after rotation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
