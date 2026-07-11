import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct RecoverableDeletionStorageTests {
    @Test func storageCleanupTrashRootInjectionKeepsManifestIsolated() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageCleanupTrashRootTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let batch = StorageCleanupTrashBatch(
            id: UUID(),
            summary: "isolated manifest",
            createdAt: Date(),
            expiresAt: Date(timeIntervalSinceNow: 60),
            snapshot: emptyUndoSnapshot(),
            files: []
        )

        try StorageCleanupTrashStore.withRootURLForTesting(root) {
            try writeStorageCleanupTrashManifest([batch])
            #expect(StorageCleanupTrashStore.loadBatches().map(\.id) == [batch.id])
        }

        #expect(!StorageCleanupTrashStore.loadBatches().contains { $0.id == batch.id })
    }

    @Test func fileQuarantineRestoresAndPermanentlyDeletesFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageCleanupQuarantineTests-\(UUID().uuidString)", isDirectory: true)
        let quarantineRoot = root.appendingPathComponent("FileQuarantine", isDirectory: true)
        let restoreFileName = "restore-\(UUID().uuidString).bin"
        let deleteFileName = "delete-\(UUID().uuidString).bin"
        let restoreURL = root.appendingPathComponent(restoreFileName)
        let deleteURL = root.appendingPathComponent(deleteFileName)
        let restoreData = Data([0x41, 0x42, 0x43])
        let deleteData = Data([0x51, 0x52, 0x53])

        defer { try? FileManager.default.removeItem(at: root) }

        try FileQuarantineStore.withRootURLForTesting(quarantineRoot) {
            try write(restoreData, to: restoreURL)
            #expect(
                try FileQuarantineStore.quarantine(
                    fileAt: restoreURL,
                    category: .projectDocument,
                    originalFileName: restoreFileName,
                    retentionDays: 14
                )
            )
            #expect(!FileManager.default.fileExists(atPath: restoreURL.path))

            let restoreEntry = try #require(
                FileQuarantineStore.loadEntries().first { $0.originalFileName == restoreFileName }
            )
            #expect(restoreEntry.category == .projectDocument)
            #expect(restoreEntry.expiresAt > restoreEntry.createdAt)

            try FileQuarantineStore.restore(restoreEntry)

            #expect(try Data(contentsOf: restoreURL) == restoreData)
            #expect(!FileQuarantineStore.loadEntries().contains { $0.id == restoreEntry.id })

            try write(deleteData, to: deleteURL)
            #expect(
                try FileQuarantineStore.quarantine(
                    fileAt: deleteURL,
                    category: .quickNoteAttachment,
                    originalFileName: deleteFileName,
                    retentionDays: 14
                )
            )

            let deleteEntry = try #require(
                FileQuarantineStore.loadEntries().first { $0.originalFileName == deleteFileName }
            )
            #expect(deleteEntry.category == .quickNoteAttachment)
            #expect(!FileManager.default.fileExists(atPath: deleteURL.path))

            try FileQuarantineStore.permanentlyDelete(deleteEntry)

            #expect(!FileManager.default.fileExists(atPath: deleteURL.path))
            #expect(!FileQuarantineStore.loadEntries().contains { $0.id == deleteEntry.id })
        }
    }

    private func emptyUndoSnapshot() -> StorageCleanupUndoSnapshot {
        StorageCleanupUndoSnapshot(
            dailyLogs: [],
            siteTodos: [],
            quickNotes: [],
            projectDrawings: [],
            projectDocuments: [],
            projectFinancialRecords: [],
            projectWarehouseMovements: []
        )
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try data.write(to: url, options: .atomic)
    }

    private func writeStorageCleanupTrashManifest(_ batches: [StorageCleanupTrashBatch]) throws {
        let data = try JSONEncoder().encode(batches.sorted { lhs, rhs in lhs.createdAt > rhs.createdAt })
        try data.write(to: try StorageCleanupTrashStore.manifestURLForTesting(), options: .atomic)
    }
}
