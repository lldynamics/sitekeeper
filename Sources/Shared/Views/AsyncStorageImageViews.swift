import SwiftUI
import UIKit
import Combine

struct AsyncPhotoThumbnailImageView<Content: View, Placeholder: View>: View {
    @Environment(\.displayScale) private var displayScale
    let fileName: String?
    var maxPointSize: CGFloat = 120
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var reloadRevision: UInt64 = 0

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .reloadThumbnail(onInvalidationOf: fileName.map(PhotoStorage.fileURL)) { reloadRevision &+= 1 }
        .task(id: ThumbnailViewRequest(key: requestKey, revision: reloadRevision)) {
            image = nil
            guard let fileName else { return }
            let loadedImage = await PhotoStorage.thumbnailAsync(
                for: fileName, maxPixelSize: maxPointSize * displayScale
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
    }

    private var requestKey: ThumbnailCacheKey? {
        fileName.map { PhotoCache.shared.key(for: $0, maxPixelSize: maxPointSize * displayScale) }
    }
}

struct AsyncQuickNoteAttachmentImageView<Content: View, Placeholder: View>: View {
    @Environment(\.displayScale) private var displayScale
    let fileName: String
    var maxPointSize: CGFloat = 120
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var reloadRevision: UInt64 = 0

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        .reloadThumbnail(onInvalidationOf: QuickNoteAttachmentStorage.fileURL(for: fileName)) { reloadRevision &+= 1 }
        .task(id: ThumbnailViewRequest(key: requestKey, revision: reloadRevision)) {
            image = nil
            let loadedImage = await QuickNoteAttachmentStorage.thumbnailAsync(
                for: fileName,
                maxPixelSize: maxPointSize * displayScale
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
    }

    private var requestKey: ThumbnailCacheKey {
        ThumbnailCacheKey(resourceURL: QuickNoteAttachmentStorage.fileURL(for: fileName),
                          maxPixelSize: Double(maxPointSize * displayScale))
    }
}

private struct ThumbnailViewRequest: Hashable {
    let key: ThumbnailCacheKey?
    let revision: UInt64
}

extension View {
    func reloadThumbnail(onInvalidationOf resourceURL: URL?, perform action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: ThumbnailCacheInvalidation.notificationName)
            .receive(on: RunLoop.main)) { notification in
            guard let resourceURL,
                  let invalidation = notification.object as? ThumbnailCacheInvalidation,
                  invalidation.affects(resourceURL) else { return }
            action()
        }
    }
}
