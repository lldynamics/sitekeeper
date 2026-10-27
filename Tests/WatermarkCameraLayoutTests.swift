import Foundation
import UIKit
import Testing
@testable import sitekeeper

struct WatermarkCameraLayoutTests {
    private let capturedAt = Date(timeIntervalSince1970: 1_780_000_000)

    @Test func longFieldsStayInsidePortraitAndLandscapeFrames() {
        let long = String(repeating: "施工段很长 👷🏽‍♀️ 钢筋加工与模板安装 ", count: 120)
        for size in [CGSize(width: 1200, height: 1600), CGSize(width: 1600, height: 1200)] {
            for template in CameraWatermarkTemplate.allCases {
                for position in WatermarkCameraStyle.Position.allCases {
                    let context = CameraWatermarkContext(
                        projectName: long, template: template, tag: long, photographer: long,
                        locationText: long, workSection: long, floor: long, process: long,
                        issueNumber: long, completedQuantity: long, receiptNote: long,
                        style: .init(position: position, detail: .full)
                    )
                    let layout = WatermarkCameraLayout.make(context: context, capturedAt: capturedAt, canvasSize: size)
                    let canvas = CGRect(origin: .zero, size: size)
                    #expect(canvas.contains(layout.contentFrame))
                    #expect(layout.contentFrame.height <= size.height * 0.61)
                    #expect(layout.lines.first?.text.hasSuffix("…") == true)
                    for line in layout.lines {
                        #expect(layout.contentFrame.contains(line.rect))
                        let width = (line.text as NSString).size(withAttributes: [
                            .font: UIFont.systemFont(ofSize: layout.canonicalFontSize, weight: .semibold)
                        ]).width * layout.coordinateScale
                        #expect(width <= line.rect.width + 0.01)
                        #expect(!line.text.contains("\n"))
                    }
                }
            }
        }
    }

    @Test func layoutScalesWithPhotoAndPreservesBottomCorner() {
        for position in WatermarkCameraStyle.Position.allCases {
            let context = CameraWatermarkContext(projectName: "东区综合楼", style: .init(position: position, detail: .full))
            let small = WatermarkCameraLayout.make(context: context, capturedAt: capturedAt, canvasSize: CGSize(width: 300, height: 400))
            let large = WatermarkCameraLayout.make(context: context, capturedAt: capturedAt, canvasSize: CGSize(width: 1200, height: 1600))
            #expect(small.lines.map(\.text) == large.lines.map(\.text))
            #expect(abs(small.fontSize * 4 - large.fontSize) < 0.001)
            #expect(abs(small.contentFrame.minX * 4 - large.contentFrame.minX) < 1)
            #expect(abs(small.contentFrame.minY * 4 - large.contentFrame.minY) < 1)
            #expect(small.canonicalFontSize == large.canonicalFontSize)
            for (previewLine, exportLine) in zip(small.lines, large.lines) {
                #expect(abs(previewLine.rect.minX * 4 - exportLine.rect.minX) < 0.001)
                #expect(abs(previewLine.rect.minY * 4 - exportLine.rect.minY) < 0.001)
                #expect(abs(previewLine.rect.width * 4 - exportLine.rect.width) < 0.001)
                #expect(abs(previewLine.rect.height * 4 - exportLine.rect.height) < 0.001)
            }
            if position == .bottomLeft {
                #expect(abs(small.contentFrame.minX - 300 * 0.028) < 0.001)
            } else {
                #expect(abs(small.contentFrame.maxX - 300 * (1 - 0.028)) < 0.001)
            }
        }
    }

