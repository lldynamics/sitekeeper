import Testing
import Foundation
import UIKit
@testable import sitekeeper

enum BackupImportExportTestSupport {
    static let fixedLegacyBackupZipAttachmentFileName = "legacy-fixture-note.bin"
    static let fixedLegacyBackupZipAttachmentData = Data([0x53, 0x4B, 0x2D, 0x4C, 0x45, 0x47, 0x41, 0x43, 0x59])

    static var shouldRunLargeBackupStressTests: Bool {
        guard let rawValue = ProcessInfo.processInfo.environment["SITEKEEPER_NIGHTLY_BACKUP_STRESS"] else {
            return false
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value == "1" || value == "true" || value == "yes"
    }

    static func writeFixedLegacyBackupZipFixture() throws -> URL {
        guard let data = Data(
            base64Encoded: fixedLegacyBackupZipFixtureBase64,
            options: [.ignoreUnknownCharacters]
        ) else {
            throw BackupArchiveError.invalidBackup
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fixed-legacy-backup-\(UUID().uuidString).zip")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func assertEmbeddedRestoreRoundtrip(
        targetSize: Int,
        filePrefix: String
    ) throws {
        let projectId = UUID()
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(
            Data([0x5A]),
            fileName: "\(filePrefix)-\(UUID().uuidString).bin"
        )
        let sourceURL = QuickNoteAttachmentStorage.fileURL(for: quickNoteFile)
        let handle = try FileHandle(forWritingTo: sourceURL)
        try handle.truncate(atOffset: UInt64(targetSize))
        try handle.close()

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "大附件流式恢复", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            quickNotes: [QuickNote(projectId: projectId, attachments: [QuickNoteAttachment(kind: .file, fileName: quickNoteFile)])],
            templates: []
        )

        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer {
            QuickNoteAttachmentStorage.delete(fileName: quickNoteFile)
            try? FileManager.default.removeItem(at: archive.fileURL)
        }

        QuickNoteAttachmentStorage.delete(fileName: quickNoteFile)
        #expect(QuickNoteAttachmentStorage.exists(fileName: quickNoteFile) == false)

        let restored = try BackupArchiveService.restoreEmbeddedFiles(from: archive.fileURL)
        #expect(restored.quickNoteAttachmentFileCount == 1)
        #expect(QuickNoteAttachmentStorage.exists(fileName: quickNoteFile))
        #expect(QuickNoteAttachmentStorage.fileSize(for: quickNoteFile) == targetSize)
    }

    static func temporaryFiles(withPrefix prefix: String) -> [URL] {
        let root = FileManager.default.temporaryDirectory
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        var result: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent.hasPrefix(prefix) {
            result.append(url)
        }
        return result
    }

    static func temporaryFiles(
        named fileName: String,
        containingPathFragment pathFragment: String
    ) -> [URL] {
        let root = FileManager.default.temporaryDirectory
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }
        var result: [URL] = []
        for case let url as URL in enumerator
        where url.lastPathComponent == fileName && url.path.contains(pathFragment) {
            result.append(url)
        }
        return result
    }

