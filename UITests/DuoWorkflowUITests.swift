import XCTest
import UIKit

extension SitekeeperUITests {
    func testDuoProgressScrollPositionSurvivesNativeFoldCycle() throws {
        try verifyDuoProgressScrollPosition(listMode: false)
    }

    func testDuoProgressListScrollPositionSurvivesNativeFoldCycle() throws {
        try verifyDuoProgressScrollPosition(listMode: true)
    }

    func testDuoProgressLargeTextSurvivesNativeFoldCycle() throws {
        try verifyDuoProgressScrollPosition(listMode: false, dynamicType: "accessibility3")
    }

    func testDuoFilteredProgressDeletionSurvivesNativeFoldCycle() throws {
        try verifyDuoFilteredProgressDeletion(listMode: false)
    }

    func testDuoFilteredProgressListDeletionSurvivesNativeFoldCycle() throws {
        try verifyDuoFilteredProgressDeletion(listMode: true)
    }

    private func verifyDuoFilteredProgressDeletion(listMode: Bool) throws {
        try requireDuoFoldSession()
        let app = launchApp(resetState: true, duoScrollFixture: true)
        let entry = app.buttons["duo-progress-test-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        if listMode { app.segmentedControls.buttons["列表"].tap() }
        let completed = app.buttons["已完成"].firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 10))
        completed.tap()
        XCTAssertTrue(completed.isSelected)
        XCTAssertTrue(app.staticTexts["Duo Progress Completed"].waitForExistence(timeout: 5))
        let overdue = app.buttons["逾期"].firstMatch
        XCTAssertTrue(overdue.waitForExistence(timeout: 10))
        overdue.tap()
        XCTAssertTrue(overdue.isSelected)
        let row = app.staticTexts["Duo Progress 12"].firstMatch
        for _ in 0..<30 {
            if row.isHittable { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.68))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.42))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(row.isHittable)
        guard row.isHittable else { return }
        XCTAssertFalse(app.staticTexts["Duo Progress Completed"].exists, "Completed tasks must be excluded by the overdue filter.")
        row.swipeLeft()
        let delete = app.buttons["删除"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        guard delete.exists else { return }
        delete.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        let neighbor = app.staticTexts["Duo Progress 11"].firstMatch
        XCTAssertTrue(neighbor.waitForExistence(timeout: 5))
        XCTAssertTrue(neighbor.isHittable)
        guard neighbor.isHittable else { return }
        let foldedWidth = app.frame.width
        try waitForDuoResize(neighbor, app: app, stage: "progress-delete-expand")
        try waitForDuoResize(neighbor, app: app, stage: "progress-delete-fold", returningToWidth: foldedWidth)
        XCTAssertFalse(row.exists)
        XCTAssertTrue(neighbor.isHittable)
        XCTAssertFalse(app.staticTexts["Duo Progress Completed"].exists)
        for _ in 0..<20 {
            if overdue.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(overdue.isHittable)
        XCTAssertTrue(overdue.isSelected, "The overdue filter must remain selected after the fold cycle.")
    }

    private func verifyDuoProgressScrollPosition(listMode: Bool, dynamicType: String? = nil) throws {
        try requireDuoFoldSession()
        let app = launchApp(resetState: true, dynamicTypeSize: dynamicType, duoScrollFixture: true)
        let entry = app.buttons["duo-progress-test-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(app.navigationBars["施工进度"].waitForExistence(timeout: 10))
        if listMode { app.segmentedControls.buttons["列表"].tap() }
        let row = app.staticTexts["Duo Progress 12"].firstMatch
        for _ in 0..<30 {
            if row.isHittable { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.68))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.42))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(row.isHittable)
        guard row.isHittable else { return }
        let foldedWidth = app.frame.width
        try waitForDuoResize(row, app: app, stage: "progress-scroll-expand")
        try waitForDuoResize(row, app: app, stage: "progress-scroll-fold", returningToWidth: foldedWidth)
        XCTAssertTrue(row.isHittable)
    }

    func testDuoDrawingGestureSelectsPreviewWhenFolded() throws {
        try verifyDuoDrawingGestureSelectsPreview(pinch: false)
    }

    func testDuoDrawingZoomSelectsPreviewWhenFolded() throws {
        try verifyDuoDrawingGestureSelectsPreview(pinch: true)
    }

    private func verifyDuoDrawingGestureSelectsPreview(pinch: Bool) throws {
        try requireDuoFoldSession()
        let app = launchApp(resetState: true, duoWorkflowFixture: true)
        openDuoDrawingIssue(app)
        let field = app.descendants(matching: .any)["drawing-issue-description"].firstMatch
        let foldedWidth = app.frame.width
        try waitForDuoResize(field, app: app, stage: "drawing-gesture-expand")
        let pdf = app.descendants(matching: .any)["pdf-preview-document"].firstMatch
        XCTAssertTrue(pdf.waitForExistence(timeout: 10))
        if pinch {
            pdf.pinch(withScale: 1.7, velocity: 1)
        } else {
            pdf.swipeUp()
        }
        let picker = app.segmentedControls["review-workspace-pane"]
        try waitForDuoResize(picker, app: app, stage: "drawing-gesture-fold", returningToWidth: foldedWidth)
        XCTAssertTrue(picker.buttons["图纸"].isSelected, "Folding after interacting with the drawing should keep the drawing visible.")
        XCTAssertTrue(pdf.isHittable)
    }

    func testDuoTodoScrollPositionSurvivesNativeFoldCycle() throws {
        try verifyDuoTodoScrollPosition(dynamicType: nil)
    }

    func testDuoTodoLargeTextSurvivesNativeFoldCycle() throws {
        try verifyDuoTodoScrollPosition(dynamicType: "accessibility3")
    }

    private func verifyDuoTodoScrollPosition(dynamicType: String?) throws {
        try requireDuoFoldSession()
        let app = launchApp(resetState: true, dynamicTypeSize: dynamicType, duoScrollFixture: true)
        let entry = app.buttons["今日待办"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Duo Todo 12")).firstMatch
        for _ in 0..<12 {
            if row.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(row.isHittable, "The middle todo must be visible before folding.")
        guard row.isHittable else { return }
        let foldedWidth = app.frame.width
        attachScreenshot(app, named: "Todo before expand")
        try waitForDuoResize(row, app: app, stage: "todo-scroll-expand")
        try waitForDuoResize(row, app: app, stage: "todo-scroll-fold", returningToWidth: foldedWidth)
        XCTAssertTrue(row.isHittable)
    }

    func testDuoFilteredTodoDeletionSurvivesNativeFoldCycle() throws {
        try requireDuoFoldSession()
        let app = launchApp(resetState: true, duoScrollFixture: true)
        let entry = app.buttons["今日待办"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        entry.tap()
        let filter = app.buttons["todo-project-filter"].firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        filter.tap()
        app.buttons["Duo Scroll Site"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Duo Todo 12")).firstMatch
        for _ in 0..<30 {
            if row.isHittable { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.68))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.42))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(row.isHittable)
        guard row.isHittable else { return }
        if row.frame.midY < app.frame.minY + 150 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        row.swipeLeft()
        let delete = app.buttons["删除"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
        let neighbor = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Duo Todo 13")).firstMatch
        XCTAssertTrue(neighbor.waitForExistence(timeout: 5))
        XCTAssertTrue(neighbor.isHittable)
        guard neighbor.isHittable else { return }
        let foldedWidth = app.frame.width
        try waitForDuoResize(neighbor, app: app, stage: "todo-delete-expand")
        try waitForDuoResize(neighbor, app: app, stage: "todo-delete-fold", returningToWidth: foldedWidth)
        XCTAssertFalse(row.exists)
        XCTAssertTrue(neighbor.isHittable)
    }

    func testDuoCompactRemindersExpandAndCollapse() throws {
        try requireDuoFoldSession()
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-uitest-skip-onboarding", "-languageCode", "zh-Hans",
                               "-AppleLanguages", "(zh-Hans)"]
        app.launchEnvironment["UITEST_REPOSITORY_FIXTURE"] = "1"
        app.launch()

        XCTAssertTrue(app.buttons["primary-module-dashboard"].waitForExistence(timeout: 10),
                      "This check starts on the folded Duo.")
        let toggle = app.buttons["dashboard-risk-expansion-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 15), "The isolated fixture must contain more than two alert categories.")
        XCTAssertTrue(app.buttons["dashboard-risk-overdue"].exists)
        XCTAssertFalse(app.buttons["dashboard-risk-missingTodayLog"].exists)
        toggle.tap()
        XCTAssertTrue(app.buttons["dashboard-risk-missingTodayLog"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dashboard-risk-dataHealth"].exists)
        toggle.tap()
        XCTAssertFalse(app.buttons["dashboard-risk-missingTodayLog"].exists)
    }

    func testDuoCompactMaterialFiltersRemainAccessible() throws {
        try requireDuoFoldSession()
        let app = launchApp()
        XCTAssertTrue(app.buttons["primary-module-checklist"].waitForExistence(timeout: 10),
                      "This check starts on the folded Duo.")
        tapPrimaryModule(app, name: "工具箱")
        element(app, identifier: "材料中心", scrollingAttempts: 8).tap()
        let library = app.segmentedControls.buttons["材料库"]
        XCTAssertTrue(library.waitForExistence(timeout: 8))
        library.tap()

        let price = app.buttons["material-library-price-filter"]
        let categoryManager = app.buttons["material-library-category-management"]
        XCTAssertTrue(price.waitForExistence(timeout: 8))
        XCTAssertTrue(price.isHittable)
        XCTAssertTrue(categoryManager.isHittable)
        XCTAssertTrue(app.buttons["material-library-add-custom-material"].isHittable)
        price.tap()
        app.buttons["未标价"].tap()
        XCTAssertEqual(price.value as? String, "未标价")
        let cable = app.buttons["电缆"]
        XCTAssertTrue(cable.waitForExistence(timeout: 5))
        cable.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "YJV 电力电缆")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(cable.isSelected)
    }

    func testDuoCompactNavigationAtAccessibilityTextSize() throws {
        try requireDuoFoldSession()
        let app = launchApp(dynamicTypeSize: "accessibility5")
        let menu = app.descendants(matching: .any)["primary-module-menu"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        XCTAssertTrue(menu.isHittable)
        tapPrimaryModule(app, name: "工具箱")
        XCTAssertTrue(app.staticTexts["工程工具箱"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(menu.value as? String, "工具箱")
    }

    func testDuoExpandedDarkProjectSidebarStaysClearWhileScrolling() throws {
        try requireDuoFoldSession()
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Requires the native Duo phone workspace.")

        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-uitest-skip-onboarding", "-languageCode", "zh-Hans",
                               "-AppleLanguages", "(zh-Hans)", "-appearanceMode", "dark",
                               "-uitest-dynamic-type-size", "large"]
        // This opt-in test runs on the dedicated simulator and adds synthetic
        // rows without resetting its existing data.
        app.launchEnvironment["UITEST_REPOSITORY_FIXTURE"] = "1"
        app.launch()
        tapPrimaryModule(app, name: "项目")

        let sidebar = app.collectionViews["边栏"].firstMatch
        let create = app.buttons["project-create-open"].firstMatch
        let firstFixture = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "分页工程 052")).firstMatch
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        XCTAssertTrue(firstFixture.waitForExistence(timeout: 15))
        guard sidebar.exists, create.exists, firstFixture.isHittable else {
            attachScreenshot(app, named: "Duo project sidebar missing scroll fixture")
            XCTFail("The expanded project sidebar must show the synthetic long list.")
            return
        }

        let before = try duoUprightInnerDisplay()
        let sidebarFrame = sidebar.frame
        let toolbarBottom = create.frame.maxY
        sidebar.swipeUp()
        XCTAssertFalse(firstFixture.isHittable, "The fixture row must move out of view for the scroll check.")
        let after = try duoUprightInnerDisplay()

        let attachment = XCTAttachment(screenshot: after.screenshot)
        attachment.name = "Duo expanded dark project sidebar after scrolling"
        attachment.lifetime = .keepAlways
        add(attachment)

        // This empty part of the toolbar should remain unchanged when rows
        // scroll underneath. Sampling a grid also catches text leaking through.
        let left = sidebarFrame.minX + sidebarFrame.width * 0.22
        let right = sidebarFrame.minX + sidebarFrame.width * 0.42
        let top = max(8, create.frame.minY)
        let bottom = min(toolbarBottom, after.frame.height - 4)
        guard right > left, bottom > top else {
            XCTFail("The expanded sidebar and toolbar must have usable geometry.")
            return
        }
        var changed = 0
        var count = 0
        for x in stride(from: left, through: right, by: 6) {
            for y in stride(from: top, through: bottom, by: 6) {
                let point = CGPoint(x: x, y: y)
                let a = try duoBackgroundSample(before.image, at: point, appFrame: before.frame)
                let b = try duoBackgroundSample(after.image, at: point, appFrame: after.frame)
                count += 1
                if a.distance(to: b) > 0.04 { changed += 1 }
            }
        }
        XCTAssertLessThan(Double(changed) / Double(count), 0.05,
                          "Scrolling must not change the background behind the project toolbar (\(changed)/\(count) patches changed).")

        let reference = try duoBackgroundSample(after.image,
                                                at: CGPoint(x: sidebarFrame.minX + 8, y: after.frame.midY),
                                                appFrame: after.frame)
        let topBackground = try duoBackgroundSample(after.image,
                                                    at: CGPoint(x: left, y: top), appFrame: after.frame)
        let bottomBackground = try duoBackgroundSample(after.image,
                                                       at: CGPoint(x: left, y: after.frame.maxY - 12),
                                                       appFrame: after.frame)
        XCTAssertGreaterThan(reference.brightness, 0.04, "The dark sidebar needs a painted background.")
        XCTAssertLessThan(reference.brightness, 0.25, "This regression must use dark appearance.")
        XCTAssertLessThan(topBackground.distance(to: reference), 0.025, "Toolbar and sidebar background should match.")
        XCTAssertLessThan(bottomBackground.distance(to: reference), 0.025, "Bottom safe area and sidebar background should match.")
    }

    func testDuoExpandedDarkToolboxBackgroundRemainsContinuous() throws {
        try requireDuoFoldSession()
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Requires the native Duo phone workspace.")

        let app = XCUIApplication()
        // Launch overrides keep this visual check independent of saved appearance preferences.
        // Do not rotate or reset data: the native preflight must already have expanded Duo.
        app.launchArguments = ["-ui-testing", "-uitest-skip-onboarding", "-languageCode", "zh-Hans",
                               "-AppleLanguages", "(zh-Hans)", "-appearanceMode", "dark",
                               "-uitest-dynamic-type-size", "large"]
        app.launch()
        // XCUI reports coordinates in its own orientation, so its app width is
        // not the SwiftUI workspace width. Verify the two visible panes below.
        FileHandle.standardOutput.write(Data("DUO_TOOLBOX_APP_FRAME \(app.frame)\n".utf8))
        tapPrimaryModule(app, name: "工具箱")

        let catalog = app.descendants(matching: .any)["toolbox-phone-catalog"].firstMatch
        let detail = app.descendants(matching: .any)["toolbox-phone-detail"].firstMatch
        XCTAssertTrue(catalog.waitForExistence(timeout: 8))
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        let pane = catalog.frame
        FileHandle.standardOutput.write(Data("DUO_TOOLBOX_PANES catalog=\(pane) detail=\(detail.frame)\n".utf8))
        guard pane.width > 0 && detail.frame.width > 0
                && pane.maxX <= detail.frame.minX + 2 else {
            attachScreenshot(app, named: "Duo toolbox missing expanded panes")
            XCTFail("The verified expanded Duo must show separate catalog and detail panes.")
            return
        }

        let quickHeader = catalog.staticTexts["快捷工具"].firstMatch
        let practicalHeader = catalog.staticTexts["实用工具"].firstMatch
        let camera = catalog.staticTexts["水印相机"].firstMatch
        let materials = catalog.staticTexts["材料中心"].firstMatch
        for element in [quickHeader, practicalHeader, camera, materials] {
            guard element.waitForExistence(timeout: 5), element.isHittable else {
                attachScreenshot(app, named: "Duo toolbox missing visual sample anchor")
                XCTFail("The visual fixture must expose both headers and ordinary tool rows: \(element)")
                return
            }
        }

        // The Duo's outer primary display is dark while opened. Capture the
        // active inner display instead of XCUIApplication's primary screenshot.
        let screens = XCUIScreen.screens
        FileHandle.standardOutput.write(Data("DUO_TOOLBOX_SCREENS \(screens.count)\n".utf8))
        guard screens.count > 1 else {
            XCTFail("The opened Duo must expose its inner display to screenshot automation.")
            return
        }
        let screenshot = screens[screens.count - 1].screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Duo expanded dark toolbox sampled background"
        attachment.lifetime = .keepAlways
        add(attachment)
        // The inner-display UIImage can carry a rotation while its CGImage is
        // still portrait. Render it upright before mapping XCUI coordinates.
        let capturedImage = screenshot.image
        let format = UIGraphicsImageRendererFormat()
        format.scale = capturedImage.scale
        format.opaque = true
        let uprightImage = UIGraphicsImageRenderer(size: capturedImage.size, format: format).image { _ in
            capturedImage.draw(at: .zero)
        }
        let image = try XCTUnwrap(uprightImage.cgImage)
        FileHandle.standardOutput.write(Data("DUO_TOOLBOX_IMAGE size=\(capturedImage.size) orientation=\(capturedImage.imageOrientation.rawValue) pixels=\(image.width)x\(image.height)\n".utf8))
        // All coordinates come from XCUI geometry. The trailing strip lies outside the
        // text/chevron insets but inside the pane, including the former black header notch.
        let points: [(String, CGPoint)] = [
            ("camera-row", CGPoint(x: pane.maxX - 6, y: camera.frame.midY)),
            ("materials-row", CGPoint(x: pane.maxX - 6, y: materials.frame.midY)),
            ("quick-header", CGPoint(x: pane.maxX - 6, y: quickHeader.frame.midY)),
            ("practical-header", CGPoint(x: pane.maxX - 6, y: practicalHeader.frame.midY)),
            ("practical-header-interior", CGPoint(x: pane.minX + pane.width * 0.60,
                                                   y: practicalHeader.frame.midY))
        ]
        let reportedFrame = app.frame
        let screenshotFrame = image.width > image.height && reportedFrame.width < reportedFrame.height
            ? CGRect(x: 0, y: 0, width: reportedFrame.height, height: reportedFrame.width)
            : reportedFrame
        let samples = try points.map { name, point in
            (name, point, try duoBackgroundSample(image, at: point, appFrame: screenshotFrame))
        }
        let evidence = XCTAttachment(string: samples.map { "\($0.0) at \($0.1): \($0.2)" }.joined(separator: "\n"))
        evidence.name = "Duo toolbox background sample coordinates and RGB"
        evidence.lifetime = .keepAlways
        add(evidence)

        let reference = samples[0].2
        // A black reference would let the original missing-background defect pass.
        // These broad bounds establish dark appearance without encoding a system color.
        XCTAssertGreaterThan(reference.brightness, 0.04, "Ordinary tool rows must have a painted background.")
        XCTAssertLessThan(reference.brightness, 0.25, "This regression must run in dark appearance.")
        for sample in samples.dropFirst() {
            XCTAssertLessThan(sample.2.distance(to: reference), 0.025,
                              "Background discontinuity at \(sample.0), \(sample.1): \(sample.2); row reference \(reference)")
        }
    }

    func testDrawingReferenceAndIssueRemainLinkedAfterSaveAndRestart() {
        var app = launchApp(resetState: true, duoWorkflowFixture: true)
        openDuoDrawingIssue(app)
        showReviewPane(app, title: "图纸")
        let page = app.staticTexts["pdf-preview-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["pdf-preview-next"].isHittable)
        app.buttons["pdf-preview-next"].tap()
        XCTAssertEqual(page.label, "2 / 3")
        app.buttons["drawing-reference-page"].tap()
        showReviewPane(app, title: "记录问题")
        let content = app.descendants(matching: .any)["drawing-issue-description"].firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        app.typeText("Duo linked inspection")
        if app.buttons["keyboard-done"].isHittable { app.buttons["keyboard-done"].tap() }
        let reference = element(app, identifier: "drawing-issue-page", scrollingAttempts: 8)
        XCTAssertEqual(reference.value as? String, "第 2 页")
        attachScreenshot(app, named: "Drawing reference and issue editor")
        app.buttons["drawing-issue-save"].tap()
        XCTAssertTrue(app.navigationBars["新建问题"].waitForNonExistence(timeout: 8))
        app.terminate()
        app = launchApp(duoWorkflowFixture: true)
        openDuoDrawingDetail(app)
        let savedNote = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Duo linked inspection")).firstMatch
        XCTAssertTrue(waitForElementByScrollingDown(savedNote, in: app, attempts: 10))
        XCTAssertTrue(savedNote.label.contains("DUO-PDF-001"))
        XCTAssertTrue(savedNote.label.contains("第 2 页"))
        attachScreenshot(app, named: "Drawing issue persisted with its source")
    }

    func testMaterialReviewUpdatesTotalAndPersistsEditedQuantity() {
        verifyMaterialReview(dynamicType: nil)
    }

    func testMaterialReviewRemainsUsableWithAccessibilityText() {
        verifyMaterialReview(dynamicType: "accessibility3")
    }

    func testDuoDrawingIssueSurvivesNativeFoldCycle() throws {
        try requireDuoFoldSession()
        let app = launchApp(resetState: true, duoWorkflowFixture: true)
        openDuoDrawingIssue(app)
        showReviewPane(app, title: "图纸")
        let page = app.staticTexts["pdf-preview-page"]
        XCTAssertTrue(page.waitForExistence(timeout: 8))
        app.buttons["pdf-preview-next"].tap()
        XCTAssertEqual(page.label, "2 / 3")
        app.buttons["drawing-reference-page"].tap()
        showReviewPane(app, title: "记录问题")
        let content = app.descendants(matching: .any)["drawing-issue-description"].firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        content.tap()
        app.typeText("Folded issue")
        let width = app.frame.width
        try waitForDuoResize(content, app: app, stage: "drawing-workspace-expand")
        XCTAssertEqual(content.value as? String, "Folded issue")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText(" expanded")
        try waitForDuoResize(content, app: app, stage: "drawing-workspace-fold", returningToWidth: width)
        XCTAssertEqual(content.value as? String, "Folded issue expanded")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText(" retained")
        XCTAssertEqual(content.value as? String, "Folded issue expanded retained")
        app.buttons["keyboard-done"].tap()
        showReviewPane(app, title: "图纸")
        XCTAssertEqual(page.label, "2 / 3")
        showReviewPane(app, title: "记录问题")
        let reference = element(app, identifier: "drawing-issue-page", scrollingAttempts: 8)
        XCTAssertEqual(reference.value as? String, "第 2 页")
        app.buttons["drawing-issue-save"].tap()
        XCTAssertTrue(app.navigationBars["新建问题"].waitForNonExistence(timeout: 8))
    }

    func testDuoMaterialQuantitySurvivesNativeFoldCycle() throws {
        try requireDuoFoldSession()
        let app = launchApp(resetState: true, duoWorkflowFixture: true)
        let quantity = openDuoMaterialQuantity(app)
        quantity.tap()
        app.typeText("5")
        let width = app.frame.width
        try waitForDuoResize(quantity, app: app, stage: "material-workspace-expand")
        XCTAssertEqual(quantity.value as? String, "25")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText("0")
        app.buttons["keyboard-done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["review-workspace-columns"].exists)
        XCTAssertTrue(app.buttons["material-sheet-more-menu"].isHittable)
        XCTAssertTrue(app.buttons["material-sheet-create"].isHittable)
        quantity.tap()
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(quantity.isHittable)
        try waitForDuoResize(quantity, app: app, stage: "material-workspace-fold", returningToWidth: width)
        XCTAssertEqual(quantity.value as? String, "250")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText("0")
        XCTAssertEqual(quantity.value as? String, "2500")
        app.buttons["keyboard-done"].tap()
        showReviewPane(app, title: "核对明细")
        if !app.otherElements["review-workspace-columns"].exists { XCTAssertFalse(quantity.isHittable) }
        XCTAssertTrue(app.staticTexts["2500 m"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Material quantity and review survived native fold")
        XCTAssertTrue(app.buttons["material-sheet-create"].isHittable)
        let more = app.buttons["material-sheet-more-menu"]
        XCTAssertTrue(more.isHittable)
        more.tap()
        XCTAssertTrue(app.buttons["导出 PDF"].waitForExistence(timeout: 5))
    }

    private func verifyMaterialReview(dynamicType: String?) {
        var app = launchApp(resetState: true, dynamicTypeSize: dynamicType, duoWorkflowFixture: true)
        let quantity = openDuoMaterialQuantity(app)
        quantity.tap()
        app.typeText(XCUIKeyboardKey.delete.rawValue + "3")
        XCTAssertEqual(quantity.value as? String, "3")
        app.buttons["keyboard-done"].tap()
        showReviewPane(app, title: "核对明细")
        if !app.otherElements["review-workspace-columns"].exists { XCTAssertFalse(quantity.isHittable) }
        XCTAssertTrue(app.staticTexts["3 m"].waitForExistence(timeout: 5))
        let total = app.descendants(matching: .any)["material-review-total"].firstMatch
        XCTAssertTrue(total.isHittable)
        XCTAssertTrue(total.label.contains("42.50"), total.label)
        attachScreenshot(app, named: "Material review and sticky total \(dynamicType ?? "default")")
        app.terminate()
        app = launchApp(dynamicTypeSize: dynamicType, duoWorkflowFixture: true)
        XCTAssertEqual(openDuoMaterialQuantity(app).value as? String, "3")
    }

    private func openDuoMaterialQuantity(_ app: XCUIApplication) -> XCUIElement {
        tapPrimaryModule(app, name: "工具箱")
        element(app, identifier: "材料中心", scrollingAttempts: 12).tap()
        app.segmentedControls.buttons["材料单"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Duo Copper")).firstMatch
        let workspace = app.otherElements["review-workspace-single"].firstMatch
        if workspace.waitForExistence(timeout: 5) {
            // The fixed total and module bar sit outside this workspace. Swiping the
            // whole app can start on those controls, especially at larger text sizes.
            for _ in 0..<30 where !row.exists {
                let start = workspace.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
                let end = workspace.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        } else {
            _ = waitForElementByScrollingDown(row, in: app, attempts: 12)
        }
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        row.tap()
        let field = app.textFields["material-quantity-71000000-0000-0000-0000-000000000002"]
        XCTAssertTrue(waitForElementByScrollingDown(field, in: app, attempts: 8))
        return field
    }

    private func openDuoDrawingDetail(_ app: XCUIApplication) {
        tapPrimaryModule(app, name: "项目")
        XCTAssertTrue(app.staticTexts["Duo Workflow Site"].firstMatch.waitForExistence(timeout: 12))
        tapPrimaryModule(app, name: "工作台")
        let search = app.textFields["搜索项目、票号、报价、图纸或资料"]
        if !search.isHittable { app.swipeDown() }
        search.tap()
        search.typeText("DUO-PDF-001\n")
        let result = app.buttons["search-suggestion-drawing-71000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        result.tap()
        XCTAssertTrue(app.navigationBars["图纸详情"].waitForExistence(timeout: 8))
    }

    private func openDuoDrawingIssue(_ app: XCUIApplication) {
        openDuoDrawingDetail(app)
        element(app, identifier: "drawing-review-open", scrollingAttempts: 12).tap()
        XCTAssertTrue(app.navigationBars["新建问题"].waitForExistence(timeout: 8))
    }

    private func showReviewPane(_ app: XCUIApplication, title: String) {
        let selector = app.segmentedControls.containing(.button, identifier: title).firstMatch
        if selector.exists {
            let button = selector.buttons[title]
            XCTAssertTrue(button.isHittable)
            button.tap()
            XCTAssertTrue(button.isSelected)
        } else {
            XCTAssertTrue(app.otherElements["review-workspace-columns"].exists)
        }
    }
}

private struct DuoBackgroundSample: CustomStringConvertible {
    let red: Double
    let green: Double
    let blue: Double

    var brightness: Double { (red + green + blue) / 3 }
    var description: String { String(format: "RGB(%.3f, %.3f, %.3f)", red, green, blue) }

    func distance(to other: Self) -> Double {
        max(abs(red - other.red), max(abs(green - other.green), abs(blue - other.blue)))
    }
}

private extension SitekeeperUITests {
    func duoUprightInnerDisplay() throws -> (screenshot: XCUIScreenshot, image: CGImage, frame: CGRect) {
        let screens = XCUIScreen.screens
        guard screens.count > 1 else {
            throw XCTSkip("The opened Duo inner display is unavailable to screenshot automation.")
        }
        let screenshot = screens[screens.count - 1].screenshot()
        let captured = screenshot.image
        let format = UIGraphicsImageRendererFormat()
        format.scale = captured.scale
        format.opaque = true
        let upright = UIGraphicsImageRenderer(size: captured.size, format: format).image { _ in
            captured.draw(at: .zero)
        }
        let image = try XCTUnwrap(upright.cgImage)
        let appFrame = XCUIApplication().frame
        let frame = image.width > image.height && appFrame.width < appFrame.height
            ? CGRect(x: 0, y: 0, width: appFrame.height, height: appFrame.width)
            : appFrame
        return (screenshot, image, frame)
    }

    func duoBackgroundSample(_ image: CGImage, at point: CGPoint, appFrame: CGRect) throws -> DuoBackgroundSample {
        let region = CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)
        XCTAssertTrue(appFrame.contains(region), "Sample must remain inside the screenshot: \(region)")
        let scaleX = CGFloat(image.width) / appFrame.width
        let scaleY = CGFloat(image.height) / appFrame.height
        let pixels = CGRect(x: (region.minX - appFrame.minX) * scaleX,
                            y: (region.minY - appFrame.minY) * scaleY,
                            width: region.width * scaleX, height: region.height * scaleY).integral
        let crop = try XCTUnwrap(image.cropping(to: pixels))
        var bytes = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
        let rendered = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: crop.width, height: crop.height,
                                          bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                            | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(crop, in: CGRect(x: 0, y: 0, width: CGFloat(crop.width), height: CGFloat(crop.height)))
            return true
        }
        XCTAssertTrue(rendered, "Screenshot pixels must be readable.")
        // Small patches and a median tolerate isolated antialiased text edges.
        func median(_ channel: Int) -> Double {
            let values = stride(from: channel, to: bytes.count, by: 4).map { bytes[$0] }.sorted()
            return Double(values[values.count / 2]) / 255
        }
        return DuoBackgroundSample(red: median(0), green: median(1), blue: median(2))
    }
}
