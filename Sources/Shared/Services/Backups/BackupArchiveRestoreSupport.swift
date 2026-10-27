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
    /// Used serially by the import coordinator; no mutable state is shared across its I/O phases.
    final class EmbeddedFileRestoreTransaction: @unchecked Sendable {
        let counts: BackupEmbeddedRestoreCounts
        private let stageRoot: URL
        private var journal: BackupArchiveRestoreJournal?
        private var finished = false
        private var restoresMetadata = false
        private let fault: BackupArchiveRestoreJournal.FaultInjector?

        init(
            stageRoot: URL,
            photoStage: URL,
            drawingStage: URL,
            documentStage: URL,
            quickNoteStage: URL,
            counts: BackupEmbeddedRestoreCounts,
            fault: BackupArchiveRestoreJournal.FaultInjector? = nil
        ) {
            self.stageRoot = stageRoot
            self.counts = counts
            self.fault = fault
        }

        deinit {
            guard !finished else { return }
            if let journal, !restoresMetadata {
                // Preserve the legacy attachment-only session's rollback-on-release contract.
                do { try journal.rollback() } catch {
                    recordBackupArchiveIssue("backup.restore.deinit_rollback_failed", error: error)
                }
            } else if journal == nil {
                cleanupTemporaryFiles()
            }
            // Metadata transactions belong to startup recovery. Never delete recovery
            // originals on release after failed rollback/finalization.
        }

        func cancel() { rollback() }

        @discardableResult
        func rollback() -> Bool {
            do {
                try rollbackOrThrow()
                return true
            } catch {
                recordBackupArchiveIssue("backup.restore.rollback_failed", fileName: journal?.root.lastPathComponent, error: error)
                return false
            }
        }

        func rollbackOrThrow() throws {
            guard !finished else { return }
            if let journal { try journal.rollback() }
            finished = true
            cleanupTemporaryFiles()
        }

        func finalize() {
            do {
                try finalizeOrThrow()
            } catch {
                recordBackupArchiveIssue("backup.restore.finalize_failed", fileName: journal?.root.lastPathComponent, error: error)
            }
        }

        func finalizeOrThrow() throws {
            guard !finished else { return }
            try journal?.finish(fault: fault)
            finished = true
            cleanupTemporaryFiles()
        }

        @discardableResult
        func commit(
            policy: BackupEmbeddedFileRestorePolicy = .restoreAll,
            storeURL: URL? = nil,
            metadataAfter: Data? = nil
        ) throws -> BackupEmbeddedRestoreCounts {
            guard !finished, journal == nil else {
                throw BackupArchiveError.restoreFailed(AppLocalization.string("备份回滚尚未完成，恢复包已保留，请重试加载后再操作。"))
            }
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            // Legacy attachment-only helpers never share journals with a live DataStore.
            // They preserve their existing explicit/deinit rollback contract independently.
            let metadataURL = storeURL ?? documents
                .appendingPathComponent(".backup-attachment-sessions", isDirectory: true)
                .appendingPathComponent("sitekeeper.json")
            restoresMetadata = metadataAfter != nil
            do {
                let prepared = try BackupArchiveRestoreJournal.begin(
                    stageRoot: stageRoot, storeURL: metadataURL, metadataAfter: metadataAfter, policy: policy
                )
                journal = prepared
                return try prepared.commitFiles()
            } catch {
                do {
                    try rollbackOrThrow()
                } catch {
                    throw BackupArchiveError.restoreFailed(AppLocalization.string("备份回滚尚未完成，恢复包已保留，请重试加载后再操作。"))
                }
                throw error
            }
        }

        private func cleanupTemporaryFiles() {
            do {
                _ = try FileOps.removeIfExists(
                    at: stageRoot,
                    context: .init(event: "backup.restore.stage_cleanup", category: .zipArchive,
                                   source: "BackupArchiveService.RestorationSession.cleanupTemporaryFiles")
                )
            } catch {
                recordBackupArchiveIssue("backup.restore.stage_cleanup_failed", fileName: stageRoot.lastPathComponent, error: error)
            }
        }
    }
}
