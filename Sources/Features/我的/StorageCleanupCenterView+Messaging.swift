import SwiftUI

extension StorageCleanupCenterView {
    func cleanupTrashExpirationDate(from date: Date) -> Date {
        let retentionDays = max(normalizedCleanupTrashRetentionDays, 1)
        return Calendar.current.date(byAdding: .day, value: retentionDays, to: date)
            ?? date.addingTimeInterval(TimeInterval(retentionDays * 24 * 60 * 60))
    }

    func cleanupConfirmationMessage(for usage: ProjectStorageUsage, category: ProjectStorageCleanupCategory) -> String {
        let preview = cleanupPreview(for: usage.projectId, category: category)
        var lines: [String] = [category.confirmationMessage(projectName: usage.projectName)]

        if preview.totalFileCount > 0 {
            lines.append(StorageCleanupSectionCopy.cleanupConfirmationDeletedFileCount(preview.totalFileCount))
            for item in preview.fileItems {
                lines.append(StorageCleanupSectionCopy.cleanupConfirmationFileLine(title: item.title, count: item.count))
            }
        } else {
            lines.append(StorageCleanupSectionCopy.cleanupConfirmationNoFileDeletion)
        }

        lines.append(StorageCleanupSectionCopy.cleanupConfirmationAffectedRecordsHeader)
        if preview.recordItems.isEmpty {
            lines.append(StorageCleanupSectionCopy.cleanupConfirmationNoRecordChange)
        } else {
            for item in preview.recordItems {
                lines.append(StorageCleanupSectionCopy.cleanupConfirmationRecordLine(title: item.title, count: item.count))
            }
        }

        if !preview.sampleFileNames.isEmpty {
            let sampleSeparator = StorageCleanupSectionCopy.cleanupConfirmationSampleSeparator
            lines.append(
                StorageCleanupSectionCopy.cleanupConfirmationSampleFiles(
                    preview.sampleFileNames.prefix(5).joined(separator: sampleSeparator)
                )
            )
        }

        lines.append(
            StorageCleanupSectionCopy.cleanupConfirmationRecoverableHint(
                dateText: Formatters.date.string(from: cleanupTrashExpirationDate(from: Date())),
                retentionDays: normalizedCleanupTrashRetentionDays
            )
        )
        lines.append(backupReminderMessage())
        return lines.joined(separator: "\n")
    }

    func backupReminderMessage() -> String {
        guard let latestDate = latestBackupDateForReminder else {
            return StorageCleanupSectionCopy.backupReminderNoBackup
        }

        let calendar = Calendar.current
        let latestDay = calendar.startOfDay(for: latestDate)
        let today = calendar.startOfDay(for: Date())
        let daysSinceBackup = max(calendar.dateComponents([.day], from: latestDay, to: today).day ?? 0, 0)
        let formattedDate = Formatters.dateTime.string(from: latestDate)
        let reminderDays = max(1, backupHealthReminderDays)

        if daysSinceBackup >= reminderDays {
            return StorageCleanupSectionCopy.backupReminderExpired(
                dateText: formattedDate,
                daysSinceBackup: daysSinceBackup
            )
        }

        return StorageCleanupSectionCopy.backupReminderRecent(dateText: formattedDate)
    }

    var latestBackupDateForReminder: Date? {
        var candidates: [Date] = []
        if localBackupLastSuccessAt > 0 {
            candidates.append(Date(timeIntervalSince1970: localBackupLastSuccessAt))
        }
        if cloudBackupLastSuccessAt > 0 {
            candidates.append(Date(timeIntervalSince1970: cloudBackupLastSuccessAt))
        }
        if let latestCloudBackup = cloudBackups.first?.modifiedAt {
            candidates.append(latestCloudBackup)
        }
        return candidates.max()
    }

    func cleanupAuditDetail(for entry: FileQuarantineEntry) -> String {
        "\(entry.category.rawValue) · \(entry.originalFileName)"
    }

    func recordCleanupAudit(
        action: OperationAuditEntry.Action,
        outcome: OperationAuditEntry.Outcome,
        summary: String,
        detail: String
    ) {
        OperationAuditLog.record(
            action: action,
            outcome: outcome,
            summary: summary,
            detail: detail,
            source: "StorageCleanupCenterView"
        )
    }

    func completeCleanupOperationSucceeded(
        action: OperationAuditEntry.Action,
        summary: String,
        detail: String,
        statusMessage: String
    ) {
        cleanupStatusMessage = statusMessage
        recordCleanupAudit(
            action: action,
            outcome: .succeeded,
            summary: summary,
            detail: detail
        )
    }

    func completeCleanupOperationFailed(
        action: OperationAuditEntry.Action,
        summary: String,
        detail: String,
        statusMessage: String
    ) {
        cleanupStatusMessage = statusMessage
        recordCleanupAudit(
            action: action,
            outcome: .failed,
            summary: summary,
            detail: detail
        )
    }
}
