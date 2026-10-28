import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ThumbnailCacheCore

typealias ThumbnailHostMemoryCache = BudgetedResourceCache<ThumbnailCacheKey, DecodedThumbnail>

struct ThumbnailHostMemoryFixtures {
    let root: URL
    let images: [URL]
    let decodedWorkingSetBytes: Int
    static let targetPixels = 1_024

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumbnail-host-memory-\(UUID().uuidString)", isDirectory: true)
        root = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let data = try Self.makeJPEG()
            let urls = try (0..<40).map { index in
                let url = directory.appendingPathComponent("source-\(index).jpg")
                try data.write(to: url, options: .atomic)
                return url
            }
            images = urls
            decodedWorkingSetBytes = try autoreleasepool {
                let value = try XCTUnwrap(ThumbnailImageDecoder.decode(at: urls[0], maxPixelSize: Self.targetPixels))
                return value.decodedByteCost * urls.count
            }
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private static func makeJPEG() throws -> Data {
        try autoreleasepool {
            let side = 2_048
            let context = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                                bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            context.setFillColor(red: 0.1, green: 0.3, blue: 0.85, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: CGFloat(side), height: CGFloat(side)))
            let image = try XCTUnwrap(context.makeImage())
            let data = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            return data as Data
        }
    }
}

final class ThumbnailHostMemorySession {
    let cache = ThumbnailHostMemoryCache(costLimit: 64 * 1_024 * 1_024, countLimit: 256, cost: { $0.decodedByteCost })

    /// Keep returned CGImages inside this scope; the test loop retains no result array.
    func loadAndRelease(_ url: URL) async throws {
        let key = ThumbnailCacheKey(resourceURL: url, maxPixelSize: Double(ThumbnailHostMemoryFixtures.targetPixels))
        let result = await cache.value(for: key) {
            autoreleasepool {
                ThumbnailImageDecoder.decode(at: url, maxPixelSize: ThumbnailHostMemoryFixtures.targetPixels)
            }
        }
        let thumbnail = try XCTUnwrap(result)
        XCTAssertLessThanOrEqual(max(thumbnail.image.width, thumbnail.image.height), ThumbnailHostMemoryFixtures.targetPixels)
        XCTAssertGreaterThan(thumbnail.decodedByteCost, 0)
    }
}

final class ThumbnailHostMemoryRecorder {
    private var sampledPeakRSS: UInt64 = 0
    private var sampledPeakFootprint: UInt64 = 0
    private var maximumRetained = 0
    private var samples: [Data] = []

    func sample(
        stage: String, round: Int = 0, session: ThumbnailHostMemorySession,
        fixtures: ThumbnailHostMemoryFixtures
    ) throws {
        let cache = session.cache.statistics
        let reading = readMemory()
        if reading.status == KERN_SUCCESS {
            sampledPeakRSS = max(sampledPeakRSS, reading.resident)
            sampledPeakFootprint = max(sampledPeakFootprint, reading.footprint)
        }
        maximumRetained = max(maximumRetained, cache.retainedCost)
        let payload: [String: Any] = [
            "stage": stage, "round": round, "process_id": ProcessInfo.processInfo.processIdentifier,
            "uptime_seconds": ProcessInfo.processInfo.systemUptime,
            "cost_limit_bytes": session.cache.costLimit, "count_limit": session.cache.countLimit,
            "retained_cost_bytes": cache.retainedCost, "entry_count": cache.entryCount,
            "in_flight_count": cache.inFlightCount, "load_count": cache.loadCount,
            "hit_count": cache.hitCount, "eviction_count": cache.evictionCount,
            "maximum_sampled_retained_cost_bytes": maximumRetained,
            "working_set_decoded_bytes": fixtures.decodedWorkingSetBytes, "source_file_count": fixtures.images.count,
            "task_info_status": reading.status,
            "resident_bytes": reading.status == KERN_SUCCESS ? NSNumber(value: reading.resident) : NSNull(),
            "phys_footprint_bytes": reading.status == KERN_SUCCESS ? NSNumber(value: reading.footprint) : NSNull(),
            "sampled_peak_resident_bytes": sampledPeakRSS, "sampled_peak_phys_footprint_bytes": sampledPeakFootprint,
            "measurement_scope": "macOS_host_ImageIO_core_only_not_iOS_UI_or_device_acceptance",
            "peak_scope": "sampled_snapshots_not_OS_high_water_mark"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        samples.append(data)
        print("PHASE2_HOST_MEMORY \(String(decoding: data, as: UTF8.self))")
        XCTAssertEqual(reading.status, KERN_SUCCESS, "Mach task_vm_info is required for process memory evidence")
        XCTAssertLessThanOrEqual(cache.retainedCost, session.cache.costLimit)
        XCTAssertLessThanOrEqual(cache.entryCount, session.cache.countLimit)
    }

    /// An explicit path opts in to an independent, complete evidence artifact.
    /// Exclusive creation preserves existing evidence even if two runs choose the same path.
    func writeSamplesIfRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["SITEKEEPER_PHASE2_MEMORY_OUTPUT"] else { return }
        guard path.hasPrefix("/"), !path.hasSuffix("/") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        var document = Data("{\"schema_version\":1,\"sample_count\":\(samples.count),\"samples\":[\n".utf8)
        for (index, sample) in samples.enumerated() {
            if index > 0 { document.append(contentsOf: ",\n".utf8) }
            document.append(sample)
        }
        document.append(contentsOf: "\n]}\n".utf8)
        try document.write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)
    }

    private func readMemory() -> (status: kern_return_t, resident: UInt64, footprint: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return (result, info.resident_size, info.phys_footprint)
    }
}
