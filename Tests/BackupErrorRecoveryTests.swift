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
                    for stageURL in BackupImportExportTestSupport.temporaryFiles(
                        named: quickNoteFile,
                        containingPathFragment: "backup-restore-"
                    ) {
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

    @Test func backupPrepareRestoreRejectsZipSlipEntryAndCleansTempStage() throws {
        let safeFileName = "backup-safe-\(UUID().uuidString).bin"
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "backup-zip-slip")
        defer { try? FileManager.default.removeItem(at: archiveURL) }

        let metadataData = try Self.makeValidBackupMetadataData()
        let safeEntryPath = BackupArchiveService.quickNotePrefix + "xx-escape.bin"
        let unsafeEntryPath = BackupArchiveService.quickNotePrefix + "../escape.bin"
        var zip = SimpleZipArchiveBuilder()
        zip.addFile(path: BackupArchiveService.manifestPath, data: try BackupImportExportTestSupport.manifestData())
        zip.addFile(path: BackupArchiveService.metadataPath, data: metadataData)
        zip.addFile(path: BackupArchiveService.quickNotePrefix + safeFileName, data: Data([0x01, 0x02]))
        zip.addFile(path: safeEntryPath, data: Data([0x03]))
        let archiveData = try Self.archiveDataByReplacingPath(
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

        let metadataData = try Self.makeValidBackupMetadataData()
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
        zip.addFile(path: BackupArchiveService.metadataPath, data: try Self.makeValidBackupMetadataData())
        zip.addFile(path: entryPath, data: Data([0x31, 0x32, 0x33]))
        let archiveData = try Self.archiveDataByCorruptingPayload(for: entryPath, in: zip.build())
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
        zip.addFile(path: BackupArchiveService.metadataPath, data: try Self.makeValidBackupMetadataData())
        zip.addFile(path: entryPath, data: Data([0x41]))
        let archiveData = try Self.archiveDataByReplacingLocalUncompressedSize(
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

private extension BackupErrorRecoveryTests {
    private static func makeValidBackupMetadataData() throws -> Data {
        let snapshot = BackupSnapshot(
            materialItems: [],
            quoteItems: [],
            laborRecords: [],
            projects: [Project(name: "恶意 ZIP 测试项目", location: "", status: .active)],
            dailyLogs: [],
            historyRecords: [],
            templates: []
        )
        return try JSONEncoder().encode(snapshot)
    }

    private static func archiveDataByReplacingPath(
        _ oldPath: String,
        with newPath: String,
        in data: Data
    ) throws -> Data {
        let oldBytes = Array(oldPath.utf8)
        let newBytes = Array(newPath.utf8)
        #expect(oldBytes.count == newBytes.count)
        guard oldBytes.count == newBytes.count else {
            throw SimpleZipArchiveReader.ZipReadError.invalidArchive
        }

        var bytes = Array(data)
        var index = 0
        var replacementCount = 0
        while index + oldBytes.count <= bytes.count {
            if Array(bytes[index..<(index + oldBytes.count)]) == oldBytes {
                bytes.replaceSubrange(index..<(index + oldBytes.count), with: newBytes)
                replacementCount += 1
                index += newBytes.count
            } else {
                index += 1
            }
        }
        #expect(replacementCount >= 2)
        guard replacementCount >= 2 else {
            throw SimpleZipArchiveReader.ZipReadError.invalidArchive
        }
        return Data(bytes)
    }

    private static func archiveDataByCorruptingPayload(
        for path: String,
        in data: Data
    ) throws -> Data {
        var bytes = Array(data)
        let headerOffset = try localHeaderOffset(for: path, in: bytes)
        let nameLength = Int(try data.uint16LE(at: headerOffset + 26))
        let extraLength = Int(try data.uint16LE(at: headerOffset + 28))
        let payloadOffset = headerOffset + 30 + nameLength + extraLength
        guard payloadOffset < bytes.count else {
            throw SimpleZipArchiveReader.ZipReadError.invalidArchive
        }
        bytes[payloadOffset] ^= 0xFF
        return Data(bytes)
    }

    private static func archiveDataByReplacingLocalUncompressedSize(
        for path: String,
        with size: UInt32,
        in data: Data
    ) throws -> Data {
        var bytes = Array(data)
        let headerOffset = try localHeaderOffset(for: path, in: bytes)
        let valueOffset = headerOffset + 22
        guard valueOffset + 4 <= bytes.count else {
            throw SimpleZipArchiveReader.ZipReadError.invalidArchive
        }
        bytes[valueOffset] = UInt8(truncatingIfNeeded: size)
        bytes[valueOffset + 1] = UInt8(truncatingIfNeeded: size >> 8)
        bytes[valueOffset + 2] = UInt8(truncatingIfNeeded: size >> 16)
        bytes[valueOffset + 3] = UInt8(truncatingIfNeeded: size >> 24)
        return Data(bytes)
    }

    private static func localHeaderOffset(for path: String, in bytes: [UInt8]) throws -> Int {
        let pathBytes = Array(path.utf8)
        guard let pathOffset = bytes.indices.first(where: { index in
            guard index + pathBytes.count <= bytes.count else { return false }
            return Array(bytes[index..<(index + pathBytes.count)]) == pathBytes
        }) else {
            throw SimpleZipArchiveReader.ZipReadError.invalidArchive
        }
        let headerOffset = pathOffset - 30
        guard headerOffset >= 0,
              headerOffset + 4 <= bytes.count,
              bytes[headerOffset] == 0x50,
              bytes[headerOffset + 1] == 0x4B,
              bytes[headerOffset + 2] == 0x03,
              bytes[headerOffset + 3] == 0x04 else {
            throw SimpleZipArchiveReader.ZipReadError.invalidArchive
        }
        return headerOffset
    }
}
