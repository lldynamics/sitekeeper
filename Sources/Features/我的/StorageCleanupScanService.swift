import Foundation

@MainActor
enum StorageCleanupScanService {
    static func scanResult(
        store: DataStore,
        cloudBackups: [CloudBackupFile],
        projectBackupEstimateByID: [UUID: Int],
        largeFileThresholdMegabytes: Int,
        videoFileExtensions: Set<String>,
        drawingSourceFileExtensions: Set<String>
    ) -> StorageCleanupScanResult {
        StorageCleanupScanner.scan(
            store: store,
            cloudBackups: cloudBackups,
            projectBackupEstimateByID: projectBackupEstimateByID,
            largeFileThresholdBytes: StorageCleanupLargeFileThresholdOption.bytes(for: largeFileThresholdMegabytes),
            videoFileExtensions: videoFileExtensions,
            drawingSourceFileExtensions: drawingSourceFileExtensions
        )
    }

    static func cleanupPreview(
        store: DataStore,
        projectId: UUID,
        category: ProjectStorageCleanupCategory,
        videoFileExtensions: Set<String>,
        drawingSourceFileExtensions: Set<String>
    ) -> CleanupImpactSummary {
        StorageCleanupScanner.cleanupPreview(
            store: store,
            projectId: projectId,
            category: category,
            videoFileExtensions: videoFileExtensions,
            drawingSourceFileExtensions: drawingSourceFileExtensions
        )
    }

    nonisolated static func projectBackupEstimates(
        baseSnapshot: BackupSnapshot,
        projectIDs: [UUID]
    ) -> [UUID: Int] {
        var estimates: [UUID: Int] = [:]
        estimates.reserveCapacity(projectIDs.count)

        for projectId in projectIDs {
            let scopedSnapshot = StorageCleanupScanner.makeProjectScopedSnapshot(
                from: baseSnapshot,
                projectId: projectId
            )
            estimates[projectId] = StorageCleanupScanner.estimateBackupBytes(for: scopedSnapshot)
        }
        return estimates
    }
}