    static func fileSize(at url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    static func makeJPEGData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let image = renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw FileStorageError.imageEncodingFailed
        }
        return data
    }

    static func metadataDataWithoutSchemaVersion(from snapshot: BackupSnapshot) throws -> Data {
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "schemaVersion")
        object.removeValue(forKey: "appVersion")
        object.removeValue(forKey: "appBuild")
        object.removeValue(forKey: "backupCreatedAt")
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func metadataDataWithSchemaVersion(_ version: Int, from snapshot: BackupSnapshot) throws -> Data {
        let encoded = try JSONEncoder().encode(snapshot)
        var object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["schemaVersion"] = version
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func manifestData(schemaVersion: Int = BackupSnapshot.currentSchemaVersion) throws -> Data {
        try JSONEncoder().encode(BackupArchiveManifest(
            schemaVersion: schemaVersion,
            metadataPath: BackupArchiveService.metadataPath
        ))
    }

    static func expectInvalidBackup(_ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("预期应拒绝 JSON 备份")
        } catch BackupArchiveError.invalidBackup {
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }
    }

    static func expectMissingManifest(_ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("预期应拒绝缺少 manifest.json 的备份")
        } catch BackupArchiveError.missingManifest {
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }
    }

    static func expectDecodingFailure(_ operation: () throws -> Void) {
        do {
            try operation()
            Issue.record("预期应拒绝旧备份数据索引")
        } catch is DecodingError {
        } catch BackupArchiveError.unsupportedSchemaVersion(_) {
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }
    }

    // Fixed schema-2 ZIP bytes captured from a previous exporter shape; do not build it with BackupArchiveService.
    private static let fixedLegacyBackupZipFixtureBase64 = """
    UEsDBBQAAAAAAABIoVzEbp1rrQAAAK0AAAANAAAAbWFuaWZlc3QuanNvbnsKICAiYXBwQnVpbGQi
    OiAiMTAwIiwKICAiYXBwTmFtZSI6ICLlt6XlnLDmjozmn5wiLAogICJhcHBWZXJzaW9uIjogIjEu
    MC4wIiwKICAiZXhwb3J0ZWRBdCI6ICIyMDI2LTA1LTAxIDA5OjAwIiwKICAibWV0YWRhdGFQYXRo
    IjogImRhdGEvYmFja3VwLmpzb24iLAogICJzY2hlbWFWZXJzaW9uIjogMgp9UEsDBBQAAAAAAABI
    oVyxYdCRkgUAAJIFAAAQAAAAZGF0YS9iYWNrdXAuanNvbnsKICAiYXBwQnVpbGQiOiAiMTAwIiwK
    ICAiYXBwVmVyc2lvbiI6ICIxLjAuMCIsCiAgImJhY2t1cENyZWF0ZWRBdCI6ICIyMDI2LTA1LTAx
    IDA5OjAwIiwKICAiY29uc3RydWN0aW9uTWV0aG9kcyI6IFtdLAogICJkYWlseUxvZ3MiOiBbXSwK
    ICAiZGVsZXRlZFVzZXJNYXRlcmlhbHMiOiBbXSwKICAiZmF2b3JpdGVNYXRlcmlhbEtleXMiOiBb
    XSwKICAiaGlkZGVuUHJlc2V0S2V5cyI6IFtdLAogICJoaXN0b3J5UmVjb3JkcyI6IFtdLAogICJs
    YWJvclJlY29yZHMiOiBbXSwKICAibWF0ZXJpYWxJdGVtcyI6IFtdLAogICJtYXRlcmlhbFByaWNl
    RW50cmllcyI6IFtdLAogICJtYXRlcmlhbFNoZWV0RHJhZnRzIjogW10sCiAgInByb2dyZXNzVGFz
    a3MiOiBbXSwKICAicHJvamVjdENvbnRhY3RzIjogW10sCiAgInByb2plY3REb2N1bWVudHMiOiBb
    XSwKICAicHJvamVjdERyYXdpbmdzIjogW10sCiAgInByb2plY3RGaW5hbmNpYWxSZWNvcmRzIjog
    W10sCiAgInByb2plY3RXYXJlaG91c2VNb3ZlbWVudHMiOiBbXSwKICAicHJvamVjdHMiOiBbCiAg
    ICB7CiAgICAgICJpZCI6ICIxMTExMTExMS0xMTExLTExMTEtMTExMS0xMTExMTExMTExMTEiLAog
    ICAgICAibG9jYXRpb24iOiAi5LiA5Y+35qW8IiwKICAgICAgIm5hbWUiOiAi5penWklQ5qC35pys
    6aG555uuIiwKICAgICAgInN0YXR1cyI6ICLov5vooYzkuK0iCiAgICB9CiAgXSwKICAicXVpY2tO
    b3RlcyI6IFsKICAgIHsKICAgICAgImF0dGFjaG1lbnRzIjogWwogICAgICAgIHsKICAgICAgICAg
    ICJjcmVhdGVkQXQiOiAiMjAyNi0wNS0wMSAwOTowMSIsCiAgICAgICAgICAiZmlsZU5hbWUiOiAi
    bGVnYWN5LWZpeHR1cmUtbm90ZS5iaW4iLAogICAgICAgICAgImlkIjogIjMzMzMzMzMzLTMzMzMt
    MzMzMy0zMzMzLTMzMzMzMzMzMzMzMyIsCiAgICAgICAgICAia2luZCI6ICJmaWxlIiwKICAgICAg
    ICAgICJvcmlnaW5hbE5hbWUiOiAibGVnYWN5LW5vdGUudHh0IgogICAgICAgIH0KICAgICAgXSwK
    ICAgICAgImNvbnRlbnQiOiAi5p2l6Ieq5Zu65a6aWklQIGZpeHR1cmUiLAogICAgICAiY3JlYXRl
    ZEF0IjogIjIwMjYtMDUtMDEgMDk6MDEiLAogICAgICAiaWQiOiAiMjIyMjIyMjItMjIyMi0yMjIy
    LTIyMjItMjIyMjIyMjIyMjIyIiwKICAgICAgInByb2plY3RJZCI6ICIxMTExMTExMS0xMTExLTEx
    MTEtMTExMS0xMTExMTExMTExMTEiLAogICAgICAidGl0bGUiOiAi5pen5aSH5Lu96ZmE5Lu2IiwK
    ICAgICAgInVwZGF0ZWRBdCI6ICIyMDI2LTA1LTAxIDA5OjAyIgogICAgfQogIF0sCiAgInF1b3Rl
    SXRlbXMiOiBbXSwKICAicmVjZW50TWF0ZXJpYWxLZXlzIjogW10sCiAgInNjaGVtYVZlcnNpb24i
    OiAyLAogICJzaXRlVG9kb3MiOiBbXSwKICAic3VwcGxpZXJQcm9maWxlcyI6IFtdLAogICJ0ZW1w
    bGF0ZXMiOiBbXSwKICAidXNlck1hdGVyaWFscyI6IFtdCn1QSwMEFAAAAAAAAEihXDGAuiEJAAAA
    CQAAADQAAABmaWxlcy9xdWljay1ub3RlLWF0dGFjaG1lbnRzL2xlZ2FjeS1maXh0dXJlLW5vdGUu
    YmluU0stTEVHQUNZUEsBAhQDFAAAAAAAAEihXMRunWutAAAArQAAAA0AAAAAAAAAAAAAAIABAAAA
    AG1hbmlmZXN0Lmpzb25QSwECFAMUAAAAAAAASKFcsWHQkZIFAACSBQAAEAAAAAAAAAAAAAAAgAHY
    AAAAZGF0YS9iYWNrdXAuanNvblBLAQIUAxQAAAAAAABIoVwxgLohCQAAAAkAAAA0AAAAAAAAAAAA
    AACAAZgGAABmaWxlcy9xdWljay1ub3RlLWF0dGFjaG1lbnRzL2xlZ2FjeS1maXh0dXJlLW5vdGUu
    YmluUEsFBgAAAAADAAMA2wAAAPMGAAAAAA==
    """
}
