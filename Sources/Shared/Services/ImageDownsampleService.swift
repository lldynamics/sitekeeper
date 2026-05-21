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

    private static func downsampledCGImage(
        _ data: Data,
        maxPixelSize: CGFloat,
        shouldCacheImmediately: Bool
    ) -> CGImage? {
        let sourceOptions: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
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
