import Foundation

enum BackupCloudTaskCoordinator {
    static func refreshBackups() async throws -> [CloudBackupFile] {
        try await FileIOTaskRunner.run(
            priority: .utility,
            logContext: .init(
                event: "backup.cloud.refresh",
                source: "BackupCloudTaskCoordinator.refreshBackups",
                category: .cloudBackup
            )
        ) {
            try CloudBackupService.listBackups()
        }
    }

    static func uploadBackup(
        snapshot: BackupSnapshot,
        progress: @escaping (BackupArchiveProgress) -> Void
    ) async throws -> CloudBackupExecutionResult {
        try await CloudBackupCoordinator.shared.backupToCloud(
            snapshot: snapshot,
            progress: progress
        )
    }

    static func copyCloudBackupToTemporaryFile(_ file: CloudBackupFile) async throws -> URL {
        try await FileIOTaskRunner.run(
            priority: .userInitiated,
            logContext: .init(
                event: "backup.cloud.copy_to_temp",
                source: "BackupCloudTaskCoordinator.copyCloudBackupToTemporaryFile",
                category: .cloudBackup,
                details: ["file_name": file.fileName]
            )
        ) {
            try CloudBackupService.copyBackupToTemporaryFile(file)
        }
    }
}
