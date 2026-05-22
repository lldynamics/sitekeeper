import UIKit
import Foundation

/// 缩略图缓存，避免重复磁盘 I/O
final class PhotoCache {
    static let shared = PhotoCache()
    private let cache = NSCache<NSString, UIImage>()

    func cachedThumbnail(for fileName: String) -> UIImage? {
        cache.object(forKey: fileName as NSString)
    }

    func thumbnail(for fileName: String) -> UIImage? {
        if let img = cachedThumbnail(for: fileName) { return img }
        return loadThumbnailFromDisk(for: fileName)
    }

    func thumbnailAsync(for fileName: String) async -> UIImage? {
        if let img = cachedThumbnail(for: fileName) { return img }
        return await Task.detached(priority: .utility) { [self] in
            loadThumbnailFromDisk(for: fileName)
        }.value
    }

    private func loadThumbnailFromDisk(for fileName: String) -> UIImage? {
        let url = PhotoStorage.thumbnailURL(for: fileName)
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            StorageIssueLog.recordEvent(
                "photo_cache.thumbnail_read_failed",
                category: .fileStorage,
                details: [
                    "source": "PhotoCache.loadThumbnailFromDisk",
                    "file_name": fileName
                ],
                error: error
            )
            return nil
        }
        guard let img = UIImage(data: data) else {
            StorageIssueLog.recordEvent(
                "photo_cache.thumbnail_decode_failed",
                category: .fileStorage,
                details: [
                    "source": "PhotoCache.loadThumbnailFromDisk",
                    "file_name": fileName
                ]
            )
            return nil
        }
        cache.setObject(img, forKey: fileName as NSString)
        return img
    }

    func invalidate(fileName: String) {
        cache.removeObject(forKey: fileName as NSString)
    }

    func clear() { cache.removeAllObjects() }
}
