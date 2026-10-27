import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct BackupImportTests {
    @Test func backupPreviewFromFileURLLoadsMetadataOnly() throws {
        let projectId = UUID()
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x0A, 0x0B]), fileName: "backup-preview-\(UUID().uuidString).bin")
        defer { QuickNoteAttachmentStorage.delete(fileName: quickNoteFile) }

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "预览项目", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            quickNotes: [QuickNote(projectId: projectId, attachments: [QuickNoteAttachment(kind: .file, fileName: quickNoteFile)])],
            templates: []
        )

        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let preview = try BackupArchiveService.previewBackup(from: archive.fileURL)
        #expect(preview.snapshot.projects.count == 1)
        #expect(preview.quickNoteAttachmentFileCount == 1)
        #expect(preview.snapshot.quickNoteAttachmentFiles.isEmpty)
    }

    @Test func backupDecodeFromFileURLRestoresEmbeddedFiles() throws {
        let projectId = UUID()
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x1A, 0x1B, 0x1C]), fileName: "backup-decode-\(UUID().uuidString).bin")
        defer { QuickNoteAttachmentStorage.delete(fileName: quickNoteFile) }

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "解包项目", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            quickNotes: [QuickNote(projectId: projectId, attachments: [QuickNoteAttachment(kind: .file, fileName: quickNoteFile)])],
            templates: []
        )

        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        let restored = try BackupArchiveService.decodeBackup(from: archive.fileURL)
        #expect(restored.projects.count == 1)
        #expect(restored.quickNoteAttachmentFiles.map(\.fileName).contains(quickNoteFile))
    }

    @Test func fixedLegacyBackupZipFixtureStillImports() throws {
        let fixtureURL = try BackupImportExportTestSupport.writeFixedLegacyBackupZipFixture()
        let attachmentFileName = BackupImportExportTestSupport.fixedLegacyBackupZipAttachmentFileName
        let attachmentData = BackupImportExportTestSupport.fixedLegacyBackupZipAttachmentData
        defer {
            try? FileManager.default.removeItem(at: fixtureURL)
            QuickNoteAttachmentStorage.delete(fileName: attachmentFileName)
        }

        QuickNoteAttachmentStorage.delete(fileName: attachmentFileName)

        let preview = try BackupArchiveService.previewBackup(from: fixtureURL)
        #expect(preview.snapshot.projects.first?.name == "旧ZIP样本项目")
        #expect(preview.snapshot.quickNotes.first?.attachments.first?.fileName == attachmentFileName)
        #expect(preview.snapshot.quickNoteAttachmentFiles.isEmpty)
        #expect(preview.quickNoteAttachmentFileCount == 1)

        let decoded = try BackupArchiveService.decodeBackup(from: fixtureURL)
        #expect(decoded.schemaVersion == BackupSnapshot.currentSchemaVersion)
        #expect(decoded.projects.first?.location == "一号楼")
        #expect(decoded.quickNoteAttachmentFiles.first?.fileName == attachmentFileName)
        #expect(decoded.quickNoteAttachmentFiles.first?.data == attachmentData)

        #expect(!QuickNoteAttachmentStorage.exists(fileName: attachmentFileName))
        let restored = try BackupArchiveService.restoreEmbeddedFiles(from: fixtureURL)
        #expect(restored.quickNoteAttachmentFileCount == 1)
        #expect(QuickNoteAttachmentStorage.data(for: attachmentFileName) == attachmentData)
    }

    @Test func backupRestoreEmbeddedFilesStreamsFromZip() throws {
        let projectId = UUID()
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x2A, 0x2B, 0x2C]), fileName: "backup-stream-\(UUID().uuidString).bin")

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "流式恢复项目", location: "现场", status: .active)],
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
    }

    @Test func backupPrepareEmbeddedFileRestoreDoesNotCommitBeforeTransactionCommit() throws {
        let projectId = UUID()
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x6A, 0x6B]), fileName: "backup-transaction-\(UUID().uuidString).bin")

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "事务恢复项目", location: "现场", status: .active)],
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

        let transaction = try BackupArchiveService.prepareEmbeddedFileRestore(from: archive.fileURL)
        #expect(transaction.counts.quickNoteAttachmentFileCount == 1)
        #expect(QuickNoteAttachmentStorage.exists(fileName: quickNoteFile) == false)

        let restored = try transaction.commit()
        #expect(restored.quickNoteAttachmentFileCount == 1)
        #expect(QuickNoteAttachmentStorage.exists(fileName: quickNoteFile))
    }

    @Test func backupRestoreEmbeddedFilesHandlesSampleZipEntry() throws {
        try BackupImportExportTestSupport.assertEmbeddedRestoreRoundtrip(
            targetSize: 2 * 1024 * 1024,
            filePrefix: "backup-stream-sample"
        )
    }

    @Test func backupRestoreEmbeddedFilesHandlesLargeZipEntry() throws {
        guard BackupImportExportTestSupport.shouldRunLargeBackupStressTests else { return }
        try BackupImportExportTestSupport.assertEmbeddedRestoreRoundtrip(
            targetSize: 32 * 1024 * 1024,
            filePrefix: "backup-large-stream"
        )
    }
}
