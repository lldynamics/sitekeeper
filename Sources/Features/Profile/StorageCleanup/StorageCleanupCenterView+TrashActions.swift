import SwiftUI

extension StorageCleanupCenterView {
    func refreshCleanupTrash() {
        let result = StorageCleanupExecutionService.refreshTrash()
        cleanupTrashBatches = result.cleanupTrashBatches
        quarantinedFiles = result.quarantinedFiles
    }

    func restoreCleanupTrash(_ batch: StorageCleanupTrashBatch) {
        StorageCleanupAuditService.record(
            StorageCleanupActionResultBuilder.restoreCleanupTrashStarted(batch),
            source: cleanupAuditSource
        )
        do {
            try StorageCleanupExecutionService.restoreCleanupTrash(batch, store: store)
            refreshCleanupTrash()
            cleanupStatusMessage = StorageCleanupAuditService.completeSucceeded(
                StorageCleanupActionResultBuilder.restoreCleanupTrashSucceeded(batch),
                source: cleanupAuditSource
            )
        } catch {
            cleanupStatusMessage = StorageCleanupAuditService.completeFailed(
                StorageCleanupActionResultBuilder.restoreCleanupTrashFailed(batch, error: error),
                source: cleanupAuditSource
            )
        }
    }

    func permanentlyDeleteCleanupTrash(_ batch: StorageCleanupTrashBatch) {
        StorageCleanupAuditService.record(
            StorageCleanupActionResultBuilder.permanentlyDeleteCleanupTrashStarted(batch),
            source: cleanupAuditSource
        )
        do {
            try StorageCleanupExecutionService.permanentlyDeleteCleanupTrash(batch)
            refreshCleanupTrash()
            cleanupStatusMessage = StorageCleanupAuditService.completeSucceeded(
                StorageCleanupActionResultBuilder.permanentlyDeleteCleanupTrashSucceeded(batch),
                source: cleanupAuditSource
            )
        } catch {
            cleanupStatusMessage = StorageCleanupAuditService.completeFailed(
                StorageCleanupActionResultBuilder.permanentlyDeleteCleanupTrashFailed(batch, error: error),
                source: cleanupAuditSource
            )
        }
    }

    func restoreQuarantinedFile(_ entry: FileQuarantineEntry) {
        StorageCleanupAuditService.record(
            StorageCleanupActionResultBuilder.restoreQuarantinedFileStarted(entry),
            source: cleanupAuditSource
        )
        do {
            try StorageCleanupExecutionService.restoreQuarantinedFile(entry, store: store)
            refreshCleanupTrash()
            cleanupStatusMessage = StorageCleanupAuditService.completeSucceeded(
                StorageCleanupActionResultBuilder.restoreQuarantinedFileSucceeded(entry),
                source: cleanupAuditSource
            )
        } catch {
            cleanupStatusMessage = StorageCleanupAuditService.completeFailed(
                StorageCleanupActionResultBuilder.restoreQuarantinedFileFailed(entry, error: error),
                source: cleanupAuditSource
            )
        }
    }

    func permanentlyDeleteQuarantinedFile(_ entry: FileQuarantineEntry) {
        StorageCleanupAuditService.record(
            StorageCleanupActionResultBuilder.permanentlyDeleteQuarantinedFileStarted(entry),
            source: cleanupAuditSource
        )
        do {
            try StorageCleanupExecutionService.permanentlyDeleteQuarantinedFile(entry)
            refreshCleanupTrash()
            cleanupStatusMessage = StorageCleanupAuditService.completeSucceeded(
                StorageCleanupActionResultBuilder.permanentlyDeleteQuarantinedFileSucceeded(entry),
                source: cleanupAuditSource
            )
        } catch {
            cleanupStatusMessage = StorageCleanupAuditService.completeFailed(
                StorageCleanupActionResultBuilder.permanentlyDeleteQuarantinedFileFailed(entry, error: error),
                source: cleanupAuditSource
            )
        }
    }

    func cleanupProjectFiles(_ usage: ProjectStorageUsage, category: ProjectStorageCleanupCategory) {
        defer { pendingCleanupProject = nil }

        let context = StorageCleanupActionResultBuilder.projectCleanupContext(
            usage: usage,
            category: category
        )
        StorageCleanupAuditService.record(
            StorageCleanupActionResultBuilder.cleanupProjectFilesStarted(context),
            source: cleanupAuditSource
        )

        do {
            let retentionDays = normalizedCleanupTrashRetentionDays
            let batch = try StorageCleanupExecutionService.cleanupProjectFiles(
                store: store,
                projectId: usage.projectId,
                category: category,
                retentionDays: retentionDays,
                summary: context.cleanupSummary,
                videoFileExtensions: videoFileExtensions,
                drawingSourceFileExtensions: drawingSourceFileExtensions
            )
            refreshCleanupTrash()
            cleanupStatusMessage = StorageCleanupAuditService.completeSucceeded(
                StorageCleanupActionResultBuilder.cleanupProjectFilesSucceeded(
                    context,
                    batch: batch,
                    retentionDays: retentionDays
                ),
                source: cleanupAuditSource
            )
        } catch {
            cleanupStatusMessage = StorageCleanupAuditService.completeFailed(
                StorageCleanupActionResultBuilder.cleanupProjectFilesFailed(context, error: error),
                source: cleanupAuditSource
            )
        }
    }
}
