import SwiftUI

extension StorageCleanupCenterView {
    func refreshCleanupTrash() {
        let now = Date()
        let purgedCount = StorageCleanupTrashStore.purgeExpiredBatches(now: now)
        let purgedFileCount = FileQuarantineStore.purgeExpiredEntries(now: now)
        cleanupTrashBatches = StorageCleanupTrashStore.loadBatches()
        quarantinedFiles = FileQuarantineStore.loadEntries()
        if purgedCount > 0 {
            StorageIssueLog.recordEvent(
                "storage_cleanup.cleanup_trash_batches_purged",
                category: .dataStore,
                details: [
                    "source": "StorageCleanupCenterView.refreshCleanupTrash",
                    "purged_count": "\(purgedCount)"
                ]
            )
        }
        if purgedFileCount > 0 {
            StorageIssueLog.recordEvent(
                "storage_cleanup.quarantined_files_purged",
                category: .fileStorage,
                details: [
                    "source": "StorageCleanupCenterView.refreshCleanupTrash",
                    "purged_count": "\(purgedFileCount)"
                ]
            )
        }
    }

    func restoreCleanupTrash(_ batch: StorageCleanupTrashBatch) {
        recordCleanupAudit(
            action: .restore,
            outcome: .started,
            summary: StorageCleanupSectionCopy.auditSummaryRestoreCleanupTrash,
            detail: batch.summary
        )
        do {
            try StorageCleanupTrashStore.restore(batch)
            batch.snapshot.restore(into: store)
            store.scheduleSave()
            refreshCleanupTrash()
            completeCleanupOperationSucceeded(
                action: .restore,
                summary: StorageCleanupSectionCopy.auditSummaryRestoreCleanupTrash,
                detail: StorageCleanupSectionCopy.auditDetailRestoredCleanupBatch(batch.summary, fileCount: batch.fileCount),
                statusMessage: StorageCleanupSectionCopy.restoredCleanupTrashStatus(batch.summary)
            )
        } catch {
            completeCleanupOperationFailed(
                action: .restore,
                summary: StorageCleanupSectionCopy.auditSummaryRestoreCleanupTrash,
                detail: StorageCleanupSectionCopy.auditDetailWithError(batch.summary, errorDescription: error.localizedDescription),
                statusMessage: StorageCleanupSectionCopy.restoreCleanupTrashFailedStatus(error.localizedDescription)
            )
        }
    }

    func permanentlyDeleteCleanupTrash(_ batch: StorageCleanupTrashBatch) {
        recordCleanupAudit(
            action: .cleanup,
            outcome: .started,
            summary: StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteCleanupTrash,
            detail: batch.summary
        )
        do {
            try StorageCleanupTrashStore.permanentlyDelete(batch)
            refreshCleanupTrash()
            completeCleanupOperationSucceeded(
                action: .cleanup,
                summary: StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteCleanupTrash,
                detail: StorageCleanupSectionCopy.auditDetailDeletedCleanupBatch(batch.summary, fileCount: batch.fileCount),
                statusMessage: StorageCleanupSectionCopy.permanentlyDeletedCleanupTrashStatus(batch.summary)
            )
        } catch {
            completeCleanupOperationFailed(
                action: .cleanup,
                summary: StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteCleanupTrash,
                detail: StorageCleanupSectionCopy.auditDetailWithError(batch.summary, errorDescription: error.localizedDescription),
                statusMessage: StorageCleanupSectionCopy.permanentlyDeleteCleanupTrashFailedStatus(error.localizedDescription)
            )
        }
    }

    func restoreQuarantinedFile(_ entry: FileQuarantineEntry) {
        let detail = cleanupAuditDetail(for: entry)
        recordCleanupAudit(
            action: .restore,
            outcome: .started,
            summary: StorageCleanupSectionCopy.auditSummaryRestoreQuarantinedFile,
            detail: detail
        )
        do {
            try FileQuarantineStore.restore(entry)
            refreshCleanupTrash()
            completeCleanupOperationSucceeded(
                action: .restore,
                summary: StorageCleanupSectionCopy.auditSummaryRestoreQuarantinedFile,
                detail: detail,
                statusMessage: StorageCleanupSectionCopy.restoredQuarantinedFileStatus(entry.originalFileName)
            )
        } catch {
            completeCleanupOperationFailed(
                action: .restore,
                summary: StorageCleanupSectionCopy.auditSummaryRestoreQuarantinedFile,
                detail: StorageCleanupSectionCopy.auditDetailWithError(
                    detail,
                    errorDescription: error.localizedDescription
                ),
                statusMessage: StorageCleanupSectionCopy.restoreQuarantinedFileFailedStatus(error.localizedDescription)
            )
        }
    }

