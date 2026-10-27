import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct BackupErrorRecoveryTests {
    @Test func backupPreparedEmbeddedFileRestoreCancelKeepsStorageUnchanged() throws {
        let projectId = UUID()
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x7A, 0x7B]), fileName: "backup-transaction-cancel-\(UUID().uuidString).bin")

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "事务取消恢复项目", location: "现场", status: .active)],
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
        transaction.cancel()

        #expect(QuickNoteAttachmentStorage.exists(fileName: quickNoteFile) == false)
    }

    @Test @MainActor func backupImportTransactionRollsBackFilesWhenMetadataPersistFails() async throws {
        let projectId = UUID()
        let quickNoteFile = "backup-transaction-persist-failure-\(UUID().uuidString).bin"
        let oldData = Data([0x41, 0x42, 0x43])
        let newData = Data([0xD1, 0xD2, 0xD3])
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(newData, fileName: quickNoteFile)

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "事务持久化失败回滚项目", location: "现场", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            quickNotes: [QuickNote(projectId: projectId, attachments: [QuickNoteAttachment(kind: .file, fileName: quickNoteFile)])],
            templates: []
        )

        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        let invalidStorageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-persist-fail-\(UUID().uuidString).tmp")
        defer {
            QuickNoteAttachmentStorage.delete(fileName: quickNoteFile)
            try? FileManager.default.removeItem(at: archive.fileURL)
            try? FileManager.default.removeItem(at: invalidStorageRoot)
        }

        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(oldData, fileName: quickNoteFile)
        #expect(QuickNoteAttachmentStorage.data(for: quickNoteFile) == oldData)

        try Data("not-a-directory".utf8).write(to: invalidStorageRoot, options: .atomic)
        let store = DataStore(storageDirectory: invalidStorageRoot)
        await store.awaitInitialLoad()
        store.replaceMaterialSheetDrafts([MaterialSheetDraft(title: "本地草稿必须回滚")])
        let previousSnapshot = store.makeSnapshot(includePhotoFiles: false)
        var importedSnapshot = snapshot
        importedSnapshot.materialSheetDrafts = [MaterialSheetDraft(title: "导入草稿")]
        let restoreTransaction = try BackupArchiveService.prepareEmbeddedFileRestore(from: archive.fileURL)

        do {
            _ = try await BackupImportCoordinator.commitAndPersistImport(
                restoreTransaction: restoreTransaction,
                importedSnapshot: importedSnapshot,
                previousSnapshot: previousSnapshot,
                importMode: .overwrite,
                store: store,
                sourceFileName: archive.fileURL.lastPathComponent
            )
            Issue.record("预期应因数据持久化失败而抛错")
        } catch {
            #expect(Bool(true))
        }

        #expect(QuickNoteAttachmentStorage.data(for: quickNoteFile) == oldData)
        #expect(store.materialSheetDrafts.map(\.title) == ["本地草稿必须回滚"])
    }

    @Test func backupImportCancelDoesNotKeepStagedTempFileOrHalfWriteExistingData() throws {
        let projectId = UUID()
        let quickNoteFile = "backup-import-cancel-\(UUID().uuidString).bin"
        let newData = Data(repeating: 0xA6, count: 2 * 256 * 1024 + 1024)
        let oldData = Data([0x11, 0x22, 0x33, 0x44])
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(newData, fileName: quickNoteFile)

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "导入取消回滚项目", location: "现场", status: .active)],
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

        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(oldData, fileName: quickNoteFile)
        #expect(QuickNoteAttachmentStorage.data(for: quickNoteFile) == oldData)

        var didRequestCancel = false
        do {
            _ = try BackupArchiveService.prepareEmbeddedFileRestore(
                from: archive.fileURL,
                shouldCancel: {
                    if didRequestCancel { return true }
                    for stageURL in BackupImportExportTestSupport.partialRestoreExtractions() {
                        if let size = BackupImportExportTestSupport.fileSize(at: stageURL),
                           size > 0,
                           size < newData.count {
                            didRequestCancel = true
                            return true
                        }
                    }
                    return false
                }
            )
            Issue.record("预期应抛出取消错误")
        } catch BackupArchiveError.cancelled {
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }

        #expect(didRequestCancel)
        #expect(BackupImportExportTestSupport.partialRestoreExtractions().isEmpty)
        #expect(QuickNoteAttachmentStorage.data(for: quickNoteFile) == oldData)
        #expect(
            BackupImportExportTestSupport.temporaryFiles(
                named: quickNoteFile,
                containingPathFragment: "backup-restore-"
            ).isEmpty
        )
    }

    @Test func backupRestoreEmbeddedFilesCancelKeepsStorageUnchanged() throws {
        let projectId = UUID()
        let quickNoteFile = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x3A, 0x3B, 0x3C]), fileName: "backup-cancel-\(UUID().uuidString).bin")

        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(id: projectId, name: "取消恢复项目", location: "现场", status: .active)],
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

        do {
            _ = try BackupArchiveService.restoreEmbeddedFiles(
                from: archive.fileURL,
                shouldCancel: { true }
            )
            Issue.record("预期应抛出取消错误")
        } catch BackupArchiveError.cancelled {
            #expect(Bool(true))
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }

        #expect(QuickNoteAttachmentStorage.exists(fileName: quickNoteFile) == false)
    }
}

