import Foundation

extension BackupArchiveService {
    static func makeArchive(from snapshot: BackupSnapshot) throws -> BackupArchive {
        try makeArchive(from: snapshot, progress: nil, shouldCancel: nil)
    }

    static func makeArchive(
        from snapshot: BackupSnapshot,
        progress: ((BackupArchiveProgress) -> Void)?,
        shouldCancel: (() -> Bool)?,
        temporaryFilePrefix: String = "backup-archive"
    ) throws -> BackupArchive {
        let metadataSnapshot = snapshot.withoutEmbeddedFiles()
        let metadata = try encodeMetadata(metadataSnapshot)
        let manifest = try encodeManifest(from: metadataSnapshot)
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: temporaryFilePrefix)
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

        let readme = makeReadme(
            includedFileCount: includedFileCount,
            missingFiles: missingFiles,
            metadataBytes: metadata.count,
            rawFilesBytes: rawFilesBytes
        )
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
        collectFileSizes(
            paths: photoFileNames(from: snapshot),
            displayName: loc("照片"),
            typeKey: "photos",
            exists: PhotoStorage.exists(fileName:),
            size: PhotoStorage.fileSize(for:),
            missingFiles: &missingFiles,
            rawFilesBytes: &rawFilesBytes
        )
        collectFileSizes(
            paths: snapshot.projectDrawings.map(\.fileName),
            displayName: loc("图纸"),
            typeKey: "drawings",
            exists: DrawingStorage.exists(fileName:),
            size: DrawingStorage.fileSize(for:),
            missingFiles: &missingFiles,
            rawFilesBytes: &rawFilesBytes
        )
        collectFileSizes(
            paths: snapshot.projectDocuments.map(\.fileName),
            displayName: loc("项目资料"),
            typeKey: "project-documents",
            exists: ProjectDocumentStorage.exists(fileName:),
            size: ProjectDocumentStorage.fileSize(for:),
            missingFiles: &missingFiles,
            rawFilesBytes: &rawFilesBytes
        )
        collectFileSizes(
            paths: quickNoteAttachmentNames(from: snapshot),
            displayName: loc("随手记/工艺附件"),
            typeKey: "quick-note-attachments",
            exists: QuickNoteAttachmentStorage.exists(fileName:),
            size: QuickNoteAttachmentStorage.fileSize(for:),
            missingFiles: &missingFiles,
            rawFilesBytes: &rawFilesBytes
        )
        return BackupArchiveEstimate(
            metadataBytes: metadataBytes,
            rawFilesBytes: rawFilesBytes,
            missingFiles: missingFiles
        )
    }
}

extension BackupArchiveService {
    static func addFiles(
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

    static func collectFileSizes(
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

    static func photoFileNames(from snapshot: BackupSnapshot) -> [String] {
        snapshot.dailyLogs.flatMap(\.allPhotoFileNames)
            + snapshot.siteTodos.compactMap(\.rectificationBeforePhotoFileName)
            + snapshot.siteTodos.compactMap(\.rectificationAfterPhotoFileName)
    }

    static func estimatedStepCount(from snapshot: BackupSnapshot) -> Int {
        var total = 3 // manifest + metadata + readme
        total += uniqueFileCount(photoFileNames(from: snapshot))
        total += uniqueFileCount(snapshot.projectDrawings.map(\.fileName))
        total += uniqueFileCount(snapshot.projectDocuments.map(\.fileName))
        total += uniqueFileCount(quickNoteAttachmentNames(from: snapshot))
        return max(total, 1)
    }

    static func uniqueFileCount(_ paths: [String]) -> Int {
        Set(paths.filter { !$0.isEmpty }).count
    }

    static func quickNoteAttachmentNames(from snapshot: BackupSnapshot) -> [String] {
        snapshot.quickNotes.flatMap { $0.attachments.map(\.fileName) }
            + snapshot.constructionMethods.flatMap(\.attachments).map(\.fileName)
            + snapshot.constructionMethods.flatMap(\.tutorialAttachments).map(\.fileName)
    }

    static func makeReadme(includedFileCount: Int, missingFiles: [String], metadataBytes: Int, rawFilesBytes: Int) -> String {
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
