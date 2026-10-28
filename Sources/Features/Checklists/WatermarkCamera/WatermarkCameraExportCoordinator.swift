import Foundation
import Observation
import UIKit

enum WatermarkCameraAlbumSaveResult: Sendable {
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
        guard let photo, let data = try? photo.jpegDataForDelivery(compression: quality.compression) else {
            return false
        }
        exportData = data
        showExporter = true
        return true
    }

    func savePhotoToAlbum(_ photo: WatermarkCapturedPhoto, storage: WatermarkCameraDraftStorage, quality: WatermarkExportQuality) async -> WatermarkAlbumSaveOutcome {
        let access = await WatermarkCameraAccess.requestPhotoLibraryAddAccessIfNeeded()
        let failure: WatermarkCameraAlbumSaveResult?
        switch access {
        case .granted: failure = nil
        case .rejectedRequest:
            failure = .blockingError(message: AppLocalization.string("wm_camera_album_permission_missing_error"), settingsURL: WatermarkCameraAccess.appSettingsURL)
        case .denied:
            failure = .blockingError(message: AppLocalization.string("wm_camera_album_permission_settings_error"), settingsURL: WatermarkCameraAccess.appSettingsURL)
        case .unknown:
            failure = .error(message: AppLocalization.string("wm_camera_album_permission_unknown_error"))
        }
        if let failure { return WatermarkAlbumSaveOutcome(result: failure, photo: photo) }
        savingToAlbum = true
        defer { savingToAlbum = false }
        return await WatermarkCameraAlbumSaveCoordinator.shared.save(photo: photo, storage: storage, quality: quality)
    }

    func saveImagesToAlbum(_ images: [UIImage]) async -> WatermarkCameraAlbumSaveResult {
        guard !images.isEmpty else {
            return .error(message: AppLocalization.string("wm_camera_capture_photo_first_message"))
        }

        let access = await WatermarkCameraAccess.requestPhotoLibraryAddAccessIfNeeded()
        switch access {
        case .granted:
            break
        case .rejectedRequest:
            return .blockingError(
                message: AppLocalization.string("wm_camera_album_permission_missing_error"),
                settingsURL: WatermarkCameraAccess.appSettingsURL
            )
        case .denied:
            return .blockingError(
                message: AppLocalization.string("wm_camera_album_permission_settings_error"),
                settingsURL: WatermarkCameraAccess.appSettingsURL
            )
        case .unknown:
            return .error(message: AppLocalization.string("wm_camera_album_permission_unknown_error"))
        }

        savingToAlbum = true
        defer { savingToAlbum = false }

        do {
            try await WatermarkPhotoAlbumWriter.write(images)
            return .success(count: images.count)
        } catch {
            return .error(
                message: String(
                    format: AppLocalization.string("wm_camera_save_album_failed_format"),
                    error.localizedDescription
                )
            )
        }
    }
}
