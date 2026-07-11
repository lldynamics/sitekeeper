import Foundation

struct BackupEmbeddedFileRestorePolicy: Sendable {
    let photoFileDestinations: [String: String]?
    let drawingFileDestinations: [String: String]?
    let documentFileDestinations: [String: String]?
    let quickNoteAttachmentFileDestinations: [String: String]?
    let overwritesExistingFiles: Bool

    static let restoreAll = Self(
        photoFileDestinations: nil,
        drawingFileDestinations: nil,
        documentFileDestinations: nil,
        quickNoteAttachmentFileDestinations: nil,
        overwritesExistingFiles: true
    )

    static func referencedBy(
        _ snapshot: BackupSnapshot,
        overwritesExistingFiles: Bool
    ) -> Self {
        Self(
            photoFileDestinations: identityDestinations(
                BackupArchiveService.photoFileNames(from: snapshot)
            ),
            drawingFileDestinations: identityDestinations(
                snapshot.projectDrawings.map(\.fileName)
            ),
            documentFileDestinations: identityDestinations(
                snapshot.projectDocuments.map(\.fileName)
            ),
            quickNoteAttachmentFileDestinations: identityDestinations(
                BackupArchiveService.quickNoteAttachmentNames(from: snapshot)
            ),
            overwritesExistingFiles: overwritesExistingFiles
        )
    }

    static func mapped(
        photoFileDestinations: [String: String],
        drawingFileDestinations: [String: String],
        documentFileDestinations: [String: String],
        quickNoteAttachmentFileDestinations: [String: String]
    ) -> Self {
        Self(
            photoFileDestinations: photoFileDestinations,
            drawingFileDestinations: drawingFileDestinations,
            documentFileDestinations: documentFileDestinations,
            quickNoteAttachmentFileDestinations: quickNoteAttachmentFileDestinations,
            overwritesExistingFiles: false
        )
    }

    private static func identityDestinations(_ fileNames: [String]) -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: Set(fileNames.filter { !$0.isEmpty }).map { ($0, $0) }
        )
    }
}

extension BackupArchiveService {
    final class EmbeddedFileRestoreTransaction: @unchecked Sendable {
        let counts: BackupEmbeddedRestoreCounts
        private let stageRoot: URL
        private let photoStage: URL
        private let drawingStage: URL
        private let documentStage: URL
        private let quickNoteStage: URL
        private enum State {
            case pending
            case committed
            case finished
        }

        private var state: State = .pending
        private var committedFiles: [CommittedBackupFile] = []

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
            switch state {
            case .pending:
                cleanupTemporaryFiles()
            case .committed:
                BackupArchiveService.rollbackCommittedFiles(committedFiles)
                cleanupTemporaryFiles()
            case .finished:
                break
            }
        }

        func cancel() {
            switch state {
            case .pending:
                state = .finished
                cleanupTemporaryFiles()
            case .committed:
                rollback()
            case .finished:
                return
            }
        }

        func rollback() {
            guard state != .finished else { return }
            if state == .committed {
                BackupArchiveService.rollbackCommittedFiles(committedFiles)
            }
            state = .finished
            committedFiles = []
            cleanupTemporaryFiles()
        }

        func finalize() {
            guard state != .finished else { return }
            state = .finished
            committedFiles = []
            cleanupTemporaryFiles()
        }

        @discardableResult
        func commit(policy: BackupEmbeddedFileRestorePolicy = .restoreAll) throws -> BackupEmbeddedRestoreCounts {
            guard state == .pending else { return counts }

            let rollbackRoot = stageRoot.appendingPathComponent("rollback", isDirectory: true)
            var currentCommittedFiles: [CommittedBackupFile] = []
            do {
                try FileManager.default.createDirectory(at: rollbackRoot, withIntermediateDirectories: true)
                let restoredPhotoFileNames = try BackupArchiveService.commitStagedFiles(
                    from: photoStage,
                    destinationURL: PhotoStorage.fileURL(for:),
                    rollbackRoot: rollbackRoot,
                    committedFiles: &currentCommittedFiles,
                    fileDestinations: policy.photoFileDestinations,
                    overwritesExistingFiles: policy.overwritesExistingFiles
                )
                PhotoStorage.regenerateThumbnails(for: restoredPhotoFileNames)
                let restoredDrawingFileNames = try BackupArchiveService.commitStagedFiles(
                    from: drawingStage,
                    destinationURL: DrawingStorage.fileURL(for:),
                    rollbackRoot: rollbackRoot,
                    committedFiles: &currentCommittedFiles,
                    fileDestinations: policy.drawingFileDestinations,
                    overwritesExistingFiles: policy.overwritesExistingFiles
                )
                let restoredDocumentFileNames = try BackupArchiveService.commitStagedFiles(
                    from: documentStage,
                    destinationURL: ProjectDocumentStorage.fileURL(for:),
                    rollbackRoot: rollbackRoot,
                    committedFiles: &currentCommittedFiles,
                    fileDestinations: policy.documentFileDestinations,
                    overwritesExistingFiles: policy.overwritesExistingFiles
                )
                let restoredQuickNoteAttachmentFileNames = try BackupArchiveService.commitStagedFiles(
                    from: quickNoteStage,
                    destinationURL: QuickNoteAttachmentStorage.fileURL(for:),
                    rollbackRoot: rollbackRoot,
                    committedFiles: &currentCommittedFiles,
                    fileDestinations: policy.quickNoteAttachmentFileDestinations,
                    overwritesExistingFiles: policy.overwritesExistingFiles
                )
                committedFiles = currentCommittedFiles
                state = .committed
                return BackupEmbeddedRestoreCounts(
                    photoFileCount: restoredPhotoFileNames.count,
                    drawingFileCount: restoredDrawingFileNames.count,
                    documentFileCount: restoredDocumentFileNames.count,
                    quickNoteAttachmentFileCount: restoredQuickNoteAttachmentFileNames.count
                )
            } catch {
                BackupArchiveService.rollbackCommittedFiles(currentCommittedFiles)
                state = .finished
                committedFiles = []
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
        committedFiles: inout [CommittedBackupFile],
        fileDestinations: [String: String]?,
        overwritesExistingFiles: Bool
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
            guard let destinationFileName = fileDestinations?[fileName] ?? (fileDestinations == nil ? fileName : nil) else {
                continue
            }
            let targetURL = destinationURL(destinationFileName)
            let rollbackURL = rollbackRoot
                .appendingPathComponent(UUID().uuidString, isDirectory: false)
                .appendingPathExtension("bak")
            do {
                try manager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let targetExists = manager.fileExists(atPath: targetURL.path)
                guard !targetExists || overwritesExistingFiles else { continue }
                let rollbackURLForRecord: URL?
                if targetExists {
                    try manager.copyItem(at: targetURL, to: rollbackURL)
                    rollbackURLForRecord = rollbackURL
                } else {
                    rollbackURLForRecord = nil
                }
                committedFiles.append(
                    CommittedBackupFile(
                        fileName: destinationFileName,
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
                committedFileNames.append(destinationFileName)
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
