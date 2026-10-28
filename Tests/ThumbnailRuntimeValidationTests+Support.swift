import Darwin
import Foundation
import Testing
import UIKit
@testable import sitekeeper

@MainActor
final class RuntimeThumbnailFiles {
    let root: URL
    private var ownedFiles: [URL] = []

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("thumbnail-runtime-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func own(_ url: URL) { ownedFiles.append(url) }

    func write(_ data: Data, name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    func cleanup() {
        StorageThumbnailCache.invalidate(directoryURL: root)
        for url in ownedFiles {
            StorageThumbnailCache.invalidate(resourceURL: url)
            try? FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.removeItem(at: root)
    }

    static func jpeg(color: UIColor, side: Int = 256) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let dimension = CGFloat(side)
        let image = UIGraphicsImageRenderer(size: CGSize(width: dimension, height: dimension), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: dimension, height: dimension))
        }
        return try #require(image.jpegData(compressionQuality: 0.85))
    }

    static func expectBlue(_ image: UIImage?) throws {
        let components = try pixel(image)
        #expect(components[2] > components[0] + 100)
        #expect(components[2] > components[1] + 100)
    }

    static func expectRed(_ image: UIImage?) throws {
        let components = try pixel(image)
        #expect(components[0] > components[1] + 100)
        #expect(components[0] > components[2] + 100)
    }

    private static func pixel(_ image: UIImage?) throws -> [Int] {
        let image = try #require(image?.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes.map(Int.init)
    }
}

actor RuntimeThumbnailGate {
    private var continuation: CheckedContinuation<DecodedThumbnail?, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?

    func load() async -> DecodedThumbnail? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitForStart() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func complete(_ image: DecodedThumbnail) {
        continuation?.resume(returning: image)
        continuation = nil
    }
}

@MainActor
func waitForRuntimeThumbnailState(_ description: String, _ condition: () -> Bool) async {
    for _ in 0..<100_000 {
        if condition() { return }
        await Task.yield()
    }
    Issue.record("Thumbnail state not reached: \(description)")
}

@MainActor
final class RuntimeThumbnailMemoryRecorder {
    private var sampledPeakRSS: UInt64 = 0
    private var sampledPeakFootprint: UInt64 = 0
    private var maximumRetained = 0

    func sample(_ stage: String, round: Int = 0, requestedWorkingSetBytes: Int = 0) throws {
        let cache = StorageThumbnailCache.statistics
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if status == KERN_SUCCESS {
            sampledPeakRSS = max(sampledPeakRSS, info.resident_size)
            sampledPeakFootprint = max(sampledPeakFootprint, info.phys_footprint)
        }
        maximumRetained = max(maximumRetained, cache.retainedCost)
        let payload: [String: Any] = [
            "stage": stage, "round": round, "process_id": ProcessInfo.processInfo.processIdentifier,
            "bundle_identifier": Bundle.main.bundleIdentifier ?? "unavailable",
            "uptime_seconds": ProcessInfo.processInfo.systemUptime,
            "cost_limit_bytes": StorageThumbnailCache.costLimit, "count_limit": StorageThumbnailCache.countLimit,
            "retained_cost_bytes": cache.retainedCost, "entry_count": cache.entryCount,
            "in_flight_count": cache.inFlightCount, "load_count": cache.loadCount,
            "hit_count": cache.hitCount, "eviction_count": cache.evictionCount,
            "maximum_sampled_retained_cost_bytes": maximumRetained,
            "working_set_decoded_bytes": requestedWorkingSetBytes, "task_info_status": status,
            "resident_bytes": status == KERN_SUCCESS ? NSNumber(value: info.resident_size) : NSNull(),
            "phys_footprint_bytes": status == KERN_SUCCESS ? NSNumber(value: info.phys_footprint) : NSNull(),
            "sampled_peak_resident_bytes": sampledPeakRSS, "sampled_peak_phys_footprint_bytes": sampledPeakFootprint,
            "measurement_scope": "simulator_app_process_snapshots_not_OS_peak_or_device_acceptance"
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print("PHASE2_MEMORY \(String(decoding: data, as: UTF8.self))")
        #expect(status == KERN_SUCCESS, "The app process must expose task_vm_info for memory evidence")
        #expect(cache.retainedCost <= StorageThumbnailCache.costLimit)
        #expect(cache.entryCount <= StorageThumbnailCache.countLimit)
    }
}
