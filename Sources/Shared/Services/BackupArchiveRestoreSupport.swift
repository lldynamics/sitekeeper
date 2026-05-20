import Foundation

extension BackupArchiveService {
    final class EmbeddedFileRestoreTransaction: @unchecked Sendable {
        let counts: BackupEmbeddedRestoreCounts
        private let stageRoot: URL
        private let photoStage: URL
        private let drawingStage: URL
        private let documentStage: URL
        private let quickNoteStage: URL
        private var isFinished = false

        init(
            stageRoot: URL,
            photoStage: URL,
            drawingStage: URL,
            documentStage: URL,
            quickNoteStage: URL,
            counts: BackupEmbeddedRestoreCounts
        ) {
            self.stageRoot = stageRoot
            self.photoStage = photoStage
            self.drawingStage = drawingStage
            self.documentStage = documentStage
            self.quickNoteStage = quickNoteStage
            self.counts = counts
        }

        deinit {
            if !isFinished {
                cleanupTemporaryFiles()
            }
        }

        func cancel() {
            guard !isFinished else { return }
            isFinished = true
            cleanupTemporaryFiles()
        }

        @discardableResult
        func commit() throws -> BackupEmbeddedRestoreCounts {
            guard !isFinished else { return counts }

            let rollbackRoot = stageRoot.appendingPathComponent("rollback", isDirectory: true)
            var committedFiles: [CommittedBackupFile] = []
            do {
                try FileManager.default.createDirectory(at: rollbackRoot, withIntermediateDirectories: true)
                let restoredPhotoFileNames = try BackupArchiveService.commitStagedFiles(
                    from: photoStage,
                    destinationURL: PhotoStorage.fileURL(for:),
                    rollbackRoot: rollbackRoot,
                    committedFiles: &committedFiles
                )
                PhotoStorage.regenerateThumbnails(for: restoredPhotoFileNames)
                try BackupArchiveService.commitStagedFiles(
                    from: drawingStage,
                    destinationURL: DrawingStorage.fileURL(for:),
                    rollbackRoot: rollbackRoot,
                    committedFiles: &committedFiles
                )
                try BackupArchiveService.commitStagedFiles(
                    from: documentStage,
                    destinationURL: ProjectDocumentStorage.fileURL(for:),
                    rollbackRoot: rollbackRoot,
                    committedFiles: &committedFiles
                )
                try BackupArchiveService.commitStagedFiles(
                    from: quickNoteStage,
                    destinationURL: QuickNoteAttachmentStorage.fileURL(for:),
                    rollbackRoot: rollbackRoot,
                    committedFiles: &committedFiles
                )
                isFinished = true
                cleanupTemporaryFiles()
                return counts
            } catch {
                BackupArchiveService.rollbackCommittedFiles(committedFiles)
                isFinished = true
                cleanupTemporaryFiles()
                throw error
            }
        }

        private func cleanupTemporaryFiles() {
            do {
                _ = try FileOps.removeIfExists(
                    at: stageRoot,
                    context: .init(
                        event: "backup.restore.stage_cleanup",
                        category: .zipArchive,
                        source: "BackupArchiveService.RestorationSession.cleanupTemporaryFiles"
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
}

fileprivate struct CommittedBackupFile {
    let fileName: String
    let targetURL: URL
    let rollbackURL: URL?
}

extension BackupArchiveService {
    @discardableResult
    fileprivate static func commitStagedFiles(
        from stageDirectory: URL,
        destinationURL: (String) -> URL,
        rollbackRoot: URL,
        committedFiles: inout [CommittedBackupFile]
    ) throws -> [String] {
        let manager = FileManager.default
        let files: [URL]
        do {
            files = try manager.contentsOfDirectory(at: stageDirectory, includingPropertiesForKeys: nil)
        } catch {
            recordBackupArchiveIssue(
                "backup.restore.stage_directory_read_failed",
                fileName: stageDirectory.lastPathComponent,
                error: error
            )
            throw BackupArchiveError.restoreFailed(locFormat("读取备份暂存目录失败：%@", stageDirectory.lastPathComponent))
        }
        var committedFileNames: [String] = []
        for sourceURL in files where !sourceURL.hasDirectoryPath {
            let fileName = sourceURL.lastPathComponent
            let targetURL = destinationURL(fileName)
            let rollbackURL = rollbackRoot
                .appendingPathComponent(UUID().uuidString, isDirectory: false)
                .appendingPathExtension("bak")
            do {
                try manager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let targetExists = manager.fileExists(atPath: targetURL.path)
                let rollbackURLForRecord: URL?
                if targetExists {
                    try manager.copyItem(at: targetURL, to: rollbackURL)
                    rollbackURLForRecord = rollbackURL
                } else {
                    rollbackURLForRecord = nil
                }
                committedFiles.append(
                    CommittedBackupFile(
                        fileName: fileName,
                        targetURL: targetURL,
                        rollbackURL: rollbackURLForRecord
                    )
                )
                _ = try FileOps.removeIfExists(
                    at: targetURL,
                    context: .init(
                        event: "backup.restore.replace_target",
                        category: .zipArchive,
                        source: "BackupArchiveService.commitStagedFiles"
                    )
                )
                try manager.copyItem(at: sourceURL, to: targetURL)
                committedFileNames.append(fileName)
            } catch {
                recordBackupArchiveIssue(
                    "backup.restore.commit_file_failed",
                    fileName: fileName,
                    path: targetURL.lastPathComponent,
                    error: error
                )
                throw BackupArchiveError.restoreFailed(locFormat("提交原文件失败：%@", fileName))
            }
        }
        return committedFileNames
    }

    fileprivate static func rollbackCommittedFiles(_ files: [CommittedBackupFile]) {
        let manager = FileManager.default
        for file in files.reversed() {
            do {
                _ = try FileOps.removeIfExists(
                    at: file.targetURL,
                    context: .init(
                        event: "backup.restore.rollback_remove_target",
                        category: .zipArchive,
                        source: "BackupArchiveService.rollbackCommittedFiles"
                    )
                )
                if let rollbackURL = file.rollbackURL, manager.fileExists(atPath: rollbackURL.path) {
                    try manager.moveItem(at: rollbackURL, to: file.targetURL)
                }
            } catch {
                recordBackupArchiveIssue(
                    "backup.restore.rollback_file_failed",
                    fileName: file.fileName,
                    error: error
                )
            }
        }
    }
}
