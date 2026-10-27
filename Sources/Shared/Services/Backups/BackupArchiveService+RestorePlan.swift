import Foundation

extension BackupArchiveService {
    static func prepareEmbeddedFileRestore(
        from fileURL: URL,
        progress: ((BackupImportProgress) -> Void)? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) throws -> EmbeddedFileRestoreTransaction {
        func report(_ completed: Int64, _ total: Int64, _ item: String) {
            progress?(BackupImportProgress(completedBytes: completed, totalBytes: max(total, 1), currentItem: item))
        }

        func failIfCancelled() throws {
            if shouldCancel?() == true || Task.isCancelled {
                throw BackupArchiveError.cancelled
            }
        }

        let ext = fileURL.pathExtension.lowercased()
        let totalBytes = Int64(max(QuickNoteAttachmentStorage.fileSize(at: fileURL), 1))
        var stage = try BackupRestoreStage()
        var shouldCleanupStageOnExit = true
        defer {
            if shouldCleanupStageOnExit { stage.cleanup() }
        }

        if ext == "json" {
            recordBackupArchiveIssue(
                "backup.restore.json_rejected",
                fileName: fileURL.lastPathComponent
            )
            throw BackupArchiveError.invalidBackup
        } else {
            try scanRestoreArchive(from: fileURL, stage: &stage, shouldCancel: shouldCancel,
                                   progress: { completed, total, path in report(completed, total, locFormat("恢复 %@", path)) })
        }

        try failIfCancelled()
        guard let manifestData = stage.manifestData else {
            recordBackupArchiveIssue(
                "backup.restore.missing_manifest",
                path: manifestPath
            )
            throw BackupArchiveError.missingManifest
        }
        _ = try decodeManifest(from: manifestData)
        report(totalBytes, totalBytes, loc("原文件已暂存"))
        shouldCleanupStageOnExit = false
        return stage.transaction
    }

    private static func scanRestoreArchive(
        from fileURL: URL, stage: inout BackupRestoreStage, shouldCancel: (() -> Bool)?,
        progress: ((Int64, Int64, String) -> Void)?
    ) throws {
        do {
            try SimpleZipArchiveReader.scan(
                fileURL: fileURL,
                limits: .backup,
                shouldCancel: { shouldCancel?() == true || Task.isCancelled },
                onProgress: { completed, total, path in
                    progress?(completed, total, path)
                },
                onEntry: { entry, readData, writeEntryToFile in
                    if shouldCancel?() == true || Task.isCancelled { throw BackupArchiveError.cancelled }
                    try stage.accept(path: entry.path, readData: readData, writeEntryToFile: writeEntryToFile)
                }
            )
        } catch SimpleZipArchiveReader.ZipReadError.cancelled {
            throw BackupArchiveError.cancelled
        } catch {
            recordBackupArchiveIssue(
                "backup.restore.attachment_scan_failed",
                fileName: fileURL.lastPathComponent,
                error: error
            )
            throw error
        }
    }

    static func stageEntry(
        _ writeEntryToFile: (URL) throws -> Void,
        fileName: String,
        to directory: URL,
        failureMessage: String,
        stage: String
    ) throws {
        do {
            let stagedURL = directory.appendingPathComponent(fileName)
            try writeEntryToFile(stagedURL)
            BackupArchiveSecurity.applyDataProtection(to: stagedURL)
        } catch BackupArchiveError.cancelled {
            throw BackupArchiveError.cancelled
        } catch SimpleZipArchiveReader.ZipReadError.cancelled {
            throw BackupArchiveError.cancelled
        } catch let error as SimpleZipArchiveReader.ZipReadError {
            throw error
        } catch {
            recordBackupArchiveIssue(
                "backup.restore.stage_zip_entry_failed",
                fileName: fileName,
                details: ["stage": stage],
                error: error
            )
            throw BackupArchiveError.restoreFailed(locFormat("%@：%@", failureMessage, fileName))
        }
    }
}
