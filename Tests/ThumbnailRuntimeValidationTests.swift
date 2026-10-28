import Foundation
import Testing
import UIKit
@testable import sitekeeper

@Suite(
    .serialized,
    .enabled(
        if: ProcessInfo.processInfo.environment["UITEST_VALIDATION_ISOLATED"] == "1"
            && Bundle.main.bundleIdentifier?.contains(".validation.followup.") == true,
        "Requires explicit opt-in and an independently prepared validation app"
    )
)
@MainActor
struct ThumbnailRuntimeValidationTests {
    @Test func photoStorageReplacementDeletionAndRestoreInvalidatePixels() async throws {
        let files = try RuntimeThumbnailFiles()
        let name = "runtime-photo-\(UUID().uuidString).jpg"
        let original = PhotoStorage.fileURL(for: name)
        files.own(original)
        files.own(PhotoStorage.thumbnailStorageURL(for: name))
        defer { files.cleanup() }
        let red = try RuntimeThumbnailFiles.jpeg(color: .red)
        let blue = try RuntimeThumbnailFiles.jpeg(color: .blue)
        _ = try PhotoStorage.saveOrThrow(original: red, fileName: name)
        try RuntimeThumbnailFiles.expectRed(await PhotoCache.shared.thumbnailAsync(for: name))
        _ = try PhotoStorage.saveOrThrow(original: blue, fileName: name)
        #expect(PhotoCache.shared.cachedThumbnail(for: name) == nil)
        try RuntimeThumbnailFiles.expectBlue(await PhotoStorage.thumbnailAsync(for: name))
        try FileQuarantineStore.withRootURLForTesting(files.root.appendingPathComponent("quarantine")) {
            try PhotoStorage.deleteOrThrow(fileName: name)
        }
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(PhotoCache.shared.cachedThumbnail(for: name) == nil)
        try PhotoStorage.restoreOrThrow([PhotoBackupFile(fileName: name, data: blue)])
        try RuntimeThumbnailFiles.expectBlue(await PhotoStorage.thumbnailAsync(for: name))
        try PhotoStorage.restoreOrThrow([PhotoBackupFile(fileName: name, data: red)])
        #expect(PhotoCache.shared.cachedThumbnail(for: name) == nil)
        try RuntimeThumbnailFiles.expectRed(await PhotoStorage.thumbnailAsync(for: name))
    }

    @Test func attachmentStorageReplacementDeletionAndRestoreInvalidatePixels() async throws {
        let files = try RuntimeThumbnailFiles()
        let name = "runtime-attachment-\(UUID().uuidString).jpg"
        let url = QuickNoteAttachmentStorage.fileURL(for: name)
        let key = ThumbnailCacheKey(resourceURL: url, maxPixelSize: 128)
        files.own(url)
        defer { files.cleanup() }
        let red = try RuntimeThumbnailFiles.jpeg(color: .red)
        let blue = try RuntimeThumbnailFiles.jpeg(color: .blue)
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(red, fileName: name)
        try RuntimeThumbnailFiles.expectRed(await QuickNoteAttachmentStorage.thumbnailAsync(for: name, maxPixelSize: 128))
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(blue, fileName: name)
        #expect(StorageThumbnailCache.cachedImage(for: key) == nil)
        try RuntimeThumbnailFiles.expectBlue(await QuickNoteAttachmentStorage.thumbnailAsync(for: name, maxPixelSize: 128))
        try FileQuarantineStore.withRootURLForTesting(files.root.appendingPathComponent("quarantine")) {
            try QuickNoteAttachmentStorage.deleteOrThrow(fileName: name)
        }
        #expect(StorageThumbnailCache.cachedImage(for: key) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        try QuickNoteAttachmentStorage.restoreOrThrow([QuickNoteAttachmentBackupFile(fileName: name, data: blue)])
        try RuntimeThumbnailFiles.expectBlue(await QuickNoteAttachmentStorage.thumbnailAsync(for: name, maxPixelSize: 128))
        try QuickNoteAttachmentStorage.restoreOrThrow([QuickNoteAttachmentBackupFile(fileName: name, data: red)])
        #expect(StorageThumbnailCache.cachedImage(for: key) == nil)
        try RuntimeThumbnailFiles.expectRed(await QuickNoteAttachmentStorage.thumbnailAsync(for: name, maxPixelSize: 128))
    }

