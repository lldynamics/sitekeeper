import SwiftUI
import UIKit

struct WatermarkCapturePreviewSection: View {
    let capturedPhoto: WatermarkCapturedPhoto?
    let capturedPhotos: [WatermarkCapturedPhoto]
    @Binding var selectedCapturedPhotoID: UUID?
    let hasMultipleCapturedPhotos: Bool
    let selectedCapturedPhotoNumber: Int
    let projectAssociationText: String
    let capturedPhotoMetaText: (Date) -> String
    let savingToAlbum: Bool
    let selectedProjectId: UUID?
    let logSeedPhoto: DailyLogSeedPhoto?
    let logDraftContent: String
    let todoSeedData: Data?
    let saveCurrentImageToAlbum: () -> Void
    let exportCurrentImage: () -> Void
    let saveAllImagesToAlbum: () -> Void
    let saveCurrentImageAsProjectDocument: () -> Void
    let requestClearPhotos: () -> Void

    var body: some View {
        if let capturedPhoto {
            Section(String(localized: "wm_camera_recent_capture_section_title")) {
                WatermarkCapturedPhotoPreview(photo: capturedPhoto)
                WatermarkCapturedPhotoList(
                    capturedPhotos: capturedPhotos,
                    selectedPhoto: capturedPhoto,
                    selectedCapturedPhotoID: $selectedCapturedPhotoID,
                    hasMultipleCapturedPhotos: hasMultipleCapturedPhotos
                )
                WatermarkCapturedPhotoMeta(
                    photo: capturedPhoto,
                    capturedPhotosCount: capturedPhotos.count,
                    hasMultipleCapturedPhotos: hasMultipleCapturedPhotos,
                    selectedCapturedPhotoNumber: selectedCapturedPhotoNumber,
                    projectAssociationText: projectAssociationText,
                    capturedPhotoMetaText: capturedPhotoMetaText
                )
                WatermarkRecentCaptureActions(
                    hasMultipleCapturedPhotos: hasMultipleCapturedPhotos,
                    savingToAlbum: savingToAlbum,
                    selectedProjectId: selectedProjectId,
                    logSeedPhoto: logSeedPhoto,
                    logDraftContent: logDraftContent,
                    todoSeedData: todoSeedData,
                    saveCurrentImageToAlbum: saveCurrentImageToAlbum,
                    exportCurrentImage: exportCurrentImage,
                    saveAllImagesToAlbum: saveAllImagesToAlbum,
                    saveCurrentImageAsProjectDocument: saveCurrentImageAsProjectDocument,
                    requestClearPhotos: requestClearPhotos
                )
            }
        } else {
            Section(String(localized: "wm_camera_recent_capture_section_title")) {
                ContentUnavailableView(
                    String(localized: "wm_camera_no_photo_title"),
                    systemImage: "camera.aperture",
                    description: Text(String(localized: "wm_camera_no_photo_message"))
                )
            }
        }
    }
}

struct WatermarkCapturedPhotoPreview: View {
    let photo: WatermarkCapturedPhoto

    var body: some View {
        Image(uiImage: photo.image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
