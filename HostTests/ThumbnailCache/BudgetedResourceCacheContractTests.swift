import Foundation
import Testing
@testable import ThumbnailCacheCore

struct BudgetedResourceCacheContractTests {
    @Test func decodedCostBudgetEvictsLeastRecentlyUsedEntry() {
        let cache = makeThumbnailTestCache(costLimit: 10, countLimit: 10)
        let a = ThumbnailPayload("a", bytes: 4)
        let b = ThumbnailPayload("b", bytes: 4)
        let c = ThumbnailPayload("c", bytes: 4)
        #expect(cache.synchronousValue(for: "a", loader: { a }) == a)
        #expect(cache.synchronousValue(for: "b", loader: { b }) == b)
        #expect(cache.cachedValue(for: "a") == a) // a is now most recently used.
        #expect(cache.synchronousValue(for: "c", loader: { c }) == c)
        #expect(cache.cachedValue(for: "b") == nil)
        #expect(cache.cachedValue(for: "a") == a)
        #expect(cache.cachedValue(for: "c") == c)
        #expect(cache.statistics.entryCount == 2)
        #expect(cache.statistics.retainedCost == 8)
        #expect(cache.statistics.evictionCount == 1)
    }

    @Test func entryBudgetAppliesEvenWhenCostBudgetHasCapacity() {
        let cache = makeThumbnailTestCache(costLimit: 1_000, countLimit: 2)
        for name in ["a", "b", "c"] {
            _ = cache.synchronousValue(for: name) { ThumbnailPayload(name) }
        }
        #expect(cache.cachedValue(for: "a") == nil)
        #expect(cache.statistics.entryCount == 2)
        #expect(cache.statistics.retainedCost == 2)
    }

    @Test func oversizedAndZeroBudgetValuesAreReturnedWithoutRetention() {
        let oversized = makeThumbnailTestCache(costLimit: 3)
        let value = ThumbnailPayload("oversized", bytes: 4)
        #expect(oversized.synchronousValue(for: "large", loader: { value }) == value)
        #expect(oversized.cachedValue(for: "large") == nil)
        #expect(oversized.statistics.retainedCost == 0)
        for cache in [makeThumbnailTestCache(costLimit: 0), makeThumbnailTestCache(countLimit: 0)] {
            #expect(cache.synchronousValue(for: "zero", loader: { value }) == value)
            #expect(cache.statistics.entryCount == 0)
            #expect(cache.statistics.retainedCost == 0)
        }
    }

    @Test func warmHitNeverCallsReplacementLoader() async {
        let cache = makeThumbnailTestCache()
        let first = ThumbnailPayload("first")
        _ = cache.synchronousValue(for: "same") { first }
        let count = cache.statistics.loadCount
        let value = await cache.value(for: "same") {
            Issue.record("A warm hit invoked its loader")
            return ThumbnailPayload("unexpected")
        }
        #expect(value == first)
        #expect(cache.statistics.loadCount == count)
        #expect(cache.statistics.hitCount >= 1)
    }

    @Test func concurrentSameKeyRequestsShareOneLoaderAndOneEntry() async {
        let cache = makeThumbnailTestCache()
        let gate = ThumbnailLoaderGate()
        let one = Task { await cache.value(for: "same") { try await gate.load() } }
        await gate.waitForStarts()
        let two = Task { await cache.value(for: "same") { try await gate.load() } }
        await waitForThumbnailState("second waiter coalesced") { cache.statistics.coalescedCount == 1 }
        #expect(await gate.starts == 1)
        #expect(cache.statistics.inFlightCount == 1)
        let expected = ThumbnailPayload("shared")
        await gate.complete(expected)
        #expect(await one.value == expected)
        #expect(await two.value == expected)
        #expect(cache.statistics.loadCount == 1)
        #expect(cache.statistics.entryCount == 1)
        #expect(cache.statistics.inFlightCount == 0)
    }

    @Test func distinctKeysCanLoadIndependentlyWithoutResultMixing() async {
        let cache = makeThumbnailTestCache()
        let first = ThumbnailLoaderGate(), second = ThumbnailLoaderGate()
        let one = Task { await cache.value(for: "one") { try await first.load() } }
        let two = Task { await cache.value(for: "two") { try await second.load() } }
        await first.waitForStarts()
        await second.waitForStarts()
        #expect(cache.statistics.inFlightCount == 2)
        let a = ThumbnailPayload("one"), b = ThumbnailPayload("two")
        await second.complete(b)
        #expect(await two.value == b)
        #expect(cache.cachedValue(for: "two") == b)
        #expect(cache.statistics.inFlightCount == 1)
        await first.complete(a)
        #expect(await one.value == a)
        #expect(cache.cachedValue(for: "one") == a)
        #expect(cache.statistics.loadCount == 2)
    }

    @Test func cancellingOneWaiterPreservesSharedWorkerAndOtherWaiter() async {
        let cache = makeThumbnailTestCache()
        let gate = ThumbnailLoaderGate()
        let one = Task { await cache.value(for: "same") { try await gate.load() } }
        await gate.waitForStarts()
        let two = Task { await cache.value(for: "same") { try await gate.load() } }
        await waitForThumbnailState("two waiters share worker") { cache.statistics.coalescedCount == 1 }
        one.cancel()
        #expect(await one.value == nil)
        #expect(cache.statistics.inFlightCount == 1)
        let expected = ThumbnailPayload("surviving waiter")
        await gate.complete(expected)
        #expect(await two.value == expected)
        #expect(await gate.cancelledCompletions == 0)
        #expect(cache.cachedValue(for: "same") == expected)
    }

