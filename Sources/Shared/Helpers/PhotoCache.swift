import UIKit
import Foundation

/// Photo compatibility entry points share the same decoded-byte budget as other thumbnails.
final class PhotoCache: Sendable {
    static let shared = PhotoCache()

    func key(for fileName: String, maxPixelSize: CGFloat = 512) -> ThumbnailCacheKey {
        ThumbnailCacheKey(resourceURL: PhotoStorage.fileURL(for: fileName), maxPixelSize: Double(maxPixelSize))
    }

    func cachedThumbnail(for fileName: String) -> UIImage? {
        StorageThumbnailCache.cachedImage(for: key(for: fileName))
    }

    func thumbnail(for fileName: String) -> UIImage? {
        StorageThumbnailCache.imageSynchronously(
            for: key(for: fileName), sourceURL: PhotoStorage.thumbnailURL(for: fileName)
        )
    }

    func thumbnailAsync(for fileName: String, maxPixelSize: CGFloat = 512) async -> UIImage? {
        await StorageThumbnailCache.image(
            for: key(for: fileName, maxPixelSize: maxPixelSize),
            sourceURL: PhotoStorage.thumbnailURL(for: fileName)
        )
    }

    func invalidate(fileName: String) {
        StorageThumbnailCache.invalidate(resourceURL: PhotoStorage.fileURL(for: fileName))
    }

    func clear() { StorageThumbnailCache.invalidate(directoryURL: PhotoStorage.photoDir) }
}
