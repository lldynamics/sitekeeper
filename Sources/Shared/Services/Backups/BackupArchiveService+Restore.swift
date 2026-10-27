import Foundation

extension BackupArchiveService {
    static func restoreEmbeddedFiles(
        from fileURL: URL,
        progress: ((BackupImportProgress) -> Void)? = nil,
        shouldCancel: (() -> Bool)? = nil
    ) throws -> BackupEmbeddedRestoreCounts {
        let transaction = try prepareEmbeddedFileRestore(
            from: fileURL,
            progress: progress,
            shouldCancel: shouldCancel
        )
        progress?(BackupImportProgress(completedBytes: 1, totalBytes: 1, currentItem: loc("提交原文件")))
        let counts: BackupEmbeddedRestoreCounts
        do {
            counts = try transaction.commit()
            transaction.finalize()
        } catch {
            transaction.rollback()
            throw error
        }
        progress?(BackupImportProgress(completedBytes: 1, totalBytes: 1, currentItem: loc("恢复完成")))
        return counts
    }
}
