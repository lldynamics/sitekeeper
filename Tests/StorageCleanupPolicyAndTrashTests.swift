import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct StorageCleanupPolicyAndTrashTests {
    @Test func legacyTrimmedQuarantineNameRestoresTheOriginalLeaf() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("quarantine-legacy-name-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent(" 旧附件.pdf ")
        let bytes = Data("legacy original".utf8)
        try bytes.write(to: source)
        let quarantine = root.appendingPathComponent("quarantine")
        try FileQuarantineStore.withRootURLForTesting(quarantine) {
            #expect(try FileQuarantineStore.quarantine(fileAt: source, category: .quickNoteAttachment))
            let entry = try #require(FileQuarantineStore.loadEntries().first)
            let oldPath = quarantine.appendingPathComponent(entry.quarantinedRelativePath)
            let legacyRelativePath = "quick-note-attachment/\(UUID().uuidString)-旧附件.pdf"
            try FileManager.default.moveItem(at: oldPath, to: quarantine.appendingPathComponent(legacyRelativePath))
            let legacy = FileQuarantineEntry(id: entry.id, category: entry.category, originalPath: source.path,
                originalFileName: "旧附件.pdf", quarantinedRelativePath: legacyRelativePath,
                createdAt: entry.createdAt, expiresAt: entry.expiresAt)
            let manifest: [String: Any] = ["schemaVersion": 1,
                "entries": [try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy))]]
            try JSONSerialization.data(withJSONObject: manifest).write(to: quarantine.appendingPathComponent("manifest.json"))
            try FileQuarantineStore.restore(legacy)
            #expect(try Data(contentsOf: source) == bytes)
            #expect(FileQuarantineStore.loadEntries().isEmpty)
        }
    }

    @Test func legacyQuarantineOutsideFamilyCannotRestoreDeleteOrExpireAndRemainsRecoverable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("quarantine-legacy-\(UUID().uuidString)")
        let external = FileManager.default.temporaryDirectory.appendingPathComponent("quarantine-external-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: external) }
        let name = "attachment.bin"
        let source = root.appendingPathComponent(name)
        let outside = external.appendingPathComponent(name)
        let bytes = Data("recovery bytes".utf8)
        let outsideBytes = Data("outside bytes".utf8)
        try bytes.write(to: source)
        try outsideBytes.write(to: outside)
        let quarantine = root.appendingPathComponent("quarantine")
        try FileQuarantineStore.withRootURLForTesting(quarantine) {
            #expect(try FileQuarantineStore.quarantine(fileAt: source, category: .quickNoteAttachment))
            let entry = try #require(FileQuarantineStore.loadEntries().first)
            let malformed = FileQuarantineEntry(id: entry.id, category: entry.category,
                originalPath: outside.path, originalFileName: name, quarantinedRelativePath: entry.quarantinedRelativePath,
                createdAt: entry.createdAt, expiresAt: Date(timeIntervalSince1970: 0))
            let manifest: [String: Any] = ["schemaVersion": 1,
                "entries": [try JSONSerialization.jsonObject(with: JSONEncoder().encode(malformed))]]
            try JSONSerialization.data(withJSONObject: manifest).write(to: quarantine.appendingPathComponent("manifest.json"))
            #expect(throws: FileStorageError.self) { try FileQuarantineStore.restore(malformed) }
            #expect(throws: FileStorageError.self) { try FileQuarantineStore.permanentlyDelete(malformed) }
            #expect(FileQuarantineStore.purgeExpiredEntries() == 0)
            #expect(FileQuarantineStore.loadEntries().map(\.id) == [entry.id])
            #expect(try Data(contentsOf: outside) == outsideBytes)
            #expect(try Data(contentsOf: quarantine.appendingPathComponent(entry.quarantinedRelativePath)) == bytes)
            // A known, valid original path still allows recovery after correcting the manifest.
            try FileQuarantineStore.restore(entry)
            #expect(try Data(contentsOf: source) == bytes)
        }
    }

    @Test func legacyUnsafeCleanupPlanFailsBeforeMovingAnyFile() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-path-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "a-safe-cleanup-\(UUID().uuidString).bin"
        let bytes = Data("preserve local original".utf8)
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(bytes, fileName: name)
        let original = QuickNoteAttachmentStorage.fileURL(for: name)
        defer { try? FileManager.default.removeItem(at: original) }
        StorageCleanupTrashStore.withRootURLForTesting(root) {
            #expect(throws: FileStorageError.self) {
                try StorageCleanupTrashStore.quarantine(
                    plan: .init(quickNoteAttachmentFileNames: [name, "z/../../outside.bin"]),
                    snapshot: StorageCleanupTrashTestSupport.emptyUndoSnapshot(), summary: "unsafe legacy", retentionDays: 7
                )
            }
            #expect(QuickNoteAttachmentStorage.data(for: name) == bytes)
            #expect(!FileManager.default.fileExists(atPath: root.path))
        }
    }

    @Test func malformedRecoveryNamesPreserveAllTrashedBytesAndAllowValidRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-recovery-path-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let names = ["a-recover-\(UUID().uuidString).bin", "b-recover-\(UUID().uuidString).bin"]
        for name in names { _ = try QuickNoteAttachmentStorage.saveDataOrThrow(Data(name.utf8), fileName: name) }
        let originals = names.map { QuickNoteAttachmentStorage.fileURL(for: $0) }
        defer { for url in originals { try? FileManager.default.removeItem(at: url) } }
        try StorageCleanupTrashStore.withRootURLForTesting(root) {
            let batch = try StorageCleanupTrashStore.quarantine(
                plan: .init(quickNoteAttachmentFileNames: Set(names)),
                snapshot: StorageCleanupTrashTestSupport.emptyUndoSnapshot(), summary: "recover", retentionDays: 7
            )
            for corruptOriginal in [true, false] {
                var files = batch.files
                let last = try #require(files.last)
                files[files.count - 1] = StorageCleanupTrashFile(
                    id: last.id, kind: last.kind,
                    originalFileName: corruptOriginal ? "../outside.bin" : last.originalFileName,
                    trashedFileName: corruptOriginal ? last.trashedFileName : "../../outside.bin"
                )
                let malformed = StorageCleanupTrashBatch(id: batch.id, summary: batch.summary, createdAt: batch.createdAt,
                    expiresAt: batch.expiresAt, snapshot: batch.snapshot, files: files)
                #expect(throws: (any Error).self) { try StorageCleanupTrashStore.restore(malformed) }
                #expect(originals.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
                #expect(StorageCleanupTrashStore.loadBatches().map(\.id) == [batch.id])
                for file in batch.files {
                    let trashed = try #require(StorageCleanupTrashStore.trashURL(batchID: batch.id, kind: file.kind, trashedFileName: file.trashedFileName))
                    #expect(try Data(contentsOf: trashed) == Data(file.originalFileName.utf8))
                }
            }
            try StorageCleanupTrashStore.restore(batch)
            for name in names { #expect(QuickNoteAttachmentStorage.data(for: name) == Data(name.utf8)) }
            #expect(StorageCleanupTrashStore.loadBatches().isEmpty)
        }
    }

    @Test func cleanupRecoveryRefusesExistingSymlinkOrDirectoryAndRetainsRecovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cleanup-recovery-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "recover-link-\(UUID().uuidString).bin"
        let bytes = Data("trash copy".utf8)
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(bytes, fileName: name)
        let original = QuickNoteAttachmentStorage.fileURL(for: name)
        defer { try? FileManager.default.removeItem(at: original) }
        let outside = root.appendingPathComponent("outside.bin")
        let outsideBytes = Data("outside protected".utf8)
        try outsideBytes.write(to: outside)
        try StorageCleanupTrashStore.withRootURLForTesting(root.appendingPathComponent("trash")) {
            let batch = try StorageCleanupTrashStore.quarantine(plan: .init(quickNoteAttachmentFileNames: [name]),
                snapshot: StorageCleanupTrashTestSupport.emptyUndoSnapshot(), summary: "link", retentionDays: 7)
            try FileManager.default.createSymbolicLink(at: original, withDestinationURL: outside)
            #expect(throws: FileStorageError.self) { try StorageCleanupTrashStore.restore(batch) }
            #expect(try Data(contentsOf: outside) == outsideBytes)
            try FileManager.default.removeItem(at: original)
            try FileManager.default.createDirectory(at: original, withIntermediateDirectories: false)
            #expect(throws: FileStorageError.self) { try StorageCleanupTrashStore.restore(batch) }
            #expect(StorageCleanupTrashStore.loadBatches().map(\.id) == [batch.id])
            try FileManager.default.removeItem(at: original)
            try StorageCleanupTrashStore.restore(batch)
            #expect(QuickNoteAttachmentStorage.data(for: name) == bytes)
        }
    }

    @Test func quarantineEntryFromRotatedAppContainerUUIDRestoresAndRejectsWrongFamily() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("quarantine-rotated-uuid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "rotated-\(UUID().uuidString).bin"
        let bytes = Data("survives app update".utf8)
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(bytes, fileName: name)
        let currentURL = try QuickNoteAttachmentStorage.validatedFileURL(for: name)
        defer { try? FileManager.default.removeItem(at: currentURL) }
        let familyFolder = currentURL.deletingLastPathComponent().lastPathComponent
        let quarantine = root.appendingPathComponent("quarantine")
        try FileQuarantineStore.withRootURLForTesting(quarantine) {
            #expect(try FileQuarantineStore.quarantine(fileAt: currentURL, category: .quickNoteAttachment))
            let entry = try #require(FileQuarantineStore.loadEntries().first)
            let oldContainerUUID = UUID().uuidString
            let wrongFamily = FileQuarantineEntry(
                id: entry.id,
                category: .quickNoteAttachment,
                originalPath: "/private/var/mobile/Containers/Data/Application/\(oldContainerUUID)/Documents/BusinessDrafts/\(name)",
                originalFileName: name,
                quarantinedRelativePath: entry.quarantinedRelativePath,
                createdAt: entry.createdAt,
                expiresAt: entry.expiresAt
            )
            #expect(throws: FileStorageError.self) { try FileQuarantineStore.restore(wrongFamily) }
            #expect(throws: FileStorageError.self) { try FileQuarantineStore.permanentlyDelete(wrongFamily) }

            let rotatedValid = FileQuarantineEntry(
                id: entry.id,
                category: .quickNoteAttachment,
                originalPath: "/private/var/mobile/Containers/Data/Application/\(oldContainerUUID)/Documents/\(familyFolder)/\(name)",
                originalFileName: name,
                quarantinedRelativePath: entry.quarantinedRelativePath,
                createdAt: entry.createdAt,
                expiresAt: entry.expiresAt
            )
            try FileQuarantineStore.restore(rotatedValid)
            #expect(QuickNoteAttachmentStorage.data(for: name) == bytes)
        }
    }

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
