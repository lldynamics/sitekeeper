import Foundation

struct WatermarkCameraLogDraftCoordinator {
    static func photoNote(for photo: WatermarkCapturedPhoto) -> String {
        photo.context.lines(capturedAt: photo.capturedAt).joined(separator: "\n")
    }
}
