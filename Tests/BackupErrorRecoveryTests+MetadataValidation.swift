import Testing
import Foundation
@testable import sitekeeper

extension BackupErrorRecoveryTests {
    @Test func backupRestoreEmbeddedFilesRejectsJSONBackup() throws {
        let projectId = UUID()
        let fileName = "backup-json-\(UUID().uuidString).bin"
        let jsonURL = FileManager.default.temporaryDirectory.appendingPathComponent("backup-json-\(UUID().uuidString).json")

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "JSON恢复项目", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: [],
            quickNoteAttachmentFiles: [QuickNoteAttachmentBackupFile(fileName: fileName, data: Data([0x4A, 0x4B, 0x4C]))]
        )

        let jsonData = try JSONEncoder().encode(snapshot)
        try jsonData.write(to: jsonURL, options: .atomic)

        defer {
            QuickNoteAttachmentStorage.delete(fileName: fileName)
            try? FileManager.default.removeItem(at: jsonURL)
        }

        QuickNoteAttachmentStorage.delete(fileName: fileName)
        #expect(QuickNoteAttachmentStorage.exists(fileName: fileName) == false)

        BackupImportExportTestSupport.expectInvalidBackup {
            _ = try BackupArchiveService.restoreEmbeddedFiles(from: jsonURL)
        }
        #expect(QuickNoteAttachmentStorage.exists(fileName: fileName) == false)
    }

    @Test func backupArchiveDecoderRejectsJSONBackupImport() throws {
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: "JSON备份", location: "", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )
        let data = try JSONEncoder().encode(snapshot)
        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-json-\(UUID().uuidString).json")
        try data.write(to: jsonURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        BackupImportExportTestSupport.expectInvalidBackup {
            _ = try BackupArchiveService.previewBackup(from: jsonURL)
        }
        BackupImportExportTestSupport.expectInvalidBackup {
            _ = try BackupArchiveService.decodeBackup(from: jsonURL)
        }
    }

    @Test func backupArchiveDecoderRejectsZIPMetadataWithoutSchemaVersion() throws {
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: "无版本备份", location: "", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )
        let metadataData = try BackupImportExportTestSupport.metadataDataWithoutSchemaVersion(from: snapshot)
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "backup-no-schema")
        var zip = try StreamingZipArchiveWriter(fileURL: archiveURL)
        try zip.addFile(path: BackupArchiveService.manifestPath, data: try BackupImportExportTestSupport.manifestData())
        try zip.addFile(path: BackupArchiveService.metadataPath, data: metadataData)
        let finishedURL = try zip.finish()
        defer { try? FileManager.default.removeItem(at: finishedURL) }

        BackupImportExportTestSupport.expectDecodingFailure {
            _ = try BackupArchiveService.previewBackup(from: finishedURL)
        }
        BackupImportExportTestSupport.expectDecodingFailure {
            _ = try BackupArchiveService.decodeBackup(from: finishedURL)
        }
    }

    @Test func backupArchiveDecoderRejectsOldSchemaVersion() throws {
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: "旧版本备份", location: "", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )
        let metadataData = try BackupImportExportTestSupport.metadataDataWithSchemaVersion(1, from: snapshot)
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "backup-old-schema")
        var zip = try StreamingZipArchiveWriter(fileURL: archiveURL)
        try zip.addFile(path: BackupArchiveService.manifestPath, data: try BackupImportExportTestSupport.manifestData())
        try zip.addFile(path: BackupArchiveService.metadataPath, data: metadataData)
        let finishedURL = try zip.finish()
        defer { try? FileManager.default.removeItem(at: finishedURL) }

        BackupImportExportTestSupport.expectDecodingFailure {
            _ = try BackupArchiveService.previewBackup(from: finishedURL)
        }
        BackupImportExportTestSupport.expectDecodingFailure {
            _ = try BackupArchiveService.decodeBackup(from: finishedURL)
        }
    }

    @Test func backupArchiveDecoderRejectsZIPWithoutManifest() throws {
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: "无清单备份", location: "", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )
        let metadataData = try JSONEncoder().encode(snapshot)
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "backup-without-manifest")
        var zip = try StreamingZipArchiveWriter(fileURL: archiveURL)
        try zip.addFile(path: BackupArchiveService.metadataPath, data: metadataData)
        let finishedURL = try zip.finish()
        defer { try? FileManager.default.removeItem(at: finishedURL) }

        BackupImportExportTestSupport.expectMissingManifest {
            _ = try BackupArchiveService.previewBackup(from: finishedURL)
        }
        BackupImportExportTestSupport.expectMissingManifest {
            _ = try BackupArchiveService.decodeBackup(from: finishedURL)
        }
        BackupImportExportTestSupport.expectMissingManifest {
            _ = try BackupArchiveService.restoreEmbeddedFiles(from: finishedURL)
        }
    }
}
