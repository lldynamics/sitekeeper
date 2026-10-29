import XCTest

extension SitekeeperUITests {
    func testLinkedInstallmentPartialOverpayThenSettlementSurvivesRestart() {
        var app = launchLinkedWorkflowApp(reset: true)
        openLinkedProjectCosts(app)
        button(app, identifier: "project.payment-plans", scrollingAttempts: 8).tap()
        let payID = "payment.installment.pay.70000000-0000-0000-0000-000000000011"
        XCTAssertTrue(app.staticTexts["计划未到期未结"].firstMatch.waitForExistence(timeout: 5))
        button(app, identifier: payID, scrollingAttempts: 8).tap()
        let amount = app.textFields["payment.actual.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        replaceLinkedText(amount, with: "30")
        app.buttons["payment.actual.save"].tap()
        XCTAssertTrue(amount.waitForNonExistence(timeout: 10))
        button(app, identifier: payID, scrollingAttempts: 8).tap()
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
        let settled = app.staticTexts["已结清"].firstMatch
        XCTAssertTrue(waitForElementByScrollingDown(settled, in: app.collectionViews.firstMatch, attempts: 8))
        XCTAssertFalse(app.buttons[payID].exists)
        XCTAssertTrue(button(app, identifier: "payment.installment.pay.70000000-0000-0000-0000-000000000012", scrollingAttempts: 8).exists)
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
        XCTAssertTrue(app.staticTexts["计划数量、10 m"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已关联入库量、4 m"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["待到货、6 m"].firstMatch.exists)
        app.navigationBars["到货入库"].buttons["取消"].tap()
        app.swipeDown()
        button(app, identifier: "project.warehouse", scrollingAttempts: 16).tap()
        let cableMovement = app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "入库", "Linked Cable")).firstMatch
        XCTAssertTrue(cableMovement.waitForExistence(timeout: 8))
        cableMovement.tap()
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

    func testSelectedBusinessQuoteVersionSurvivesRestartAndFiltersOtherVersions() {
        var app = launchLinkedWorkflowApp(reset: true)
        openLinkedProjectCosts(app)
        button(app, identifier: "project.business-quote-selection", scrollingAttempts: 8).tap()
        let picker = app.buttons["quotation-business-version-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        let pickerControl = picker.buttons.firstMatch
        XCTAssertTrue(pickerControl.waitForExistence(timeout: 5))
        pickerControl.tap()
        let version = app.buttons["V1"].firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 5))
        version.tap()
        let selectedOnly = app.switches["quotation-current-business-version-only"]
        XCTAssertTrue(selectedOnly.waitForExistence(timeout: 8))
        let selectedReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: selectedOnly)
        XCTAssertEqual(XCTWaiter.wait(for: [selectedReady], timeout: 10), .completed)
        enableLinkedSwitch(selectedOnly)
        assertLinkedV1Filter(app)
        app.terminate()
        app = launchLinkedWorkflowApp()
        openLinkedProjectCosts(app)
        button(app, identifier: "project.business-quote-selection", scrollingAttempts: 8).tap()
        let restored = app.switches["quotation-current-business-version-only"]
        XCTAssertTrue(restored.waitForExistence(timeout: 8))
        XCTAssertTrue(restored.isEnabled)
        enableLinkedSwitch(restored)
        assertLinkedV1Filter(app)
    }

    func testPartialArrivalCanBeReviewedAndReceivedFromFollowUp() {
        let app = launchLinkedWorkflowApp(reset: true)
        openLinkedProjectCosts(app)
        button(app, identifier: "project-detail-more-menu", scrollingAttempts: 3).tap()
        button(app, identifier: "project-detail-field-workflow", scrollingAttempts: 3).tap()
        button(app, identifier: "project.material-follow-up", scrollingAttempts: 4).tap()
        let receive = button(app, identifier: "material-follow-up.receive.70000000-0000-0000-0000-000000000004", scrollingAttempts: 8)
        XCTAssertTrue(receive.exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "采购状态与关联到货数量不一致")).firstMatch.exists)
        receive.tap()
        XCTAssertTrue(app.navigationBars["到货入库"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已关联入库量、4 m"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["待到货、6 m"].firstMatch.exists)
        let quantity = app.textFields["material.receipt.quantity"]
        quantity.tap()
        quantity.typeText("6")
        app.buttons["material.receipt.save"].tap()
        XCTAssertTrue(quantity.waitForNonExistence(timeout: 10))
        XCTAssertFalse(app.buttons["material-follow-up.receive.70000000-0000-0000-0000-000000000004"].exists)
    }

    private func launchLinkedWorkflowApp(reset: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-uitest-skip-onboarding", "-languageCode", "zh-Hans", "-AppleLanguages", "(zh-Hans)"]
        if reset { app.launchArguments.append("-uitest-reset-state") }
        app.launchEnvironment["UITEST_LINKED_WORKFLOW_FIXTURE"] = "1"
        app.launchEnvironment["UITEST_DISABLE_ANIMATIONS"] = "1"
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

    private func enableLinkedSwitch(_ control: XCUIElement) {
        if String(describing: control.value ?? "") != "1" {
            control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "1"), object: control)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 8), .completed)
    }

    private func assertLinkedV1Filter(_ app: XCUIApplication) {
        let list = app.collectionViews.firstMatch
        XCTAssertTrue(waitForElementByScrollingDown(app.staticTexts["Linked Quote V1"].firstMatch, in: list, attempts: 8))
        XCTAssertTrue(waitForElementByScrollingDown(app.staticTexts["参考合计、¥20.00"].firstMatch, in: list, attempts: 8))
        XCTAssertTrue(app.staticTexts["Linked Quote V2"].firstMatch.waitForNonExistence(timeout: 8))
    }
}
