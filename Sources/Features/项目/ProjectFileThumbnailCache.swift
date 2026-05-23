import UIKit

enum ProjectFileThumbnailCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}
