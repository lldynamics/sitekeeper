import Foundation
import ImageIO
import UIKit

/// Only visible rows request decoded pixels. The cache bounds both count and decoded memory.
actor WatermarkCameraImageLoader {
    static let shared = WatermarkCameraImageLoader()
    private struct Entry {
        let image: UIImage
        let cost: Int
        var access: UInt64
    }
    private var entries: [String: Entry] = [:]
    private var clock: UInt64 = 0
    private var decodedCost = 0
    private let maximumCost = 24 * 1_024 * 1_024
    private let maximumCount = 48

    func thumbnail(for photo: WatermarkCapturedPhoto, maxPixelSize: Int = 720) -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let pixels = max(64, min(maxPixelSize, 2_400))
        let key = "\(photo.watermarkedURL?.path ?? photo.id.uuidString):\(pixels)"
        clock &+= 1
        if var entry = entries[key] {
            entry.access = clock
            entries[key] = entry
            return entry.image
        }
        let source: CGImageSource?
        if let url = photo.watermarkedURL {
            source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        } else if let data = photo.pendingWatermarkedData {
            source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        } else {
            source = nil
        }
        let image: UIImage?
        if let source {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
        } else if photo.watermarkedURL == nil {
            image = photo.fallbackWatermarkedImage ?? photo.thumbnail
        } else {
            image = nil
        }
        guard let image else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? pixels * pixels * 4
        // In-memory fallback images may be full resolution; never pin them in this cache.
        guard cost <= maximumCost else { return image }
        while entries.count >= maximumCount || decodedCost + cost > maximumCost {
            guard let oldest = entries.min(by: { $0.value.access < $1.value.access }) else { break }
            decodedCost -= oldest.value.cost
            entries.removeValue(forKey: oldest.key)
        }
        entries[key] = Entry(image: image, cost: cost, access: clock)
        decodedCost += cost
        return image
    }

    func imageForDelivery(_ photo: WatermarkCapturedPhoto) throws -> UIImage {
        try photo.imageForDelivery()
    }

    func originalImage(for photo: WatermarkCapturedPhoto) -> UIImage? { photo.originalImage }

    func removeCachedImages() {
        entries.removeAll()
        decodedCost = 0
    }
}
