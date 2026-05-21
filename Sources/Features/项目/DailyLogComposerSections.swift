import SwiftUI
import PhotosUI
import UIKit

struct DailyLogWatermarkPhotoSection: View {
    @Binding var cameraPhotoTag: PhotoTag
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var photoDrafts: [PhotoDraft]

    let onOpenCamera: () -> Void

    var body: some View {
        Section(String(localized: "现场照片")) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Picker(String(localized: "拍照标签"), selection: $cameraPhotoTag) {
                    ForEach(PhotoTag.allCases, id: \.self) { tag in
                        Text(tag.displayName).tag(tag)
                    }
                }
                Button {
                    onOpenCamera()
                } label: {
                    Label(String(localized: "拍照"), systemImage: "camera.fill")
                }
                .disabled(photoDrafts.count >= 6)
            }

            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 6, matching: .images) {
                Label(String(localized: "选择照片"), systemImage: "camera.fill")
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
                    Picker(String(localized: "照片标签"), selection: $draft.tag) {
                        ForEach(PhotoTag.allCases, id: \.self) { tag in
                            Text(tag.displayName).tag(tag)
                        }
                    }
                    TextField(String(localized: "照片备注"), text: $draft.note)
                }
            }
        }
    }
}
