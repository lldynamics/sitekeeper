import Foundation

enum BackupCloudTaskCoordinator {
    static func refreshBackups() async throws -> [CloudBackupFile] {
        try await Task.detached(priority: .utility) {
            try CloudBackupService.listBackups()
        }.value
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
        try await Task.detached(priority: .userInitiated) {
            try CloudBackupService.copyBackupToTemporaryFile(file)
        }.value
    }
}
