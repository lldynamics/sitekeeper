import XCTest

extension SitekeeperUITests {
    func testStorageFailureBlocksEditingAndRetryPreservesExistingProject() {
        let app = launchStorageFailureFixture()
        let alert = app.alerts["数据读写异常"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        alert.buttons["知道了"].tap()
        let retry = app.buttons["storage-recovery-retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["project-create-open"].isHittable)
        attachScreenshot(app, named: "storage-failure-blocks-editing")
        retry.tap()
        XCTAssertTrue(retry.waitForNonExistence(timeout: 10))
        tapPrimaryModule(app, name: "项目")
        XCTAssertTrue(app.staticTexts["读取恢复保留项目"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["project-create-open"].isEnabled)
        app.terminate()
        _ = launchApp(resetState: false)
        tapPrimaryModule(app, name: "项目")
        XCTAssertTrue(app.staticTexts["读取恢复保留项目"].firstMatch.waitForExistence(timeout: 10))
    }

    func testStorageFailureKeepsBackupRecoveryAccessible() {
        let app = launchStorageFailureFixture(dynamicTypeSize: "accessibility5")
        let alert = app.alerts["数据读写异常"]
        XCTAssertTrue(alert.waitForExistence(timeout: 15))
        alert.buttons["知道了"].tap()
        let restore = app.buttons["storage-recovery-restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        let recovery = app.scrollViews.containing(.button, identifier: "storage-recovery-restore").firstMatch
        for _ in 0..<6 {
            if restore.isHittable { break }
            recovery.swipeUp()
        }
        XCTAssertTrue(restore.isHittable)
        restore.tap()
        let cancelImporter = app.buttons.matching(NSPredicate(format: "label IN %@", ["取消", "Cancel"])).firstMatch
        XCTAssertTrue(cancelImporter.waitForExistence(timeout: 10))
        XCTAssertTrue(cancelImporter.isEnabled)
        cancelImporter.tap()
        XCTAssertTrue(app.descendants(matching: .any)["backup-local-form"].waitForExistence(timeout: 10))
        attachScreenshot(app, named: "storage-failure-recovery-remains-accessible")
    }

    func testClearAllIncludesTrialCopyAndKeepsItWhenCancelled() {
        let app = launchApp(resetState: true, allowClearWithoutBackup: true)
        openSafetySettings(app)
        app.buttons["repository-workspace-entry"].tap()
        let create = app.buttons["repository-workspace-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        let close = app.buttons["repository-workspace-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20))
        close.tap()
        let copy = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "repository-workspace-open-")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10))
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        openClearConfirmation(app)
        XCTAssertTrue(app.staticTexts["- 试用副本 1 条"].exists)
        let warning = app.descendants(matching: .any)["clear-repository-copies-warning"]
        XCTAssertTrue(warning.exists)
        clearDataConfirmationAction(app, title: "取消").tap()
        XCTAssertTrue(app.textFields["确认删除数据"].waitForNonExistence(timeout: 5))
        app.buttons["repository-workspace-entry"].tap()
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        openClearConfirmation(app)
        let phrase = app.textFields["确认删除数据"]
        phrase.tap()
        phrase.typeText("确认删除数据")
        clearDataConfirmationAction(app, title: "确认清空").tap()
        XCTAssertTrue(phrase.waitForNonExistence(timeout: 15))
        let result = app.staticTexts["clear-local-data-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        XCTAssertEqual(result.label, "本机数据已清空")
        app.buttons["repository-workspace-entry"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertFalse(copy.exists)
        app.terminate()
        _ = launchApp(resetState: false)
        openSafetySettings(app)
        app.buttons["repository-workspace-entry"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertFalse(copy.exists)
        attachScreenshot(app, named: "clear-all-removes-trial-copies-after-relaunch")
    }

    func testIndividualTrialCopyDeleteKeepsOtherCopy() {
        let app = launchApp(resetState: true)
        openSafetySettings(app)
        app.buttons["repository-workspace-entry"].tap()
        let create = app.buttons["repository-workspace-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        for _ in 0..<2 {
            create.tap()
            let close = app.buttons["repository-workspace-close"]
            XCTAssertTrue(close.waitForExistence(timeout: 20))
            close.tap()
            XCTAssertTrue(create.waitForExistence(timeout: 10))
        }
        let copies = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "repository-workspace-open-"))
        XCTAssertEqual(copies.count, 2)
        let originalIdentifiers = Set(copies.allElementsBoundByIndex.map(\.identifier))
        let manager = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "repository-workspace-manage-")).firstMatch
        manager.tap()
        XCTAssertTrue(app.buttons["导出副本备份"].waitForExistence(timeout: 5))
        app.buttons["删除试用副本"].tap()
        let confirmation = app.alerts["删除试用副本"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(confirmation.waitForNonExistence(timeout: 5))
        XCTAssertEqual(Set(copies.allElementsBoundByIndex.map(\.identifier)), originalIdentifiers)
        manager.tap()
        app.buttons["删除试用副本"].tap()
        let delete = confirmation.buttons["删除试用副本"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let removed = NSPredicate(format: "count == 1")
        let removal = XCTNSPredicateExpectation(predicate: removed, object: copies)
        let result = XCTWaiter.wait(for: [removal], timeout: 10)
        if result != .completed {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            attachScreenshot(app, named: "trial-copy-delete-diagnostic")
        }
        XCTAssertEqual(result, .completed, "Expected one remaining copy; found \(copies.count)")
        let survivor = copies.firstMatch.identifier
        XCTAssertTrue(originalIdentifiers.contains(survivor))
        app.terminate()
        _ = launchApp(resetState: false)
        openSafetySettings(app)
        app.buttons["repository-workspace-entry"].tap()
        XCTAssertTrue(app.buttons[survivor].waitForExistence(timeout: 5))
        XCTAssertEqual(copies.count, 1)
    }

    private func launchStorageFailureFixture(dynamicTypeSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-uitest-reset-state", "-uitest-skip-onboarding", "-languageCode", "zh-Hans", "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment["UITEST_STORAGE_RECOVERY_FIXTURE"] = "1"
        if let dynamicTypeSize { app.launchEnvironment["UITEST_DYNAMIC_TYPE_SIZE"] = dynamicTypeSize }
        app.launch()
        return app
    }

    private func openSafetySettings(_ app: XCUIApplication) {
        tapPrimaryModule(app, name: "我的")
        let settings = button(app, identifier: "profile-settings-link", scrollingAttempts: 8)
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
    }

    private func openClearConfirmation(_ app: XCUIApplication) {
        app.buttons["清空本机全部数据（需先备份）"].tap()
        let next = app.buttons["继续清空"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        XCTAssertTrue(app.textFields["确认删除数据"].waitForExistence(timeout: 5))
    }
}
