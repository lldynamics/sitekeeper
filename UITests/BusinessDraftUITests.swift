import XCTest

private enum DuoFoldTransitionError: Error {
    case invalidInitialWidth(stage: String)
    case resizeNotObserved(stage: String)
    case targetNotHittable(stage: String)
    case unverifiedDevice
}

extension SitekeeperUITests {
    func testDailyLogDraftKeepsTextAndKeyboardAcrossRotation() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let name = "Rotating Draft Project"
        var text = "Unsaved rotating inspection"
        var app = launchApp(resetState: true)
        createBusinessDraftTestProject(app, named: name)
        openDailyLogDraftFromDashboard(app, projectName: name)
        let content = businessDraftField(app, identifier: "daily-log-compose-content")
        content.tap()
        // A tap can stop the animated form scroll before it focuses the editor.
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) { content.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        content.typeText(text)
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            rotateAndVerifySupportedSceneGeometry(app, to: orientation)
            assertBusinessDraftValue(content, equals: text)
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            content.tap()
            content.typeText(" retained")
            text += " retained"
            assertBusinessDraftValue(content, equals: text)
            attachScreenshot(app, named: "Daily log draft retained after device orientation change")
        }
        assertBusinessDraftValue(content, equals: text)
        cancelBusinessDraftForm(app, title: "写日志", field: content)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.terminate()
        app = launchApp()
        openDailyLogDraftFromDashboard(app, projectName: name)
        assertBusinessDraftValue(businessDraftField(app, identifier: "daily-log-compose-content"), equals: text)
    }

    func testUnfinishedDailyLogDraftSurvivesRestartCancelAndExplicitDiscard() {
        let projectName = "Daily Draft Recovery Project"
        let contentText = "Draft inspection still unfinished; retain this exact text."
        var app = launchApp(resetState: true)
        createBusinessDraftTestProject(app, named: projectName)
        openDailyLogDraftFromDashboard(app, projectName: projectName)
        let content = businessDraftField(app, identifier: "daily-log-compose-content")
        content.tap()
        content.typeText(contentText)
        assertBusinessDraftValue(content, equals: contentText)
        attachScreenshot(app, named: "Unfinished daily log before forced termination")

        // No Save or Cancel: only the automatic draft writer can recover this form.
        app.terminate()
        app = launchApp()
        openDailyLogDraftFromDashboard(app, projectName: projectName)
        let recovered = businessDraftField(app, identifier: "daily-log-compose-content")
        assertBusinessDraftValue(recovered, equals: contentText)
        attachScreenshot(app, named: "Daily log draft recovered after restart")

        cancelBusinessDraftForm(app, title: "写日志", field: recovered)
        app.terminate()
        app = launchApp()
        openDailyLogDraftFromDashboard(app, projectName: projectName)
        let retained = businessDraftField(app, identifier: "daily-log-compose-content")
        assertBusinessDraftValue(retained, equals: contentText)

        discardBusinessDraft(app, identifier: "daily-log-discard-draft", field: retained)
        app.terminate()
        app = launchApp()
        openDailyLogDraftFromDashboard(app, projectName: projectName)
        assertBusinessDraftEmpty(businessDraftField(app, identifier: "daily-log-compose-content"))
        attachScreenshot(app, named: "Daily log form blank after explicit draft discard")
    }

    func testDailyLogWeatherStartsUnselectedAndManualWeatherSurvivesRestart() {
        let name = "Weather Observation Project"
        var app = launchApp(resetState: true)
        createBusinessDraftTestProject(app, named: name)
        openDailyLogDraftFromDashboard(app, projectName: name)
        let picker = button(app, identifier: "daily-log-weather-picker", scrollingAttempts: 10)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertEqual(picker.value as? String, "待填写")
        picker.tap()
        app.buttons["大雨"].tap()
        XCTAssertEqual(picker.value as? String, "大雨")
        app.terminate()
        app = launchApp()
        openDailyLogDraftFromDashboard(app, projectName: name)
        let restoredPicker = button(app, identifier: "daily-log-weather-picker", scrollingAttempts: 10)
        XCTAssertEqual(restoredPicker.value as? String, "大雨")
        attachScreenshot(app, named: "Actual site weather restored from draft")
    }

    func testFinancialDraftRestoresRawAmountAndNoteThenCommitsExactlyOnce() {
        let projectName = "Financial Draft Recovery Project"
        let noteText = "Draft finance once-only ledger evidence"
        var app = launchApp(resetState: true)
        createBusinessDraftTestProject(app, named: projectName)
        openFinancialDraftFromDashboard(app, projectName: projectName)
        let amount = businessDraftField(app, identifier: "finance-draft-amount")
        amount.tap()
        amount.typeText("12.")
        dismissFloatingKeyboardPreview(app)
        let note = businessDraftField(app, identifier: "finance-draft-note")
        note.tap()
        note.typeText(noteText)
        assertBusinessDraftValue(amount, equals: "12.")
        assertBusinessDraftValue(note, equals: noteText)
        attachScreenshot(app, named: "Raw unfinished financial amount before forced termination")

        // Relaunch without resetting or manually saving the business record.
        app.terminate()
        app = launchApp()
        openFinancialDraftFromDashboard(app, projectName: projectName)
        let recoveredAmount = businessDraftField(app, identifier: "finance-draft-amount")
        assertBusinessDraftValue(recoveredAmount, equals: "12.")
        let recoveredNote = businessDraftField(app, identifier: "finance-draft-note")
        assertBusinessDraftValue(recoveredNote, equals: noteText)
        attachScreenshot(app, named: "Exact financial draft values recovered after restart")

        let amountToFinish = businessDraftField(app, identifier: "finance-draft-amount")
        amountToFinish.tap()
        amountToFinish.typeText("34")
        assertBusinessDraftValue(amountToFinish, equals: "12.34")
        dismissFloatingKeyboardPreview(app)
        let keyboardDone = app.buttons["keyboard-done"]
        if keyboardDone.exists, keyboardDone.isHittable { keyboardDone.tap() }
        let save = app.buttons["business-form-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 5), .completed)
        // A rapid repeated confirmation must not append a second ledger record.
        save.doubleTap()
        XCTAssertTrue(amountToFinish.waitForNonExistence(timeout: 10))
        assertSingleFinancialDraftLedgerRecord(app, note: noteText)

        app.terminate()
        app = launchApp()
        openFinancialDraftFromDashboard(app, projectName: projectName)
        let freshAmount = businessDraftField(app, identifier: "finance-draft-amount")
        assertBusinessDraftEmpty(freshAmount)
        assertBusinessDraftEmpty(businessDraftField(app, identifier: "finance-draft-note"))
        XCTAssertFalse(app.buttons["business-form-save"].isEnabled)
        attachScreenshot(app, named: "New financial form blank after successful draft commit")
        cancelBusinessDraftForm(app, title: "项目记账", field: freshAmount)
        assertSingleFinancialDraftLedgerRecord(app, note: noteText)
    }

    func testProjectWorkspaceSelectionAndEditorSurviveRotation() {
        let app = launchApp(resetState: true)
        let first = "Split Project Alpha"
        let second = "Split Project Beta"
        createBusinessDraftTestProject(app, named: first)
        createBusinessDraftTestProject(app, named: second)
        app.staticTexts[first].firstMatch.tap()
        XCTAssertTrue(app.navigationBars[first].waitForExistence(timeout: 5))
        let more = app.buttons["project-detail-more-menu"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        app.buttons["编辑项目资料"].tap()
        let name = app.textFields["工程名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" draft")
        XCTAssertEqual(name.value as? String, first + " draft")
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        // This covers rotation only. Native Duo folding has a separate preflight and case.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, first + " draft")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        attachScreenshot(app, named: "Project split editor after rotation")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(name.value as? String, first + " draft")
        app.navigationBars["编辑资料"].buttons["取消"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars[first].exists)

        let secondRow = app.staticTexts[second].firstMatch
        if !secondRow.isHittable {
            // Duo may place the system back control in its side toolbar.
            let back = app.buttons["BackButton"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            back.tap()
        }
        XCTAssertTrue(secondRow.waitForExistence(timeout: 5))
        XCTAssertTrue(secondRow.isHittable)
        secondRow.tap()
        XCTAssertTrue(app.navigationBars[second].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Project split changed selection after editor cancellation")
    }

    func testDuoProjectWorkspaceEditorSurvivesNativeFoldCycle() throws {
        try requireDuoFoldSession()
        let app = launchApp(resetState: true)
        let project = "Duo Split Project"
        let otherProject = "Duo Other Project"
        createBusinessDraftTestProject(app, named: project)
        createBusinessDraftTestProject(app, named: otherProject)
        app.staticTexts[project].firstMatch.tap()
        XCTAssertTrue(app.navigationBars[project].waitForExistence(timeout: 5))
        app.buttons["project-detail-more-menu"].tap()
        app.buttons["编辑项目资料"].tap()
        let name = app.textFields["工程名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(" draft")
        XCTAssertEqual(name.value as? String, project + " draft")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        attachScreenshot(app, named: "Project editor draft before native fold cycle")
        let foldedWidth = app.frame.width
        // Scene geometry supplements the native controller receipt; field width alone is insufficient.
        try waitForDuoResize(app, app: app, stage: "project-editor-expand")
        XCTAssertEqual(name.value as? String, project + " draft")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText(" retained")
        try waitForDuoResize(app, app: app, stage: "project-editor-fold", returningToWidth: foldedWidth)
        XCTAssertEqual(name.value as? String, project + " draft retained")
        let done = app.buttons["keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, project + " draft retained")
        attachScreenshot(app, named: "Project editor retained through native fold cycle")
        app.navigationBars["编辑资料"].buttons["取消"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars[project].exists)

        // Cancelling the retained editor must return to the same selected project.
        app.buttons["project-detail-more-menu"].tap()
        app.buttons["编辑项目资料"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, project)
        app.navigationBars["编辑资料"].buttons["取消"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))

        // A stale split selection must not prevent opening another project after folding.
        let otherProjectRow = app.staticTexts[otherProject].firstMatch
        if !otherProjectRow.isHittable {
            let back = app.buttons["BackButton"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 3))
            back.tap()
        }
        XCTAssertTrue(otherProjectRow.waitForExistence(timeout: 5))
        XCTAssertTrue(otherProjectRow.isHittable)
        otherProjectRow.tap()
        XCTAssertTrue(app.navigationBars[otherProject].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Duo project selection usable after native fold and editor cancellation")
    }

    // Opt-in native Device Hub fold/unfold run; never substitute rotation or a trait override.
    func testDuoDailyLogKeepsUnsavedTextAndKeyboardAcrossFoldCycle() throws {
        try requireDuoFoldSession()
        let app = launchApp(resetState: true)
        createBusinessDraftTestProject(app, named: "Duo State Project")
        openDailyLogDraftFromDashboard(app, projectName: "Duo State Project")
        let content = businessDraftField(app, identifier: "daily-log-compose-content")
        content.tap()
        content.typeText("Duo unsaved inspection")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let foldedWidth = app.frame.width
        try waitForDuoResize(content, app: app, stage: "editor-expand")
        XCTAssertTrue(app.navigationBars["写日志"].exists)
        assertBusinessDraftValue(content, equals: "Duo unsaved inspection")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText(" retained")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        try waitForDuoResize(content, app: app, stage: "editor-fold", returningToWidth: foldedWidth)
        XCTAssertTrue(app.navigationBars["写日志"].exists)
        assertBusinessDraftValue(content, equals: "Duo unsaved inspection retained")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText(" twice")
        let done = app.buttons["keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        assertBusinessDraftValue(content, equals: "Duo unsaved inspection retained twice")
        attachScreenshot(app, named: "Duo folded editor retained text and dismissed keyboard")
        app.terminate()
        app.launchArguments.removeAll { $0 == "-uitest-reset-state" }
        app.launchEnvironment.removeValue(forKey: "UITEST_RESET_STATE")
        app.launch()
        openDailyLogDraftFromDashboard(app, projectName: "Duo State Project")
        assertBusinessDraftValue(businessDraftField(app, identifier: "daily-log-compose-content"),
                                equals: "Duo unsaved inspection retained twice")
    }

    func requireDuoFoldSession() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SITEKEEPER_DUO_INTERACTIVE"] == "1" else {
            throw XCTSkip("Requires the dedicated Duo device and native Device Hub fold controls.")
        }
        try XCTSkipUnless(
            environment["SITEKEEPER_DUO_POSTURE_VERIFIED"] == "1",
            "Requires a successful native posture-control preflight for this device session."
        )
        let session = environment["SITEKEEPER_DUO_PREFLIGHT_SESSION"] ?? ""
        try XCTSkipUnless(UUID(uuidString: session) != nil, "Requires this run's native preflight receipt UUID.")
        guard let expected = UUID(uuidString: environment["SITEKEEPER_DUO_EXPECTED_UDID"] ?? ""),
              let actual = UUID(uuidString: environment["SIMULATOR_UDID"] ?? ""), expected == actual else {
            throw DuoFoldTransitionError.unverifiedDevice
        }
        FileHandle.standardOutput.write(Data("DUO_SESSION \(session) device=\(actual.uuidString)\n".utf8))
    }

    func waitForDuoResize(
        _ element: XCUIElement, app: XCUIApplication, stage: String, returningToWidth: CGFloat? = nil
    ) throws {
        // Measure the scene: a capped form or PDF search field need not widen when it does.
        // Geometry alone is not native-fold evidence; requireDuoFoldSession gates the session.
        let width = app.frame.width
        guard width > 0 else { throw DuoFoldTransitionError.invalidInitialWidth(stage: stage) }
        FileHandle.standardOutput.write(Data("DUO_READY \(stage) width=\(width)\n".utf8))
        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard element.exists, abs(app.frame.width - width) > 60 else { return false }
            return returningToWidth.map { abs(app.frame.width - $0) <= 8 } ?? true
        }, object: nil)
        guard XCTWaiter.wait(for: [resized], timeout: 90) == .completed else {
            throw DuoFoldTransitionError.resizeNotObserved(stage: stage)
        }
        // Native display handoff updates scene bounds before UIKit finishes its
        // keyboard, sheet and hit-test layout. Require the target to settle too.
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            element.exists && element.isHittable
        }, object: nil)
        guard XCTWaiter.wait(for: [hittable], timeout: 20) == .completed else {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Native transition target unavailable \(stage)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            attachScreenshot(app, named: "Native transition target unavailable \(stage)")
            throw DuoFoldTransitionError.targetNotHittable(stage: stage)
        }
        attachScreenshot(app, named: "Duo native transition \(stage)")
        FileHandle.standardOutput.write(Data("DUO_RESIZED \(stage) width=\(app.frame.width)\n".utf8))
    }

    private func createBusinessDraftTestProject(_ app: XCUIApplication, named projectName: String) {
        tapPrimaryModule(app, name: "项目")
        let create = app.buttons["project-create-open"]
        XCTAssertTrue(create.waitForExistence(timeout: 8))
        create.tap()
        let name = app.textFields["project-create-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(projectName)
        app.buttons["project-create-submit"].tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts[projectName].firstMatch.waitForExistence(timeout: 8))
    }

    private func openBusinessDraftDashboard(_ app: XCUIApplication, projectName: String) {
        // Wait for actual persisted project loading before choosing the project-scoped draft.
        tapPrimaryModule(app, name: "项目")
        XCTAssertTrue(app.staticTexts[projectName].firstMatch.waitForExistence(timeout: 10))
        tapPrimaryModule(app, name: "工作台")
    }

    private func openDailyLogDraftFromDashboard(_ app: XCUIApplication, projectName: String) {
        openBusinessDraftDashboard(app, projectName: projectName)
        let writeLog = button(app, identifier: "写日志", scrollingAttempts: 8)
        XCTAssertTrue(writeLog.isHittable)
        writeLog.tap()
        // Opening the form must not scroll past its weather/date controls.
        XCTAssertTrue(app.navigationBars["写日志"].waitForExistence(timeout: 5))
    }

    private func openFinancialDraftFromDashboard(_ app: XCUIApplication, projectName: String) {
        openBusinessDraftDashboard(app, projectName: projectName)
        let bookkeeping = button(app, identifier: "记账", scrollingAttempts: 8)
        XCTAssertTrue(bookkeeping.isHittable)
        bookkeeping.tap()
        XCTAssertTrue(app.navigationBars["项目记账"].waitForExistence(timeout: 5))
    }

    private func businessDraftField(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        let field = element(app, identifier: identifier, scrollingAttempts: 10)
        XCTAssertTrue(field.exists)
        XCTAssertTrue(field.isHittable)
        return field
    }

    private func assertBusinessDraftValue(_ field: XCUIElement, equals value: String, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, line: line)
        XCTAssertEqual(field.value as? String, value, line: line)
    }

    private func assertBusinessDraftEmpty(_ field: XCUIElement, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let value = field.value as? String ?? ""
            return value.isEmpty || value == field.placeholderValue
        }, object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, line: line)
    }

    private func cancelBusinessDraftForm(_ app: XCUIApplication, title: String, field: XCUIElement) {
        let cancel = app.navigationBars[title].buttons["取消"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
    }

    private func discardBusinessDraft(_ app: XCUIApplication, identifier: String, field: XCUIElement) {
        let discard = button(app, identifier: identifier, scrollingAttempts: 10)
        XCTAssertTrue(discard.isHittable)
        discard.tap()
        // Exclude the form's trigger, which has the same visible destructive title.
        let confirmation = app.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", "丢弃草稿", identifier
        )).firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
    }

    private func assertSingleFinancialDraftLedgerRecord(_ app: XCUIApplication, note: String) {
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", note))
        XCTAssertTrue(waitForElementByScrollingDown(rows.firstMatch, in: app, attempts: 18))
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows.firstMatch.label.contains("12.34"))
        attachScreenshot(app, named: "Exactly one persisted financial ledger record")
    }
}
