import Foundation

struct WatermarkCameraLogDraftCoordinator {
    var tag: String
    var photographer: String
    var locationText: String
    var exportQuality: WatermarkExportQuality

    var logDraftContent: String {
        WatermarkCameraTextBuilder.logDraftContent(tag: tag)
    }

    func todoSeedData(for photo: WatermarkCapturedPhoto?) -> Data? {
        photo?.image.jpegData(compressionQuality: max(0.82, exportQuality.compression - 0.06))
    }

    func logSeedPhoto(for photo: WatermarkCapturedPhoto?) -> DailyLogSeedPhoto? {
        guard let photo,
              let data = todoSeedData(for: photo) else { return nil }
        return DailyLogSeedPhoto(
            data: data,
            note: Self.photoNote(for: photo),
            tag: PhotoTag(rawValue: photo.context.tag.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .general,
            capturedAt: photo.capturedAt
        )
    }

    static func photoNote(for photo: WatermarkCapturedPhoto) -> String {
        photo.context.lines(capturedAt: photo.capturedAt).joined(separator: "\n")
    }

    func photoNote(capturedAt: Date) -> String {
        WatermarkCameraTextBuilder.photoNote(
            capturedAt: capturedAt,
            photographer: photographer,
            locationText: locationText,
            tag: tag
        )
    }
}
