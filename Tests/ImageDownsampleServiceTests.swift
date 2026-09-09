import Testing
import Darwin
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
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

    @Test func fileDownsamplePreservesPixelOrientation() throws {
        let source = try Self.makeOrientedJPEGData(width: 120, height: 240, orientation: .right)
        let fileURL = try Self.writeTemporary(source, extension: "jpg")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let image = try #require(
            ImageDownsampleService.downsampledImage(at: fileURL, maxPixelSize: 100)
        )

        #expect(image.size.width > image.size.height)
        #expect(max(image.size.width, image.size.height) <= 100.0)
    }

    @Test func fileDownsamplePreservesTransparency() throws {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 300), format: format).image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 300))
            UIColor.systemBlue.withAlphaComponent(0.5).setFill()
            context.fill(CGRect(x: 50, y: 50, width: 500, height: 200))
        }
        let source = try #require(image.pngData())
        let sourceImage = try #require(UIImage(data: source)?.cgImage)
        #expect(sourceImage.width == 600)
        #expect(sourceImage.height == 300)
        let fileURL = try Self.writeTemporary(source, extension: "png")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let thumbnail = try #require(
            ImageDownsampleService.downsampledImage(at: fileURL, maxPixelSize: 180)
        )
        let alphaInfo = try #require(thumbnail.cgImage?.alphaInfo)

        #expect(max(thumbnail.size.width, thumbnail.size.height) <= 180.0)
        #expect(![.none, .noneSkipFirst, .noneSkipLast].contains(alphaInfo))
    }

    @Test func cancelledAsyncDownsampleDoesNotReturnAnImage() async throws {
        let source = try Self.makeJPEGData(width: 1200, height: 800)
        let fileURL = try Self.writeTemporary(source, extension: "jpg")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let image = await Task {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return await ImageDownsampleService.downsampledImageAsync(
                at: fileURL,
                maxPixelSize: 240,
                source: "ImageDownsampleServiceTests.cancelled"
            )
        }.value

        #expect(image == nil)
    }

    fileprivate static func makeJPEGData(width: CGFloat, height: CGFloat) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: width, height: height),
            format: format
        )
        let image = renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        guard let data = image.jpegData(compressionQuality: 0.92) else {
            throw FileStorageError.imageEncodingFailed
        }
        return data
    }

    private static func makeOrientedJPEGData(
        width: CGFloat,
        height: CGFloat,
        orientation: CGImagePropertyOrientation
    ) throws -> Data {
        let source = try makeJPEGData(width: width, height: height)
        let image = try #require(UIImage(data: source)?.cgImage)
        #expect(image.width == Int(width))
        #expect(image.height == Int(height))
        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImagePropertyOrientation: orientation.rawValue] as CFDictionary
        )
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    fileprivate static func writeTemporary(_ data: Data, extension ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("image-downsample-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        try data.write(to: url, options: .atomic)
        return url
    }
}

final class ImageDownsamplePerformanceTests: XCTestCase {
    func testSequentialThumbnailLoadingFromSingleTwelveMegapixelFile() throws {
        let source = try ImageDownsampleServiceTests.makeJPEGData(width: 4_000, height: 3_000)
        let sourceImage = try XCTUnwrap(UIImage(data: source)?.cgImage)
        XCTAssertEqual(sourceImage.width, 4_000)
        XCTAssertEqual(sourceImage.height, 3_000)
        let fileURL = try ImageDownsampleServiceTests.writeTemporary(source, extension: "jpg")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let options = XCTMeasureOptions()
        options.iterationCount = 1
        let baselineResidentBytes = residentMemoryBytes()
        var observedPeakResidentBytes = baselineResidentBytes
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            for _ in 0..<200 {
                autoreleasepool {
                    let image = ImageDownsampleService.downsampledImage(at: fileURL, maxPixelSize: 360)
                    XCTAssertNotNil(image)
                    XCTAssertLessThanOrEqual(max(image?.size.width ?? 0, image?.size.height ?? 0), 360)
                    observedPeakResidentBytes = max(observedPeakResidentBytes, residentMemoryBytes())
                }
            }
        }
        let residentGrowthBytes = observedPeakResidentBytes - min(observedPeakResidentBytes, baselineResidentBytes)
        XCTAssertLessThan(
            residentGrowthBytes,
            128 * 1_024 * 1_024,
            "Sequential thumbnails should not retain full 12 MP decodes"
        )
    }

    private func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }
}
