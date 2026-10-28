#if canImport(UIKit)
import Foundation
import UIKit

/// One process-wide budget for photo, project-file and quick-note thumbnails.
enum StorageThumbnailCache {
    private final class Storage: @unchecked Sendable {
        let cache = BudgetedResourceCache<ThumbnailCacheKey, DecodedThumbnail>(
            costLimit: 64 * 1_024 * 1_024, countLimit: 256, cost: { $0.decodedByteCost }
        )
        private var memoryWarningObserver: NSObjectProtocol?

        init() {
            memoryWarningObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
            ) { [weak self] _ in self?.cache.purgeRetainedValues() }
        }

        deinit {
            if let memoryWarningObserver { NotificationCenter.default.removeObserver(memoryWarningObserver) }
        }
    }

    private static let storage = Storage()

    // Internal read-only diagnostics used by isolated runtime validation.
    static var statistics: BudgetedResourceCache<ThumbnailCacheKey, DecodedThumbnail>.Statistics {
        storage.cache.statistics
    }

    static var costLimit: Int { storage.cache.costLimit }
    static var countLimit: Int { storage.cache.countLimit }

    static func cachedImage(for key: ThumbnailCacheKey) -> UIImage? {
        storage.cache.cachedValue(for: key).map { UIImage(cgImage: $0.image) }
    }

    static func image(for key: ThumbnailCacheKey, sourceURL: URL) async -> UIImage? {
        await image(for: key) {
            ThumbnailImageDecoder.decode(at: sourceURL, maxPixelSize: key.pixelSize)
        }
    }

    static func image(
        for key: ThumbnailCacheKey,
        loader: @escaping @Sendable () async -> DecodedThumbnail?
    ) async -> UIImage? {
        let value = await storage.cache.value(for: key, loader: loader)
        guard !Task.isCancelled else { return nil }
        return value.map { UIImage(cgImage: $0.image) }
    }

    static func imageSynchronously(for key: ThumbnailCacheKey, sourceURL: URL) -> UIImage? {
        storage.cache.synchronousValue(for: key) {
            ThumbnailImageDecoder.decode(at: sourceURL, maxPixelSize: key.pixelSize)
        }.map { UIImage(cgImage: $0.image) }
    }

    static func invalidate(resourceURL: URL) {
        let path = resourceURL.standardizedFileURL.path
        storage.cache.invalidate { $0.resource == path }
        notify(.resource(resourceURL))
    }

    static func invalidate(directoryURL: URL) {
        let prefix = directoryURL.standardizedFileURL.path + "/"
        storage.cache.invalidate { $0.resource.hasPrefix(prefix) }
        notify(.directory(directoryURL))
    }

    static func clear() {
        storage.cache.clear()
        notify(.all)
    }

    private static func notify(_ invalidation: ThumbnailCacheInvalidation) {
        NotificationCenter.default.post(name: ThumbnailCacheInvalidation.notificationName, object: invalidation)
    }
}
#endif
