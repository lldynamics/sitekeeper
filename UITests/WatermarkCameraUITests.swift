import XCTest
import UIKit

extension SitekeeperUITests {
    func testWatermarkDraftsRestoreAndBatchLogKeepsPhotos() {
        let app = launchWatermarkApp(seed: true)
        openWatermark(app)
        XCTAssertTrue(app.staticTexts["watermark-draft-status"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["watermark-draft-status"].label.contains("已暂存"))
        app.buttons["全选"].tap()
        XCTAssertTrue(app.staticTexts["已选 2 / 2 张"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Watermark draft gallery")
        app.terminate()
        let restored = launchWatermarkApp(seed: false)
        openWatermark(restored)
        XCTAssertTrue(restored.staticTexts["watermark-draft-status"].waitForExistence(timeout: 15))
        restored.buttons["全选"].tap()
        XCTAssertTrue(restored.staticTexts["已选 2 / 2 张"].waitForExistence(timeout: 5))
        let log = restored.buttons["watermark-batch-log"]
        for _ in 0..<5 where !log.isHittable { restored.swipeUp() }
        XCTAssertTrue(log.isHittable)
        log.tap()
        XCTAssertTrue(restored.navigationBars["施工日志"].waitForExistence(timeout: 10) || restored.navigationBars["新增日志"].waitForExistence(timeout: 10))
        attachScreenshot(restored, named: "Watermark batch log draft")
    }

    func testWatermarkAnnotationPreservesSourceAndCreatesThirdDraft() {
        let app = launchWatermarkApp(seed: true)
        openWatermark(app)
        XCTAssertTrue(app.staticTexts["watermark-draft-status"].waitForExistence(timeout: 15))
        let menu = app.buttons["导出与更多操作"]
        for _ in 0..<4 where !menu.isHittable { app.swipeUp() }
        XCTAssertTrue(menu.isHittable)
        menu.tap()
        app.buttons["标注副本"].tap()
        XCTAssertTrue(app.navigationBars["照片标注"].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Watermark annotation editor")
        app.buttons["添加箭头"].tap()
        app.buttons["保存副本"].tap()
        XCTAssertTrue(app.navigationBars["照片标注"].waitForNonExistence(timeout: 10))
        for _ in 0..<5 where !app.buttons["全选"].isHittable { app.swipeDown() }
        XCTAssertTrue(app.staticTexts["watermark-draft-status"].waitForExistence(timeout: 10))
        app.buttons["全选"].tap()
        XCTAssertTrue(app.staticTexts["已选 3 / 3 张"].waitForExistence(timeout: 10))
    }

    private func launchWatermarkApp(seed: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-skip-onboarding", "-AppleLanguages", "(zh-Hans)", "-languageCode", "zh-Hans"]
        if seed { app.launchArguments += ["-uitest-reset-state", "-uitest-review-regression-fixture", "-uitest-watermark-fixture"] }
        app.launchEnvironment["UITEST_REVIEW_REGRESSION_FIXTURE"] = seed ? "1" : "0"
        app.launch()
        return app
    }

    private func openWatermark(_ app: XCUIApplication) {
        tapPrimaryModule(app, name: "工具箱")
        let camera = app.staticTexts["水印相机"].firstMatch
        XCTAssertTrue(camera.waitForExistence(timeout: 10))
        camera.tap()
    }
}