extension BackupErrorRecoveryTests {
    @Test func backupPrepareRestoreRejectsZipSlipEntryAndCleansTempStage() throws {
        let safeFileName = "backup-safe-\(UUID().uuidString).bin"
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "backup-zip-slip")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let metadataData = try BackupArchiveValidationTestSupport.makeValidBackupMetadataData()
        let safeEntryPath = BackupArchiveService.quickNotePrefix + "xx-escape.bin"
        let unsafeEntryPath = BackupArchiveService.quickNotePrefix + "../escape.bin"
        var zip = SimpleZipArchiveBuilder()
        zip.addFile(path: BackupArchiveService.manifestPath, data: try BackupImportExportTestSupport.manifestData())
        zip.addFile(path: BackupArchiveService.metadataPath, data: metadataData)
        zip.addFile(path: BackupArchiveService.quickNotePrefix + safeFileName, data: Data([0x01, 0x02]))
        zip.addFile(path: safeEntryPath, data: Data([0x03]))
        let archiveData = try BackupArchiveValidationTestSupport.archiveDataByReplacingPath(
            safeEntryPath,
            with: unsafeEntryPath,
            in: zip.build()
        )
        try archiveData.write(to: archiveURL, options: .atomic)

        do {
            _ = try BackupArchiveService.prepareEmbeddedFileRestore(from: archiveURL)
            Issue.record("预期应拒绝 zip-slip 路径")
        } catch SimpleZipArchiveReader.ZipReadError.unsafePath(let path) {
            #expect(path.contains(".."))
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }

        #expect(
            BackupImportExportTestSupport.temporaryFiles(
                named: safeFileName,
                containingPathFragment: "backup-restore-"
            ).isEmpty
        )
    }

    @Test func backupPrepareRestoreRejectsDuplicateEntryAndCleansTempStage() throws {
        let duplicateFileName = "backup-duplicate-\(UUID().uuidString).bin"
        let duplicatePath = BackupArchiveService.quickNotePrefix + duplicateFileName
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "backup-duplicate-entry")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let metadataData = try BackupArchiveValidationTestSupport.makeValidBackupMetadataData()
        var zip = SimpleZipArchiveBuilder()
        zip.addFile(path: BackupArchiveService.manifestPath, data: try BackupImportExportTestSupport.manifestData())
        zip.addFile(path: BackupArchiveService.metadataPath, data: metadataData)
        zip.addFile(path: duplicatePath, data: Data([0x11, 0x12]))
        zip.addFile(path: duplicatePath, data: Data([0x21, 0x22]))
        try zip.build().write(to: archiveURL, options: .atomic)

        do {
            _ = try BackupArchiveService.prepareEmbeddedFileRestore(from: archiveURL)
            Issue.record("预期应拒绝重复 ZIP entry")
        } catch SimpleZipArchiveReader.ZipReadError.duplicateEntry(let path) {
            #expect(path == duplicatePath)
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }

        #expect(
            BackupImportExportTestSupport.temporaryFiles(
                named: duplicateFileName,
                containingPathFragment: "backup-restore-"
            ).isEmpty
        )
    }

    @Test func backupPrepareRestoreRejectsCorruptedEntryChecksumAndCleansTempStage() throws {
        let fileName = "backup-corrupt-crc-\(UUID().uuidString).bin"
        let entryPath = BackupArchiveService.quickNotePrefix + fileName
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "backup-corrupt-crc")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        var zip = SimpleZipArchiveBuilder()
        zip.addFile(path: BackupArchiveService.manifestPath, data: try BackupImportExportTestSupport.manifestData())
        zip.addFile(path: BackupArchiveService.metadataPath, data: try BackupArchiveValidationTestSupport.makeValidBackupMetadataData())
        zip.addFile(path: entryPath, data: Data([0x31, 0x32, 0x33]))
        let archiveData = try BackupArchiveValidationTestSupport.archiveDataByCorruptingPayload(for: entryPath, in: zip.build())
        try archiveData.write(to: archiveURL, options: .atomic)

        do {
            _ = try BackupArchiveService.prepareEmbeddedFileRestore(from: archiveURL)
            Issue.record("预期应拒绝 CRC 校验失败的 ZIP entry")
        } catch SimpleZipArchiveReader.ZipReadError.checksumMismatch(let path) {
            #expect(path == entryPath)
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }

        #expect(
            BackupImportExportTestSupport.temporaryFiles(
                named: fileName,
                containingPathFragment: "backup-restore-"
            ).isEmpty
        )
    }

    @Test func backupPrepareRestoreRejectsForgedOversizedUncompressedEntry() throws {
        let fileName = "backup-forged-size-\(UUID().uuidString).bin"
        let entryPath = BackupArchiveService.quickNotePrefix + fileName
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "backup-forged-size")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        var zip = SimpleZipArchiveBuilder()
        zip.addFile(path: BackupArchiveService.manifestPath, data: try BackupImportExportTestSupport.manifestData())
        zip.addFile(path: BackupArchiveService.metadataPath, data: try BackupArchiveValidationTestSupport.makeValidBackupMetadataData())
        zip.addFile(path: entryPath, data: Data([0x41]))
        let archiveData = try BackupArchiveValidationTestSupport.archiveDataByReplacingLocalUncompressedSize(
            for: entryPath,
            with: 2_000_000_000,
            in: zip.build()
        )
        try archiveData.write(to: archiveURL, options: .atomic)

        do {
            _ = try BackupArchiveService.prepareEmbeddedFileRestore(from: archiveURL)
            Issue.record("预期应拒绝伪造超大解压尺寸的 ZIP entry")
        } catch SimpleZipArchiveReader.ZipReadError.limitExceeded(let reason) {
            #expect(reason == entryPath)
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }
    }
}