    func permanentlyDeleteQuarantinedFile(_ entry: FileQuarantineEntry) {
        let detail = cleanupAuditDetail(for: entry)
        recordCleanupAudit(
            action: .cleanup,
            outcome: .started,
            summary: StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteQuarantinedFile,
            detail: detail
        )
        do {
            try FileQuarantineStore.permanentlyDelete(entry)
            refreshCleanupTrash()
            completeCleanupOperationSucceeded(
                action: .cleanup,
                summary: StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteQuarantinedFile,
                detail: detail,
                statusMessage: StorageCleanupSectionCopy.permanentlyDeletedQuarantinedFileStatus(entry.originalFileName)
            )
        } catch {
            completeCleanupOperationFailed(
                action: .cleanup,
                summary: StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteQuarantinedFile,
                detail: StorageCleanupSectionCopy.auditDetailWithError(
                    detail,
                    errorDescription: error.localizedDescription
                ),
                statusMessage: StorageCleanupSectionCopy.permanentlyDeleteQuarantinedFileFailedStatus(error.localizedDescription)
            )
        }
    }

    func cleanupProjectFiles(_ usage: ProjectStorageUsage, category: ProjectStorageCleanupCategory) {
        let projectId = usage.projectId
        let auditDetail = StorageCleanupSectionCopy.projectCleanupAuditDetail(
            projectName: usage.projectName,
            categoryDisplayName: category.displayName
        )
        let undoSnapshot = StorageCleanupUndoSnapshot.capture(from: store)
        recordCleanupAudit(
            action: .cleanup,
            outcome: .started,
            summary: StorageCleanupSectionCopy.auditSummaryCleanupByProject,
            detail: auditDetail
        )
        var cleanupPlan = DeferredProjectFileCleanupPlan()

        switch category {
        case .photos:
            cleanupPlan.merge(cleanupProjectPhotos(projectId))
        case .videos:
            cleanupPlan.merge(cleanupProjectVideos(projectId))
        case .drawings:
            cleanupPlan.merge(cleanupProjectDrawings(projectId))
        case .tickets:
            cleanupPlan.merge(cleanupProjectTickets(projectId))
        case .all:
            cleanupPlan.merge(cleanupProjectPhotos(projectId))
            cleanupPlan.merge(cleanupProjectVideos(projectId))
            cleanupPlan.merge(cleanupProjectDrawings(projectId))
            cleanupPlan.merge(cleanupProjectTickets(projectId))
        }

        let summary = StorageCleanupSectionCopy.projectCleanupSummary(
            projectName: usage.projectName,
            categoryResultTitle: category.resultTitle
        )
        do {
            let retentionDays = normalizedCleanupTrashRetentionDays
            let batch = try StorageCleanupTrashStore.quarantine(
                plan: cleanupPlan,
                snapshot: undoSnapshot,
                summary: summary,
                retentionDays: retentionDays
            )
            refreshCleanupTrash()
            completeCleanupOperationSucceeded(
                action: .cleanup,
                summary: StorageCleanupSectionCopy.auditSummaryCleanupByProject,
                detail: StorageCleanupSectionCopy.auditDetailWithRetention(
                    auditDetail,
                    fileCount: batch.fileCount,
                    retentionDays: retentionDays
                ),
                statusMessage: StorageCleanupSectionCopy.projectFilesMovedToTrashStatus(
                    projectName: usage.projectName,
                    categoryResultTitle: category.resultTitle,
                    fileCount: batch.fileCount,
                    recoverableDateText: Formatters.date.string(from: batch.expiresAt)
                )
            )
            store.scheduleSave()
        } catch {
            undoSnapshot.restore(into: store)
            completeCleanupOperationFailed(
                action: .cleanup,
                summary: StorageCleanupSectionCopy.auditSummaryCleanupByProject,
                detail: StorageCleanupSectionCopy.auditDetailWithError(
                    auditDetail,
                    errorDescription: error.localizedDescription
                ),
                statusMessage: StorageCleanupSectionCopy.cleanupTrashWriteFailedStatus(error.localizedDescription)
            )
            store.scheduleSave()
        }
        pendingCleanupProject = nil
    }

    @discardableResult
    func cleanupProjectPhotos(_ projectId: UUID) -> DeferredProjectFileCleanupPlan {
        DeferredProjectFileCleanupPlan(
            store.clearProjectPhotoReferences(projectId: projectId)
        )
    }

    @discardableResult
    func cleanupProjectVideos(_ projectId: UUID) -> DeferredProjectFileCleanupPlan {
        DeferredProjectFileCleanupPlan(
            store.clearProjectVideoReferences(
                projectId: projectId,
                videoFileExtensions: videoFileExtensions
            )
        )
    }

    @discardableResult
    func cleanupProjectDrawings(_ projectId: UUID) -> DeferredProjectFileCleanupPlan {
        DeferredProjectFileCleanupPlan(
            store.clearProjectDrawingSourceReferences(
                projectId: projectId,
                drawingFileExtensions: drawingSourceFileExtensions
            )
        )
    }

    @discardableResult
    func cleanupProjectTickets(_ projectId: UUID) -> DeferredProjectFileCleanupPlan {
        DeferredProjectFileCleanupPlan(
            store.clearProjectTicketDocumentReferences(projectId: projectId)
        )
    }
}
