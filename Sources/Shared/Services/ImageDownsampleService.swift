import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

enum ImageDownsampleService {
    static func downsampledJPEGData(
        _ data: Data,
        maxPixelSize: CGFloat,
        compressionQuality: CGFloat
    ) -> Data? {
        guard let image = downsampledCGImage(
            data,
            maxPixelSize: maxPixelSize,
            shouldCacheImmediately: false
        ) else {
            return nil
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        let options: CFDictionary = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return output as Data
    }

    static func downsampledJPEGData(
        _ image: UIImage,
        maxPixelSize: CGFloat,
        sourceCompressionQuality: CGFloat,
        compressionQuality: CGFloat
    ) -> Data? {
        guard let sourceData = image.jpegData(compressionQuality: sourceCompressionQuality) ?? image.pngData() else {
            return nil
        }
        return downsampledJPEGData(
            sourceData,
            maxPixelSize: maxPixelSize,
            compressionQuality: compressionQuality
        )
    }

    static func downsampledImage(_ data: Data, maxPixelSize: CGFloat) -> UIImage? {
        guard let image = downsampledCGImage(
            data,
            maxPixelSize: maxPixelSize,
            shouldCacheImmediately: true
        ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    static func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        guard maxPixelSize > 0 else { return nil }
        let sourceOptions: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        guard let image = downsampledCGImage(
            source: source,
            maxPixelSize: maxPixelSize,
            shouldCacheImmediately: true
        ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    static func downsampledImageAsync(
        at url: URL,
        maxPixelSize: CGFloat,
        source: String
    ) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        do {
            return try await FileIOTaskRunner.runWithRelay(
                priority: .utility,
                logContext: .init(
                    event: "image.downsample",
                    source: source,
                    category: .fileStorage,
                    details: ["file": url.lastPathComponent]
                )
            ) { relay in
                guard !relay.isCancelled(), !Task.isCancelled else { return nil }
                let image = downsampledImage(at: url, maxPixelSize: maxPixelSize)
                guard !relay.isCancelled(), !Task.isCancelled else { return nil }
                return image
            }
        } catch {
            return nil
        }
    }

    private static func downsampledCGImage(
        _ data: Data,
        maxPixelSize: CGFloat,
        shouldCacheImmediately: Bool
    ) -> CGImage? {
        let sourceOptions: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        return downsampledCGImage(
            source: source,
            maxPixelSize: maxPixelSize,
            shouldCacheImmediately: shouldCacheImmediately
        )
    }

    private static func downsampledCGImage(
        source: CGImageSource,
        maxPixelSize: CGFloat,
        shouldCacheImmediately: Bool
    ) -> CGImage? {
        guard maxPixelSize > 0 else { return nil }
        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: shouldCacheImmediately
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
    }
}
