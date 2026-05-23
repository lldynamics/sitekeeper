import SwiftUI

extension StorageCleanupCenterView {
    var largeFileThresholdBytes: Int {
        StorageCleanupLargeFileThresholdOption.bytes(for: largeFileThresholdMB)
    }

    var scanResult: StorageCleanupScanResult {
        StorageCleanupScanner.scan(
            store: store,
            cloudBackups: cloudBackups,
            projectBackupEstimateByID: projectBackupEstimateByID,
            largeFileThresholdBytes: largeFileThresholdBytes,
            videoFileExtensions: videoFileExtensions,
            drawingSourceFileExtensions: drawingSourceFileExtensions
        )
    }

    var categorySummaries: [StorageCategorySummary] {
        scanResult.categorySummaries
    }

    var largeFileItems: [StorageLargeFileItem] {
        scanResult.largeFileItems
    }

    var projectUsages: [ProjectStorageUsage] {
        scanResult.projectUsages
    }

    func normalizeLargeFileThresholdPreference() {
        let normalized = StorageCleanupLargeFileThresholdOption.normalizedMegabytes(largeFileThresholdMB)
        if largeFileThresholdMB != normalized {
            largeFileThresholdMB = normalized
        }
    }

    func normalizeCleanupTrashRetentionPreference() {
        let normalized = StorageCleanupTrashRetentionOption.normalizedDays(cleanupTrashRetentionDays)
        if cleanupTrashRetentionDays != normalized {
            cleanupTrashRetentionDays = normalized
        }
    }

    func refreshCloudBackups() async {
        guard !isRefreshingCloudBackups else { return }
        isRefreshingCloudBackups = true
        defer { isRefreshingCloudBackups = false }

        let task = Task.detached(priority: .utility) { () -> ([CloudBackupFile], String?) in
            do {
                return (try CloudBackupService.listBackups(), nil)
            } catch {
                return ([], error.localizedDescription)
            }
        }
        let (backups, errorMessage) = await task.value

        if let errorMessage, !errorMessage.isEmpty {
            cloudBackups = []
            cloudBackupError = errorMessage
            StorageIssueLog.recordEvent(
                "storage_cleanup.cloud_backup_list_failed",
                category: .cloudBackup,
                details: [
                    "source": "StorageCleanupCenterView.refreshCloudBackups",
                    "error_message": errorMessage
                ]
            )
        } else {
            cloudBackups = backups
            cloudBackupError = nil
        }
    }

    func cleanupPreview(for projectId: UUID, category: ProjectStorageCleanupCategory) -> CleanupImpactSummary {
        StorageCleanupScanner.cleanupPreview(
            store: store,
            projectId: projectId,
            category: category,
            videoFileExtensions: videoFileExtensions,
            drawingSourceFileExtensions: drawingSourceFileExtensions
        )
    }

    @MainActor
    func refreshProjectBackupEstimates() async {
        guard !isRefreshingProjectBackupEstimates else { return }
        isRefreshingProjectBackupEstimates = true
        defer { isRefreshingProjectBackupEstimates = false }

        let baseSnapshot = store.makeSnapshot(includePhotoFiles: false)
        let projectIDs = store.projects.map(\.id)
        let estimateTask = Task.detached(priority: .utility) { () -> [UUID: Int] in
            var estimates: [UUID: Int] = [:]
            estimates.reserveCapacity(projectIDs.count)

            for projectId in projectIDs {
                let scopedSnapshot = StorageCleanupScanner.makeProjectScopedSnapshot(from: baseSnapshot, projectId: projectId)
                estimates[projectId] = StorageCleanupScanner.estimateBackupBytes(for: scopedSnapshot)
            }
            return estimates
        }

        projectBackupEstimateByID = await estimateTask.value
    }
}
