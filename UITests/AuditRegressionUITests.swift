import XCTest
import UIKit

extension SitekeeperUITests {
    func testIPadOnboardingProjectComposerDoesNotReopenAfterModuleSwitch() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Requires the iPad split navigation shell.")
        let app = launchApp(skipOnboarding: false, resetState: true)
        let onboardingCreate = app.buttons["onboarding-create-project"]
        let projectNameField = app.textFields["project-create-name"]
        let projectName = "Onboarding Navigation Project"

        XCTAssertTrue(onboardingCreate.waitForExistence(timeout: 5))
        onboardingCreate.tap()
        XCTAssertTrue(projectNameField.waitForExistence(timeout: 5))
        app.navigationBars["新建工程"].buttons["取消"].tap()
        XCTAssertTrue(projectNameField.waitForNonExistence(timeout: 5))

        // Cancelling consumes only this request; a new onboarding action must still work.
        XCTAssertTrue(onboardingCreate.waitForExistence(timeout: 5))
        onboardingCreate.tap()
        XCTAssertTrue(projectNameField.waitForExistence(timeout: 5))
        projectNameField.tap()
        projectNameField.typeText(projectName)
        app.buttons["project-create-submit"].tap()
        XCTAssertTrue(projectNameField.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["首次设置"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[projectName].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        assertIPadProjectListReturnsWithoutComposer(app, projectName: projectName)

        // The normal toolbar action remains available after the one-time request is consumed.
        let manualCreate = app.buttons["project-create-open"]
        XCTAssertTrue(manualCreate.waitForExistence(timeout: 5))
        manualCreate.tap()
        XCTAssertTrue(projectNameField.waitForExistence(timeout: 5))
        app.navigationBars["新建工程"].buttons["取消"].tap()
        XCTAssertTrue(projectNameField.waitForNonExistence(timeout: 5))
        assertIPadProjectListReturnsWithoutComposer(app, projectName: projectName)
    }

    private func assertIPadProjectListReturnsWithoutComposer(_ app: XCUIApplication, projectName: String) {
        tapPrimaryModule(app, name: "工具箱")
        XCTAssertTrue(app.navigationBars["工程工具箱"].waitForExistence(timeout: 5))
        tapPrimaryModule(app, name: "项目")
        XCTAssertTrue(app.staticTexts[projectName].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["project-create-name"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["project-create-open"].isHittable)
    }

    func testLocalBackupRoundTripRestoresClearedProjectAfterRestart() {
        let slot = UUID().uuidString
        let projectName = "Backup Round Trip Project"
        let app = launchApp(
            skipOnboarding: false,
            resetState: true,
            allowClearWithoutBackup: true,
            backupRoundTripSlot: slot
        )

        createProjectForBackupRoundTrip(app, named: projectName)
        exportAndValidateRoundTripBackup(app)
        clearLocalDataForBackupRoundTrip(app)

        tapPrimaryModule(app, name: "项目")
        XCTAssertFalse(app.staticTexts[projectName].waitForExistence(timeout: 2))

        restoreRoundTripBackup(app)

        persistAndRestart(app)
        let restarted = launchApp()
        tapPrimaryModule(restarted, name: "项目")
        XCTAssertTrue(restarted.staticTexts[projectName].firstMatch.waitForExistence(timeout: 8))
    }

    private func createProjectForBackupRoundTrip(_ app: XCUIApplication, named projectName: String) {
        let create = app.buttons.containing(.staticText, identifier: "新建项目").firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let name = app.textFields["project-create-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(projectName)
        app.buttons["project-create-submit"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
    }

    private func exportAndValidateRoundTripBackup(_ app: XCUIApplication) {
        openRoundTripBackupPage(app)
        let export = roundTripBackupElement(app, identifier: "backup-export-local")
        XCTAssertTrue(export.isHittable)
        export.tap()
        let ready = roundTripBackupElement(app, identifier: "ui-test-backup-roundtrip-ready")
        XCTAssertTrue(ready.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["ui-test-backup-roundtrip-restore"].isEnabled)
    }

    private func clearLocalDataForBackupRoundTrip(_ app: XCUIApplication) {
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        let settings = button(app, identifier: "profile-settings-link", scrollingAttempts: 8)
        XCTAssertTrue(settings.isHittable)
        settings.tap()
        app.buttons["清空本机全部数据（需先备份）"].tap()
        let continueClear = app.buttons["继续清空"]
        XCTAssertTrue(continueClear.waitForExistence(timeout: 5))
        continueClear.tap()
        let phrase = app.textFields["确认删除数据"]
        XCTAssertTrue(phrase.waitForExistence(timeout: 5))
        phrase.tap()
        phrase.typeText("确认删除数据")
        let confirmClear = clearDataConfirmationAction(app, title: "确认清空")
        XCTAssertTrue(confirmClear.isEnabled)
        confirmClear.tap()
        XCTAssertTrue(phrase.waitForNonExistence(timeout: 15))
        let clearResult = app.staticTexts["clear-local-data-result"]
        XCTAssertTrue(clearResult.waitForExistence(timeout: 15))
        XCTAssertEqual(clearResult.label, "本机数据已清空")
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
    }

    private func restoreRoundTripBackup(_ app: XCUIApplication) {
        openRoundTripBackupPage(app)
        let restore = roundTripBackupElement(app, identifier: "ui-test-backup-roundtrip-restore")
        XCTAssertTrue(restore.isEnabled)
        restore.tap()
        XCTAssertTrue(app.navigationBars["确认导入"].waitForExistence(timeout: 15))
        let confirmImport = app.buttons["backup-import-confirm"]
        XCTAssertTrue(waitForElementByScrollingDown(confirmImport, in: app, attempts: 24))
        confirmImport.tap()
        let status = roundTripBackupElement(app, identifier: "backup-status-message")
        XCTAssertTrue(status.exists)
        XCTAssertTrue(status.label.contains("导入完成"))
    }

    private func openRoundTripBackupPage(_ app: XCUIApplication) {
        openDataSafetyCenter(app)
        let shortcut = app.buttons["data-management-shortcut-backup"]
        XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
        shortcut.tap()
    }

    private func roundTripBackupElement(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        let match = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let form = UIDevice.current.userInterfaceIdiom == .pad
            ? app.scrollViews.containing(.button, identifier: "backup-export-local").firstMatch
            : app.descendants(matching: .any).matching(identifier: "backup-local-form").firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 5))
        for _ in 0..<30 {
            if match.waitForExistence(timeout: 1), match.isHittable { return match }
            // A full flick can skip the local actions when the safety header collapses.
            let start = form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            let end = start.withOffset(CGVector(dx: 0, dy: -100))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        }
        return match
    }

    func testEnglishLaborEntryUsesTranslatedLabels() {
        let app = launchApp(resetState: true, languageCode: "en")
        tapPrimaryModule(app, name: "Toolbox")
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
        let content = element(app, identifier: "daily-log-compose-content", scrollingAttempts: 8)
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
