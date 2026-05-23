import Foundation

enum BackupArchiveService {
    static var largeArchiveWarningBytes: Int { TransferLimitPolicy.backupArchiveWarningBytes }
    static let manifestPath = "manifest.json"
    static let metadataPath = "data/backup.json"
    private static let readmePath = "README.txt"
    static let photoPrefix = "files/photos/"
    static let drawingPrefix = "files/drawings/"
    static let documentPrefix = "files/project-documents/"
    static let quickNotePrefix = "files/quick-note-attachments/"

    static func loc(_ key: String) -> String {
        String(localized: String.LocalizationValue(stringLiteral: key))
    }

    static func locFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: loc(key), arguments: arguments)
    }

    static func makeArchive(from snapshot: BackupSnapshot) throws -> BackupArchive {
        try makeArchive(from: snapshot, progress: nil, shouldCancel: nil)
    }

    static func makeArchive(
        from snapshot: BackupSnapshot,
        progress: ((BackupArchiveProgress) -> Void)?,
        shouldCancel: (() -> Bool)?
    ) throws -> BackupArchive {
        let metadataSnapshot = snapshot.withoutEmbeddedFiles()
        let metadata = try encodeMetadata(metadataSnapshot)
        let manifest = try encodeManifest(from: metadataSnapshot)
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "backup-archive")
        var zip = try StreamingZipArchiveWriter(fileURL: archiveURL)
        var writerFinished = false
        defer {
            if !writerFinished {
                do {
                    try zip.close()
                } catch {
                    recordBackupArchiveIssue(
                        "backup.archive.close_failed",
                        fileName: archiveURL.lastPathComponent,
                        error: error
                    )
                }
                do {
                    _ = try FileOps.removeIfExists(
                        at: archiveURL,
                        context: .init(
                            event: "backup.archive.temp_cleanup",
                            category: .zipArchive,
                            source: "BackupArchiveService.makeArchive"
                        )
                    )
                } catch {
                    recordBackupArchiveIssue(
                        "backup.archive.temp_cleanup_failed",
                        fileName: archiveURL.lastPathComponent,
                        error: error
                    )
                }
            }
        }
        var includedFileCount = 0
        var missingFiles: [String] = []
        var rawFilesBytes = 0
        let totalSteps = estimatedStepCount(from: snapshot)
        var completedSteps = 0
        func failIfCancelled() throws {
            if shouldCancel?() == true || Task.isCancelled {
                throw BackupArchiveError.cancelled
            }
        }
        func reportProgress(_ item: String) {
            completedSteps += 1
            progress?(BackupArchiveProgress(completedSteps: completedSteps, totalSteps: totalSteps, currentItem: item))
        }

        try failIfCancelled()
        try zip.addFile(path: manifestPath, data: manifest)
        reportProgress(loc("写入备份清单"))
        try failIfCancelled()
        try zip.addFile(path: metadataPath, data: metadata)
        reportProgress(loc("写入数据索引"))
        try addFiles(
            paths: photoFileNames(from: snapshot),
            prefix: photoPrefix,
            displayName: loc("照片"),
            typeKey: "photos",
            fileURLProvider: PhotoStorage.fileURL(for:),
            sizeProvider: PhotoStorage.fileSize(for:),
            zip: &zip,
            includedFileCount: &includedFileCount,
            missingFiles: &missingFiles,
            rawFilesBytes: &rawFilesBytes,
            shouldCancel: failIfCancelled,
            onStep: reportProgress
        )
        try addFiles(
            paths: snapshot.projectDrawings.map(\.fileName),
            prefix: drawingPrefix,
            displayName: loc("图纸"),
            typeKey: "drawings",
            fileURLProvider: DrawingStorage.fileURL(for:),
            sizeProvider: DrawingStorage.fileSize(for:),
            zip: &zip,
            includedFileCount: &includedFileCount,
            missingFiles: &missingFiles,
            rawFilesBytes: &rawFilesBytes,
            shouldCancel: failIfCancelled,
            onStep: reportProgress
        )
        try addFiles(
            paths: snapshot.projectDocuments.map(\.fileName),
            prefix: documentPrefix,
            displayName: loc("项目资料"),
            typeKey: "project-documents",
            fileURLProvider: ProjectDocumentStorage.fileURL(for:),
            sizeProvider: ProjectDocumentStorage.fileSize(for:),
            zip: &zip,
            includedFileCount: &includedFileCount,
            missingFiles: &missingFiles,
            rawFilesBytes: &rawFilesBytes,
            shouldCancel: failIfCancelled,
            onStep: reportProgress
        )
        try addFiles(
            paths: quickNoteAttachmentNames(from: snapshot),
            prefix: quickNotePrefix,
            displayName: loc("随手记/工艺附件"),
            typeKey: "quick-note-attachments",
            fileURLProvider: QuickNoteAttachmentStorage.fileURL(for:),
            sizeProvider: QuickNoteAttachmentStorage.fileSize(for:),
            zip: &zip,
            includedFileCount: &includedFileCount,
            missingFiles: &missingFiles,
            rawFilesBytes: &rawFilesBytes,
            shouldCancel: failIfCancelled,
            onStep: reportProgress
        )

        let readme = makeReadme(includedFileCount: includedFileCount, missingFiles: missingFiles, metadataBytes: metadata.count, rawFilesBytes: rawFilesBytes)
        try failIfCancelled()
        try zip.addFile(path: readmePath, data: Data(readme.utf8))
        reportProgress(loc("写入说明文件"))

        let finishedURL = try zip.finish()
        writerFinished = true
        return BackupArchive(
            fileURL: finishedURL,
            includedFileCount: includedFileCount,
            missingFiles: missingFiles,
            metadataBytes: metadata.count,
            rawFilesBytes: rawFilesBytes
        )
    }

    static func estimateArchive(from snapshot: BackupSnapshot) -> BackupArchiveEstimate {
        let metadataBytes: Int
        do {
            metadataBytes = try encodeMetadata(snapshot.withoutEmbeddedFiles()).count
        } catch {
            recordBackupArchiveIssue(
                "backup.archive.estimate_metadata_encode_failed",
                error: error
            )
            metadataBytes = 0
        }
        var missingFiles: [String] = []
        var rawFilesBytes = 0
        collectFileSizes(paths: photoFileNames(from: snapshot), displayName: loc("照片"), typeKey: "photos", exists: PhotoStorage.exists(fileName:), size: PhotoStorage.fileSize(for:), missingFiles: &missingFiles, rawFilesBytes: &rawFilesBytes)
        collectFileSizes(paths: snapshot.projectDrawings.map(\.fileName), displayName: loc("图纸"), typeKey: "drawings", exists: DrawingStorage.exists(fileName:), size: DrawingStorage.fileSize(for:), missingFiles: &missingFiles, rawFilesBytes: &rawFilesBytes)
        collectFileSizes(paths: snapshot.projectDocuments.map(\.fileName), displayName: loc("项目资料"), typeKey: "project-documents", exists: ProjectDocumentStorage.exists(fileName:), size: ProjectDocumentStorage.fileSize(for:), missingFiles: &missingFiles, rawFilesBytes: &rawFilesBytes)
        collectFileSizes(paths: quickNoteAttachmentNames(from: snapshot), displayName: loc("随手记/工艺附件"), typeKey: "quick-note-attachments", exists: QuickNoteAttachmentStorage.exists(fileName:), size: QuickNoteAttachmentStorage.fileSize(for:), missingFiles: &missingFiles, rawFilesBytes: &rawFilesBytes)
        return BackupArchiveEstimate(metadataBytes: metadataBytes, rawFilesBytes: rawFilesBytes, missingFiles: missingFiles)
    }

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

    private static func decodeJSONSnapshot(from data: Data) throws -> BackupSnapshot {
        let header = try JSONDecoder().decode(BackupSchemaHeader.self, from: data)
        try validateSupportedSchemaVersion(header.schemaVersion)
        return try JSONDecoder().decode(BackupSnapshot.self, from: data)
    }

    static func decodeManifest(from data: Data) throws -> BackupArchiveManifest {
        let manifest = try JSONDecoder().decode(BackupArchiveManifest.self, from: data)
        try validateSupportedSchemaVersion(manifest.schemaVersion)
        guard manifest.metadataPath == metadataPath else {
            throw BackupArchiveError.invalidBackup
        }
        return manifest
    }

    private static func encodeManifest(from snapshot: BackupSnapshot) throws -> Data {
        let manifest = BackupArchiveManifest(
            schemaVersion: snapshot.schemaVersion,
            appVersion: snapshot.appVersion,
            appBuild: snapshot.appBuild,
            appName: AppBrand.displayName,
            exportedAt: snapshot.backupCreatedAt,
            metadataPath: metadataPath
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(manifest)
        } catch {
            throw BackupArchiveError.encodingFailed
        }
    }

    private static func validateSupportedSchemaVersion(_ version: Int) throws {
        guard version == BackupSnapshot.currentSchemaVersion else {
            throw BackupArchiveError.unsupportedSchemaVersion(version)
        }
    }

    private static func encodeMetadata(_ snapshot: BackupSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(snapshot)
        } catch {
            throw BackupArchiveError.encodingFailed
        }
    }

    private static func addFiles(
        paths: [String],
        prefix: String,
        displayName: String,
        typeKey: String,
        fileURLProvider: (String) -> URL,
        sizeProvider: (String) -> Int,
        zip: inout StreamingZipArchiveWriter,
        includedFileCount: inout Int,
        missingFiles: inout [String],
        rawFilesBytes: inout Int,
        shouldCancel: () throws -> Void,
        onStep: (String) -> Void
    ) throws {
        var seen = Set<String>()
        for fileName in paths where !fileName.isEmpty && !seen.contains(fileName) {
            try shouldCancel()
            seen.insert(fileName)
            let sourceURL = fileURLProvider(fileName)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                missingFiles.append("\(displayName) \(fileName)")
                recordBackupArchiveIssue(
                    "backup.archive.source_file_missing",
                    fileName: fileName,
                    type: typeKey
                )
                onStep(locFormat("检查%@ %@", displayName, fileName))
                continue
            }

            do {
                try zip.addFile(path: prefix + fileName, sourceFileURL: sourceURL)
            } catch {
                recordBackupArchiveIssue(
                    "backup.archive.source_file_write_failed",
                    fileName: fileName,
                    path: prefix + fileName,
                    type: typeKey,
                    error: error
                )
                throw error
            }
            includedFileCount += 1
            let estimatedFileSize = max(sizeProvider(fileName), QuickNoteAttachmentStorage.fileSize(at: sourceURL))
            rawFilesBytes += estimatedFileSize
            onStep(locFormat("打包%@ %@", displayName, fileName))
        }
    }

    private static func collectFileSizes(
        paths: [String],
        displayName: String,
        typeKey: String,
        exists: (String) -> Bool,
        size: (String) -> Int,
        missingFiles: inout [String],
        rawFilesBytes: inout Int
    ) {
        var seen = Set<String>()
        for fileName in paths where !fileName.isEmpty && !seen.contains(fileName) {
            seen.insert(fileName)
            guard exists(fileName) else {
                missingFiles.append("\(displayName) \(fileName)")
                recordBackupArchiveIssue(
                    "backup.archive.estimate_source_file_missing",
                    fileName: fileName,
                    type: typeKey
                )
                continue
            }
            rawFilesBytes += size(fileName)
        }
    }

    static func leafFileName(for path: String, prefix: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        let fileName = String(path.dropFirst(prefix.count))
        guard !fileName.isEmpty, !fileName.contains("/") else { return nil }
        return fileName
    }

    private static func photoFileNames(from snapshot: BackupSnapshot) -> [String] {
        snapshot.dailyLogs.flatMap(\.allPhotoFileNames) + snapshot.siteTodos.compactMap(\.rectificationBeforePhotoFileName) + snapshot.siteTodos.compactMap(\.rectificationAfterPhotoFileName)
    }

    private static func estimatedStepCount(from snapshot: BackupSnapshot) -> Int {
        var total = 3 // manifest + metadata + readme
        total += uniqueFileCount(photoFileNames(from: snapshot))
        total += uniqueFileCount(snapshot.projectDrawings.map(\.fileName))
        total += uniqueFileCount(snapshot.projectDocuments.map(\.fileName))
        total += uniqueFileCount(quickNoteAttachmentNames(from: snapshot))
        return max(total, 1)
    }

    private static func uniqueFileCount(_ paths: [String]) -> Int {
        Set(paths.filter { !$0.isEmpty }).count
    }

    private static func quickNoteAttachmentNames(from snapshot: BackupSnapshot) -> [String] {
        snapshot.quickNotes.flatMap { $0.attachments.map(\.fileName) }
            + snapshot.constructionMethods.flatMap(\.attachments).map(\.fileName)
            + snapshot.constructionMethods.flatMap(\.tutorialAttachments).map(\.fileName)
    }

    private static func makeReadme(includedFileCount: Int, missingFiles: [String], metadataBytes: Int, rawFilesBytes: Int) -> String {
        [
            locFormat("%@ 备份包", AppBrand.displayName),
            locFormat("生成时间: %@", Formatters.now()),
            locFormat("备份格式: schema %lld", Int64(BackupSnapshot.currentSchemaVersion)),
            locFormat("应用版本: %@ (%@)", AppBrand.appVersion, AppBrand.appBuild),
            locFormat("清单文件: %@", manifestPath),
            locFormat("数据索引: %@", metadataPath),
            locFormat("原文件数量: %lld", Int64(includedFileCount)),
            locFormat("数据索引大小: %@", QuickNoteAttachmentStorage.formattedFileSize(metadataBytes)),
            locFormat("原文件大小: %@", QuickNoteAttachmentStorage.formattedFileSize(rawFilesBytes)),
            locFormat("缺失文件: %lld", Int64(missingFiles.count)),
            "",
            loc("目录:"),
            locFormat("%@ 现场照片和整改照片", photoPrefix),
            locFormat("%@ DWG/DXF/PDF 图纸", drawingPrefix),
            locFormat("%@ 票据和项目资料", documentPrefix),
            locFormat("%@ 随手记媒体与工艺教程附件", quickNotePrefix),
            "",
            missingFiles.isEmpty ? loc("未发现缺失原文件。") : loc("缺失原文件:") + "\n" + missingFiles.joined(separator: "\n")
        ].joined(separator: "\n")
    }
}

private extension BackupSnapshot {
    func withoutEmbeddedFiles() -> BackupSnapshot {
        var copy = self
        copy.photoFiles = []
        copy.drawingFiles = []
        copy.documentFiles = []
        copy.quickNoteAttachmentFiles = []
        return copy
    }
}
