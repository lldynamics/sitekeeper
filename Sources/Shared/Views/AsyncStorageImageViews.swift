import SwiftUI
import UIKit

struct AsyncPhotoThumbnailImageView<Content: View, Placeholder: View>: View {
    let fileName: String?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: fileName) {
            image = nil
            guard let fileName else { return }
            image = await PhotoStorage.thumbnailAsync(for: fileName)
        }
    }
}

struct AsyncQuickNoteAttachmentImageView<Content: View, Placeholder: View>: View {
    let fileName: String
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .task(id: fileName) {
            image = nil
            guard let data = await QuickNoteAttachmentStorage.dataAsync(for: fileName),
                  let uiImage = UIImage(data: data) else {
                return
            }
            image = uiImage
        }
    }
}