    @Test func cancellingEveryWaiterCancelsWorkerAndCannotRemoveReplacementFlight() async {
        let cache = makeThumbnailTestCache()
        let old = ThumbnailLoaderGate(), replacement = ThumbnailLoaderGate()
        let one = Task { await cache.value(for: "same") { try await old.load() } }
        await old.waitForStarts()
        let two = Task { await cache.value(for: "same") { try await old.load() } }
        await waitForThumbnailState("two old waiters") { cache.statistics.coalescedCount == 1 }
        one.cancel()
        two.cancel()
        #expect(await one.value == nil)
        #expect(await two.value == nil)
        await waitForThumbnailState("last cancellation removes flight") { cache.statistics.inFlightCount == 0 }
        let next = Task { await cache.value(for: "same") { try await replacement.load() } }
        await replacement.waitForStarts()
        await old.complete(ThumbnailPayload("stale"))
        await waitForThumbnailState("old cancelled worker finished") { cache.statistics.completedLoadCount == 1 }
        #expect(cache.statistics.inFlightCount == 1)
        #expect(cache.cachedValue(for: "same") == nil)
        #expect(await old.cancelledCompletions == 1)
        let current = ThumbnailPayload("current")
        await replacement.complete(current)
        #expect(await next.value == current)
        #expect(cache.cachedValue(for: "same") == current)
    }

    @Test func invalidateRejectsOldCompletionAndKeepsReplacementFlight() async {
        await assertOldCompletionCannotPolluteReplacement(clearAll: false)
    }

    @Test func clearRejectsOldCompletionAndKeepsReplacementFlight() async {
        await assertOldCompletionCannotPolluteReplacement(clearAll: true)
    }

    @Test func nilResultReleasesFlightAndAllowsRetry() async {
        let cache = makeThumbnailTestCache()
        #expect(await cache.value(for: "retry", loader: { nil }) == nil)
        #expect(cache.statistics.inFlightCount == 0)
        #expect(cache.statistics.entryCount == 0)
        let expected = ThumbnailPayload("retry succeeds")
        #expect(await cache.value(for: "retry", loader: { expected }) == expected)
        #expect(cache.statistics.loadCount == 2)
    }

    @Test func throwingLoaderReleasesFlightAndAllowsRetry() async {
        let cache = makeThumbnailTestCache()
        let gate = ThumbnailLoaderGate()
        let first = Task { await cache.value(for: "retry") { try await gate.load() } }
        await gate.waitForStarts()
        let second = Task { await cache.value(for: "retry") { try await gate.load() } }
        await waitForThumbnailState("throwing load has two waiters") { cache.statistics.coalescedCount == 1 }
        await gate.fail()
        #expect(await first.value == nil)
        #expect(await second.value == nil)
        #expect(cache.statistics.inFlightCount == 0)
        let expected = ThumbnailPayload("after error")
        #expect(await cache.value(for: "retry", loader: { expected }) == expected)
        #expect(cache.statistics.loadCount == 2)
    }

    @Test func synchronousInvalidationDuringLoaderPreventsOldRefill() {
        let cache = makeThumbnailTestCache()
        let old = ThumbnailPayload("old"), current = ThumbnailPayload("new")
        _ = cache.synchronousValue(for: "same") {
            cache.invalidate { $0 == "same" }
            _ = cache.synchronousValue(for: "same") { current }
            return old
        }
        #expect(cache.cachedValue(for: "same") == current)
        #expect(cache.statistics.entryCount == 1)
    }

    @Test func synchronousClearDuringLoaderPreventsOldRefill() {
        let cache = makeThumbnailTestCache()
        let old = ThumbnailPayload("old")
        _ = cache.synchronousValue(for: "same") {
            cache.clear()
            return old
        }
        #expect(cache.cachedValue(for: "same") == nil)
        #expect(cache.statistics.retainedCost == 0)
    }

    private func assertOldCompletionCannotPolluteReplacement(clearAll: Bool) async {
        let cache = makeThumbnailTestCache()
        let untouched = ThumbnailPayload("untouched")
        _ = cache.synchronousValue(for: "other") { untouched }
        let old = ThumbnailLoaderGate(), replacement = ThumbnailLoaderGate()
        let oldTask = Task { await cache.value(for: "same") { try await old.load() } }
        await old.waitForStarts()
        if clearAll { cache.clear() } else { cache.invalidate { $0 == "same" } }
        let next = Task { await cache.value(for: "same") { try await replacement.load() } }
        await replacement.waitForStarts()
        await old.complete(ThumbnailPayload("stale"))
        _ = await oldTask.value
        await waitForThumbnailState("old invalidated worker finished") { cache.statistics.completedLoadCount == 1 }
        #expect(cache.cachedValue(for: "same") == nil)
        #expect(cache.statistics.inFlightCount == 1)
        #expect(cache.cachedValue(for: "other") == (clearAll ? nil : untouched))
        let current = ThumbnailPayload("replacement")
        await replacement.complete(current)
        #expect(await next.value == current)
        #expect(cache.cachedValue(for: "same") == current)
        #expect(cache.statistics.inFlightCount == 0)
    }
}