    @Test func cancelledSubscriberDoesNotCancelAnotherActualImageReader() async throws {
        let files = try RuntimeThumbnailFiles()
        defer { files.cleanup() }
        let url = try files.write(RuntimeThumbnailFiles.jpeg(color: .blue), name: "blue.jpg")
        let pixels = try #require(ThumbnailImageDecoder.decode(at: url, maxPixelSize: 128))
        let key = ThumbnailCacheKey(resourceURL: url, maxPixelSize: 128)
        let gate = RuntimeThumbnailGate()
        let before = StorageThumbnailCache.statistics.coalescedCount
        let first = Task { await StorageThumbnailCache.image(for: key) { await gate.load() } }
        await gate.waitForStart()
        let second = Task { await StorageThumbnailCache.image(for: key) { await gate.load() } }
        await waitForRuntimeThumbnailState("shared UIKit reader") {
            StorageThumbnailCache.statistics.coalescedCount > before
        }
        first.cancel()
        #expect(await first.value == nil)
        await gate.complete(pixels)
        try RuntimeThumbnailFiles.expectBlue(await second.value)
        try RuntimeThumbnailFiles.expectBlue(StorageThumbnailCache.cachedImage(for: key))
    }

    @Test func invalidatedOldImageCannotPolluteReplacementImageFlight() async throws {
        let files = try RuntimeThumbnailFiles()
        defer { files.cleanup() }
        let redURL = try files.write(RuntimeThumbnailFiles.jpeg(color: .red), name: "red.jpg")
        let blueURL = try files.write(RuntimeThumbnailFiles.jpeg(color: .blue), name: "blue.jpg")
        let red = try #require(ThumbnailImageDecoder.decode(at: redURL, maxPixelSize: 128))
        let blue = try #require(ThumbnailImageDecoder.decode(at: blueURL, maxPixelSize: 128))
        let key = ThumbnailCacheKey(resourceURL: redURL, maxPixelSize: 128)
        let old = RuntimeThumbnailGate(), replacement = RuntimeThumbnailGate()
        let completed = StorageThumbnailCache.statistics.completedLoadCount
        let first = Task { await StorageThumbnailCache.image(for: key) { await old.load() } }
        await old.waitForStart()
        StorageThumbnailCache.invalidate(resourceURL: redURL)
        let second = Task { await StorageThumbnailCache.image(for: key) { await replacement.load() } }
        await replacement.waitForStart()
        await old.complete(red)
        #expect(await first.value == nil)
        await waitForRuntimeThumbnailState("old UIKit flight completion") {
            StorageThumbnailCache.statistics.completedLoadCount > completed
        }
        #expect(StorageThumbnailCache.cachedImage(for: key) == nil)
        await replacement.complete(blue)
        try RuntimeThumbnailFiles.expectBlue(await second.value)
        try RuntimeThumbnailFiles.expectBlue(StorageThumbnailCache.cachedImage(for: key))
    }

    @Test func memoryWarningPurgesRetainedPixelsAndPreservesActiveUIKitReader() async throws {
        let files = try RuntimeThumbnailFiles()
        defer { files.cleanup() }
        StorageThumbnailCache.clear()
        let url = try files.write(RuntimeThumbnailFiles.jpeg(color: .blue), name: "blue.jpg")
        let key = ThumbnailCacheKey(resourceURL: url, maxPixelSize: 128)
        _ = await StorageThumbnailCache.image(for: key, sourceURL: url)
        #expect(StorageThumbnailCache.statistics.retainedCost > 0)
        let gate = RuntimeThumbnailGate()
        let loadingKey = ThumbnailCacheKey(resourceURL: url, maxPixelSize: 192)
        let pixels = try #require(ThumbnailImageDecoder.decode(at: url, maxPixelSize: 192))
        let pending = Task { await StorageThumbnailCache.image(for: loadingKey) { await gate.load() } }
        await gate.waitForStart()
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        #expect(StorageThumbnailCache.statistics.retainedCost == 0)
        await gate.complete(pixels)
        try RuntimeThumbnailFiles.expectBlue(await pending.value)
        #expect(StorageThumbnailCache.statistics.entryCount == 0)
        #expect(StorageThumbnailCache.cachedImage(for: loadingKey) == nil)
        let recorder = RuntimeThumbnailMemoryRecorder()
        try recorder.sample("memory_warning_after_active_reader")
    }

