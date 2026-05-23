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

        do {
            let backups = try await FileIOTaskRunner.run(
                priority: .utility,
                logContext: .init(
                    event: "storage_cleanup.cloud_backup_list",
                    source: "StorageCleanupCenterView.refreshCloudBackups",
                    category: .cloudBackup
                )
            ) {
                try CloudBackupService.listBackups()
            }
            cloudBackups = backups
            cloudBackupError = nil
        } catch {
            let errorMessage = error.localizedDescription
            cloudBackups = []
            cloudBackupError = errorMessage
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
        do {
            projectBackupEstimateByID = try await FileIOTaskRunner.run(priority: .utility) {
                var estimates: [UUID: Int] = [:]
                estimates.reserveCapacity(projectIDs.count)

                for projectId in projectIDs {
                    let scopedSnapshot = StorageCleanupScanner.makeProjectScopedSnapshot(from: baseSnapshot, projectId: projectId)
                    estimates[projectId] = StorageCleanupScanner.estimateBackupBytes(for: scopedSnapshot)
                }
                return estimates
            }
        } catch {
            projectBackupEstimateByID = [:]
        }
    }
}
