import Foundation
import CoreGraphics
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ThumbnailCacheCore

enum ThumbnailBenchmarkPhase: String, CaseIterable, Sendable { case before, after }

enum ThumbnailBenchmarkWorkload: String, CaseIterable {
    case coldDecode = "cold_decode"
    case warmRepeated = "warm_repeated"
    case sameKeyConcurrent = "same_key_concurrent"
    case budgetRotation = "budget_rotation"
    case invalidateReload = "invalidate_reload"

    var requestCount: Int {
        switch self {
        case .coldDecode: 4
        case .warmRepeated: 32
        case .sameKeyConcurrent: 8
        case .budgetRotation: 18
        case .invalidateReload: 2
        }
    }
}

struct ThumbnailBenchmarkObservation: Equatable, Sendable {
    let width: Int
    let height: Int
    let decodedByteCost: Int

    init(_ value: DecodedThumbnail) {
        width = value.image.width
        height = value.image.height
        decodedByteCost = value.decodedByteCost
    }
}

/// This adapter preserves the frozen URL-based ImageIO source/thumbnail options.
/// It excludes UIKit wrapping, FileIOTaskRunner logging and cancellation relay.
/// Source: phase2 baseline ImageDownsampleService.swift, SHA-256 below.
enum LegacyUncachedThumbnailDecoder {
    static let referenceSHA256 = "a28bc289c4fea6194ff6caa48b9b823ed27edfbf12d5e088fa7c201713556a2b"

    static func decode(at url: URL, maxPixelSize: Int) -> DecodedThumbnail? {
        guard maxPixelSize > 0 else { return nil }
        let sourceOptions: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let thumbnailOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }
        return DecodedThumbnail(image: image)
    }
}

final class ThumbnailBenchmarkCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0
    private var successes = 0

    func decode(_ operation: () -> DecodedThumbnail?) -> DecodedThumbnail? {
        lock.withLock { attempts += 1 }
        let result = autoreleasepool(invoking: operation)
        if result != nil { lock.withLock { successes += 1 } }
        return result
    }

    var snapshot: (attempts: Int, successes: Int) { lock.withLock { (attempts, successes) } }
}

/// All decoder workers stop here until the test proves simultaneous misses.
/// The candidate needs one loader plus seven registered/coalesced waiters;
/// the reference needs eight workers at the gate before any decode can finish.
actor ThumbnailBenchmarkLatch {
    private(set) var arrivals = 0
    private var isOpen = false
    private var pending: [CheckedContinuation<Void, Never>] = []

    func hold() async {
        arrivals += 1
        guard !isOpen else { return }
        await withCheckedContinuation { pending.append($0) }
    }

    func release() {
        isOpen = true
        let continuations = pending
        pending.removeAll()
        continuations.forEach { $0.resume() }
    }
}

final class ThumbnailBenchmarkSession: @unchecked Sendable {
    let phase: ThumbnailBenchmarkPhase
    let counter = ThumbnailBenchmarkCounter()
    let cache: BudgetedResourceCache<ThumbnailCacheKey, DecodedThumbnail>

    init(phase: ThumbnailBenchmarkPhase, costLimit: Int) {
        self.phase = phase
        cache = BudgetedResourceCache(costLimit: costLimit, countLimit: 20, cost: { $0.decodedByteCost })
    }

    func image(at url: URL, pixelSize: Int, latch: ThumbnailBenchmarkLatch? = nil) async -> ThumbnailBenchmarkObservation? {
        let decoded: DecodedThumbnail?
        switch phase {
        case .before:
            decoded = await Task.detached(priority: .utility) { [counter] in
                if let latch { await latch.hold() }
                return counter.decode { LegacyUncachedThumbnailDecoder.decode(at: url, maxPixelSize: pixelSize) }
            }.value
        case .after:
            let key = ThumbnailCacheKey(resourceURL: url, maxPixelSize: Double(pixelSize), variant: "phase2-benchmark")
            decoded = await cache.value(for: key) { [counter] in
                if let latch { await latch.hold() }
                return counter.decode { ThumbnailImageDecoder.decode(at: url, maxPixelSize: pixelSize) }
            }
        }
        return decoded.map(ThumbnailBenchmarkObservation.init)
    }

    func invalidate(_ url: URL) {
        cache.invalidate { $0.resource == url.standardizedFileURL.path }
    }
}

struct ThumbnailBenchmarkFixtures: Sendable {
    static let pixelSize = 256
    let root: URL
    let images: [URL]
    let corrupt: URL
    let replacementTarget: URL
    let originalPNG: Data
    let replacementPNG: Data
    let fingerprint: String
    let threeImageBudget: Int

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("phase2-image-bench-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            var generated: [URL] = []
            var evidence: [String] = []
            var maximumCost = 0
            for index in 0..<8 {
                let jpeg = index.isMultiple(of: 2)
                let url = root.appendingPathComponent("image-\(index).\(jpeg ? "jpg" : "png")")
                let data = try Self.encoded(width: 1024, height: 768, colorIndex: index, jpeg: jpeg)
                try data.write(to: url)
                generated.append(url)
                evidence.append("\(url.lastPathComponent):\(Self.hash(data))")
                let old = try XCTUnwrap(LegacyUncachedThumbnailDecoder.decode(at: url, maxPixelSize: Self.pixelSize))
                let new = try XCTUnwrap(ThumbnailImageDecoder.decode(at: url, maxPixelSize: Self.pixelSize))
                XCTAssertEqual(ThumbnailBenchmarkObservation(old), ThumbnailBenchmarkObservation(new))
                maximumCost = max(maximumCost, new.decodedByteCost)
            }
            images = generated
            originalPNG = try Self.encoded(width: 1024, height: 768, colorIndex: 10, jpeg: false)
            replacementPNG = try Self.encoded(width: 768, height: 1024, colorIndex: 11, jpeg: false)
            corrupt = root.appendingPathComponent("corrupt.png")
            let invalid = Data([0x89, 0x50, 0x4e, 0x47, 0x00, 0xff, 0x00])
            try invalid.write(to: corrupt)
            replacementTarget = root.appendingPathComponent("invalidated.png")
            try originalPNG.write(to: replacementTarget)
            evidence.append("corrupt:\(Self.hash(invalid))")
            evidence.append("original:\(Self.hash(originalPNG))")
            evidence.append("replacement:\(Self.hash(replacementPNG))")
            fingerprint = Self.hash(Data(evidence.joined(separator: "\n").utf8))
            threeImageBudget = maximumCost * 3
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func encoded(width: Int, height: Int, colorIndex: Int, jpeg: Bool) throws -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        for y in stride(from: 0, to: height, by: 32) {
            for x in stride(from: 0, to: width, by: 32) {
                context.setFillColor(CGColor(
                    red: CGFloat((x / 32 + colorIndex) % 13) / 12,
                    green: CGFloat((y / 32 + colorIndex) % 11) / 10,
                    blue: CGFloat((x / 32 + y / 32 + colorIndex) % 9) / 8,
                    alpha: 1
                ))
                context.fill(CGRect(x: CGFloat(x), y: CGFloat(y), width: 32, height: 32))
            }
        }
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let type = jpeg ? UTType.jpeg.identifier : UTType.png.identifier
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}
