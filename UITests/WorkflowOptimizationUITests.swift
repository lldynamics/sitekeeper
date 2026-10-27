import XCTest

extension SitekeeperUITests {
    func testWeeklyProgressIncludesSpanningTasksAndExcludesOtherWeeks() {
        let app = launchWorkflowApp(resetState: true)
        openWorkflowDashboard(app)
        let overview = app.buttons["dashboard-more-overview"]
        if overview.exists { overview.tap() }
        let past = element(app, identifier: "Past Week Work", scrollingAttempts: 12)
        XCTAssertTrue(past.waitForExistence(timeout: 5))
        past.tap()
        XCTAssertTrue(app.navigationBars["施工进度"].waitForExistence(timeout: 5))
        let week = app.buttons["本周"]
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        week.tap()
        XCTAssertTrue(app.staticTexts["Spanning Week Work"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Inside Week Work"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Past Week Work"].exists)
        XCTAssertFalse(app.staticTexts["Next Week Work"].exists)
        attachScreenshot(app, named: "Weekly progress includes continuous construction")
    }

    func testTodoDraftRestoresTextAndBothPhotosAfterRestartCancelAndDiscard() {
        var app = launchWorkflowApp(resetState: true)
        openWorkflowTodoDraft(app)
        let title = element(app, identifier: "todo-draft-title", scrollingAttempts: 8)
        title.tap()
        title.typeText("Unfinished Workflow Todo")
        let owner = element(app, identifier: "todo-draft-owner", scrollingAttempts: 8)
        owner.tap()
        owner.typeText("Workflow Owner")
        let note = element(app, identifier: "todo-draft-note", scrollingAttempts: 8)
        note.tap()
        note.typeText("Exact unsaved inspection notes")
        app.terminate()
        app = launchWorkflowApp()
        openWorkflowTodoDraft(app)
        XCTAssertEqual(element(app, identifier: "todo-draft-title", scrollingAttempts: 8).value as? String, "Unfinished Workflow Todo")
        XCTAssertEqual(element(app, identifier: "todo-draft-owner", scrollingAttempts: 8).value as? String, "Workflow Owner")
        XCTAssertEqual(element(app, identifier: "todo-draft-note", scrollingAttempts: 8).value as? String, "Exact unsaved inspection notes")
        XCTAssertTrue(element(app, identifier: "todo-draft-before-photo", scrollingAttempts: 12).exists)
        XCTAssertTrue(element(app, identifier: "todo-draft-after-photo", scrollingAttempts: 12).exists)
        attachScreenshot(app, named: "Todo text and both draft photos restored")
        app.navigationBars["新增待办"].buttons["取消"].tap()
        app.terminate()
        app = launchWorkflowApp()
        openWorkflowTodoDraft(app)
        XCTAssertEqual(element(app, identifier: "todo-draft-title", scrollingAttempts: 8).value as? String, "Unfinished Workflow Todo")
        discardWorkflowTodoDraft(app)
        app.terminate()
        app = launchWorkflowApp()
        openWorkflowTodoDraft(app)
        let fresh = element(app, identifier: "todo-draft-title", scrollingAttempts: 8)
        XCTAssertTrue((fresh.value as? String ?? "").isEmpty || fresh.value as? String == fresh.placeholderValue)
        XCTAssertFalse(app.images["todo-draft-before-photo"].exists)
        XCTAssertFalse(app.images["todo-draft-after-photo"].exists)
    }

    func testTodoSaveCommitsOnceAndEditDraftNeedsExplicitRecovery() {
        var app = launchWorkflowApp(resetState: true)
        openWorkflowTodoDraft(app)
        let title = element(app, identifier: "todo-draft-title", scrollingAttempts: 8)
        title.tap()
        title.typeText("Workflow Saved Todo")
        app.buttons["todo-draft-save"].doubleTap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        app.terminate()
        app = launchWorkflowApp()
        openWorkflowDashboard(app)
        searchWorkflow(app, keyword: "Workflow Saved Todo")
        let resultID = "search-suggestion-todo-60000000-0000-0000-0000-000000000050"
        XCTAssertEqual(app.buttons.matching(identifier: resultID).count, 1)
        app.buttons[resultID].tap()
        let owner = element(app, identifier: "todo-draft-owner", scrollingAttempts: 8)
        owner.tap()
        owner.typeText("Unsaved owner")
        app.navigationBars["编辑待办"].buttons["取消"].tap()
        app.terminate()
        app = launchWorkflowApp()
        openWorkflowDashboard(app)
        searchWorkflow(app, keyword: "Workflow Saved Todo")
        app.buttons[resultID].tap()
        XCTAssertTrue(app.buttons["todo-restore-draft"].waitForExistence(timeout: 5))
        let currentOwner = element(app, identifier: "todo-draft-owner", scrollingAttempts: 8)
        XCTAssertNotEqual(currentOwner.value as? String, "Unsaved owner")
        app.buttons["todo-restore-draft"].tap()
        XCTAssertEqual(element(app, identifier: "todo-draft-owner", scrollingAttempts: 8).value as? String, "Unsaved owner")
        discardWorkflowTodoDraft(app)
        app.terminate()
        app = launchWorkflowApp()
        openWorkflowDashboard(app)
        searchWorkflow(app, keyword: "Workflow Saved Todo")
        app.buttons[resultID].tap()
        XCTAssertFalse(app.buttons["todo-restore-draft"].exists)
        XCTAssertNotEqual(element(app, identifier: "todo-draft-owner", scrollingAttempts: 8).value as? String, "Unsaved owner")
    }

