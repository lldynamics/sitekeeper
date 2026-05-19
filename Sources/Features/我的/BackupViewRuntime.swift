import SwiftUI
import Foundation

extension BackupView {
    func refreshCloudBackups(force: Bool = false) {
        if cloudState.isRefreshingCloudBackups && !force {
            return
        }

        beginCloudRefreshTask()
        cloudState.cloudBackupTask = Task {
            do {
                let files = try await BackupCloudTaskCoordinator.refreshBackups()
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    applyCloudBackupsRefreshSuccess(files: files, force: force)
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    applyCloudBackupsRefreshFailure(error: error)
                }
            }
        }
    }

    func uploadBackupToICloud() {
        lastExportSucceeded = false
        clearAllStatusMessages()
        let options = cloudBackupOptions
        guard options.hasSelectedContent else {
            setCloudStatus(CloudBackupContentError.noSelection.localizedDescription)
            return
        }
        beginCloudUploadTask(currentItem: String(localized: "准备生成云备份"))
        let snapshot = store.makeCloudBackupSnapshot(options: options)

        cloudState.cloudBackupTask = Task {
            do {
                let result = try await BackupCloudTaskCoordinator.uploadBackup(
                    snapshot: snapshot,
                    progress: { progress in
                        Task { @MainActor in
                            exportProgress = progress
                        }
                    }
                )

                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeCloudBackupTask(status: String(localized: "已取消 iCloud 备份"))
                    }
                    return
                }

                await MainActor.run {
                    cloudState.cloudBackups = result.allBackups
                    setCloudStatus(String(
                        format: String(localized: "已备份到 iCloud：%@，%@。"),
                        result.savedFile.formattedSize,
                        result.savedFile.formattedModifiedAt
                    ))
                    cloudLastSuccessAt = result.savedFile.modifiedAt.timeIntervalSince1970
                    hasCompletedBackupExportTask = true
                    hasSeenBackupGuide = true
                    finalizeCloudBackupTask()
                }
            } catch {
                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeCloudBackupTask(status: String(localized: "已取消 iCloud 备份"))
                    }
                    return
                }
                await MainActor.run {
                    finalizeCloudBackupTask(status: String(format: String(localized: "iCloud 备份失败：%@"), error.localizedDescription))
                }
            }
        }
    }

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

    func normalizeCloudBackupSettings() {
        if CloudBackupAutoInterval(rawValue: cloudAutoIntervalRawValue) == nil {
            cloudAutoIntervalRawValue = CloudBackupAutoInterval.disabled.rawValue
        }
        cloudBackupRetentionCount = CloudBackupRetentionCountOption.normalized(cloudBackupRetentionCount)
        if !cloudIncludeProjectRecords {
            cloudIncludeProjectFilesAndNotes = false
            cloudIncludeAttachments = false
        } else if !cloudIncludeProjectFilesAndNotes {
            cloudIncludeAttachments = false
        }
    }

    func setStatus(_ message: String) {
        statusMessage = message
        emitStatusHaptic(message)
    }

    func clearStatus() {
        statusMessage = ""
    }

    func setCloudStatus(_ message: String) {
        cloudState.cloudStatusMessage = message
        emitStatusHaptic(message)
    }

    func clearCloudStatus() {
        cloudState.cloudStatusMessage = ""
    }

    func clearAllStatusMessages() {
        clearStatus()
        clearCloudStatus()
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

    private func applyCloudBackupsRefreshSuccess(files: [CloudBackupFile], force: Bool) {
        cloudState.cloudBackups = files
        if files.isEmpty && force {
            setCloudStatus(String(localized: "iCloud 中还没有备份。"))
        } else if !files.isEmpty && cloudState.cloudStatusMessage.contains(String(localized: "没有备份")) {
            clearCloudStatus()
        }
        cloudState.isRefreshingCloudBackups = false
        cloudState.cloudBackupTask = nil
    }

    private func applyCloudBackupsRefreshFailure(error: Error) {
        cloudState.cloudBackups = []
        setCloudStatus(String(format: String(localized: "iCloud 读取失败：%@"), error.localizedDescription))
        cloudState.isRefreshingCloudBackups = false
        cloudState.cloudBackupTask = nil
    }

    @MainActor
    private func finalizeCloudBackupTask(status: String? = nil) {
        BackupTaskStateReducer.finalizeCloud(state: &cloudState, status: status)
    }

    private func emitStatusHaptic(_ message: String) {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if normalized.contains(String(localized: "失败"))
            || normalized.contains(String(localized: "错误"))
            || normalized.contains(String(localized: "未能"))
            || normalized.contains(String(localized: "失效"))
            || normalized.contains(String(localized: "不正确")) {
            AppHaptics.error()
            return
        }
        if normalized.contains(String(localized: "取消"))
            || normalized.contains(String(localized: "警告"))
            || normalized.contains(String(localized: "提示")) {
            AppHaptics.warning()
            return
        }
        AppHaptics.success()
    }

    private func beginCloudRefreshTask() {
        cloudState.cloudBackupTask?.cancel()
        cloudState.isRefreshingCloudBackups = true
    }

    private func beginCloudUploadTask(currentItem: String) {
        cloudState.cloudBackupTask?.cancel()
        cloudState.isUploadingCloudBackup = true
        exportProgress = BackupArchiveProgress(completedSteps: 0, totalSteps: 1, currentItem: currentItem)
    }
}