    @Test func realImageCacheBudgetAndRepeatedWorkingSetMemoryTrend() async throws {
        let files = try RuntimeThumbnailFiles()
        defer { files.cleanup() }
        #expect(StorageThumbnailCache.costLimit == 64 * 1_024 * 1_024)
        #expect(StorageThumbnailCache.countLimit == 256)
        let data = try RuntimeThumbnailFiles.jpeg(color: .blue, side: 2_048)
        let urls = try (0..<40).map { try files.write(data, name: "large-\($0).jpg") }
        let workingSet = try #require(ThumbnailImageDecoder.decode(at: urls[0], maxPixelSize: 1_024)).decodedByteCost * urls.count
        #expect(workingSet > StorageThumbnailCache.costLimit)
        let recorder = RuntimeThumbnailMemoryRecorder()
        try recorder.sample("before_warmup", requestedWorkingSetBytes: workingSet)
        for _ in 0..<3 {
            for url in urls.prefix(4) { _ = try await loadAndRelease(url, pixels: 1_024) }
            StorageThumbnailCache.invalidate(directoryURL: files.root)
        }
        try recorder.sample("warmed_and_cleared", requestedWorkingSetBytes: workingSet)
        try await exerciseLargeWorkingSet(urls, workingSet: workingSet, recorder: recorder)
        try await exerciseCountBudget(files, recorder: recorder)
    }
}

private extension ThumbnailRuntimeValidationTests {
    func loadAndRelease(_ url: URL, pixels: Int) async throws -> Int {
        let key = ThumbnailCacheKey(resourceURL: url, maxPixelSize: Double(pixels))
        let image = try #require(await StorageThumbnailCache.image(for: key, sourceURL: url))
        let cgImage = try #require(image.cgImage)
        #expect(max(cgImage.width, cgImage.height) <= pixels)
        return cgImage.bytesPerRow * cgImage.height
    }

    func exerciseLargeWorkingSet(
        _ urls: [URL], workingSet: Int, recorder: RuntimeThumbnailMemoryRecorder
    ) async throws {
        for round in 1...3 {
            let before = StorageThumbnailCache.statistics.evictionCount
            for (index, url) in urls.enumerated() {
                _ = try await loadAndRelease(url, pixels: 1_024)
                if index.isMultiple(of: 8) {
                    try recorder.sample("loading_\(index)", round: round, requestedWorkingSetBytes: workingSet)
                }
            }
            #expect(StorageThumbnailCache.statistics.evictionCount > before)
            try recorder.sample("round_loaded", round: round, requestedWorkingSetBytes: workingSet)
            StorageThumbnailCache.invalidate(directoryURL: urls[0].deletingLastPathComponent())
            #expect(StorageThumbnailCache.statistics.retainedCost == 0)
            for _ in 0..<16 { await Task.yield() }
            try recorder.sample("round_cleared", round: round, requestedWorkingSetBytes: workingSet)
        }
    }

    func exerciseCountBudget(_ files: RuntimeThumbnailFiles, recorder: RuntimeThumbnailMemoryRecorder) async throws {
        let data = try RuntimeThumbnailFiles.jpeg(color: .red, side: 32)
        for index in 0..<300 {
            let url = try files.write(data, name: "tiny-\(index).jpg")
            _ = try await loadAndRelease(url, pixels: 32)
        }
        #expect(StorageThumbnailCache.statistics.entryCount == StorageThumbnailCache.countLimit)
        try recorder.sample("count_budget_300_requests")
        StorageThumbnailCache.invalidate(directoryURL: files.root)
        #expect(StorageThumbnailCache.statistics.retainedCost == 0)
        try recorder.sample("all_owned_images_cleared")
    }
}
