import Foundation

private enum BackupArchiveDataCache {
    static let storage = NSCache<NSString, NSData>()
}

struct BackupArchive {
    let fileURL: URL
    let includedFileCount: Int
    let missingFiles: [String]
    let metadataBytes: Int
    let rawFilesBytes: Int

    var totalBytes: Int { QuickNoteAttachmentStorage.fileSize(at: fileURL) }

    // 兼容旧调用：需要内存数据时按需读取。
    @available(*, deprecated, message: "请优先使用 fileURL 流式读取，避免整包加载到内存。")
    var data: Data {
        let cacheKey = fileURL.path as NSString
        if let cached = BackupArchiveDataCache.storage.object(forKey: cacheKey) {
            return Data(referencing: cached)
        }
        do {
            let loaded = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            BackupArchiveDataCache.storage.setObject(loaded as NSData, forKey: cacheKey)
            return loaded
        } catch {
            StorageIssueLog.record("备份归档读取失败：\(fileURL.lastPathComponent)，\(error.localizedDescription)")
            return Data()
        }
    }

    func loadData() async -> Data {
        let cacheKey = fileURL.path as NSString
        if let cached = BackupArchiveDataCache.storage.object(forKey: cacheKey) {
            return Data(referencing: cached)
        }
        return await Task.detached(priority: .utility) {
            do {
                let loaded = try Data(contentsOf: fileURL, options: .mappedIfSafe)
                BackupArchiveDataCache.storage.setObject(loaded as NSData, forKey: cacheKey)
                return loaded
            } catch {
                StorageIssueLog.record("备份归档异步读取失败：\(fileURL.lastPathComponent)，\(error.localizedDescription)")
                return Data()
            }
        }.value
    }
}

struct BackupArchiveEstimate {
    let metadataBytes: Int
    let rawFilesBytes: Int
    let missingFiles: [String]

    var estimatedBytes: Int { metadataBytes + rawFilesBytes }
}

struct BackupArchiveProgress {
    let completedSteps: Int
    let totalSteps: Int
    let currentItem: String

    var fractionCompleted: Double {
        guard totalSteps > 0 else { return 0 }
        return min(max(Double(completedSteps) / Double(totalSteps), 0), 1)
    }
}

struct BackupImportProgress {
    let completedBytes: Int64
    let totalBytes: Int64
    let currentItem: String

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }
}

struct BackupImportPreview {
    let snapshot: BackupSnapshot
    let photoFileCount: Int
    let drawingFileCount: Int
    let documentFileCount: Int
    let quickNoteAttachmentFileCount: Int
}

struct BackupEmbeddedRestoreCounts {
    var photoFileCount = 0
    var drawingFileCount = 0
    var documentFileCount = 0
    var quickNoteAttachmentFileCount = 0

    var totalCount: Int {
        photoFileCount + drawingFileCount + documentFileCount + quickNoteAttachmentFileCount
    }
}

enum BackupArchiveError: LocalizedError {
    case encodingFailed
    case missingMetadata
    case invalidBackup
    case restoreFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "备份数据编码失败。"
        case .missingMetadata:
            return "备份 ZIP 缺少数据索引。"
        case .invalidBackup:
            return "备份文件格式不正确。"
        case .restoreFailed(let reason):
            return reason
        case .cancelled:
            return "已取消备份导出。"
        }
    }

}

