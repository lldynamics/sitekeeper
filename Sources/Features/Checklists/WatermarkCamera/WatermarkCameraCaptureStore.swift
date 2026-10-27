import Observation
import UIKit

@Observable
final class WatermarkCameraCaptureStore {
    var photos: [WatermarkCapturedPhoto] = []
    var selectedPhotoID: UUID?

    var selectedPhoto: WatermarkCapturedPhoto? {
        if let selectedPhotoID,
           let selected = photos.first(where: { $0.id == selectedPhotoID }) {
            return selected
        }
        return photos.first
    }

    var hasMultiplePhotos: Bool {
        photos.count > 1
    }

    var selectedPhotoNumber: Int {
        guard let id = selectedPhoto?.id,
              let index = photos.firstIndex(where: { $0.id == id }) else {
            return 1
        }
        return index + 1
    }

    @discardableResult
    func replace(with images: [UIImage], capturedAt: Date, context: CameraWatermarkContext) -> Int {
        let outputs = images.map {
            WatermarkCapturedPhoto(
                image: $0.applyingCameraWatermark(context: context, capturedAt: capturedAt),
                capturedAt: capturedAt
            )
        }
        photos = outputs
        selectedPhotoID = outputs.first?.id
        return outputs.count
    }

    func clear() {
        photos.removeAll()
        selectedPhotoID = nil
    }
}
