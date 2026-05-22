import SwiftUI
import Foundation

extension BackupView {
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

    func emitStatusHaptic(_ message: String) {
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
}
