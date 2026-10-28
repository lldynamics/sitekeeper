import Foundation
import CoreGraphics
import ImageIO

/// The immutable decoded pixels are shared across readers; no drawing context is shared.
final class DecodedThumbnail: @unchecked Sendable {
    let image: CGImage

    init(image: CGImage) { self.image = image }

    var decodedByteCost: Int {
        let bytes = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        return bytes.overflow ? Int.max : bytes.partialValue
    }
}

enum ThumbnailImageDecoder {
    static func decode(at url: URL, maxPixelSize: Int) -> DecodedThumbnail? {
        guard maxPixelSize > 0, !Task.isCancelled else { return nil }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary), !Task.isCancelled else { return nil }
        return DecodedThumbnail(image: image)
    }
}

struct ThumbnailCacheKey: Hashable, Sendable {
    let resource: String
    let pixelSize: Int
    let variant: String

    init(resourceURL: URL, maxPixelSize: Double, variant: String = "image") {
        resource = resourceURL.standardizedFileURL.path
        pixelSize = maxPixelSize.isFinite ? Int(min(2_048, max(1, maxPixelSize.rounded(.up)))) : 1
        self.variant = variant
    }
}