enum BackupArchiveService {
    static var largeArchiveWarningBytes: Int { TransferLimitPolicy.backupArchiveWarningBytes }
    static let metadataPath = "data/backup.json"
    private static let readmePath = "README.txt"
    private static let photoPrefix = "files/photos/"
    private static let drawingPrefix = "files/drawings/"
    private static let documentPrefix = "files/project-documents/"
    private static let quickNotePrefix = "files/quick-note-attachments/"

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
        let archiveURL = StreamingZipArchiveWriter.makeTemporaryFileURL(prefix: "backup-archive")
        var zip = try StreamingZipArchiveWriter(fileURL: archiveURL)
        var writerFinished = false
        defer {
            if !writerFinished {
                do {
                    try zip.close()
                } catch {
                    StorageIssueLog.record("备份归档关闭失败：\(archiveURL.lastPathComponent)，\(error.localizedDescription)")
                }
                do {
                    try FileManager.default.removeItem(at: archiveURL)
                } catch {
                    StorageIssueLog.record("备份归档临时文件清理失败：\(archiveURL.lastPathComponent)，\(error.localizedDescription)")
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
        try zip.addFile(path: metadataPath, data: metadata)
        reportProgress("写入数据索引")
        try addFiles(
            paths: photoFileNames(from: snapshot),
            prefix: photoPrefix,
            displayName: "照片",
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
            displayName: "图纸",
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
            displayName: "项目资料",
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
            displayName: "随手记/工艺附件",
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
        reportProgress("写入说明文件")

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
            StorageIssueLog.record("备份体积估算失败：索引编码失败，\(error.localizedDescription)")
            metadataBytes = 0
        }
        var missingFiles: [String] = []
        var rawFilesBytes = 0
        collectFileSizes(paths: photoFileNames(from: snapshot), displayName: "照片", exists: PhotoStorage.exists(fileName:), size: PhotoStorage.fileSize(for:), missingFiles: &missingFiles, rawFilesBytes: &rawFilesBytes)
        collectFileSizes(paths: snapshot.projectDrawings.map(\.fileName), displayName: "图纸", exists: DrawingStorage.exists(fileName:), size: DrawingStorage.fileSize(for:), missingFiles: &missingFiles, rawFilesBytes: &rawFilesBytes)
        collectFileSizes(paths: snapshot.projectDocuments.map(\.fileName), displayName: "项目资料", exists: ProjectDocumentStorage.exists(fileName:), size: ProjectDocumentStorage.fileSize(for:), missingFiles: &missingFiles, rawFilesBytes: &rawFilesBytes)
        collectFileSizes(paths: quickNoteAttachmentNames(from: snapshot), displayName: "随手记/工艺附件", exists: QuickNoteAttachmentStorage.exists(fileName:), size: QuickNoteAttachmentStorage.fileSize(for:), missingFiles: &missingFiles, rawFilesBytes: &rawFilesBytes)
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
            report(0, totalBytes, "读取备份索引")
            let data: Data
            do {
                data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            } catch {
                StorageIssueLog.record("备份预览读取失败：\(fileURL.lastPathComponent)，\(error.localizedDescription)")
                throw error
            }
            try failIfCancelled()
            let snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: data)
            report(totalBytes, totalBytes, "读取完成")
            return BackupImportPreview(
                snapshot: snapshot.withoutEmbeddedFiles(),
                photoFileCount: snapshot.photoFiles.count,
                drawingFileCount: snapshot.drawingFiles.count,
                documentFileCount: snapshot.documentFiles.count,
                quickNoteAttachmentFileCount: snapshot.quickNoteAttachmentFiles.count
            )
        }

        var metadataData: Data?
        var photoCount = 0
        var drawingCount = 0
        var documentCount = 0
        var quickNoteAttachmentCount = 0

        do {
            try SimpleZipArchiveReader.scan(
                fileURL: fileURL,
                shouldCancel: { shouldCancel?() == true || Task.isCancelled },
                onProgress: { completed, total, path in
                    report(completed, total, "扫描 \(path)")
                },
                onEntry: { entry, readData, _ in
                    try failIfCancelled()
                    if entry.path == metadataPath {
                        metadataData = try readData()
                        return
                    }
                    if leafFileName(for: entry.path, prefix: photoPrefix) != nil {
                        photoCount += 1
                        return
                    }
                    if leafFileName(for: entry.path, prefix: drawingPrefix) != nil {
                        drawingCount += 1
                        return
                    }
                    if leafFileName(for: entry.path, prefix: documentPrefix) != nil {
                        documentCount += 1
                        return
                    }
                    if leafFileName(for: entry.path, prefix: quickNotePrefix) != nil {
                        quickNoteAttachmentCount += 1
                    }
                }
            )
        } catch SimpleZipArchiveReader.ZipReadError.cancelled {
            throw BackupArchiveError.cancelled
        } catch {
            StorageIssueLog.record("备份预览扫描失败：\(fileURL.lastPathComponent)，\(error.localizedDescription)")
            throw error
        }

        try failIfCancelled()
        guard let metadataData else {
            StorageIssueLog.record("备份预览失败：缺少数据索引 \(metadataPath)")
            throw BackupArchiveError.missingMetadata
        }
        let snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: metadataData)
        report(totalBytes, totalBytes, "读取完成")
        return BackupImportPreview(
            snapshot: snapshot.withoutEmbeddedFiles(),
            photoFileCount: photoCount,
            drawingFileCount: drawingCount,
            documentFileCount: documentCount,
            quickNoteAttachmentFileCount: quickNoteAttachmentCount
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
            report(0, totalBytes, "读取旧版备份")
            let data: Data
            do {
                data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            } catch {
                StorageIssueLog.record("备份解码读取失败：\(fileURL.lastPathComponent)，\(error.localizedDescription)")
                throw error
            }
            try failIfCancelled()
            report(totalBytes, totalBytes, "解析完成")
            return try decodeJSONSnapshot(from: data)
        }

