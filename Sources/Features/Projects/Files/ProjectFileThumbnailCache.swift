import UIKit

enum ProjectFileThumbnailCache {
    private final class Storage: @unchecked Sendable {
        let cache = NSCache<NSString, UIImage>()
    }

    private static let storage = Storage()

    static func image(for key: String) -> UIImage? {
        storage.cache.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, for key: String) {
        storage.cache.setObject(image, forKey: key as NSString)
    }
}
