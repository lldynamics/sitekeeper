import Foundation
import Testing
@testable import ThumbnailCacheCore

struct ThumbnailPayload: Equatable, Sendable {
    let name: String
    let bytes: Int

    init(_ name: String, bytes: Int = 1) {
        self.name = name
        self.bytes = bytes
    }
}

typealias ThumbnailTestCache = BudgetedResourceCache<String, ThumbnailPayload>

func makeThumbnailTestCache(costLimit: Int = 10, countLimit: Int = 2) -> ThumbnailTestCache {
    ThumbnailTestCache(costLimit: costLimit, countLimit: countLimit, cost: { $0.bytes })
}

/// A continuation gate deliberately ignores cancellation until explicitly released.
/// This models non-cooperative disk/decode work and exposes stale completion races.
actor ThumbnailLoaderGate {
    private(set) var starts = 0
    private(set) var cancelledCompletions = 0
    private var pending: [CheckedContinuation<ThumbnailPayload?, Error>] = []
    private var startWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func load() async throws -> ThumbnailPayload? {
        starts += 1
        let value = try await withCheckedThrowingContinuation { continuation in
            pending.append(continuation)
            let ready = startWaiters.filter { $0.0 <= starts }
            startWaiters.removeAll { $0.0 <= starts }
            ready.forEach { $0.1.resume() }
        }
        if Task.isCancelled { cancelledCompletions += 1 }
        return value
    }

    func waitForStarts(_ count: Int = 1) async {
        guard starts < count else { return }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func complete(_ value: ThumbnailPayload?) {
        let continuations = pending
        pending.removeAll()
        continuations.forEach { $0.resume(returning: value) }
    }

    func fail() {
        let continuations = pending
        pending.removeAll()
        continuations.forEach { $0.resume(throwing: ThumbnailLoaderFailure.expected) }
    }
}

enum ThumbnailLoaderFailure: Error {
    case expected
}

/// Wait for an explicit cache state, never for an assumed scheduling duration.
/// The bounded yield loop also turns a broken state transition into a test failure.
@discardableResult
func waitForThumbnailState(
    _ description: String,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async -> Bool {
    for _ in 0..<100_000 {
        if condition() { return true }
        await Task.yield()
    }
    Issue.record("Cache state was not reached: \(description)", sourceLocation: sourceLocation)
    return false
}
