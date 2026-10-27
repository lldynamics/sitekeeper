import Foundation

actor CloudBackupCoordinator {
    static let shared = CloudBackupCoordinator()

    func backupToCloud(
        snapshot: BackupSnapshot,
        progress: (@Sendable (BackupArchiveProgress) -> Void)? = nil
    ) async throws -> CloudBackupExecutionResult {
        var archiveFileURL: URL?
        let retentionCount = CloudBackupSettingsStore.loadRetentionCount()
        do {
            let archive = try await FileIOTaskRunner.runWithRelay(
                priority: .userInitiated,
                logContext: .init(
                    event: "cloud_backup.make_archive",
                    source: "CloudBackupCoordinator.backupToCloud",
                    category: .zipArchive,
                    details: ["retention_count": "\(retentionCount)"]
                )
            ) { relay in
                try BackupArchiveService.makeArchive(
                    from: snapshot,
                    progress: progress,
                    shouldCancel: { relay.isCancelled() || Task.isCancelled }
                )
            }
            archiveFileURL = archive.fileURL
            guard archive.missingFiles.isEmpty else {
                throw CloudBackupPreparationError.missingFiles(archive.missingFiles.count)
            }

            let savedFile = try await saveArchiveToCloud(archive.fileURL, retentionCount: retentionCount)

            let files = try await FileIOTaskRunner.run(
                priority: .utility,
                logContext: .init(
                    event: "cloud_backup.list_after_upload",
                    source: "CloudBackupCoordinator.backupToCloud",
                    category: .cloudBackup
                )
            ) {
                try Task.checkCancellation()
                return try CloudBackupService.refreshUploadStatusAndPrune(keepMostRecent: retentionCount)
            }
            cleanupTemporaryArchive(archive.fileURL, source: "CloudBackupCoordinator.backupToCloud.afterUpload")
            archiveFileURL = nil
            return CloudBackupExecutionResult(savedFile: files.first { $0.id == savedFile.id } ?? savedFile, allBackups: files)
        } catch {
            if let archiveFileURL {
                cleanupTemporaryArchive(archiveFileURL, source: "CloudBackupCoordinator.backupToCloud.failureCleanup")
            }
            throw error
        }
    }
    private func saveArchiveToCloud(_ archiveURL: URL, retentionCount: Int) async throws -> CloudBackupFile {
        return try await FileIOTaskRunner.run(
            priority: .utility,
            logContext: .init(
                event: "cloud_backup.save_archive",
                source: "CloudBackupCoordinator.backupToCloud",
                category: .cloudBackup,
                details: ["retention_count": "\(retentionCount)"]
            )
        ) {
            try Task.checkCancellation()
            let file = try CloudBackupService.saveArchiveToCloud(archiveFileURL: archiveURL)
            CloudBackupSettingsStore.savePendingFileName(file.fileName)
            return file
        }
    }

    private func cleanupTemporaryArchive(_ url: URL, source: String) {
        do {
            _ = try FileOps.removeIfExists(at: url, context: .init(
                event: "cloud_backup.temp_archive_cleanup", category: .cloudBackup, source: source
            ))
        } catch {
            // FileOps records cleanup errors; preserve the upload result or original error.
        }
    }
}

enum CloudBackupPreparationError: LocalizedError, Equatable {
    case missingFiles(Int)

    var errorDescription: String? {
        switch self {
        case let .missingFiles(count):
            String(format: AppLocalization.string("云备份未上传：有 %lld 个附件原文件缺失，请修复后重试。"), Int64(count))
        }
    }
}
