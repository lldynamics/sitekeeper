import Foundation

struct BackupExportOutcome {
    let preparedFileURL: URL
    let summary: String
}

enum BackupExportCoordinator {
    static func exportBackup(
        snapshot: BackupSnapshot,
        suggestedFileName: String,
        progress: @escaping @Sendable (BackupArchiveProgress) -> Void,
        shouldCancel: @escaping @Sendable () -> Bool
    ) async throws -> BackupExportOutcome {
        let archive = try await FileIOTaskRunner.runWithRelay(
            priority: .userInitiated,
            logContext: .init(
                event: "backup.export.archive",
                source: "BackupExportCoordinator.exportBackup",
                category: .zipArchive
            )
        ) { relay in
            try BackupArchiveService.makeArchive(
                from: snapshot,
                progress: progress,
                shouldCancel: {
                    shouldCancel() || relay.isCancelled() || Task.isCancelled
                }
            )
        }

        let archiveTotalBytes = archive.totalBytes
        let preparedURL = try ExportFileURLPreparer.prepare(
            sourceFileURL: archive.fileURL,
            suggestedFileName: suggestedFileName
        )

        if shouldCancel() || Task.isCancelled {
            ExportFileURLPreparer.cleanup(fileURL: preparedURL)
            throw BackupArchiveError.cancelled
        }

        var summary = "导出成功：包含 \(archive.includedFileCount) 个原文件，大小 \(formattedFileSize(archiveTotalBytes))。"
        if !archive.missingFiles.isEmpty {
            summary += " 有 \(archive.missingFiles.count) 个原文件缺失，已写入备份包清单。"
        }
        return BackupExportOutcome(preparedFileURL: preparedURL, summary: summary)
    }

    private static func formattedFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}
