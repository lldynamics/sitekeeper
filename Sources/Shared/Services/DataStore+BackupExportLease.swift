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
        let fileLease = FileQuarantineStore.beginBackupExport(protecting: referencedFileURLsForBackupProtection())
        defer {
            FileQuarantineStore.endBackupExport(fileLease, retaining: referencedFileURLsForBackupProtection())
            activeBackupExportCount -= 1
        }
        return try await operation()
    }

    func requireNoBackupExport() throws {
        guard !isExportingBackup else {
            throw PersistenceBlockedError(message: String(localized: "正在导出备份，请等待完成后再清理或恢复。"))
        }
    }

    private func referencedFileURLsForBackupProtection() -> Set<URL> {
        let photos = PhotoStorage.referencedFileNames(logs: dailyLogs, todos: siteTodos)
        let extraAttachments = constructionMethods.flatMap(\.attachments) + constructionMethods.flatMap(\.tutorialAttachments)
        let attachments = QuickNoteAttachmentStorage.referencedFileNames(for: quickNotes, extraAttachments: extraAttachments)
        return Set(photos.map(PhotoStorage.fileURL(for:))
            + photos.map(PhotoStorage.thumbnailStorageURL(for:))
            + projectDrawings.map { DrawingStorage.fileURL(for: $0.fileName) }
            + projectDocuments.map { ProjectDocumentStorage.fileURL(for: $0.fileName) }
            + attachments.map(QuickNoteAttachmentStorage.fileURL(for:)))
    }
}
