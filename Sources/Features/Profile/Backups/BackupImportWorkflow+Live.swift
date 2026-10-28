import Foundation

/// Uses the existing archive cancellation relay and import transaction unchanged.
/// UI state and localized presentation remain in BackupView.
@MainActor
struct LiveBackupImportWorkflowOperations: BackupImportWorkflowOperations {
    let store: DataStore
    let selectedImportMode: @MainActor () -> ImportMode

    func readMetadata(
        from sourceURL: URL,
        progress: @escaping @MainActor @Sendable (BackupImportWorkflowProgress) -> Void
    ) async throws -> BackupSnapshot {
        let preview = try await FileIOTaskRunner.runWithRelay(
            priority: .userInitiated,
            logContext: .init(
                event: "backup.import.preview_fallback",
                source: "BackupView.startApplyingImport",
                category: .zipArchive,
                details: ["file_name": sourceURL.lastPathComponent]
            )
        ) { relay in
            try BackupArchiveService.previewBackup(
                from: sourceURL,
                progress: { value in
                    Task { @MainActor in progress(Self.workflowProgress(value)) }
                },
                shouldCancel: { relay.isCancelled() || Task.isCancelled }
            )
        }
        return preview.snapshot
    }

    func captureContext(importedMetadata: BackupSnapshot) -> BackupImportWorkflowContext<BackupSnapshot> {
        let previous = store.makeSnapshot(includePhotoFiles: false)
        let mode = selectedImportMode()
        let impact = mode == .overwrite
            ? BackupImportCoordinator.overwrittenLocalFiles(previous: previous, imported: importedMetadata)
            : BackupFileImpactSummary()
        return BackupImportWorkflowContext(
            previousMetadata: previous,
            mode: mode == .overwrite ? .overwrite : .merge,
            overwrittenFileCount: impact.totalCount
        )
    }

    func stageFiles(
        from sourceURL: URL,
        progress: @escaping @MainActor @Sendable (BackupImportWorkflowProgress) -> Void
    ) async throws -> BackupArchiveService.EmbeddedFileRestoreTransaction {
        try await FileIOTaskRunner.runWithRelay(
            priority: .userInitiated,
            logContext: .init(
                event: "backup.import.prepare_restore",
                source: "BackupView.startApplyingImport",
                category: .zipArchive,
                details: ["file_name": sourceURL.lastPathComponent]
            )
        ) { relay in
            try BackupArchiveService.prepareEmbeddedFileRestore(
                from: sourceURL,
                progress: { value in
                    Task { @MainActor in progress(Self.workflowProgress(value)) }
                },
                shouldCancel: { relay.isCancelled() || Task.isCancelled }
            )
        }
    }

    func stagedFileCount(_ files: BackupArchiveService.EmbeddedFileRestoreTransaction) -> Int {
        files.counts.totalCount
    }

    func cancelStagedFiles(_ files: BackupArchiveService.EmbeddedFileRestoreTransaction) {
        files.cancel()
    }

    func commit(
        _ files: BackupArchiveService.EmbeddedFileRestoreTransaction,
        importedMetadata: BackupSnapshot,
        context: BackupImportWorkflowContext<BackupSnapshot>,
        sourceFileName: String,
        onPersistingMetadata: @escaping @MainActor () -> Void
    ) async throws -> Int {
        let counts = try await BackupImportCoordinator.commitAndPersistImport(
            restoreTransaction: files,
            importedSnapshot: importedMetadata,
            previousSnapshot: context.previousMetadata,
            importMode: context.mode == .overwrite ? .overwrite : .merge,
            store: store,
            sourceFileName: sourceFileName,
            onPersistingMetadata: onPersistingMetadata
        )
        return counts.totalCount
    }

    func cleanupOverwrittenFiles(
        context: BackupImportWorkflowContext<BackupSnapshot>,
        importedMetadata: BackupSnapshot
    ) {
        BackupImportCoordinator.cleanupOverwrittenFiles(previous: context.previousMetadata, imported: importedMetadata)
    }

    func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let archiveError = error as? BackupArchiveError, case .cancelled = archiveError { return true }
        return false
    }

    private static func workflowProgress(_ progress: BackupImportProgress) -> BackupImportWorkflowProgress {
        BackupImportWorkflowProgress(
            completedBytes: progress.completedBytes,
            totalBytes: progress.totalBytes,
            currentItem: progress.currentItem
        )
    }
}

extension BackupImportWorkflowPhase {
    var importStage: BackupImportStage {
        switch self {
        case .readingMetadata: .readingMetadata
        case .stagingFiles: .stagingFiles
        case .applyingMetadata: .applyingMetadata
        case .committingFiles: .committingFiles
        case .persistingMetadata: .persistingMetadata
        case .cleaningOverwrittenFiles: .cleaningOverwrittenFiles
        }
    }
}
