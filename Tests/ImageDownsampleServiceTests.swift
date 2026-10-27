import Testing
import Darwin
import CoreImage
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
}

extension ImageDownsampleServiceTests {
    @Test func cameraJPEGUsesPixelDimensionsAndDoesNotUpscale() throws {
        let source = try #require(UIImage(data: Self.makeJPEGData(width: 240, height: 120))?.cgImage)
        let image = UIImage(cgImage: source, scale: 3, orientation: .up)
        for (limit, width, height) in [(160.0, 160, 80), (600.0, 240, 120)] {
            let data = try #require(ImageDownsampleService.downsampledJPEGData(
                image, maxPixelSize: CGFloat(limit), compressionQuality: 0.8
            ))
            let output = try #require(UIImage(data: data)?.cgImage)
            #expect(output.width == width)
            #expect(output.height == height)
        }
    }

    @Test(arguments: [UIImage.Orientation.up, .upMirrored, .down, .downMirrored,
                      .left, .leftMirrored, .right, .rightMirrored])
    func cameraJPEGNormalizesRotationAndMirroring(_ orientation: UIImage.Orientation) throws {
        let colors: [[Int]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let source = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 80), format: format).image { context in
            for (index, color) in colors.enumerated() {
                UIColor(red: CGFloat(color[0]) / 255, green: CGFloat(color[1]) / 255,
                        blue: CGFloat(color[2]) / 255, alpha: 1).setFill()
                context.fill(CGRect(x: (index % 2) * 60, y: (index / 2) * 40, width: 60, height: 40))
            }
        }
        let image = UIImage(cgImage: try #require(source.cgImage), scale: 2, orientation: orientation)
        let data = try #require(ImageDownsampleService.downsampledJPEGData(
            image, maxPixelSize: 60, compressionQuality: 0.8
        ))
        let decoded = try #require(UIImage(data: data))
        let output = try #require(decoded.cgImage)
        let corners: [Int]
        switch orientation {
        case .up: corners = [0, 1, 2, 3]
        case .upMirrored: corners = [1, 0, 3, 2]
        case .down: corners = [3, 2, 1, 0]
        case .downMirrored: corners = [2, 3, 0, 1]
        case .left: corners = [1, 3, 0, 2]
        case .leftMirrored: corners = [0, 2, 1, 3]
        case .right: corners = [2, 0, 3, 1]
        case .rightMirrored: corners = [3, 1, 2, 0]
        @unknown default: return
        }
        let swapsAxes = [UIImage.Orientation.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
        #expect(output.width == (swapsAxes ? 40 : 60))
        #expect(output.height == (swapsAxes ? 60 : 40))
        #expect(decoded.imageOrientation == .up)
        let pixels = try Self.rgbaPixels(output)
        for (index, colorIndex) in corners.enumerated() {
            let x = output.width * (index % 2 == 0 ? 1 : 3) / 4
            let y = output.height * (index < 2 ? 1 : 3) / 4
            for channel in 0..<3 {
                #expect(abs(Int(pixels[(y * output.width + x) * 4 + channel]) - colors[colorIndex][channel]) < 20)
            }
        }
    }

    @Test func cameraJPEGAvoidsIntermediateLossyEncoding() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let source = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 96), format: format).image { context in
            for y in 0..<96 {
                for x in 0..<128 {
                    let level = CGFloat(((x * 37 + y * 17) ^ (x * y)) % 256) / 255
                    UIColor(white: level, alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        let singleJPEG = try #require(source.jpegData(compressionQuality: 0.8))
        let actualJPEG = try #require(ImageDownsampleService.downsampledJPEGData(
            source, maxPixelSize: 128, compressionQuality: 0.8
        ))
        let original = try Self.rgbaPixels(#require(source.cgImage))
        let reference = try Self.rgbaPixels(#require(UIImage(data: singleJPEG)?.cgImage))
        let actual = try Self.rgbaPixels(#require(UIImage(data: actualJPEG)?.cgImage))
        func meanSquaredError(_ pixels: [UInt8]) -> Double {
            stride(from: 0, to: original.count, by: 4).reduce(0.0) { sum, index in
                let error = Double(pixels[index]) - Double(original[index])
                return sum + error * error
            } / Double(original.count / 4)
        }
        #expect(meanSquaredError(actual) <= meanSquaredError(reference) * 1.03 + 0.1)
    }

    @Test func cameraJPEGSupportsCoreImageBackedInput() throws {
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 240, height: 120))
        let image = UIImage(ciImage: source, scale: 2, orientation: .right)
        #expect(image.cgImage == nil)
        let data = try #require(ImageDownsampleService.downsampledJPEGData(
            image, maxPixelSize: 60, compressionQuality: 0.8
        ))
        let output = try #require(UIImage(data: data)?.cgImage)
        #expect(output.width == 30)
        #expect(output.height == 60)
        let pixels = try Self.rgbaPixels(output)
        #expect(pixels[0] > 230)
        #expect(pixels[1] < 20)
        #expect(pixels[2] < 20)
    }

    @Test func cameraJPEGRejectsEmptyImagesAndInvalidPixelLimits() throws {
        let image = try #require(UIImage(data: Self.makeJPEGData(width: 120, height: 80)))
        for limit in [CGFloat.zero, -1, 0.5, .nan, .infinity] {
            #expect(ImageDownsampleService.downsampledJPEGData(
                image, maxPixelSize: limit, compressionQuality: 0.8
            ) == nil)
        }
        #expect(ImageDownsampleService.downsampledJPEGData(
            UIImage(), maxPixelSize: 1600, compressionQuality: 0.8
        ) == nil)
    }

    private static func rgbaPixels(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }
}

extension ImageDownsampleServiceTests {
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
