import SwiftUI

extension StorageCleanupCenterView {
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

    func refreshScanResult() {
        scanResult = StorageCleanupScanService.scanResult(
            store: store,
            cloudBackups: cloudBackups,
            projectBackupEstimateByID: projectBackupEstimateByID,
            largeFileThresholdMegabytes: largeFileThresholdMB,
            videoFileExtensions: videoFileExtensions,
            drawingSourceFileExtensions: drawingSourceFileExtensions
        )
    }

    func refreshCloudBackups(refreshScan: Bool = true) async {
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
        if refreshScan {
            refreshScanResult()
        }
    }

    func cleanupPreview(for projectId: UUID, category: ProjectStorageCleanupCategory) -> CleanupImpactSummary {
        StorageCleanupScanService.cleanupPreview(
            store: store,
            projectId: projectId,
            category: category,
            videoFileExtensions: videoFileExtensions,
            drawingSourceFileExtensions: drawingSourceFileExtensions
        )
    }

    @MainActor
    func refreshProjectBackupEstimates(refreshScan: Bool = true) async {
        guard !isRefreshingProjectBackupEstimates else { return }
        isRefreshingProjectBackupEstimates = true
        defer { isRefreshingProjectBackupEstimates = false }

        let baseSnapshot = store.makeSnapshot(includePhotoFiles: false)
        let projectIDs = store.projects.map(\.id)
        do {
            projectBackupEstimateByID = try await FileIOTaskRunner.run(priority: .utility) {
                StorageCleanupScanService.projectBackupEstimates(
                    baseSnapshot: baseSnapshot,
                    projectIDs: projectIDs
                )
            }
        } catch {
            projectBackupEstimateByID = [:]
        }
        if refreshScan {
            refreshScanResult()
        }
    }

    @MainActor
    func refreshInitialStorageData() async {
        await refreshCloudBackups(refreshScan: false)
        await refreshProjectBackupEstimates(refreshScan: false)
        refreshScanResult()
        hasCompletedInitialStorageLoad = true
    }
}
