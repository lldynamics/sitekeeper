import Foundation

extension BackupArchiveService {
    static func previewBackup(
        from fileURL: URL,
        progress: ((BackupImportProgress) -> Void)? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) throws -> BackupImportPreview {
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
        if ext == "json" {
            recordBackupArchiveIssue(
                "backup.archive.preview_json_rejected",
                fileName: fileURL.lastPathComponent
            )
            throw BackupArchiveError.invalidBackup
        }

        let contents = try scanReadContents(
            from: fileURL, limits: .backup, includeEmbeddedData: false,
            shouldCancel: shouldCancel, failureEvent: "backup.archive.preview_scan_failed",
            onProgress: { completed, total, path in report(completed, total, locFormat("扫描 %@", path)) }
        )

        try failIfCancelled()
        let (metadataData, manifestData) = try contents.validatedMetadataData(eventPrefix: "preview")
        let manifest = try decodeManifest(from: manifestData)
        let snapshot = try decodeJSONSnapshot(from: metadataData)
        report(totalBytes, totalBytes, loc("读取完成"))
        return BackupImportPreview(
            snapshot: snapshot.withoutEmbeddedFiles(),
            manifest: manifest,
            incomingFiles: BackupFileImpactSummary(
                photoFileNames: contents.photoFileNames,
                drawingFileNames: contents.drawingFileNames,
                documentFileNames: contents.documentFileNames,
                quickNoteAttachmentFileNames: contents.quickNoteAttachmentFileNames
            ),
            overwrittenLocalFiles: BackupFileImpactSummary()
        )
    }

    static func decodeBackup(
        from fileURL: URL,
        progress: ((BackupImportProgress) -> Void)? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) throws -> BackupSnapshot {
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
        if ext == "json" {
            recordBackupArchiveIssue(
                "backup.archive.decode_json_rejected",
                fileName: fileURL.lastPathComponent
            )
            throw BackupArchiveError.invalidBackup
        }

        let contents = try scanReadContents(
            from: fileURL, limits: .inMemory, includeEmbeddedData: true,
            shouldCancel: shouldCancel, failureEvent: "backup.archive.decode_scan_failed",
            onProgress: { completed, total, path in report(completed, total, locFormat("读取 %@", path)) }
        )

        try failIfCancelled()
        let (metadataData, manifestData) = try contents.validatedMetadataData(eventPrefix: "decode")
        _ = try decodeManifest(from: manifestData)
        var snapshot = try decodeJSONSnapshot(from: metadataData)
        snapshot.photoFiles = contents.photoFiles
        snapshot.drawingFiles = contents.drawingFiles
        snapshot.documentFiles = contents.documentFiles
        snapshot.quickNoteAttachmentFiles = contents.quickNoteAttachmentFiles
        report(totalBytes, totalBytes, loc("解析完成"))
        return snapshot
    }
    private static func scanReadContents(
        from fileURL: URL, limits: BackupArchiveLimits, includeEmbeddedData: Bool,
        shouldCancel: (() -> Bool)?, failureEvent: String,
        onProgress: ((Int64, Int64, String) -> Void)?
    ) throws -> BackupArchiveReadContents {
        var contents = BackupArchiveReadContents()
        do {
            try SimpleZipArchiveReader.scan(
                fileURL: fileURL, limits: limits,
                shouldCancel: { shouldCancel?() == true || Task.isCancelled },
                onProgress: onProgress,
                onEntry: { entry, readData, _ in
                    if shouldCancel?() == true || Task.isCancelled { throw BackupArchiveError.cancelled }
                    try contents.accept(path: entry.path, readData: readData, includeEmbeddedData: includeEmbeddedData)
                }
            )
        } catch SimpleZipArchiveReader.ZipReadError.cancelled {
            throw BackupArchiveError.cancelled
        } catch {
            recordBackupArchiveIssue(failureEvent, fileName: fileURL.lastPathComponent, error: error)
            throw error
        }
        return contents
    }
}
