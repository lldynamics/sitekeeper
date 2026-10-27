import XCTest

extension SitekeeperUITests {
    func testLinkedInstallmentPartialOverpayThenSettlementSurvivesRestart() {
        var app = launchLinkedWorkflowApp(reset: true)
        openLinkedProjectCosts(app)
        button(app, identifier: "project.payment-plans", scrollingAttempts: 8).tap()
        let payID = "payment.installment.pay.70000000-0000-0000-0000-000000000011"
        XCTAssertTrue(app.buttons[payID].waitForExistence(timeout: 5))
        app.buttons[payID].tap()
        let amount = app.textFields["payment.actual.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        replaceLinkedText(amount, with: "30")
        app.buttons["payment.actual.save"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 10))
        app.buttons[payID].tap()
        XCTAssertEqual(amount.value as? String, "70")
        replaceLinkedText(amount, with: "71")
        app.buttons["payment.actual.save"].tap()
        XCTAssertTrue(app.staticTexts["收付金额、方向或关联期次不符合当前计划，请重新核对。"].waitForExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "71")
        replaceLinkedText(amount, with: "70")
        app.buttons["payment.actual.save"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.buttons[payID].exists)
        XCTAssertTrue(app.staticTexts["已结清"].firstMatch.exists)
        attachScreenshot(app, named: "Deposit settled and retention remains")
        app.terminate()
        app = launchLinkedWorkflowApp()
        openLinkedProjectCosts(app)
        button(app, identifier: "project.payment-plans", scrollingAttempts: 8).tap()
        XCTAssertTrue(app.staticTexts["已结清"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons[payID].exists)
        XCTAssertTrue(app.buttons["payment.installment.pay.70000000-0000-0000-0000-000000000012"].exists)
    }

    func testLinkedMaterialReceiptGeneratesOneDraftAndRetainsPlannedQuantity() {
        let app = launchLinkedWorkflowApp(reset: true)
        openLinkedProjectCosts(app)
        let receive = button(app, identifier: "material.receive.70000000-0000-0000-0000-000000000003", scrollingAttempts: 14)
        XCTAssertTrue(receive.exists)
        receive.tap()
        let quantity = app.textFields["material.receipt.quantity"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        quantity.tap()
        quantity.typeText("4")
        app.buttons["material.receipt.save"].tap()
        XCTAssertTrue(quantity.waitForNonExistence(timeout: 10))
        receive.tap()
        XCTAssertTrue(app.staticTexts["10 m"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["4 m"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["6 m"].firstMatch.exists)
        app.navigationBars["到货入库"].buttons["取消"].tap()
        app.swipeDown()
        button(app, identifier: "project.warehouse", scrollingAttempts: 16).tap()
        let cable = app.staticTexts["Linked Cable"].firstMatch
        XCTAssertTrue(cable.waitForExistence(timeout: 8))
        cable.tap()
        button(app, identifier: "入库记账", scrollingAttempts: 8).tap()
        let create = app.buttons["warehouse.ledger.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.doubleTap()
        XCTAssertTrue(app.buttons["打开关联账目"].waitForExistence(timeout: 10))
        XCTAssertFalse(create.exists)
        attachScreenshot(app, named: "Warehouse receipt linked to one bookkeeping draft")
    }

    func testLinkedMaterialPageNavigationShowsLaterRowsWithoutLosingFirstPage() {
        let app = launchLinkedWorkflowApp(reset: true)
        openLinkedProjectCosts(app)
        button(app, identifier: "下一页", scrollingAttempts: 14).tap()
        XCTAssertTrue(app.staticTexts["Paged Material 50"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Linked Cable"].exists)
        button(app, identifier: "上一页", scrollingAttempts: 8).tap()
        XCTAssertTrue(app.staticTexts["Linked Cable"].firstMatch.waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Bounded material pages preserve all records")
    }

    private func launchLinkedWorkflowApp(reset: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-uitest-skip-onboarding", "-languageCode", "zh-Hans", "-AppleLanguages", "(zh-Hans)"]
        if reset { app.launchArguments.append("-uitest-reset-state") }
        app.launchEnvironment["UITEST_LINKED_WORKFLOW_FIXTURE"] = "1"
        app.launch()
        return app
    }

    private func openLinkedProjectCosts(_ app: XCUIApplication) {
        tapPrimaryModule(app, name: "项目")
        let project = app.staticTexts["Linked Site"].firstMatch
        XCTAssertTrue(project.waitForExistence(timeout: 12))
        project.tap()
        button(app, identifier: "成本", scrollingAttempts: 6).tap()
        XCTAssertTrue(button(app, identifier: "project.payment-plans", scrollingAttempts: 8).exists)
    }

    private func replaceLinkedText(_ field: XCUIElement, with value: String) {
        field.tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + value)
    }
}
