import Foundation

@MainActor
enum StorageCleanupExecutionService {
    struct RefreshTrashResult {
        let cleanupTrashBatches: [StorageCleanupTrashBatch]
        let quarantinedFiles: [FileQuarantineEntry]
        let purgedCleanupBatchCount: Int
        let purgedQuarantineFileCount: Int
    }

    static func refreshTrash(now: Date = Date()) -> RefreshTrashResult {
        let purgedCleanupBatchCount = StorageCleanupTrashStore.purgeExpiredBatches(now: now)
        let purgedQuarantineFileCount = FileQuarantineStore.purgeExpiredEntries(now: now)
        let cleanupTrashBatches = StorageCleanupTrashStore.loadBatches()
        let quarantinedFiles = FileQuarantineStore.loadEntries()

        if purgedCleanupBatchCount > 0 {
            StorageIssueLog.recordEvent(
                "storage_cleanup.cleanup_trash_batches_purged",
                category: .dataStore,
                details: [
                    "source": "StorageCleanupExecutionService.refreshTrash",
                    "purged_count": "\(purgedCleanupBatchCount)"
                ]
            )
        }
        if purgedQuarantineFileCount > 0 {
            StorageIssueLog.recordEvent(
                "storage_cleanup.quarantined_files_purged",
                category: .fileStorage,
                details: [
                    "source": "StorageCleanupExecutionService.refreshTrash",
                    "purged_count": "\(purgedQuarantineFileCount)"
                ]
            )
        }

        return RefreshTrashResult(
            cleanupTrashBatches: cleanupTrashBatches,
            quarantinedFiles: quarantinedFiles,
            purgedCleanupBatchCount: purgedCleanupBatchCount,
            purgedQuarantineFileCount: purgedQuarantineFileCount
        )
    }

    static func restoreCleanupTrash(_ batch: StorageCleanupTrashBatch, store: DataStore) throws {
        try store.requireMaintenanceAllowed()
        try StorageCleanupTrashStore.restore(batch)
        batch.snapshot.restore(into: store)
        store.scheduleSave()
    }

    static func permanentlyDeleteCleanupTrash(_ batch: StorageCleanupTrashBatch) throws {
        try StorageCleanupTrashStore.permanentlyDelete(batch)
    }

    static func restoreQuarantinedFile(_ entry: FileQuarantineEntry, store: DataStore) throws {
        try store.requireMaintenanceAllowed()
        try FileQuarantineStore.restore(entry)
    }

    static func permanentlyDeleteQuarantinedFile(_ entry: FileQuarantineEntry) throws {
        try FileQuarantineStore.permanentlyDelete(entry)
    }

    static func cleanupProjectFiles(
        store: DataStore,
        projectId: UUID,
        category: ProjectStorageCleanupCategory,
        retentionDays: Int,
        summary: String,
        videoFileExtensions: Set<String>,
        drawingSourceFileExtensions: Set<String>
    ) throws -> StorageCleanupTrashBatch {
        try store.requireMaintenanceAllowed()
        let undoSnapshot = StorageCleanupUndoSnapshot.capture(from: store)
        let cleanupPlan = cleanupPlan(
            store: store,
            projectId: projectId,
            category: category,
            videoFileExtensions: videoFileExtensions,
            drawingSourceFileExtensions: drawingSourceFileExtensions
        )

        do {
            let batch = try StorageCleanupTrashStore.quarantine(
                plan: cleanupPlan,
                snapshot: undoSnapshot,
                summary: summary,
                retentionDays: retentionDays
            )
            store.scheduleSave()
            return batch
        } catch {
            undoSnapshot.restore(into: store)
            store.scheduleSave()
            throw error
        }
    }

    private static func cleanupPlan(
        store: DataStore,
        projectId: UUID,
        category: ProjectStorageCleanupCategory,
        videoFileExtensions: Set<String>,
        drawingSourceFileExtensions: Set<String>
    ) -> DeferredProjectFileCleanupPlan {
        var cleanupPlan = DeferredProjectFileCleanupPlan()
        switch category {
        case .photos:
            cleanupPlan.merge(
                DeferredProjectFileCleanupPlan(
                    store.clearProjectPhotoReferences(projectId: projectId)
                )
            )
        case .videos:
            cleanupPlan.merge(
                DeferredProjectFileCleanupPlan(
                    store.clearProjectVideoReferences(
                        projectId: projectId,
                        videoFileExtensions: videoFileExtensions
                    )
                )
            )
        case .drawings:
            cleanupPlan.merge(
                DeferredProjectFileCleanupPlan(
                    store.clearProjectDrawingSourceReferences(
                        projectId: projectId,
                        drawingFileExtensions: drawingSourceFileExtensions
                    )
                )
            )
        case .tickets:
            cleanupPlan.merge(
                DeferredProjectFileCleanupPlan(
                    store.clearProjectTicketDocumentReferences(projectId: projectId)
                )
            )
        case .all:
            cleanupPlan.merge(
                DeferredProjectFileCleanupPlan(
                    store.clearProjectPhotoReferences(projectId: projectId)
                )
            )
            cleanupPlan.merge(
                DeferredProjectFileCleanupPlan(
                    store.clearProjectVideoReferences(
                        projectId: projectId,
                        videoFileExtensions: videoFileExtensions
                    )
                )
            )
            cleanupPlan.merge(
                DeferredProjectFileCleanupPlan(
                    store.clearProjectDrawingSourceReferences(
                        projectId: projectId,
                        drawingFileExtensions: drawingSourceFileExtensions
                    )
                )
            )
            cleanupPlan.merge(
                DeferredProjectFileCleanupPlan(
                    store.clearProjectTicketDocumentReferences(projectId: projectId)
                )
            )
        }
        return cleanupPlan
    }
}
