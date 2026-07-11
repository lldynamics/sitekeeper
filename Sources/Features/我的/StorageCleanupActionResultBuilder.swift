import Foundation

enum StorageCleanupActionResultBuilder {
    struct AuditEvent {
        let action: OperationAuditEntry.Action
        let summary: String
        let detail: String
    }

    struct CompletionEvent {
        let action: OperationAuditEntry.Action
        let summary: String
        let detail: String
        let statusMessage: String
    }

    struct ProjectCleanupContext {
        let usage: ProjectStorageUsage
        let category: ProjectStorageCleanupCategory
        let auditDetail: String
        let cleanupSummary: String
    }

    static func restoreCleanupTrashStarted(_ batch: StorageCleanupTrashBatch) -> AuditEvent {
        AuditEvent(
            action: .restore,
            summary: StorageCleanupSectionCopy.auditSummaryRestoreCleanupTrash,
            detail: batch.summary
        )
    }

    static func restoreCleanupTrashSucceeded(_ batch: StorageCleanupTrashBatch) -> CompletionEvent {
        CompletionEvent(
            action: .restore,
            summary: StorageCleanupSectionCopy.auditSummaryRestoreCleanupTrash,
            detail: StorageCleanupSectionCopy.auditDetailRestoredCleanupBatch(batch.summary, fileCount: batch.fileCount),
            statusMessage: StorageCleanupSectionCopy.restoredCleanupTrashStatus(batch.summary)
        )
    }

    static func restoreCleanupTrashFailed(_ batch: StorageCleanupTrashBatch, error: Error) -> CompletionEvent {
        CompletionEvent(
            action: .restore,
            summary: StorageCleanupSectionCopy.auditSummaryRestoreCleanupTrash,
            detail: StorageCleanupSectionCopy.auditDetailWithError(batch.summary, errorDescription: error.localizedDescription),
            statusMessage: StorageCleanupSectionCopy.restoreCleanupTrashFailedStatus(error.localizedDescription)
        )
    }

    static func permanentlyDeleteCleanupTrashStarted(_ batch: StorageCleanupTrashBatch) -> AuditEvent {
        AuditEvent(
            action: .cleanup,
            summary: StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteCleanupTrash,
            detail: batch.summary
        )
    }

    static func permanentlyDeleteCleanupTrashSucceeded(_ batch: StorageCleanupTrashBatch) -> CompletionEvent {
        CompletionEvent(
            action: .cleanup,
            summary: StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteCleanupTrash,
            detail: StorageCleanupSectionCopy.auditDetailDeletedCleanupBatch(batch.summary, fileCount: batch.fileCount),
            statusMessage: StorageCleanupSectionCopy.permanentlyDeletedCleanupTrashStatus(batch.summary)
        )
    }

    static func permanentlyDeleteCleanupTrashFailed(_ batch: StorageCleanupTrashBatch, error: Error) -> CompletionEvent {
        CompletionEvent(
            action: .cleanup,
            summary: StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteCleanupTrash,
            detail: StorageCleanupSectionCopy.auditDetailWithError(batch.summary, errorDescription: error.localizedDescription),
            statusMessage: StorageCleanupSectionCopy.permanentlyDeleteCleanupTrashFailedStatus(error.localizedDescription)
        )
    }

    static func restoreQuarantinedFileStarted(_ entry: FileQuarantineEntry) -> AuditEvent {
        AuditEvent(
            action: .restore,
            summary: StorageCleanupSectionCopy.auditSummaryRestoreQuarantinedFile,
            detail: StorageCleanupAuditService.cleanupAuditDetail(for: entry)
        )
    }

    static func restoreQuarantinedFileSucceeded(_ entry: FileQuarantineEntry) -> CompletionEvent {
        CompletionEvent(
            action: .restore,
            summary: StorageCleanupSectionCopy.auditSummaryRestoreQuarantinedFile,
            detail: StorageCleanupAuditService.cleanupAuditDetail(for: entry),
            statusMessage: StorageCleanupSectionCopy.restoredQuarantinedFileStatus(entry.originalFileName)
        )
    }

