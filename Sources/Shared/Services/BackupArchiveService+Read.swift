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

        var metadataData: Data?
        var manifestData: Data?
        var photoFileNames: [String] = []
        var drawingFileNames: [String] = []
        var documentFileNames: [String] = []
        var quickNoteAttachmentFileNames: [String] = []

        do {
            try SimpleZipArchiveReader.scan(
                fileURL: fileURL,
                shouldCancel: { shouldCancel?() == true || Task.isCancelled },
                onProgress: { completed, total, path in
                    report(completed, total, locFormat("扫描 %@", path))
                },
                onEntry: { entry, readData, _ in
                    try failIfCancelled()
                    if entry.path == metadataPath {
                        metadataData = try readData()
                        return
                    }
                    if entry.path == manifestPath {
                        manifestData = try readData()
                        return
                    }
                    if let fileName = leafFileName(for: entry.path, prefix: photoPrefix) {
                        photoFileNames.append(fileName)
                        return
                    }
                    if let fileName = leafFileName(for: entry.path, prefix: drawingPrefix) {
                        drawingFileNames.append(fileName)
                        return
                    }
                    if let fileName = leafFileName(for: entry.path, prefix: documentPrefix) {
                        documentFileNames.append(fileName)
                        return
                    }
                    if let fileName = leafFileName(for: entry.path, prefix: quickNotePrefix) {
                        quickNoteAttachmentFileNames.append(fileName)
                    }
                }
            )
        } catch SimpleZipArchiveReader.ZipReadError.cancelled {
            throw BackupArchiveError.cancelled
        } catch {
            recordBackupArchiveIssue(
                "backup.archive.preview_scan_failed",
                fileName: fileURL.lastPathComponent,
                error: error
            )
            throw error
        }

        try failIfCancelled()
        guard let metadataData else {
            recordBackupArchiveIssue(
                "backup.archive.preview_missing_metadata",
                path: metadataPath
            )
            throw BackupArchiveError.missingMetadata
        }
        guard let manifestData else {
            recordBackupArchiveIssue(
                "backup.archive.preview_missing_manifest",
                path: manifestPath
            )
            throw BackupArchiveError.missingManifest
        }
        let manifest = try decodeManifest(from: manifestData)
        let snapshot = try decodeJSONSnapshot(from: metadataData)
        report(totalBytes, totalBytes, loc("读取完成"))
        return BackupImportPreview(
            snapshot: snapshot.withoutEmbeddedFiles(),
            manifest: manifest,
            incomingFiles: BackupFileImpactSummary(
                photoFileNames: photoFileNames,
                drawingFileNames: drawingFileNames,
                documentFileNames: documentFileNames,
                quickNoteAttachmentFileNames: quickNoteAttachmentFileNames
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

        var metadataData: Data?
        var manifestData: Data?
        var photoFiles: [PhotoBackupFile] = []
        var drawingFiles: [DrawingBackupFile] = []
        var documentFiles: [ProjectDocumentBackupFile] = []
        var quickNoteAttachmentFiles: [QuickNoteAttachmentBackupFile] = []

        do {
            try SimpleZipArchiveReader.scan(
                fileURL: fileURL,
                shouldCancel: { shouldCancel?() == true || Task.isCancelled },
                onProgress: { completed, total, path in
                    report(completed, total, locFormat("读取 %@", path))
                },
                onEntry: { entry, readData, _ in
                    try failIfCancelled()
                    if entry.path == metadataPath {
                        metadataData = try readData()
                        return
                    }
                    if entry.path == manifestPath {
                        manifestData = try readData()
                        return
                    }
                    if let fileName = leafFileName(for: entry.path, prefix: photoPrefix) {
                        photoFiles.append(PhotoBackupFile(fileName: fileName, data: try readData()))
                        return
                    }
                    if let fileName = leafFileName(for: entry.path, prefix: drawingPrefix) {
                        drawingFiles.append(DrawingBackupFile(fileName: fileName, data: try readData()))
                        return
                    }
                    if let fileName = leafFileName(for: entry.path, prefix: documentPrefix) {
                        documentFiles.append(ProjectDocumentBackupFile(fileName: fileName, data: try readData()))
                        return
                    }
                    if let fileName = leafFileName(for: entry.path, prefix: quickNotePrefix) {
                        quickNoteAttachmentFiles.append(QuickNoteAttachmentBackupFile(fileName: fileName, data: try readData()))
                    }
                }
            )
        } catch SimpleZipArchiveReader.ZipReadError.cancelled {
            throw BackupArchiveError.cancelled
        } catch {
            recordBackupArchiveIssue(
                "backup.archive.decode_scan_failed",
                fileName: fileURL.lastPathComponent,
                error: error
            )
            throw error
        }

        try failIfCancelled()
        guard let metadataData else {
            recordBackupArchiveIssue(
                "backup.archive.decode_missing_metadata",
                path: metadataPath
            )
            throw BackupArchiveError.missingMetadata
        }
        guard let manifestData else {
            recordBackupArchiveIssue(
                "backup.archive.decode_missing_manifest",
                path: manifestPath
            )
            throw BackupArchiveError.missingManifest
        }
        _ = try decodeManifest(from: manifestData)
        var snapshot = try decodeJSONSnapshot(from: metadataData)
        snapshot.photoFiles = photoFiles
        snapshot.drawingFiles = drawingFiles
        snapshot.documentFiles = documentFiles
        snapshot.quickNoteAttachmentFiles = quickNoteAttachmentFiles
        report(totalBytes, totalBytes, loc("解析完成"))
        return snapshot
    }
}
