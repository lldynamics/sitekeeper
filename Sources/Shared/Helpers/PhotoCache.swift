import UIKit

/// 缩略图缓存，避免重复磁盘 I/O
final class PhotoCache {
    static let shared = PhotoCache()
    private let cache = NSCache<NSString, UIImage>()

    func thumbnail(for fileName: String) -> UIImage? {
        if let img = cache.object(forKey: fileName as NSString) { return img }
        let url = PhotoStorage.thumbnailURL(for: fileName)
        guard let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else { return nil }
        cache.setObject(img, forKey: fileName as NSString)
        return img
    }

    func invalidate(fileName: String) {
        cache.removeObject(forKey: fileName as NSString)
    }

    func clear() { cache.removeAllObjects() }
}
