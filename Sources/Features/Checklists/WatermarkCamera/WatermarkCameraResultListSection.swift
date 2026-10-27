import SwiftUI
import UIKit

struct WatermarkCapturedPhotoList: View {
    let capturedPhotos: [WatermarkCapturedPhoto]
    let selectedPhoto: WatermarkCapturedPhoto
    @Binding var selectedCapturedPhotoID: UUID?
    let hasMultipleCapturedPhotos: Bool

    @ViewBuilder
    var body: some View {
        if hasMultipleCapturedPhotos {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(capturedPhotos.enumerated()), id: \.element.id) { index, photo in
                        Button {
                            selectedCapturedPhotoID = photo.id
                        } label: {
                            WatermarkCaptureThumbnail(
                                photo: photo,
                                index: index,
                                isSelected: photo.id == selectedPhoto.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct WatermarkCapturedPhotoMeta: View {
    let photo: WatermarkCapturedPhoto
    let capturedPhotosCount: Int
    let hasMultipleCapturedPhotos: Bool
    let selectedCapturedPhotoNumber: Int
    let projectAssociationText: String
    let capturedPhotoMetaText: (Date) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(capturedPhotoMetaText(photo.capturedAt))
            Text(projectAssociationText)
            if hasMultipleCapturedPhotos {
                Text(
                    String(
                        format: AppLocalization.string("wm_camera_burst_progress_text_format"),
                        capturedPhotosCount,
                        selectedCapturedPhotoNumber
                    )
                )
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

struct WatermarkRecentCaptureActions: View {
    let hasMultipleCapturedPhotos: Bool
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
        HStack(spacing: 12) {
            Button(action: saveCurrentImageToAlbum) {
                Label(AppLocalization.string("wm_camera_save_album_button"), systemImage: "photo.on.rectangle.angled")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(savingToAlbum)

            WatermarkMoreMenu(
                isToolbar: false,
                hasMultipleCapturedPhotos: hasMultipleCapturedPhotos,
                savingToAlbum: savingToAlbum,
                selectedProjectId: selectedProjectId,
                logSeedPhoto: logSeedPhoto,
                logDraftContent: logDraftContent,
                todoSeedData: todoSeedData,
                exportCurrentImage: exportCurrentImage,
                saveAllImagesToAlbum: saveAllImagesToAlbum,
                saveCurrentImageAsProjectDocument: saveCurrentImageAsProjectDocument,
                requestClearPhotos: requestClearPhotos
            )
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

private struct WatermarkCaptureThumbnail: View {
    let photo: WatermarkCapturedPhoto
    let index: Int
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected ? Color.appPrimaryAction : Color.appStrokeSecondary,
                            lineWidth: isSelected ? 2 : 1
                        )
                }
            Text("\(index + 1)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(4)
        }
    }
}
