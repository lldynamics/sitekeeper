import Foundation

/// Owns staged restore files until the validated transaction takes ownership.
struct BackupRestoreStage {
    let stageRoot: URL
    let photoStage: URL
    let drawingStage: URL
    let documentStage: URL
    let quickNoteStage: URL
    var counts = BackupEmbeddedRestoreCounts()
    var manifestData: Data?
    var metadataData: Data?
    private var stagedNames: [String: [String: String]] = [:]

    init() throws {
        stageRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-restore-\(UUID().uuidString)", isDirectory: true)
        photoStage = stageRoot.appendingPathComponent("photos", isDirectory: true)
        drawingStage = stageRoot.appendingPathComponent("drawings", isDirectory: true)
        documentStage = stageRoot.appendingPathComponent("project-documents", isDirectory: true)
        quickNoteStage = stageRoot.appendingPathComponent("quick-note-attachments", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: photoStage, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: drawingStage, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: documentStage, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: quickNoteStage, withIntermediateDirectories: true)
            [stageRoot, photoStage, drawingStage, documentStage, quickNoteStage].forEach { BackupArchiveSecurity.applyDataProtection(to: $0) }
        } catch {
            recordBackupArchiveIssue(
                "backup.restore.stage_create_failed",
                fileName: stageRoot.lastPathComponent,
                error: error
            )
            throw BackupArchiveError.restoreFailed(BackupArchiveService.locFormat("创建导入暂存目录失败：%@", error.localizedDescription))
        }
    }

    func cleanup() {
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

    var transaction: BackupArchiveService.EmbeddedFileRestoreTransaction {
        BackupArchiveService.EmbeddedFileRestoreTransaction(stageRoot: stageRoot, photoStage: photoStage, drawingStage: drawingStage,
                                       documentStage: documentStage, quickNoteStage: quickNoteStage, counts: counts)
    }

    mutating func accept(path: String, readData: () throws -> Data, writeEntryToFile: (URL) throws -> Void) throws {
        if path == BackupArchiveService.manifestPath {
            manifestData = try readData()
            return
        }
        if path == BackupArchiveService.metadataPath {
            metadataData = try readData()
            return
        }
        for target in targets {
            guard let name = BackupArchiveService.leafFileName(for: path, prefix: target.prefix) else { continue }
            let key = AttachmentStoragePath.comparisonKey(name)
            if let firstName = stagedNames[target.stage]?[key] {
                // Older backups may contain two spellings of one file. Accept them
                // only when their independently verified payloads are identical.
                let temporaryName = ".backup-alias-\(UUID().uuidString)"
                let temporaryURL = target.directory.appendingPathComponent(temporaryName)
                defer { try? FileManager.default.removeItem(at: temporaryURL) }
                try BackupArchiveService.stageEntry(writeEntryToFile, fileName: temporaryName, to: target.directory,
                                                    failureMessage: target.failureMessage, stage: target.stage)
                let firstURL = target.directory.appendingPathComponent(firstName)
                let firstSize = try firstURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
                let secondSize = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
                guard firstSize == secondSize,
                      try BackupArchiveSecurity.sha256Hex(of: firstURL) == BackupArchiveSecurity.sha256Hex(of: temporaryURL) else {
                    throw SimpleZipArchiveReader.ZipReadError.duplicateEntry(path)
                }
                try FileManager.default.removeItem(at: temporaryURL)
                return
            }
            try BackupArchiveService.stageEntry(writeEntryToFile, fileName: name, to: target.directory,
                                                failureMessage: target.failureMessage, stage: target.stage)
            stagedNames[target.stage, default: [:]][key] = name
            counts[keyPath: target.count] += 1
            return
        }
    }

    private struct Target {
        let prefix: String
        let directory: URL
        let failureMessage: String
        let stage: String
        let count: WritableKeyPath<BackupEmbeddedRestoreCounts, Int>
    }

    private var targets: [Target] {
        [
            Target(prefix: BackupArchiveService.photoPrefix, directory: photoStage,
                   failureMessage: BackupArchiveService.loc("暂存照片失败"), stage: "photos", count: \.photoFileCount),
            Target(prefix: BackupArchiveService.drawingPrefix, directory: drawingStage,
                   failureMessage: BackupArchiveService.loc("暂存图纸失败"), stage: "drawings", count: \.drawingFileCount),
            Target(prefix: BackupArchiveService.documentPrefix, directory: documentStage,
                   failureMessage: BackupArchiveService.loc("暂存项目资料失败"), stage: "project-documents", count: \.documentFileCount),
            Target(prefix: BackupArchiveService.quickNotePrefix, directory: quickNoteStage,
                   failureMessage: BackupArchiveService.loc("暂存随手记/工艺附件失败"), stage: "quick-note-attachments", count: \.quickNoteAttachmentFileCount)
        ]
    }
}
