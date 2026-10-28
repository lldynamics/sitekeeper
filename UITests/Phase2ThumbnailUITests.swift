import XCTest
import UIKit

extension SitekeeperUITests {
    func testPhase2ThumbnailsRefreshAfterSameNameReplacement() {
        let app = launchPhase2Thumbnails()
        expectThumbnailColor(.red, in: app)
        attachScreenshot(app, named: "phase2-original-red-thumbnails")
        for revision in 1...4 {
            app.buttons["phase2-replace-images"].tap()
            expectThumbnailColor(revision.isMultiple(of: 2) ? .red : .blue, in: app)
            XCTAssertEqual(app.staticTexts["phase2-image-revision"].label, "样本版本 \(revision)")
        }
        app.buttons["phase2-replace-images"].tap()
        expectThumbnailColor(.blue, in: app)
        attachScreenshot(app, named: "phase2-same-name-refreshed-blue-thumbnails")
        app.terminate()
    }

    func testPhase2ThumbnailsSurviveMemoryWarningResizeAndReappearance() {
        let app = launchPhase2Thumbnails()
        expectThumbnailColor(.red, in: app)
        app.buttons["phase2-memory-warning"].tap()
        expectThumbnailColor(.red, in: app)
        app.buttons["phase2-resize-images"].tap()
        expectThumbnailColor(.red, in: app)
        app.buttons["phase2-toggle-images"].tap()
        XCTAssertTrue(app.otherElements["phase2-photo-image"].waitForNonExistence(timeout: 5))
        app.buttons["phase2-replace-images"].tap()
        app.buttons["phase2-toggle-images"].tap()
        expectThumbnailColor(.blue, in: app)
        app.buttons["phase2-resize-images"].tap()
        expectThumbnailColor(.blue, in: app)
        attachScreenshot(app, named: "phase2-reappeared-blue-thumbnails")
        app.terminate()
    }

    private func launchPhase2Thumbnails() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-uitest-skip-onboarding", "-languageCode", "zh-Hans"]
        app.launchEnvironment["UITEST_PHASE2_THUMBNAILS"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["phase2-replace-images"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["phase2-fixture-error"].exists)
        return app
    }

    private func expectThumbnailColor(_ expected: Phase2PixelColor, in app: XCUIApplication) {
        let identifiers = ["phase2-photo-image", "phase2-attachment-image", "phase2-project-image"]
        let predicate = NSPredicate { _, _ in
            let image = app.screenshot().image
            return identifiers.allSatisfy { identifier in
                let element = app.descendants(matching: .any)[identifier].firstMatch
                guard element.exists else { return false }
                return expected.matches(image, elementFrame: element.frame, appFrame: app.frame)
            }
        }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: app)], timeout: 12)
        if result != .completed { attachScreenshot(app, named: "phase2-thumbnail-color-failure") }
        XCTAssertEqual(result, .completed, "All three rendered thumbnails must show \(expected)")
    }
}

private enum Phase2PixelColor {
    case red
    case blue

    func matches(_ screenshot: UIImage, elementFrame: CGRect, appFrame: CGRect) -> Bool {
        guard appFrame.width > 0, appFrame.height > 0, appFrame.contains(elementFrame),
              let source = screenshot.cgImage else { return false }
        let scaleX = CGFloat(source.width) / appFrame.width
        let scaleY = CGFloat(source.height) / appFrame.height
        let pixelRect = CGRect(x: (elementFrame.midX - appFrame.minX) * scaleX,
                               y: (elementFrame.midY - appFrame.minY) * scaleY, width: 1, height: 1)
        guard let sample = source.cropping(to: pixelRect) else { return false }
        var bytes = [UInt8](repeating: 0, count: 4)
        let didDraw = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                            | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(sample, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard didDraw else { return false }
        switch self {
        case .red: return bytes[0] > 200 && bytes[1] < 60 && bytes[2] < 60
        case .blue: return bytes[2] > 200 && bytes[0] < 60 && bytes[1] < 60
        }
    }
}
