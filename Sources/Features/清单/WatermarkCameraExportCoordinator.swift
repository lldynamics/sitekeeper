import Foundation
import Observation
import UIKit

enum WatermarkCameraAlbumSaveResult {
    case success(count: Int)
    case blockingError(message: String, settingsURL: URL?)
    case error(message: String)
}

@MainActor @Observable
final class WatermarkCameraExportCoordinator {
    var exportData = Data()
    var showExporter = false
    var savingToAlbum = false

    func prepareExport(photo: WatermarkCapturedPhoto?, quality: WatermarkExportQuality) -> Bool {
        guard let data = photo?.image.jpegData(compressionQuality: quality.compression) else {
            return false
        }
        exportData = data
        showExporter = true
        return true
    }

    func saveImagesToAlbum(_ images: [UIImage]) async -> WatermarkCameraAlbumSaveResult {
        guard !images.isEmpty else {
            return .error(message: String(localized: "wm_camera_capture_photo_first_message"))
        }

        let access = await WatermarkCameraAccess.requestPhotoLibraryAddAccessIfNeeded()
        switch access {
        case .granted:
            break
        case .rejectedRequest:
            return .blockingError(
                message: String(localized: "wm_camera_album_permission_missing_error"),
                settingsURL: WatermarkCameraAccess.appSettingsURL
            )
        case .denied:
            return .blockingError(
                message: String(localized: "wm_camera_album_permission_settings_error"),
                settingsURL: WatermarkCameraAccess.appSettingsURL
            )
        case .unknown:
            return .error(message: String(localized: "wm_camera_album_permission_unknown_error"))
        }

        savingToAlbum = true
        defer { savingToAlbum = false }

        do {
            try await WatermarkPhotoAlbumWriter.write(images)
            return .success(count: images.count)
        } catch {
            return .error(
                message: String(
                    format: String(localized: "wm_camera_save_album_failed_format"),
                    error.localizedDescription
                )
            )
        }
    }
}
