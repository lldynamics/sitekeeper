import SwiftUI
import PhotosUI
import UIKit

struct DailyLogWatermarkPhotoSection: View {
    @Binding var cameraPhotoTag: PhotoTag
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var photoDrafts: [PhotoDraft]
    let isImporting: Bool

    let onOpenCamera: () -> Void

    var body: some View {
        Section(AppLocalization.string("现场照片")) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Picker(AppLocalization.string("拍照标签"), selection: $cameraPhotoTag) {
                    ForEach(PhotoTag.allCases, id: \.self) { tag in
                        Text(tag.displayName).tag(tag)
                    }
                }
                Button {
                    onOpenCamera()
                } label: {
                    Label(AppLocalization.string("拍照"), systemImage: "camera.fill")
                }
                .disabled(photoDrafts.count >= 6)
            }

            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 6, matching: .images) {
                Label(AppLocalization.string("选择照片"), systemImage: "camera.fill")
            }
            .disabled(isImporting)
            .accessibilityIdentifier("daily-log-compose-photo-picker")

            if isImporting {
                ProgressView(AppLocalization.string("加载中…"))
                    .accessibilityIdentifier("daily-log-compose-photo-loading")
            }

            ForEach($photoDrafts) { $draft in
                VStack(alignment: .leading, spacing: 6) {
                    if let uiImage = UIImage(data: draft.data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Picker(AppLocalization.string("照片标签"), selection: $draft.tag) {
                        ForEach(PhotoTag.allCases, id: \.self) { tag in
                            Text(tag.displayName).tag(tag)
                        }
                    }
                    TextField(AppLocalization.string("照片备注"), text: $draft.note)
                }
            }
        }
    }
}