        var metadataData: Data?
        var photoFiles: [PhotoBackupFile] = []
        var drawingFiles: [DrawingBackupFile] = []
        var documentFiles: [ProjectDocumentBackupFile] = []
        var quickNoteAttachmentFiles: [QuickNoteAttachmentBackupFile] = []

        do {
            try SimpleZipArchiveReader.scan(
                fileURL: fileURL,
                shouldCancel: { shouldCancel?() == true || Task.isCancelled },
                onProgress: { completed, total, path in
                    report(completed, total, "读取 \(path)")
                },
                onEntry: { entry, readData, _ in
                    try failIfCancelled()
                    if entry.path == metadataPath {
                        metadataData = try readData()
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
            StorageIssueLog.record("备份解码扫描失败：\(fileURL.lastPathComponent)，\(error.localizedDescription)")
            throw error
        }

        try failIfCancelled()
        guard let metadataData else {
            StorageIssueLog.record("备份解码失败：缺少数据索引 \(metadataPath)")
            throw BackupArchiveError.missingMetadata
        }
        var snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: metadataData)
        snapshot.photoFiles = photoFiles
        snapshot.drawingFiles = drawingFiles
        snapshot.documentFiles = documentFiles
        snapshot.quickNoteAttachmentFiles = quickNoteAttachmentFiles
        report(totalBytes, totalBytes, "解析完成")
        return snapshot
    }

    static func restoreEmbeddedFiles(
        from fileURL: URL,
        progress: ((BackupImportProgress) -> Void)? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) throws -> BackupEmbeddedRestoreCounts {
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

        let stageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-restore-\(UUID().uuidString)", isDirectory: true)
        let photoStage = stageRoot.appendingPathComponent("photos", isDirectory: true)
        let drawingStage = stageRoot.appendingPathComponent("drawings", isDirectory: true)
        let documentStage = stageRoot.appendingPathComponent("project-documents", isDirectory: true)
        let quickNoteStage = stageRoot.appendingPathComponent("quick-note-attachments", isDirectory: true)

        func stageData(_ data: Data, fileName: String, to directory: URL, failureMessage: String) throws {
            do {
                try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            } catch {
                StorageIssueLog.record("\(failureMessage)：\(fileName)，\(error.localizedDescription)")
                throw BackupArchiveError.restoreFailed("\(failureMessage)：\(fileName)")
            }
        }

        func stageEntry(
            _ writeEntryToFile: (URL) throws -> Void,
            fileName: String,
            to directory: URL,
            failureMessage: String
        ) throws {
            do {
                try writeEntryToFile(directory.appendingPathComponent(fileName))
            } catch BackupArchiveError.cancelled {
                throw BackupArchiveError.cancelled
            } catch SimpleZipArchiveReader.ZipReadError.cancelled {
                throw BackupArchiveError.cancelled
            } catch {
                StorageIssueLog.record("\(failureMessage)：\(fileName)，\(error.localizedDescription)")
                throw BackupArchiveError.restoreFailed("\(failureMessage)：\(fileName)")
            }
        }

        do {
            try FileManager.default.createDirectory(at: photoStage, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: drawingStage, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: documentStage, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: quickNoteStage, withIntermediateDirectories: true)
        } catch {
            StorageIssueLog.record("创建导入暂存目录失败：\(stageRoot.lastPathComponent)，\(error.localizedDescription)")
            throw BackupArchiveError.restoreFailed("创建导入暂存目录失败：\(error.localizedDescription)")
        }

        defer {
            do {
                try FileManager.default.removeItem(at: stageRoot)
            } catch {
                StorageIssueLog.record("备份导入暂存目录清理失败：\(stageRoot.lastPathComponent)，\(error.localizedDescription)")
            }
        }

        if ext == "json" {
            report(0, totalBytes, "读取旧版备份附件")
            let data: Data
            do {
                data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            } catch {
                StorageIssueLog.record("读取旧版备份附件失败：\(fileURL.lastPathComponent)，\(error.localizedDescription)")
                throw error
            }
            try failIfCancelled()
            let snapshot = try JSONDecoder().decode(BackupSnapshot.self, from: data)
            for file in snapshot.photoFiles {
                try failIfCancelled()
                try stageData(file.data, fileName: file.fileName, to: photoStage, failureMessage: "暂存照片失败")
                counts.photoFileCount += 1
            }
            for file in snapshot.drawingFiles {
                try failIfCancelled()
                try stageData(file.data, fileName: file.fileName, to: drawingStage, failureMessage: "暂存图纸失败")
                counts.drawingFileCount += 1
            }
            for file in snapshot.documentFiles {
                try failIfCancelled()
                try stageData(file.data, fileName: file.fileName, to: documentStage, failureMessage: "暂存项目资料失败")
                counts.documentFileCount += 1
            }
            for file in snapshot.quickNoteAttachmentFiles {
                try failIfCancelled()
                try stageData(file.data, fileName: file.fileName, to: quickNoteStage, failureMessage: "暂存随手记/工艺附件失败")
                counts.quickNoteAttachmentFileCount += 1
            }
        } else {
            do {
                try SimpleZipArchiveReader.scan(
                    fileURL: fileURL,
                    shouldCancel: { shouldCancel?() == true || Task.isCancelled },
                    onProgress: { completed, total, path in
                        report(completed, total, "恢复 \(path)")
                    },
                    onEntry: { entry, _, writeEntryToFile in
                        try failIfCancelled()
                        if let fileName = leafFileName(for: entry.path, prefix: photoPrefix) {
                            try stageEntry(writeEntryToFile, fileName: fileName, to: photoStage, failureMessage: "暂存照片失败")
                            counts.photoFileCount += 1
                            return
                        }
                        if let fileName = leafFileName(for: entry.path, prefix: drawingPrefix) {
                            try stageEntry(writeEntryToFile, fileName: fileName, to: drawingStage, failureMessage: "暂存图纸失败")
                            counts.drawingFileCount += 1
                            return
                        }
                        if let fileName = leafFileName(for: entry.path, prefix: documentPrefix) {
                            try stageEntry(writeEntryToFile, fileName: fileName, to: documentStage, failureMessage: "暂存项目资料失败")
                            counts.documentFileCount += 1
                            return
                        }
                        if let fileName = leafFileName(for: entry.path, prefix: quickNotePrefix) {
                            try stageEntry(writeEntryToFile, fileName: fileName, to: quickNoteStage, failureMessage: "暂存随手记/工艺附件失败")
                            counts.quickNoteAttachmentFileCount += 1
                        }
                    }
                )
            } catch SimpleZipArchiveReader.ZipReadError.cancelled {
                throw BackupArchiveError.cancelled
            } catch {
                StorageIssueLog.record("备份附件恢复扫描失败：\(fileURL.lastPathComponent)，\(error.localizedDescription)")
                throw error
            }
        }

        try failIfCancelled()
        report(totalBytes, totalBytes, "提交原文件")
        let restoredPhotoFileNames = try commitStagedFiles(from: photoStage, destinationURL: PhotoStorage.fileURL(for:))
        PhotoStorage.regenerateThumbnails(for: restoredPhotoFileNames)
        try commitStagedFiles(from: drawingStage, destinationURL: DrawingStorage.fileURL(for:))
        try commitStagedFiles(from: documentStage, destinationURL: ProjectDocumentStorage.fileURL(for:))
        try commitStagedFiles(from: quickNoteStage, destinationURL: QuickNoteAttachmentStorage.fileURL(for:))
        report(totalBytes, totalBytes, "恢复完成")
        return counts
    }

    @available(*, deprecated, message: "请优先使用 decodeBackup(from: fileURL) 流式解包，避免整包内存读取。")
    static func decodeBackup(from data: Data) throws -> BackupSnapshot {
        do {
            let jsonSnapshot = try decodeJSONSnapshot(from: data)
            return jsonSnapshot
        } catch {
            StorageIssueLog.record("旧版备份 JSON 解析失败，尝试按 ZIP 解析：\(error.localizedDescription)")
        }
        let entries = try SimpleZipArchiveReader.read(data)
        guard let metadata = entries.first(where: { $0.path == metadataPath })?.data else {
            throw BackupArchiveError.missingMetadata
        }
        var snapshot = try decodeJSONSnapshot(from: metadata)
        snapshot.photoFiles = entries.backupFiles(prefix: photoPrefix) { PhotoBackupFile(fileName: $0, data: $1) }
        snapshot.drawingFiles = entries.backupFiles(prefix: drawingPrefix) { DrawingBackupFile(fileName: $0, data: $1) }
        snapshot.documentFiles = entries.backupFiles(prefix: documentPrefix) { ProjectDocumentBackupFile(fileName: $0, data: $1) }
        snapshot.quickNoteAttachmentFiles = entries.backupFiles(prefix: quickNotePrefix) { QuickNoteAttachmentBackupFile(fileName: $0, data: $1) }
        return snapshot
    }

    private static func decodeJSONSnapshot(from data: Data) throws -> BackupSnapshot {
        try JSONDecoder().decode(BackupSnapshot.self, from: data)
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
                StorageIssueLog.record("备份打包缺失原文件：\(displayName) \(fileName)")
                onStep("检查\(displayName) \(fileName)")
                continue
            }

            do {
                try zip.addFile(path: prefix + fileName, sourceFileURL: sourceURL)
            } catch {
                StorageIssueLog.record("备份打包写入失败：\(displayName) \(fileName)，\(error.localizedDescription)")
                throw error
            }
            includedFileCount += 1
            let estimatedFileSize = max(sizeProvider(fileName), QuickNoteAttachmentStorage.fileSize(at: sourceURL))
            rawFilesBytes += estimatedFileSize
            onStep("打包\(displayName) \(fileName)")
        }
    }

    private static func collectFileSizes(
        paths: [String],
        displayName: String,
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
                StorageIssueLog.record("备份体积估算缺失原文件：\(displayName) \(fileName)")
                continue
            }
            rawFilesBytes += size(fileName)
        }
    }

    private static func leafFileName(for path: String, prefix: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        let fileName = String(path.dropFirst(prefix.count))
        guard !fileName.isEmpty, !fileName.contains("/") else { return nil }
        return fileName
    }

    @discardableResult
    private static func commitStagedFiles(from stageDirectory: URL, destinationURL: (String) -> URL) throws -> [String] {
        let manager = FileManager.default
        let files: [URL]
        do {
            files = try manager.contentsOfDirectory(at: stageDirectory, includingPropertiesForKeys: nil)
        } catch {
            StorageIssueLog.record("读取备份暂存目录失败：\(stageDirectory.lastPathComponent)，\(error.localizedDescription)")
            throw BackupArchiveError.restoreFailed("读取备份暂存目录失败：\(stageDirectory.lastPathComponent)")
        }
        var committedFileNames: [String] = []
        for sourceURL in files where !sourceURL.hasDirectoryPath {
            let fileName = sourceURL.lastPathComponent
            let targetURL = destinationURL(fileName)
            do {
                try manager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if manager.fileExists(atPath: targetURL.path) {
                    _ = try manager.replaceItemAt(
                        targetURL,
                        withItemAt: sourceURL,
                        backupItemName: nil,
                        options: [.usingNewMetadataOnly]
                    )
                } else {
                    try manager.moveItem(at: sourceURL, to: targetURL)
                }
                committedFileNames.append(fileName)
            } catch {
                StorageIssueLog.record("提交备份原文件失败：\(fileName)，\(error.localizedDescription)")
                throw BackupArchiveError.restoreFailed("提交原文件失败：\(fileName)")
            }
        }
        return committedFileNames
    }

    private static func photoFileNames(from snapshot: BackupSnapshot) -> [String] {
        snapshot.dailyLogs.flatMap(\.allPhotoFileNames) + snapshot.siteTodos.compactMap(\.rectificationBeforePhotoFileName) + snapshot.siteTodos.compactMap(\.rectificationAfterPhotoFileName)
    }

    private static func estimatedStepCount(from snapshot: BackupSnapshot) -> Int {
        var total = 2 // metadata + readme
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
            "\(AppBrand.displayName) 备份包",
            "生成时间: \(Formatters.now())",
            "数据索引: \(metadataPath)",
            "原文件数量: \(includedFileCount)",
            "数据索引大小: \(QuickNoteAttachmentStorage.formattedFileSize(metadataBytes))",
            "原文件大小: \(QuickNoteAttachmentStorage.formattedFileSize(rawFilesBytes))",
            "缺失文件: \(missingFiles.count)",
            "",
            "目录:",
            "\(photoPrefix) 现场照片和整改照片",
            "\(drawingPrefix) CAD/PDF 图纸",
            "\(documentPrefix) 票据和项目资料",
            "\(quickNotePrefix) 随手记媒体与工艺教程附件",
            "",
            missingFiles.isEmpty ? "未发现缺失原文件。" : "缺失原文件:\n" + missingFiles.joined(separator: "\n")
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

private extension Array where Element == SimpleZipArchiveReader.Entry {
    func backupFiles<File>(prefix: String, makeFile: (String, Data) -> File) -> [File] {
        compactMap { entry in
            guard entry.path.hasPrefix(prefix) else { return nil }
            let fileName = String(entry.path.dropFirst(prefix.count))
            guard !fileName.isEmpty, !fileName.contains("/") else { return nil }
            return makeFile(fileName, entry.data)
        }
    }
}
