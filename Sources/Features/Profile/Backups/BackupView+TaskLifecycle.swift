import SwiftUI
import Foundation

extension BackupView {
    @MainActor
    func finalizeImportTask(
        status: String? = nil,
        cleanupPendingFile: Bool = false,
        closePreview: Bool = false
    ) {
        BackupTaskStateReducer.finalizeImport(
            isImportingBackup: &isImportingBackup,
            importTask: &importTask,
            statusMessage: &statusMessage,
            status: status
        )
        if closePreview {
            showPreview = false
        }
        if cleanupPendingFile {
            cleanupPendingImportFileIfNeeded()
        }
    }

    @MainActor
    func finalizeExportTask(status: String? = nil, cleanupExportFile: Bool = false) {
        BackupTaskStateReducer.finalizeExport(
            isExportingArchive: &isExportingArchive,
            exportTask: &exportTask,
            statusMessage: &statusMessage,
            status: status
        )
        if cleanupExportFile {
            cleanupExportArchiveIfNeeded()
        }
    }

    @MainActor
    func resetBackupRuntimeStateOnDisappear() {
        estimateState.backupEstimateTask?.cancel()
        estimateState.backupEstimateTask = nil
        estimateState.isEstimatingBackup = false

        exportTask?.cancel()
        cloudState.cloudBackupTask?.cancel()
        importTask?.cancel()

        finalizeExportTask(cleanupExportFile: true)
        finalizeCloudBackupTask()
        finalizeImportTask(cleanupPendingFile: true)
    }

    func refreshBackupEstimateIfNeeded(force: Bool = false) {
        let signature = backupEstimateSignature
        if !force, signature == estimateState.lastBackupEstimateSignature {
            return
        }

        estimateState.backupEstimateTask?.cancel()
        estimateState.isEstimatingBackup = true
        let snapshot = store.makeSnapshot(includePhotoFiles: false)

        estimateState.backupEstimateTask = Task {
            let estimate = await Task.detached(priority: .utility) {
                BackupArchiveService.estimateArchive(from: snapshot)
            }.value

            guard !Task.isCancelled else { return }

            await MainActor.run {
                estimateState.backupEstimate = estimate
                estimateState.lastBackupEstimateSignature = signature
                estimateState.isEstimatingBackup = false
            }
        }
    }

    func beginExportTask(currentItem: String) {
        exportTask?.cancel()
        AppHaptics.impact(.light)
        isExportingArchive = true
        exportProgress = BackupArchiveProgress(completedSteps: 0, totalSteps: 1, currentItem: currentItem)
    }

    func beginImportTask(title: String, totalBytes: Int64, currentItem: String) {
        importTask?.cancel()
        AppHaptics.impact(.light)
        isImportingBackup = true
        importProgressTitle = title
        importProgress = BackupImportProgress(
            completedBytes: 0,
            totalBytes: max(totalBytes, 1),
            currentItem: currentItem
        )
    }
}
