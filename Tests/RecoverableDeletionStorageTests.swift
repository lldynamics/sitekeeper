import Foundation
import Dispatch
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

    @Test func concurrentQuarantinePreservesAndRestoresEveryFile() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConcurrentQuarantineTests-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fileCount = 80
        let sources = (0..<fileCount).map { sourceRoot.appendingPathComponent("file-\($0).bin") }
        for (index, source) in sources.enumerated() {
            try Data("file-\(index)".utf8).write(to: source)
        }
        let categories: [FileQuarantineCategory] = [.photoOriginal, .drawing, .projectDocument, .quickNoteAttachment]

        try FileQuarantineStore.withRootURLForTesting(root.appendingPathComponent("quarantine")) {
            DispatchQueue.concurrentPerform(iterations: categories.count) { worker in
                for index in stride(from: worker, to: fileCount, by: categories.count) {
                    do {
                        #expect(try FileQuarantineStore.quarantine(fileAt: sources[index], category: categories[worker]))
                    } catch {
                        Issue.record(error)
                    }
                }
            }

            let entries = FileQuarantineStore.loadEntries()
            #expect(entries.count == fileCount)
            #expect(Set(entries.map(\.originalPath)) == Set(sources.map(\.path)))
            #expect(sources.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })

            DispatchQueue.concurrentPerform(iterations: categories.count) { worker in
                for index in stride(from: worker, to: entries.count, by: categories.count) {
                    do {
                        try FileQuarantineStore.restore(entries[index])
                    } catch {
                        Issue.record(error)
                    }
                }
            }

            #expect(FileQuarantineStore.loadEntries().isEmpty)
            for (index, source) in sources.enumerated() {
                let restoredData = try Data(contentsOf: source)
                #expect(restoredData == Data("file-\(index)".utf8))
            }
        }
    }

    @Test func concurrentQuarantineTestRootsRemainIsolated() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConcurrentQuarantineRootsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sources = (0..<8).map { root.appendingPathComponent("scope-\($0).bin") }
        for source in sources { try Data([0x41]).write(to: source) }

        DispatchQueue.concurrentPerform(iterations: sources.count) { index in
            do {
                try FileQuarantineStore.withRootURLForTesting(root.appendingPathComponent("quarantine-\(index)")) {
                    #expect(FileQuarantineStore.loadEntries().isEmpty)
                    #expect(try FileQuarantineStore.quarantine(fileAt: sources[index], category: .projectDocument))
                    let entries = FileQuarantineStore.loadEntries()
                    #expect(entries.map(\.originalPath) == [sources[index].path])
                    for entry in entries { try FileQuarantineStore.restore(entry) }
                    #expect(FileQuarantineStore.loadEntries().isEmpty)
                }
            } catch {
                Issue.record(error)
            }
        }

        for source in sources { #expect(try Data(contentsOf: source) == Data([0x41])) }
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

@MainActor
extension RecoverableDeletionStorageTests {
    @Test func deferredQuarantineRetainsReplacementAndWaitsForAllReaders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("deferred-replace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("attachment.bin")
        try Data([1]).write(to: file)
        try FileQuarantineStore.withRootURLForTesting(root.appendingPathComponent("quarantine")) {
            let first = FileQuarantineStore.beginBackupExport(protecting: [file])
            let second = FileQuarantineStore.beginBackupExport(protecting: [file])
            try FileQuarantineStore.quarantine(fileAt: file, category: .quickNoteAttachment)
            FileQuarantineStore.endBackupExport(first, retaining: [])
            #expect(FileManager.default.fileExists(atPath: file.path))
            // Atomic replacement represents a new owner reusing the same pathname.
            try Data([2, 3]).write(to: file, options: .atomic)
            FileQuarantineStore.endBackupExport(second, retaining: [])
            #expect(try Data(contentsOf: file) == Data([2, 3]))
            #expect(!FileQuarantineStore.isQuarantineDeferred(for: file))
            #expect(FileQuarantineStore.loadEntries().isEmpty)
        }
    }

    @Test func deferredQuarantineFailureKeepsRequestAndRetriesAfterRepair() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("deferred-retry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("attachment.bin")
        let quarantine = root.appendingPathComponent("quarantine")
        try Data([4]).write(to: file)
        try FileQuarantineStore.withRootURLForTesting(quarantine) {
            let lease = FileQuarantineStore.beginBackupExport(protecting: [file])
            try FileQuarantineStore.quarantine(fileAt: file, category: .quickNoteAttachment)
            try FileManager.default.createDirectory(at: quarantine.appendingPathComponent("manifest.json"), withIntermediateDirectories: true)
            FileQuarantineStore.endBackupExport(lease, retaining: [])
            #expect(try Data(contentsOf: file) == Data([4]))
            #expect(FileQuarantineStore.isQuarantineDeferred(for: file))
            try FileManager.default.removeItem(at: quarantine.appendingPathComponent("manifest.json"))
            let retry = FileQuarantineStore.beginBackupExport(protecting: [file])
            FileQuarantineStore.endBackupExport(retry, retaining: [])
            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(!FileQuarantineStore.isQuarantineDeferred(for: file))
            #expect(FileQuarantineStore.loadEntries().count == 1)
        }
    }
}
