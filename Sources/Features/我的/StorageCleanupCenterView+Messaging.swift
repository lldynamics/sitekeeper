import SwiftUI

extension StorageCleanupCenterView {
    var cleanupAuditSource: String { "StorageCleanupCenterView" }

    func cleanupTrashExpirationDate(from date: Date) -> Date {
        StorageCleanupMessagingService.cleanupTrashExpirationDate(
            from: date,
            retentionDays: normalizedCleanupTrashRetentionDays
        )
    }

    func cleanupConfirmationMessage(for usage: ProjectStorageUsage, category: ProjectStorageCleanupCategory) -> String {
        let preview = cleanupPreview(for: usage.projectId, category: category)
        return StorageCleanupMessagingService.cleanupConfirmationMessage(
            usage: usage,
            category: category,
            preview: preview,
            recoverableDate: cleanupTrashExpirationDate(from: Date()),
            retentionDays: normalizedCleanupTrashRetentionDays,
            backupReminderMessage: backupReminderMessage()
        )
    }

    func backupReminderMessage() -> String {
        StorageCleanupMessagingService.backupReminderMessage(
            latestBackupDate: latestBackupDateForReminder,
            backupHealthReminderDays: backupHealthReminderDays
        )
    }

    var latestBackupDateForReminder: Date? {
        StorageCleanupMessagingService.latestBackupDate(
            localBackupLastSuccessAt: localBackupLastSuccessAt,
            cloudBackupLastSuccessAt: cloudBackupLastSuccessAt,
            latestCloudBackupDate: cloudBackups.first?.modifiedAt
        )
    }
}
