import SwiftUI
import UIKit

struct AsyncPhotoThumbnailImageView<Content: View, Placeholder: View>: View {
    @Environment(\.displayScale) private var displayScale
    let fileName: String?
    var maxPointSize: CGFloat = 120
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
            let loadedImage = await ImageDownsampleService.downsampledImageAsync(
                at: PhotoStorage.thumbnailURL(for: fileName),
                maxPixelSize: maxPointSize * displayScale,
                source: "AsyncPhotoThumbnailImageView"
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
    }
}

struct AsyncQuickNoteAttachmentImageView<Content: View, Placeholder: View>: View {
    @Environment(\.displayScale) private var displayScale
    let fileName: String
    var maxPointSize: CGFloat = 120
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
            let loadedImage = await QuickNoteAttachmentStorage.thumbnailAsync(
                for: fileName,
                maxPixelSize: maxPointSize * displayScale
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
    }
}
