import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct StorageCleanupPolicyAndTrashTests {
    @Test func trashRetentionNormalizesToNearestAllowedOption() {
        #expect(StorageCleanupTrashRetentionOption.normalizedDays(-2) == 3)
        #expect(StorageCleanupTrashRetentionOption.normalizedDays(4) == 3)
        #expect(StorageCleanupTrashRetentionOption.normalizedDays(6) == 7)
        #expect(StorageCleanupTrashRetentionOption.normalizedDays(13) == 14)
        #expect(StorageCleanupTrashRetentionOption.normalizedDays(29) == 30)
        #expect(StorageCleanupTrashRetentionOption.defaultDays == 7)
    }

    @Test func largeFileThresholdNormalizesAndFiltersLargeFileItems() {
        #expect(StorageCleanupLargeFileThresholdOption.normalizedMegabytes(1) == 5)
        #expect(StorageCleanupLargeFileThresholdOption.normalizedMegabytes(18) == 20)
        #expect(StorageCleanupLargeFileThresholdOption.normalizedMegabytes(47) == 50)
        #expect(StorageCleanupLargeFileThresholdOption.normalizedMegabytes(90) == 100)
        #expect(StorageCleanupLargeFileThresholdOption.bytes(for: 18) == 20 * 1024 * 1024)
        #expect(StorageCleanupLargeFileRuleSuggestion.photo.bytes == 5 * 1024 * 1024)
        #expect(StorageCleanupLargeFileRuleSuggestion.ticket.bytes == 20 * 1024 * 1024)
        #expect(StorageCleanupLargeFileRuleSuggestion.video.bytes == 50 * 1024 * 1024)

        let storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageCleanupPolicyTests-\(UUID().uuidString)", isDirectory: true)
        let store = DataStore(storageDirectory: storageDirectory)
        store.clearAllBusinessData(deleteStoredFiles: false)
        defer { try? FileManager.default.removeItem(at: storageDirectory) }

        let belowThreshold = StorageLargeFileItem(
            id: "below",
            category: .photo,
            title: "below.bin",
            detail: "fixture",
            bytes: 19 * 1024 * 1024
        )
        let atThreshold = StorageLargeFileItem(
            id: "at",
            category: .ticket,
            title: "at.bin",
            detail: "fixture",
            bytes: 20 * 1024 * 1024
        )
        let aboveThreshold = StorageLargeFileItem(
            id: "above",
            category: .video,
            title: "above.bin",
            detail: "fixture",
            bytes: 21 * 1024 * 1024
        )

        let items = StorageCleanupScanner.buildLargeFileItems(
            store: store,
            largeFileThresholdBytes: StorageCleanupLargeFileThresholdOption.bytes(for: 18),
            historyBytes: 0,
            photoEntries: [belowThreshold],
            videoEntries: [aboveThreshold],
            drawingEntries: [],
            ticketEntries: [atThreshold],
            backupEntries: []
        )

        #expect(items.map(\.id) == ["above", "at"])
    }
}
