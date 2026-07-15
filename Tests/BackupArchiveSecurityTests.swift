import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct BackupArchiveSecurityTests {
    @Test func streamingSHA256MatchesKnownVector() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-sha256-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc".utf8).write(to: url, options: .atomic)

        #expect(
            try BackupArchiveSecurity.sha256Hex(of: url)
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test func remoteRestoreValidationAcceptsUntouchedArchiveAndRejectsChangedCopy() throws {
        let snapshot = BackupSnapshot(
            materialItems: [], quoteItems: [], laborRecords: [],
            projects: [Project(name: "远端校验", location: "现场", status: .active)],
            dailyLogs: [], historyRecords: [], templates: []
        )
        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }
        let digest = try BackupArchiveSecurity.sha256Hex(of: archive.fileURL)

        try BackupArchiveSecurity.validateRemoteCopy(at: archive.fileURL, expectedSHA256: digest)

        var changed = try Data(contentsOf: archive.fileURL)
        changed[changed.startIndex] ^= 0x01
        try changed.write(to: archive.fileURL, options: .atomic)
        do {
            try BackupArchiveSecurity.validateRemoteCopy(at: archive.fileURL, expectedSHA256: digest)
            Issue.record("预期应拒绝 SHA-256 不匹配的远端副本")
        } catch BackupArchiveSecurityError.digestMismatch {
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }
    }

    @Test func fullArchiveValidationReadsManifestAndMetadata() throws {
        let snapshot = BackupSnapshot(
            materialItems: [], quoteItems: [], laborRecords: [], projects: [],
            dailyLogs: [], historyRecords: [], templates: []
        )
        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let manifest = try BackupArchiveService.validateArchive(at: archive.fileURL)
        #expect(manifest.schemaVersion == BackupSnapshot.currentSchemaVersion)
        #expect(manifest.metadataPath == BackupArchiveService.metadataPath)
    }
}
