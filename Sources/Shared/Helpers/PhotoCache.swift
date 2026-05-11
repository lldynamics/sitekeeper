import UIKit
import Foundation

/// 缩略图缓存，避免重复磁盘 I/O
final class PhotoCache {
    static let shared = PhotoCache()
    private let cache = NSCache<NSString, UIImage>()

    func thumbnail(for fileName: String) -> UIImage? {
        if let img = cache.object(forKey: fileName as NSString) { return img }
        let url = PhotoStorage.thumbnailURL(for: fileName)
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            StorageIssueLog.record("照片缩略图读取失败：\(fileName)")
            return nil
        }
        guard let img = UIImage(data: data) else {
            StorageIssueLog.record("照片缩略图解码失败：\(fileName)")
            return nil
        }
        cache.setObject(img, forKey: fileName as NSString)
        return img
    }

    func thumbnailAsync(for fileName: String) async -> UIImage? {
        if let img = cache.object(forKey: fileName as NSString) { return img }
        let url = PhotoStorage.thumbnailURL(for: fileName)
        return await Task.detached(priority: .utility) { [cache] in
            let data: Data
            do {
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } catch {
                StorageIssueLog.record("照片缩略图读取失败：\(fileName)")
                return nil
            }
            guard let img = UIImage(data: data) else {
                StorageIssueLog.record("照片缩略图解码失败：\(fileName)")
                return nil
            }
            cache.setObject(img, forKey: fileName as NSString)
            return img
        }.value
    }

    func invalidate(fileName: String) {
        cache.removeObject(forKey: fileName as NSString)
    }

    func clear() { cache.removeAllObjects() }
}
