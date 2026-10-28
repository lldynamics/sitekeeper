import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import ThumbnailCacheCore

struct ThumbnailImageDecoderTests {
    @Test func cacheKeysSeparateDirectoriesSizesAndVariants() {
        let url = URL(fileURLWithPath: "/tmp/one/images/../photo.jpg")
        let equivalent = URL(fileURLWithPath: "/tmp/one/photo.jpg")
        let key = ThumbnailCacheKey(resourceURL: url, maxPixelSize: 120 * 3)
        #expect(key == ThumbnailCacheKey(resourceURL: equivalent, maxPixelSize: 360))
        #expect(key != ThumbnailCacheKey(resourceURL: equivalent, maxPixelSize: 361))
        #expect(key != ThumbnailCacheKey(resourceURL: equivalent, maxPixelSize: 360, variant: "video"))
        #expect(key != ThumbnailCacheKey(resourceURL: URL(fileURLWithPath: "/tmp/two/photo.jpg"), maxPixelSize: 360))
        #expect(ThumbnailCacheKey(resourceURL: url, maxPixelSize: .greatestFiniteMagnitude).pixelSize == 2_048)
    }

    @Test func realImageIODecodingRespectsSizeOrientationAndTransparentPixels() throws {
        try withFixtureDirectory { directory in
            let png = directory.appendingPathComponent("transparent.png")
            let jpeg = directory.appendingPathComponent("rotated.jpg")
            let context = try #require(CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8,
                                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
            context.fill(CGRect(x: 20, y: 10, width: 40, height: 20))
            let source = try #require(context.makeImage())
            try write(source, to: png, type: "public.png", orientation: 1)
            try write(source, to: jpeg, type: "public.jpeg", orientation: 6)
            let transparent = try #require(ThumbnailImageDecoder.decode(at: png, maxPixelSize: 20))
            #expect(transparent.image.width == 20)
            #expect(transparent.image.height == 10)
            #expect(transparent.decodedByteCost >= 20 * 10 * 4)
            let pixels = try #require(CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8,
                                               bytesPerRow: 80, space: CGColorSpaceCreateDeviceRGB(),
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            pixels.draw(transparent.image, in: CGRect(x: 0, y: 0, width: 20, height: 10))
            let data = try #require(pixels.data).assumingMemoryBound(to: UInt8.self)
            #expect(data[3] == 0)
            #expect(data[5 * 80 + 10 * 4 + 3] > 0)
            let rotated = try #require(ThumbnailImageDecoder.decode(at: jpeg, maxPixelSize: 20))
            #expect(rotated.image.width == 10)
            #expect(rotated.image.height == 20)
        }
    }

    @Test func corruptMissingAndInvalidDimensionInputsReturnNoImage() throws {
        try withFixtureDirectory { directory in
            let file = directory.appendingPathComponent("corrupt.png")
            try Data("invalid image".utf8).write(to: file)
            #expect(ThumbnailImageDecoder.decode(at: file, maxPixelSize: 256) == nil)
            #expect(ThumbnailImageDecoder.decode(at: file, maxPixelSize: 0) == nil)
            #expect(ThumbnailImageDecoder.decode(at: directory.appendingPathComponent("missing.jpg"), maxPixelSize: 256) == nil)
        }
    }

    private func write(_ image: CGImage, to url: URL, type: String, orientation: Int) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func withFixtureDirectory(_ operation: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("thumbnail-decoder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try operation(directory)
    }
}
