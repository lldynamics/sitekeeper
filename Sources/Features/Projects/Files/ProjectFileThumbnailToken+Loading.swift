import UIKit

extension ProjectFileThumbnailToken {
    func loadImageAsync() async -> UIImage? {
        switch self {
        case .photo(let fileName):
            return await PhotoStorage.thumbnailAsync(for: fileName, maxPixelSize: 256)
        case .quickNote(let kind, let fileName):
            switch kind {
            case .photo, .drawing:
                return await QuickNoteAttachmentStorage.thumbnailAsync(for: fileName, maxPixelSize: 256)
            case .video:
                let key = ThumbnailCacheKey(resourceURL: QuickNoteAttachmentStorage.fileURL(for: fileName),
                                            maxPixelSize: 512, variant: "video")
                return await StorageThumbnailCache.image(for: key) {
                    guard !Task.isCancelled,
                          let image = QuickNoteAttachmentStorage.videoThumbnail(for: fileName)?.cgImage,
                          !Task.isCancelled else { return nil }
                    return DecodedThumbnail(image: image)
                }
            case .audio, .file:
                return nil
            }
        }
    }

}
