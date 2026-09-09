import XCTest

extension SitekeeperUITests {
    func testEnglishLaborEntryUsesTranslatedLabels() {
        let app = launchApp(resetState: true, languageCode: "en")
        tapPrimaryModule(app, name: "工具箱")
        element(app, identifier: "Labor Records", scrollingAttempts: 10).tap()
        XCTAssertTrue(app.navigationBars["Labor Records"].waitForExistence(timeout: 5))
        app.buttons["labor-add-record"].tap()
        XCTAssertTrue(app.textFields["labor-work-type-input"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["工种"].exists)
        XCTAssertEqual(app.buttons["business-form-save"].label, "Save")
        attachScreenshot(app, named: "English labor entry")
    }

    func testCreatedProjectSurvivesRestart() {
        let app = launchApp(skipOnboarding: false, resetState: true)
        let create = app.buttons.containing(.staticText, identifier: "新建项目").firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let name = app.textFields["project-create-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Audit Project 2026")
        app.buttons["project-create-submit"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        persistAndRestart(app)
        let restarted = launchApp()
        tapPrimaryModule(restarted, name: "项目")
        XCTAssertTrue(restarted.staticTexts["Audit Project 2026"].firstMatch.waitForExistence(timeout: 8))
    }

    func testCreatedDailyLogSurvivesRestart() {
        let app = launchApp(resetState: true)
        button(app, identifier: "写日志").tap()
        let content = app.textFields["daily-log-compose-content"]
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        content.typeText("Audit concrete inspection complete")
        app.buttons["business-form-save"].tap()
        XCTAssertTrue(content.waitForNonExistence(timeout: 5))
        persistAndRestart(app)
        let restarted = launchApp()
        button(restarted, identifier: "写日志").tap()
        let cancel = restarted.buttons["取消"].firstMatch
        if cancel.waitForExistence(timeout: 3) { cancel.tap() }
        XCTAssertTrue(restarted.staticTexts["Audit concrete inspection complete"].firstMatch.waitForExistence(timeout: 8))
    }

    func testCustomLaborTypesRemainEditableAfterHistoryAndRestart() {
        let app = launchApp(resetState: true)
        openLaborRecords(app)
        addAuditLabor(app, workType: "Audit Electrician", team: "Audit Team A")
        addAuditLabor(app, workType: "Audit Plumber", team: "Audit Team B")
        persistAndRestart(app)
        let restarted = launchApp()
        openLaborRecords(restarted)
        let second = restarted.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Audit Plumber")).firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 8))
        let first = restarted.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Audit Electrician")).firstMatch
        XCTAssertTrue(first.exists)
    }

    private func openLaborRecords(_ app: XCUIApplication) {
        tapPrimaryModule(app, name: "工具箱")
        element(app, identifier: "人工记录", scrollingAttempts: 10).tap()
        XCTAssertTrue(app.navigationBars["人工记录"].waitForExistence(timeout: 5))
    }

    private func addAuditLabor(_ app: XCUIApplication, workType: String, team: String) {
        app.buttons["labor-add-record"].tap()
        for (identifier, value) in [
            ("labor-work-type-input", workType),
            ("labor-team-input", team),
            ("labor-workers-input", "2"),
            ("labor-duration-input", "1"),
            ("labor-rate-input", "300")
        ] {
            let field = element(app, identifier: identifier)
            XCTAssertTrue(field.exists)
            field.tap()
            if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
            field.typeText(value)
        }
        app.buttons["business-form-save"].tap()
        XCTAssertTrue(app.buttons["business-form-save"].waitForNonExistence(timeout: 5))
    }

    private func persistAndRestart(_ app: XCUIApplication) {
        // Backgrounding exercises the production scene-phase flush before process termination.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.terminate()
    }
}