    @Test func templatesPresentRelevantEngineeringFields() {
        var context = CameraWatermarkContext(
            projectName: "东区综合楼", workSection: "A 施工段", floor: "3 层", process: "桥架安装",
            issueNumber: "ZG-001", completedQuantity: "120 米", receiptNote: "桥架采购收据"
        )
        let expected = [
            CameraWatermarkTemplate.constructionLog: String(format: AppLocalization.string("%@: %@"), AppLocalization.string("施工工序"), "桥架安装"),
            .rectification: String(format: AppLocalization.string("%@: %@"), AppLocalization.string("问题编号"), "ZG-001"),
            .paymentProof: String(format: AppLocalization.string("%@: %@"), AppLocalization.string("完成工程量"), "120 米"),
            .receipt: String(format: AppLocalization.string("%@: %@"), AppLocalization.string("票据说明"), "桥架采购收据")
        ]
        for template in CameraWatermarkTemplate.allCases {
            context.template = template
            #expect(context.lines(capturedAt: capturedAt).contains(expected[template]!))
            context.style.detail = .compact
            let compactLines = context.lines(capturedAt: capturedAt)
            #expect(compactLines.count == 3)
            #expect(compactLines.contains(expected[template]!))
            context.style.detail = .full
        }
        let blank = CameraWatermarkContext(projectName: nil)
        #expect(blank.lines(capturedAt: capturedAt).contains(String(format: AppLocalization.string("%@: %@"), AppLocalization.string("施工工序"), AppLocalization.string("未填写"))))
    }

    @Test func capturedContextRoundTripsAndDoesNotFollowLaterSettings() throws {
        var current = CameraWatermarkContext(
            projectName: "原项目", template: .paymentProof, photographer: "李工", locationText: "现场东门",
            workSection: "东段", floor: "2 层", process: "穿线", completedQuantity: "80 米",
            style: .init(position: .bottomLeft, detail: .compact),
            locationSnapshot: .init(text: "现场东门", timestamp: capturedAt, horizontalAccuracy: 30, provenance: .device)
        )
        let data = try JSONEncoder().encode(current)
        let frozen = try JSONDecoder().decode(CameraWatermarkContext.self, from: data)
        #expect(frozen == current)
        current.projectName = "之后选择的项目"
        current.completedQuantity = "200 米"
        #expect(frozen.projectName == "原项目")
        #expect(frozen.completedQuantity == "80 米")
        let legacy = try JSONDecoder().decode(CameraWatermarkContext.self, from: Data(#"{"projectName":"旧工程","tag":"现场"}"#.utf8))
        #expect(legacy.style == .init())
        #expect(legacy.workSection.isEmpty)
        #expect(legacy.locationSnapshot == nil)
    }

    @Test func engineeringStyleAndLocationSettingsPersistWithoutFreshnessClaim() throws {
        let name = "WatermarkCameraLayoutTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = UserPreferencesStore(defaults: defaults)
        let settings = WatermarkCameraSettingsStore(preferences: preferences)
        settings.workSection = "东段"
        settings.floor = "2 层"
        settings.process = "桥架安装"
        settings.issueNumber = "ZG-001"
        settings.completedQuantity = "30 米"
        settings.receiptNote = "材料采购"
        settings.style = .init(position: .bottomLeft, detail: .compact)
        let fix = WatermarkLocationSnapshot(text: "现场", timestamp: Date(), horizontalAccuracy: 25, provenance: .device)
        settings.acceptDeviceLocation(fix)
        #expect(settings.locationSnapshot == fix)
        let restored = WatermarkCameraSettingsStore(preferences: preferences)
        #expect(restored.workSection == "东段")
        #expect(restored.floor == "2 层")
        #expect(restored.process == "桥架安装")
        #expect(restored.issueNumber == "ZG-001")
        #expect(restored.completedQuantity == "30 米")
        #expect(restored.receiptNote == "材料采购")
        #expect(restored.style == settings.style)
        #expect(restored.locationSnapshot == fix)
        #expect(restored.locationStatusText() == String(format: AppLocalization.string("上次定位（%@），请核对或重新定位"), Formatters.dateTime.string(from: fix.timestamp!)))
        restored.setManualLocation("手填地址")
        #expect(restored.locationSnapshot?.provenance == .manual)
        #expect(restored.locationSnapshot?.timestamp == nil)
        #expect(restored.locationText == "手填地址")
        let manualRestored = WatermarkCameraSettingsStore(preferences: preferences)
        #expect(manualRestored.locationStatusText() == AppLocalization.string("上次填写的位置，请核对"))
    }
}
