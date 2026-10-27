import Foundation

extension BackupImportCoordinator {
    @MainActor
    static func commitAppliedImport(
        restoreTransaction: BackupArchiveService.EmbeddedFileRestoreTransaction,
        restorePolicy: BackupEmbeddedFileRestorePolicy,
        previousSnapshot: BackupSnapshot,
        importMode: ImportMode,
        store: DataStore,
        sourceFileName: String,
        onPersistingMetadata: @MainActor () -> Void
    ) async throws -> BackupEmbeddedRestoreCounts {
        let appliedSnapshot = store.makeSnapshot(includePhotoFiles: false)
        let storeURL = store.storeURL
        var failedStage = "commit_files"
        var metadataCommitted = false
        do {
            let metadataAfter = try BackupArchiveRestoreJournal.encodeMetadata(appliedSnapshot)
            let restoredCounts = try await FileIOTaskRunner.run(
                priority: .userInitiated,
                logContext: .init(
                    event: "backup.import.commit_restore_files",
                    source: "BackupImportCoordinator.commitAndPersistImport",
                    category: .zipArchive,
                    details: [
                        "file": sourceFileName,
                        "mode": importMode.rawValue
                    ]
                )
            ) {
                try restoreTransaction.commit(
                    policy: restorePolicy, storeURL: storeURL,
                    metadataAfter: metadataAfter
                )
            }
            failedStage = "persist_metadata"
            onPersistingMetadata()
            try await store.persistAppliedBackup(encodedData: metadataAfter)
            metadataCommitted = true
            try await Task.detached(priority: .utility) { try restoreTransaction.finalizeOrThrow() }.value
            return restoredCounts
        } catch {
            if metadataCommitted {
                store.setLoadState(.failed)
                store.persistenceErrorMessage = AppLocalization.string("备份已写入，但恢复事务尚未结束，已暂停保存。请重试读取。")
                throw error
            }
            if error is BackupArchiveRestoreJournal.RecoveryPendingError { store.setLoadState(.failed) }
            do {
                try await Task.detached(priority: .utility) { try restoreTransaction.rollbackOrThrow() }.value
            } catch {
                applyImportMetadata(snapshot: previousSnapshot, mode: .overwrite, store: store)
                store.setLoadState(.failed)
                store.persistenceErrorMessage = AppLocalization.string("备份回滚尚未完成，恢复包已保留，请重试加载后再操作。")
                throw error
            }
            await rollbackMetadata(previousSnapshot, store: store, sourceFileName: sourceFileName, failedStage: failedStage)
            throw error
        }
    }

    @MainActor
    private static func rollbackMetadata(_ previousSnapshot: BackupSnapshot, store: DataStore, sourceFileName: String, failedStage: String) async {
        applyImportMetadata(snapshot: previousSnapshot, mode: .overwrite, store: store)
        do {
            // A failed atomic import write leaves the original disk metadata intact.
            // In particular, never overwrite an unreadable original during rollback.
            if store.loadState == .ready {
                try await store.persistAppliedBackup()
            }
        } catch {
            StorageIssueLog.recordEvent(
                "backup.import.rollback_persist_failed",
                category: .dataStore,
                details: [
                    "file": sourceFileName,
                    "stage": failedStage
                ],
                error: error
            )
        }
    }
}
