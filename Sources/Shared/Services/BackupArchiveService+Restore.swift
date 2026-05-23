import Foundation

extension BackupArchiveService {
    static func restoreEmbeddedFiles(
        from fileURL: URL,
        progress: ((BackupImportProgress) -> Void)? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) throws -> BackupEmbeddedRestoreCounts {
        let transaction = try prepareEmbeddedFileRestore(
            from: fileURL,
            progress: progress,
            shouldCancel: shouldCancel
        )
        progress?(BackupImportProgress(completedBytes: 1, totalBytes: 1, currentItem: loc("提交原文件")))
        let counts: BackupEmbeddedRestoreCounts
        do {
            counts = try transaction.commit()
            transaction.finalize()
        } catch {
            transaction.rollback()
            throw error
        }
        progress?(BackupImportProgress(completedBytes: 1, totalBytes: 1, currentItem: loc("恢复完成")))
        return counts
    }

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
        var counts = BackupEmbeddedRestoreCounts()
        var manifestData: Data?

        let stageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-restore-\(UUID().uuidString)", isDirectory: true)
        let photoStage = stageRoot.appendingPathComponent("photos", isDirectory: true)
        let drawingStage = stageRoot.appendingPathComponent("drawings", isDirectory: true)
        let documentStage = stageRoot.appendingPathComponent("project-documents", isDirectory: true)
        let quickNoteStage = stageRoot.appendingPathComponent("quick-note-attachments", isDirectory: true)

        func stageEntry(
            _ writeEntryToFile: (URL) throws -> Void,
            fileName: String,
            to directory: URL,
            failureMessage: String,
            stage: String
        ) throws {
            do {
                try writeEntryToFile(directory.appendingPathComponent(fileName))
            } catch BackupArchiveError.cancelled {
                throw BackupArchiveError.cancelled
            } catch SimpleZipArchiveReader.ZipReadError.cancelled {
                throw BackupArchiveError.cancelled
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

        do {
            try FileManager.default.createDirectory(at: photoStage, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: drawingStage, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: documentStage, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: quickNoteStage, withIntermediateDirectories: true)
        } catch {
            recordBackupArchiveIssue(
                "backup.restore.stage_create_failed",
                fileName: stageRoot.lastPathComponent,
                error: error
            )
            throw BackupArchiveError.restoreFailed(locFormat("创建导入暂存目录失败：%@", error.localizedDescription))
        }
        var shouldCleanupStageOnExit = true
        defer {
            if shouldCleanupStageOnExit {
                do {
                    _ = try FileOps.removeIfExists(
                        at: stageRoot,
                        context: .init(
                            event: "backup.restore.stage_cleanup",
                            category: .zipArchive,
                            source: "BackupArchiveService.restoreArchive"
                        )
                    )
                } catch {
                    recordBackupArchiveIssue(
                        "backup.restore.stage_cleanup_failed",
                        fileName: stageRoot.lastPathComponent,
                        error: error
                    )
                }
            }
        }

        if ext == "json" {
            recordBackupArchiveIssue(
                "backup.restore.json_rejected",
                fileName: fileURL.lastPathComponent
            )
            throw BackupArchiveError.invalidBackup
        } else {
            do {
                try SimpleZipArchiveReader.scan(
                    fileURL: fileURL,
                    shouldCancel: { shouldCancel?() == true || Task.isCancelled },
                    onProgress: { completed, total, path in
                        report(completed, total, locFormat("恢复 %@", path))
                    },
                    onEntry: { entry, readData, writeEntryToFile in
                        try failIfCancelled()
                        if entry.path == manifestPath {
                            manifestData = try readData()
                            return
                        }
                        if let fileName = leafFileName(for: entry.path, prefix: photoPrefix) {
                            try stageEntry(writeEntryToFile, fileName: fileName, to: photoStage, failureMessage: loc("暂存照片失败"), stage: "photos")
                            counts.photoFileCount += 1
                            return
                        }
                        if let fileName = leafFileName(for: entry.path, prefix: drawingPrefix) {
                            try stageEntry(writeEntryToFile, fileName: fileName, to: drawingStage, failureMessage: loc("暂存图纸失败"), stage: "drawings")
                            counts.drawingFileCount += 1
                            return
                        }
                        if let fileName = leafFileName(for: entry.path, prefix: documentPrefix) {
                            try stageEntry(writeEntryToFile, fileName: fileName, to: documentStage, failureMessage: loc("暂存项目资料失败"), stage: "project-documents")
                            counts.documentFileCount += 1
                            return
                        }
                        if let fileName = leafFileName(for: entry.path, prefix: quickNotePrefix) {
                            try stageEntry(writeEntryToFile, fileName: fileName, to: quickNoteStage, failureMessage: loc("暂存随手记/工艺附件失败"), stage: "quick-note-attachments")
                            counts.quickNoteAttachmentFileCount += 1
                        }
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

        try failIfCancelled()
        guard let manifestData else {
            recordBackupArchiveIssue(
                "backup.restore.missing_manifest",
                path: manifestPath
            )
            throw BackupArchiveError.missingManifest
        }
        _ = try decodeManifest(from: manifestData)
        report(totalBytes, totalBytes, loc("原文件已暂存"))
        shouldCleanupStageOnExit = false
        return EmbeddedFileRestoreTransaction(
            stageRoot: stageRoot,
            photoStage: photoStage,
            drawingStage: drawingStage,
            documentStage: documentStage,
            quickNoteStage: quickNoteStage,
            counts: counts
        )
    }
}
