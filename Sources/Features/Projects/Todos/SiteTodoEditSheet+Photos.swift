import SwiftUI
import PhotosUI
import UIKit

extension SiteTodoEditSheet {
    @ViewBuilder
    func photoPickerRow(before: Bool) -> some View {
        let title = AppLocalization.string(before ? "整改前" : "整改后")
        let data = before ? beforePhotoData : afterPhotoData
        let fileName = before ? draft.record.rectificationBeforePhotoFileName : draft.record.rectificationAfterPhotoFileName
        let hasPhoto = data != nil || fileName != nil
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PhotosPicker(selection: before ? $beforePhotoItem : $afterPhotoItem, matching: .images) {
                    Label(String(format: AppLocalization.string(hasPhoto ? "替换%@照片" : "添加%@照片"), title), systemImage: "photo.on.rectangle")
                }
                Spacer()
                if hasPhoto {
                    Button(AppLocalization.string("移除"), role: .destructive) {
                        if before {
                            beforePhotoData = nil
                            draft.beforePhotoID = nil
                            draft.record.rectificationBeforePhotoFileName = nil
                        } else {
                            afterPhotoData = nil
                            draft.afterPhotoID = nil
                            draft.afterPhotoSourceID = nil
                            draft.record.rectificationAfterPhotoFileName = nil
                        }
                    }
                    .font(.caption)
                }
            }
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier(before ? "todo-draft-before-photo" : "todo-draft-after-photo")
            } else if fileName != nil {
                AsyncPhotoThumbnailImageView(fileName: fileName) { image in
                    image.resizable().scaledToFit().frame(maxHeight: 150).clipShape(RoundedRectangle(cornerRadius: 8))
                } placeholder: {
                    Image(systemName: "photo").frame(maxWidth: .infinity, minHeight: 88)
                }
            }
        }
    }

    func importTodoPhoto(_ item: PhotosPickerItem, before: Bool) async {
        defer {
            if before { beforePhotoImportTask = nil
            beforePhotoItem = nil } else { afterPhotoImportTask = nil
            afterPhotoItem = nil }
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self), !Task.isCancelled else { return }
            let normalized = ImageDownsampleService.downsampledJPEGData(data, maxPixelSize: 1600, compressionQuality: 0.8) ?? data
            guard !Task.isCancelled else { return }
            let photoID = UUID()
            try draftStore.savePhoto(normalized, id: photoID, key: draftKey)
            if before { beforePhotoData = normalized
            draft.beforePhotoID = photoID } else { afterPhotoData = normalized
            draft.afterPhotoID = photoID
            draft.afterPhotoSourceID = nil }
            persistDraft()
        } catch {
            draftError = String(format: AppLocalization.string("整改照片保存失败：%@"), error.localizedDescription)
        }
    }
}
