import Foundation
import XCTest
@testable import ThumbnailCacheCore

/// Opt-in macOS ImageIO/core-cache workloads. These do not exercise UIKit,
/// memory-warning delivery, UI frame rate, disk cold-starts or process RSS.
final class ThumbnailImageBenchmarkTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testColdDecode() async throws { try await run(.coldDecode) }
    func testWarmRepeated() async throws { try await run(.warmRepeated) }
    func testSameKeyConcurrent() async throws { try await run(.sameKeyConcurrent) }
    func testBudgetRotation() async throws { try await run(.budgetRotation) }
    func testInvalidateReload() async throws { try await run(.invalidateReload) }

    private struct Sample {
        let milliseconds: Double
        let decodeAttempts: Int
        let successfulDecodes: Int
        let retainedCost: Int
        let retainedEntries: Int
        let evictions: Int
        let coalesced: Int
        let observations: [ThumbnailBenchmarkObservation?]
    }

    private func run(_ workload: ThumbnailBenchmarkWorkload) async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SITEKEEPER_RUN_PHASE2_BENCHMARK"] == "1",
                          "Set SITEKEEPER_RUN_PHASE2_BENCHMARK=1 to run the image cache host benchmarks")
        let fixtures = try ThumbnailBenchmarkFixtures()
        defer { try? FileManager.default.removeItem(at: fixtures.root) }
        let budget = workload == .budgetRotation ? fixtures.threeImageBudget : 64 * 1024 * 1024
        var samples: [ThumbnailBenchmarkPhase: [Sample]] = [.before: [], .after: []]
        // One warm-up per strategy, then seven interleaved pairs. Alternate pair
        // order to reduce systematic bias from always running one strategy last.
        for iteration in -1..<7 {
            let order: [ThumbnailBenchmarkPhase] = iteration.isMultiple(of: 2) ? [.after, .before] : [.before, .after]
            var pair: [ThumbnailBenchmarkPhase: Sample] = [:]
            for phase in order {
                pair[phase] = try await measure(workload, phase: phase, fixtures: fixtures, budget: budget)
            }
            XCTAssertEqual(pair[.before]?.observations, pair[.after]?.observations)
            if iteration >= 0 {
                for phase in ThumbnailBenchmarkPhase.allCases { samples[phase, default: []].append(try XCTUnwrap(pair[phase])) }
            }
        }
        for phase in ThumbnailBenchmarkPhase.allCases {
            try emit(workload, phase: phase, fixtures: fixtures, budget: budget, samples: try XCTUnwrap(samples[phase]))
        }
    }

    private func measure(
        _ workload: ThumbnailBenchmarkWorkload, phase: ThumbnailBenchmarkPhase,
        fixtures: ThumbnailBenchmarkFixtures, budget: Int
    ) async throws -> Sample {
        let session = ThumbnailBenchmarkSession(phase: phase, costLimit: budget)
        if workload == .invalidateReload { try fixtures.originalPNG.write(to: fixtures.replacementTarget, options: .atomic) }
        if workload == .warmRepeated || workload == .invalidateReload {
            let url = workload == .warmRepeated ? fixtures.images[0] : fixtures.replacementTarget
            let preloaded = await session.image(at: url, pixelSize: ThumbnailBenchmarkFixtures.pixelSize)
            XCTAssertNotNil(preloaded)
        }
        let initial = session.counter.snapshot
        let initialStats = session.cache.statistics
        let start = DispatchTime.now().uptimeNanoseconds
        let observations = try await perform(workload, session: session, fixtures: fixtures)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        let final = session.counter.snapshot
        let stats = session.cache.statistics
        XCTAssertEqual(observations.count, workload.requestCount)
        if workload != .coldDecode {
            XCTAssertEqual(observations.compactMap { $0 }.count, workload.requestCount)
        }
        XCTAssertLessThanOrEqual(stats.retainedCost, budget)
        XCTAssertEqual(stats.inFlightCount, 0)
        if phase == .before { XCTAssertEqual(stats.retainedCost, 0) }
        let sample = Sample(
            milliseconds: elapsed, decodeAttempts: final.attempts - initial.attempts,
            successfulDecodes: final.successes - initial.successes,
            retainedCost: stats.retainedCost, retainedEntries: stats.entryCount,
            evictions: stats.evictionCount - initialStats.evictionCount,
            coalesced: stats.coalescedCount - initialStats.coalescedCount,
            observations: observations
        )
        assertWorkloadResult(workload, phase: phase, sample: sample, statistics: stats)
        return sample
    }

    private func assertWorkloadResult(
        _ workload: ThumbnailBenchmarkWorkload, phase: ThumbnailBenchmarkPhase,
        sample: Sample,
        statistics: BudgetedResourceCache<ThumbnailCacheKey, DecodedThumbnail>.Statistics
    ) {
        switch workload {
        case .coldDecode:
            XCTAssertEqual(sample.decodeAttempts, 4)
            XCTAssertEqual(sample.observations.compactMap { $0 }.count, 2)
        case .warmRepeated:
            XCTAssertEqual(sample.decodeAttempts, phase == .before ? 32 : 0)
        case .sameKeyConcurrent:
            XCTAssertEqual(sample.decodeAttempts, phase == .before ? 8 : 1)
            if phase == .after { XCTAssertEqual(statistics.coalescedCount, 7) }
        case .budgetRotation:
            if phase == .after { XCTAssertGreaterThan(statistics.evictionCount, 0) }
        case .invalidateReload:
            XCTAssertNotEqual(sample.observations[0]?.width, sample.observations[1]?.width)
            XCTAssertEqual(sample.decodeAttempts, phase == .before ? 2 : 1)
        }
    }

    private func perform(
        _ workload: ThumbnailBenchmarkWorkload, session: ThumbnailBenchmarkSession,
        fixtures: ThumbnailBenchmarkFixtures
    ) async throws -> [ThumbnailBenchmarkObservation?] {
        let pixels = ThumbnailBenchmarkFixtures.pixelSize
        switch workload {
        case .coldDecode:
            var output: [ThumbnailBenchmarkObservation?] = []
            for url in [fixtures.images[0], fixtures.images[1], fixtures.corrupt, fixtures.corrupt] {
                output.append(await session.image(at: url, pixelSize: pixels))
            }
            return output
        case .warmRepeated:
            var output: [ThumbnailBenchmarkObservation?] = []
            for _ in 0..<workload.requestCount { output.append(await session.image(at: fixtures.images[0], pixelSize: pixels)) }
            return output
        case .sameKeyConcurrent:
            return try await performConcurrentMisses(workload, session: session, fixtures: fixtures)
        case .budgetRotation:
            var output: [ThumbnailBenchmarkObservation?] = []
            for index in [0, 1, 2, 0, 1, 2, 3, 4, 5, 3, 4, 5, 6, 7, 0, 6, 7, 0] {
                output.append(await session.image(at: fixtures.images[index], pixelSize: pixels))
            }
            return output
        case .invalidateReload:
            let first = await session.image(at: fixtures.replacementTarget, pixelSize: pixels)
            // Deliberately measure replacement-file I/O plus invalidation/reload.
            // Only this test's newly-created temporary PNG is overwritten.
            try fixtures.replacementPNG.write(to: fixtures.replacementTarget, options: .atomic)
            session.invalidate(fixtures.replacementTarget)
            let second = await session.image(at: fixtures.replacementTarget, pixelSize: pixels)
            return [first, second]
        }
    }

    private func performConcurrentMisses(
        _ workload: ThumbnailBenchmarkWorkload, session: ThumbnailBenchmarkSession,
        fixtures: ThumbnailBenchmarkFixtures
    ) async throws -> [ThumbnailBenchmarkObservation?] {
        let pixels = ThumbnailBenchmarkFixtures.pixelSize
        let latch = ThumbnailBenchmarkLatch()
        let requests = (0..<workload.requestCount).map { _ in
            Task { await session.image(at: fixtures.images[0], pixelSize: pixels, latch: latch) }
        }
        let deadline = DispatchTime.now().uptimeNanoseconds + 5_000_000_000
        var simultaneousMisses = false
        while DispatchTime.now().uptimeNanoseconds < deadline {
            let arrivals = await latch.arrivals
            simultaneousMisses = session.phase == .before
                ? arrivals == workload.requestCount
                : arrivals == 1 && session.cache.statistics.coalescedCount == workload.requestCount - 1
            if simultaneousMisses { break }
            await Task.yield()
        }
        // Release even on a failed readiness check; never leave workers hung.
        await latch.release()
        var output: [ThumbnailBenchmarkObservation?] = []
        for request in requests { output.append(await request.value) }
        guard simultaneousMisses else { throw BenchmarkFailure.simultaneousMissGateTimedOut }
        return output
    }

    private func emit(
        _ workload: ThumbnailBenchmarkWorkload, phase: ThumbnailBenchmarkPhase,
        fixtures: ThumbnailBenchmarkFixtures, budget: Int, samples: [Sample]
    ) throws {
        XCTAssertEqual(samples.count, 7)
        let times = samples.map(\.milliseconds)
        let record: [String: Any] = [
            "schema": 1, "phase": phase.rawValue, "name": workload.rawValue,
            "fixture_sha256": fixtures.fingerprint,
            "legacy_source_sha256": LegacyUncachedThumbnailDecoder.referenceSHA256,
            "max_pixel_size": ThumbnailBenchmarkFixtures.pixelSize, "requests": workload.requestCount,
            "concurrency": workload == .sameKeyConcurrent ? 8 : 1,
            "budget_bytes": budget, "count_limit": 20,
            "fixture_source_dimensions": "1024x768; replacement 768x1024; corrupt PNG header",
            "warmups_per_phase": 1, "samples_ms": times, "median_ms": times.sorted()[3],
            "decode_attempts": samples.map(\.decodeAttempts),
            "successful_decodes": samples.map(\.successfulDecodes),
            "retained_decoded_cost_bytes": samples.map(\.retainedCost),
            "retained_entries": samples.map(\.retainedEntries),
            "evictions": samples.map(\.evictions), "coalesced_requests": samples.map(\.coalesced),
            "scope": "macOS ImageIO plus actual core cache; retained decoded budget is not RSS; no UIKit/device/FPS acceptance",
            "cold_definition": "fresh application cache; source files and OS/decoder caches may already be warm",
            "sample_preconditions": "fixture generation/preflight excluded; warm_repeated and invalidate_reload preload each fresh session outside timing/counters",
            "host_os": ProcessInfo.processInfo.operatingSystemVersionString,
            "paired_sampling": "one warm-up per phase plus seven interleaved pairs; pair order alternates",
            "invalidation_includes_temporary_file_write": workload == .invalidateReload
        ]
        let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
        print("PHASE2_IMAGE_BENCH " + String(decoding: data, as: UTF8.self))
    }

    private enum BenchmarkFailure: Error { case simultaneousMissGateTimedOut }
}
