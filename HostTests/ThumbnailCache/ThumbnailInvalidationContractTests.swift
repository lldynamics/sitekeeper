import Foundation
import Testing
@testable import ThumbnailCacheCore

struct ThumbnailInvalidationContractTests {
    @Test func memoryPressurePreservesActiveReadersWithoutRefillingRetainedCache() async {
        let cache = makeThumbnailTestCache()
        _ = cache.synchronousValue(for: "retained") { ThumbnailPayload("retained") }
        let gate = ThumbnailLoaderGate()
        let first = Task { await cache.value(for: "loading") { try await gate.load() } }
        await gate.waitForStarts()
        let second = Task { await cache.value(for: "loading") { try await gate.load() } }
        await waitForThumbnailState("shared active load before memory pressure") { cache.statistics.coalescedCount == 1 }

        cache.purgeRetainedValues()
        #expect(cache.statistics.retainedCost == 0)
        #expect(cache.statistics.inFlightCount == 1)
        let expected = ThumbnailPayload("visible result")
        await gate.complete(expected)
        #expect(await first.value == expected)
        #expect(await second.value == expected)
        #expect(await gate.cancelledCompletions == 0)
        #expect(cache.statistics.entryCount == 0)
        #expect(cache.statistics.retainedCost == 0)

        // A later explicit request may cache again; there is no automatic reload loop.
        #expect(await cache.value(for: "later", loader: { expected }) == expected)
        #expect(cache.cachedValue(for: "later") == expected)
    }

    @Test func invalidationMatchesCanonicalResourcesAndDirectoryBoundaries() {
        let file = URL(fileURLWithPath: "/tmp/photos/image.jpg")
        let equivalent = URL(fileURLWithPath: "/tmp/photos/nested/../image.jpg")
        #expect(ThumbnailCacheInvalidation.resource(equivalent).affects(file))
        #expect(!ThumbnailCacheInvalidation.resource(file).affects(URL(fileURLWithPath: "/tmp/notes/image.jpg")))
        let directory = ThumbnailCacheInvalidation.directory(URL(fileURLWithPath: "/tmp/photos/"))
        #expect(directory.affects(file))
        #expect(directory.affects(URL(fileURLWithPath: "/tmp/photos/nested/image.jpg")))
        #expect(!directory.affects(URL(fileURLWithPath: "/tmp/photos-old/image.jpg")))
        #expect(ThumbnailCacheInvalidation.directory(URL(fileURLWithPath: "/")).affects(file))
        #expect(ThumbnailCacheInvalidation.all.affects(file))
    }
}
