import Foundation

enum BackupTaskStateReducer {
    static func finalizeExport(
        isExportingArchive: inout Bool,
        exportTask: inout Task<Void, Never>?,
        statusMessage: inout String,
        status: String? = nil
    ) {
        isExportingArchive = false
        exportTask = nil
        if let status {
            statusMessage = status
        }
    }

    static func finalizeImport(
        isImportingBackup: inout Bool,
        importTask: inout Task<Void, Never>?,
        statusMessage: inout String,
        status: String? = nil
    ) {
        isImportingBackup = false
        importTask = nil
        if let status {
            statusMessage = status
        }
    }

    static func finalizeCloud(
        isUploadingCloudBackup: inout Bool,
        isRefreshingCloudBackups: inout Bool,
        cloudBackupTask: inout Task<Void, Never>?,
        cloudStatusMessage: inout String,
        status: String? = nil
    ) {
        isUploadingCloudBackup = false
        isRefreshingCloudBackups = false
        cloudBackupTask = nil
        if let status {
            cloudStatusMessage = status
        }
    }

    static func finalizeCloud(
        state: inout BackupCloudState,
        status: String? = nil
    ) {
        state.isUploadingCloudBackup = false
        state.isRefreshingCloudBackups = false
        state.cloudBackupTask = nil
        if let status {
            state.cloudStatusMessage = status
        }
    }
}
