import Foundation

enum WatermarkCameraAlbumSaveResult: Sendable {
    case success(count: Int)
    case blockingError(message: String, settingsURL: URL?)
    case error(message: String)
}

@MainActor
enum WatermarkCameraExportCoordinator {
    static func savePhotoToAlbum(_ photo: WatermarkCapturedPhoto, storage: WatermarkCameraDraftStorage, quality: WatermarkExportQuality) async -> WatermarkAlbumSaveOutcome {
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
        return await WatermarkCameraAlbumSaveCoordinator.shared.save(photo: photo, storage: storage, quality: quality)
    }
}
