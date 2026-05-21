import Testing
import UIKit
@testable import sitekeeper

struct ImageDownsampleServiceTests {
    @Test func downsampledJPEGDataProducesImageWithinTargetSize() throws {
        let source = try Self.makeJPEGData(width: 2400, height: 1200)

        let normalized = try #require(
            ImageDownsampleService.downsampledJPEGData(
                source,
                maxPixelSize: 600,
                compressionQuality: 0.8
            )
        )
        let image = try #require(UIImage(data: normalized))

        #expect(max(image.size.width, image.size.height) <= 600.0)
    }

    @Test func downsampledImageProducesThumbnailWithinTargetSize() throws {
        let source = try Self.makeJPEGData(width: 1800, height: 900)

        let image = try #require(
            ImageDownsampleService.downsampledImage(
                source,
                maxPixelSize: 256
            )
        )

        #expect(max(image.size.width, image.size.height) <= 256.0)
    }

    private static func makeJPEGData(width: CGFloat, height: CGFloat) throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw FileStorageError.imageEncodingFailed
        }
        return data
    }
}
