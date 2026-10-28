import Foundation
import XCTest
@testable import ThumbnailCacheCore

/// Opt-in process memory observations of the real macOS ImageIO/core implementation.
/// This does not exercise UIKit wrappers, memory-warning delivery, iOS UI or devices.
final class ThumbnailHostMemoryTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFiveWorkingSetRotationsAndClearMemoryTrend() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SITEKEEPER_RUN_PHASE2_MEMORY"] == "1",
                          "Set SITEKEEPER_RUN_PHASE2_MEMORY=1 for the synthetic host memory workload")
        let fixtures = try ThumbnailHostMemoryFixtures()
        defer { try? FileManager.default.removeItem(at: fixtures.root) }
        let recorder = ThumbnailHostMemoryRecorder()
        try await warmUp(fixtures, recorder: recorder)
        // A new cache separates warm-up counters and retained objects from measurement.
        let session = ThumbnailHostMemorySession()
        XCTAssertEqual(session.cache.costLimit, 64 * 1_024 * 1_024)
        XCTAssertEqual(session.cache.countLimit, 256)
        XCTAssertGreaterThan(fixtures.decodedWorkingSetBytes, session.cache.costLimit)
        try recorder.sample(stage: "measurement_baseline_after_warmup", session: session, fixtures: fixtures)
        for round in 1...5 {
            try await measureRound(round, session: session, fixtures: fixtures, recorder: recorder)
        }
        try recorder.sample(stage: "measurement_finished", round: 5, session: session, fixtures: fixtures)
        try recorder.writeSamplesIfRequested()
    }

    private func warmUp(
        _ fixtures: ThumbnailHostMemoryFixtures, recorder: ThumbnailHostMemoryRecorder
    ) async throws {
        let session = ThumbnailHostMemorySession()
        try recorder.sample(stage: "before_independent_warmup", session: session, fixtures: fixtures)
        for _ in 0..<3 {
            for url in fixtures.images.prefix(4) { try await session.loadAndRelease(url) }
            session.cache.clear()
        }
        XCTAssertEqual(session.cache.statistics.retainedCost, 0)
        try recorder.sample(stage: "independent_warmup_cleared", session: session, fixtures: fixtures)
    }

    private func measureRound(
        _ round: Int, session: ThumbnailHostMemorySession,
        fixtures: ThumbnailHostMemoryFixtures, recorder: ThumbnailHostMemoryRecorder
    ) async throws {
        let before = session.cache.statistics
        for (index, url) in fixtures.images.enumerated() {
            try await session.loadAndRelease(url)
            if index.isMultiple(of: 8) {
                try recorder.sample(stage: "loading_\(index)", round: round, session: session, fixtures: fixtures)
            }
        }
        XCTAssertGreaterThan(session.cache.statistics.evictionCount, before.evictionCount)
        XCTAssertEqual(session.cache.statistics.loadCount - before.loadCount, fixtures.images.count)
        try recorder.sample(stage: "round_loaded", round: round, session: session, fixtures: fixtures)
        session.cache.clear()
        XCTAssertEqual(session.cache.statistics.retainedCost, 0)
        XCTAssertEqual(session.cache.statistics.entryCount, 0)
        XCTAssertEqual(session.cache.statistics.inFlightCount, 0)
        for _ in 0..<16 { await Task.yield() }
        // Allocators and ImageIO may keep resident pages. Observe them without a guessed RSS threshold.
        try recorder.sample(stage: "round_cleared", round: round, session: session, fixtures: fixtures)
    }
}