    static func restoreQuarantinedFileFailed(_ entry: FileQuarantineEntry, error: Error) -> CompletionEvent {
        let detail = StorageCleanupAuditService.cleanupAuditDetail(for: entry)
        return CompletionEvent(
            action: .restore,
            summary: StorageCleanupSectionCopy.auditSummaryRestoreQuarantinedFile,
            detail: StorageCleanupSectionCopy.auditDetailWithError(
                detail,
                errorDescription: error.localizedDescription
            ),
            statusMessage: StorageCleanupSectionCopy.restoreQuarantinedFileFailedStatus(error.localizedDescription)
        )
    }

    static func permanentlyDeleteQuarantinedFileStarted(_ entry: FileQuarantineEntry) -> AuditEvent {
        AuditEvent(
            action: .cleanup,
            summary: StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteQuarantinedFile,
            detail: StorageCleanupAuditService.cleanupAuditDetail(for: entry)
        )
    }

    static func permanentlyDeleteQuarantinedFileSucceeded(_ entry: FileQuarantineEntry) -> CompletionEvent {
        CompletionEvent(
            action: .cleanup,
            summary: StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteQuarantinedFile,
            detail: StorageCleanupAuditService.cleanupAuditDetail(for: entry),
            statusMessage: StorageCleanupSectionCopy.permanentlyDeletedQuarantinedFileStatus(entry.originalFileName)
        )
    }

    static func permanentlyDeleteQuarantinedFileFailed(_ entry: FileQuarantineEntry, error: Error) -> CompletionEvent {
        let detail = StorageCleanupAuditService.cleanupAuditDetail(for: entry)
        return CompletionEvent(
            action: .cleanup,
            summary: StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteQuarantinedFile,
            detail: StorageCleanupSectionCopy.auditDetailWithError(
                detail,
                errorDescription: error.localizedDescription
            ),
            statusMessage: StorageCleanupSectionCopy.permanentlyDeleteQuarantinedFileFailedStatus(error.localizedDescription)
        )
    }

    static func projectCleanupContext(
        usage: ProjectStorageUsage,
        category: ProjectStorageCleanupCategory
    ) -> ProjectCleanupContext {
        ProjectCleanupContext(
            usage: usage,
            category: category,
            auditDetail: StorageCleanupSectionCopy.projectCleanupAuditDetail(
                projectName: usage.projectName,
                categoryDisplayName: category.displayName
            ),
            cleanupSummary: StorageCleanupSectionCopy.projectCleanupSummary(
                projectName: usage.projectName,
                categoryResultTitle: category.resultTitle
            )
        )
    }

    static func cleanupProjectFilesStarted(_ context: ProjectCleanupContext) -> AuditEvent {
        AuditEvent(
            action: .cleanup,
            summary: StorageCleanupSectionCopy.auditSummaryCleanupByProject,
            detail: context.auditDetail
        )
    }

    static func cleanupProjectFilesSucceeded(
        _ context: ProjectCleanupContext,
        batch: StorageCleanupTrashBatch,
        retentionDays: Int
    ) -> CompletionEvent {
        CompletionEvent(
            action: .cleanup,
            summary: StorageCleanupSectionCopy.auditSummaryCleanupByProject,
            detail: StorageCleanupSectionCopy.auditDetailWithRetention(
                context.auditDetail,
                fileCount: batch.fileCount,
                retentionDays: retentionDays
            ),
            statusMessage: StorageCleanupSectionCopy.projectFilesMovedToTrashStatus(
                projectName: context.usage.projectName,
                categoryResultTitle: context.category.resultTitle,
                fileCount: batch.fileCount,
                recoverableDateText: Formatters.date.string(from: batch.expiresAt)
            )
        )
    }

    static func cleanupProjectFilesFailed(_ context: ProjectCleanupContext, error: Error) -> CompletionEvent {
        CompletionEvent(
            action: .cleanup,
            summary: StorageCleanupSectionCopy.auditSummaryCleanupByProject,
            detail: StorageCleanupSectionCopy.auditDetailWithError(
                context.auditDetail,
                errorDescription: error.localizedDescription
            ),
            statusMessage: StorageCleanupSectionCopy.cleanupTrashWriteFailedStatus(error.localizedDescription)
        )
    }
}
