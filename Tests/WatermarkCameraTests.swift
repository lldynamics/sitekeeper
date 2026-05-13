import Foundation
import Testing
@testable import sitekeeper

struct WatermarkCameraTests {
    @Test func watermarkLinesUseCapturedTime() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
        components.month = 5
        components.day = 3
        components.hour = 9
        components.minute = 8
        let capturedAt = try #require(components.date)

        let context = CameraWatermarkContext(
            projectName: "测试工程",
            template: .constructionLog,
            tag: "现场",
            photographer: "金工",
            locationText: "31.23000, 121.47000"
        )
        let lines = context.lines(capturedAt: capturedAt)

        #expect(lines.contains("时间: \(Formatters.dateTime.string(from: capturedAt))"))
        #expect(lines.contains("工程: 测试工程"))
        #expect(lines.contains("拍摄: 金工"))
    }

    @Test func dailyLogSeedPhotoKeepsDraftMetadata() throws {
        let capturedAt = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: 3, hour: 10, minute: 15)))
        let data = Data([0x01, 0x02, 0x03])
        let seed = DailyLogSeedPhoto(data: data, note: "来源: 水印相机", tag: .rectificationBefore, capturedAt: capturedAt)
        let draft = seed.photoDraft

        #expect(draft.data == data)
        #expect(draft.note == "来源: 水印相机")
        #expect(draft.tag == .rectificationBefore)
        #expect(seed.capturedAt == capturedAt)
    }
}