    func testBusinessSearchFiltersByProjectAndTypeAndOpensExactQuote() {
        var app = launchWorkflowApp(resetState: true)
        openWorkflowDashboard(app)
        searchWorkflow(app, keyword: "SharedSearch")
        let firstID = "search-suggestion-quote-60000000-0000-0000-0000-000000000010"
        let secondID = "search-suggestion-quote-60000000-0000-0000-0000-000000000011"
        XCTAssertTrue(app.buttons[firstID].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[secondID].exists)
        app.buttons["dashboard-search-category-filter"].tap()
        app.buttons["财务记录"].tap()
        XCTAssertFalse(app.buttons[firstID].exists)
        app.buttons["dashboard-search-category-filter"].tap()
        app.buttons["预结算信息"].tap()
        XCTAssertTrue(app.buttons[firstID].waitForExistence(timeout: 5))
        app.buttons["dashboard-search-project-filter"].tap()
        app.buttons["Workflow Alpha"].tap()
        XCTAssertTrue(app.buttons[firstID].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons[secondID].exists)
        app.buttons[firstID].tap()
        let opened = app.navigationBars["编辑报价"].waitForExistence(timeout: 8)
        attachScreenshot(app, named: "Search quote destination")
        if !opened { print("Quote destination hierarchy: \(app.debugDescription)") }
        XCTAssertTrue(opened)
        XCTAssertEqual(app.textFields["项目名称"].value as? String, "SharedSearch")
        attachScreenshot(app, named: "Search project and type filters open exact quote")
        let save = app.buttons["business-form-save"]
        XCTAssertTrue(save.isEnabled)
        let name = app.textFields["项目名称"]
        name.tap()
        name.typeText(" Revised")
        save.tap()
        XCTAssertTrue(app.navigationBars["编辑报价"].waitForNonExistence(timeout: 8))
        app.terminate()
        app = launchWorkflowApp()
        openWorkflowDashboard(app)
        searchWorkflow(app, keyword: "SharedSearch")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "search-suggestion-quote-")).count, 2)
        XCTAssertEqual(app.buttons.matching(identifier: firstID).count, 1)
        XCTAssertTrue(app.buttons[firstID].label.contains("SharedSearch Revised"))
        app.buttons[firstID].tap()
        XCTAssertTrue(app.navigationBars["编辑报价"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.textFields["项目名称"].value as? String, "SharedSearch Revised")
    }

    func testBusinessSearchOpensExactFinancialRecord() {
        assertWorkflowSearchDestination(keyword: "INV-WORKFLOW-001", category: "financial", suffix: "020", title: "编辑账目")
    }

    func testBusinessSearchOpensExactHistoricalDrawing() {
        assertWorkflowSearchDestination(keyword: "DWG-WORKFLOW-001", category: "drawing", suffix: "040", title: "图纸详情")
    }

    func testBusinessSearchOpensExactDocument() {
        assertWorkflowSearchDestination(keyword: "DOC-WORKFLOW-001", category: "document", suffix: "030", title: "扫描件详情")
    }

    private func assertWorkflowSearchDestination(keyword: String, category: String, suffix: String, title: String) {
        let app = launchWorkflowApp(resetState: true)
        openWorkflowDashboard(app)
        searchWorkflow(app, keyword: keyword)
        let result = app.buttons["search-suggestion-\(category)-60000000-0000-0000-0000-000000000\(suffix)"]
        XCTAssertTrue(result.waitForExistence(timeout: 5), keyword)
        result.tap()
        let opened = app.navigationBars[title].waitForExistence(timeout: 8)
        attachScreenshot(app, named: "Search exact record \(category)")
        if !opened { print("Search destination hierarchy: \(app.debugDescription)") }
        XCTAssertTrue(opened, keyword)
        if category == "document" {
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", keyword)).firstMatch.waitForExistence(timeout: 5))
        }
    }

    private func launchWorkflowApp(resetState: Bool = false) -> XCUIApplication {
        launchApp(resetState: resetState, workflowOptimizationFixture: true)
    }

    private func openWorkflowDashboard(_ app: XCUIApplication) {
        tapPrimaryModule(app, name: "项目")
        XCTAssertTrue(app.staticTexts["Workflow Alpha"].firstMatch.waitForExistence(timeout: 12))
        tapPrimaryModule(app, name: "工作台")
    }

    private func searchWorkflow(_ app: XCUIApplication, keyword: String) {
        let search = app.textFields["搜索项目、票号、报价、图纸或资料"]
        if !search.isHittable { app.swipeDown() }
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText(keyword)
        if app.keyboards.firstMatch.exists { search.typeText("\n") }
    }

    private func openWorkflowTodoDraft(_ app: XCUIApplication) {
        openWorkflowDashboard(app)
        searchWorkflow(app, keyword: "新建待办")
        let command = app.buttons["search-suggestion-command-new-todo"]
        XCTAssertTrue(command.waitForExistence(timeout: 5))
        command.tap()
        XCTAssertTrue(app.navigationBars["新增待办"].waitForExistence(timeout: 5))
    }

    private func discardWorkflowTodoDraft(_ app: XCUIApplication) {
        let discard = element(app, identifier: "todo-discard-draft", scrollingAttempts: 12)
        discard.tap()
        let confirmation = app.buttons.matching(NSPredicate(
            format: "label == %@ AND identifier != %@", "丢弃草稿", "todo-discard-draft"
        )).firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.tap()
        XCTAssertTrue(app.buttons["todo-draft-save"].waitForNonExistence(timeout: 8))
    }
}
