import Foundation

extension DataStore {
    var isExportingBackup: Bool { activeBackupExportCount > 0 }

    /// Snapshot creation belongs inside this scope. The lease survives every suspension
    /// until file readers finish, including their cancellation/failure cleanup.
    func withBackupExport<T: Sendable>(_ operation: @MainActor () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        guard loadState == .ready, !isApplyingBackup else {
            throw PersistenceBlockedError(message: persistenceErrorMessage)
        }
        activeBackupExportCount += 1
        defer { activeBackupExportCount -= 1 }
        return try await operation()
    }

    func requireNoBackupExport() throws {
        guard !isExportingBackup else {
            throw PersistenceBlockedError(message: String(localized: "正在导出备份，请等待完成后再清理或恢复。"))
        }
    }
}
