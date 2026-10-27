import Foundation
import Testing
@testable import sitekeeper

struct BackupCapacityContractTests {
    @Test func backupBudgetAcceptsMultipleLegalAttachmentsPastOldTotalLimit() throws {
        let limits = BackupArchiveLimits.backup
        var total: UInt64 = 0
        let oldLimit = UInt64(TransferLimitPolicy.limits(for: .production).maxImportBytes)
        try limits.validate(path: "files/a.bin", size: oldLimit, entryCount: 1, total: &total)
        try limits.validate(path: "files/b.bin", size: oldLimit, entryCount: 2, total: &total)
        #expect(total > oldLimit)
        #expect(limits.maximumTotalBytes > limits.maximumEntryBytes)
    }

    @Test func budgetRejectsEntryCountTotalOverflowAndLargeMetadata() throws {
        let limits = BackupArchiveLimits.backup
        var total: UInt64 = 0
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) {
            try limits.validate(path: "files/a", size: limits.maximumEntryBytes + 1, entryCount: 1, total: &total)
        }
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) {
            try limits.validate(path: "files/a", size: 0, entryCount: limits.maximumEntryCount + 1, total: &total)
        }
        total = limits.maximumTotalBytes
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) {
            try limits.validate(path: "files/a", size: 1, entryCount: 1, total: &total)
        }
        total = UInt64.max
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) {
            try limits.validate(path: "files/a", size: 1, entryCount: 1, total: &total)
        }
        total = 0
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) {
            try limits.validate(path: BackupArchiveService.metadataPath, size: limits.maximumMetadataBytes + 1, entryCount: 1, total: &total)
        }
    }

    @Test func writerAndScannerShareExactByteAndCountBoundaries() throws {
        let url = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "capacity-contract")
        defer { try? FileManager.default.removeItem(at: url) }
        let limits = BackupArchiveLimits(maximumEntryBytes: 8, maximumTotalBytes: 12, maximumEntryCount: 2)
        var writer = try StreamingZipArchiveWriter(fileURL: url, limits: limits)
        try writer.addFile(path: "a", data: Data(repeating: 1, count: 8))
        try writer.addFile(path: "b", data: Data(repeating: 2, count: 4))
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) {
            try writer.addFile(path: "c", data: Data())
        }
        _ = try writer.finish()
        var paths: [String] = []
        try SimpleZipArchiveReader.scan(fileURL: url, limits: limits, verifyAllEntries: true) { entry, _, _ in
            paths.append(entry.path)
        }
        #expect(paths == ["a", "b"])
        let smaller = BackupArchiveLimits(maximumEntryBytes: 8, maximumTotalBytes: 11, maximumEntryCount: 2)
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) {
            try SimpleZipArchiveReader.scan(fileURL: url, limits: smaller) { _, _, _ in }
        }
    }

    @Test func backupWriterRejectsOversizedSparseSourceBeforeCopying() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("oversized-source-\(UUID().uuidString)")
        let url = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "capacity-oversized")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: url)
        }
        FileManager.default.createFile(atPath: source.path, contents: nil)
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: BackupArchiveLimits.backup.maximumEntryBytes + 1)
        try handle.close()
        var writer = try StreamingZipArchiveWriter(fileURL: url, limits: .backup)
        defer { try? writer.close() }
        let before = try Data(contentsOf: url)
        #expect(throws: SimpleZipArchiveReader.ZipReadError.self) {
            try writer.addFile(path: "files/large.bin", sourceFileURL: source)
        }
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func productionStreamingRestoreSupportsArchiveLargerThan500MiB() throws {
        guard BackupImportExportTestSupport.shouldRunLargeBackupStressTests else { return }
        try BackupImportExportTestSupport.assertEmbeddedRestoreRoundtrip(
            targetSize: 512 * 1024 * 1024,
            filePrefix: "backup-over-500MiB"
        )
    }
}
