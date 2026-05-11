import Foundation

struct BackupRuntimeState {
    var isExportingArchive: Bool
    var isImportingBackup: Bool
    var isUploadingCloudBackup: Bool
    var isRefreshingCloudBackups: Bool

    var isBusy: Bool {
        isExportingArchive || isImportingBackup || isUploadingCloudBackup
    }

    var isCloudBusy: Bool {
        isRefreshingCloudBackups || isUploadingCloudBackup
    }
}

struct BackupEstimateState {
    var backupEstimate = BackupArchiveEstimate(
        metadataBytes: 0,
        rawFilesBytes: 0,
        missingFiles: []
    )
    var isEstimatingBackup = false
    var backupEstimateTask: Task<Void, Never>?
    var lastBackupEstimateSignature = 0
}

struct BackupCloudState {
    var cloudBackups: [CloudBackupFile] = []
    var cloudStatusMessage = ""
    var isRefreshingCloudBackups = false
    var isUploadingCloudBackup = false
    var cloudBackupTask: Task<Void, Never>?
    var pendingCloudRestore: CloudBackupFile?
    var showCloudRestoreConfirm = false
}
