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
        cloudState.cloudBackupTask = Task {
            do {
                let result = try await store.withBackupExport {
                    let snapshot = store.makeCloudBackupSnapshot(options: options)
                    return try await BackupCloudTaskCoordinator.uploadBackup(
                        snapshot: snapshot,
                        progress: { progress in
                            Task { @MainActor in
                                exportProgress = progress
                            }
                        }
                    )
                }

                guard !Task.isCancelled else {
                    await MainActor.run {
                        finalizeCloudBackupTask(status: String(localized: "已取消 iCloud 备份"))
                    }
                    return
                }

                await MainActor.run {
                    cloudState.cloudBackups = result.allBackups
                    setCloudStatus(result.savedFile.uploadState.statusMessage)
                    if result.savedFile.uploadState == .uploaded {
                        hasCompletedBackupExportTask = true
                        hasSeenBackupGuide = true
                    }
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

    func applyCloudBackupsRefreshSuccess(files: [CloudBackupFile], force: Bool) {
        cloudState.cloudBackups = files
        if files.isEmpty && force {
            setCloudStatus(String(localized: "iCloud 中还没有备份。"))
        } else if let latest = files.first {
            setCloudStatus(latest.uploadState.statusMessage)
            if latest.uploadState == .uploaded {
                hasCompletedBackupExportTask = true
            }
        } else if !files.isEmpty && cloudState.cloudStatusMessage.contains(String(localized: "没有备份")) {
            clearCloudStatus()
        }
        cloudState.isRefreshingCloudBackups = false
        cloudState.cloudBackupTask = nil
    }

    func applyCloudBackupsRefreshFailure(error: Error) {
        cloudState.cloudBackups = []
        setCloudStatus(String(format: String(localized: "iCloud 读取失败：%@"), error.localizedDescription))
        cloudState.isRefreshingCloudBackups = false
        cloudState.cloudBackupTask = nil
    }

    @MainActor
    func finalizeCloudBackupTask(status: String? = nil) {
        BackupTaskStateReducer.finalizeCloud(state: &cloudState, status: status)
    }

    func beginCloudRefreshTask() {
        cloudState.cloudBackupTask?.cancel()
        cloudState.isRefreshingCloudBackups = true
    }

    func beginCloudUploadTask(currentItem: String) {
        cloudState.cloudBackupTask?.cancel()
        cloudState.isUploadingCloudBackup = true
        exportProgress = BackupArchiveProgress(completedSteps: 0, totalSteps: 1, currentItem: currentItem)
    }
}
