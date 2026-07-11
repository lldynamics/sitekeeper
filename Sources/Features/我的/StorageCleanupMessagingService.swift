import Foundation

enum StorageCleanupMessagingService {
    static func cleanupTrashExpirationDate(from date: Date, retentionDays: Int) -> Date {
        let normalizedRetentionDays = max(retentionDays, 1)
        return Calendar.current.date(byAdding: .day, value: normalizedRetentionDays, to: date)
            ?? date.addingTimeInterval(TimeInterval(normalizedRetentionDays * 24 * 60 * 60))
    }

    static func latestBackupDate(
        localBackupLastSuccessAt: Double,
        cloudBackupLastSuccessAt: Double,
        latestCloudBackupDate: Date?
    ) -> Date? {
        var candidates: [Date] = []
        if localBackupLastSuccessAt > 0 {
            candidates.append(Date(timeIntervalSince1970: localBackupLastSuccessAt))
        }
        if cloudBackupLastSuccessAt > 0 {
            candidates.append(Date(timeIntervalSince1970: cloudBackupLastSuccessAt))
        }
        if let latestCloudBackupDate {
            candidates.append(latestCloudBackupDate)
        }
        return candidates.max()
    }

    static func backupReminderMessage(
        latestBackupDate: Date?,
        backupHealthReminderDays: Int,
        now: Date = Date()
    ) -> String {
        guard let latestDate = latestBackupDate else {
            return StorageCleanupSectionCopy.backupReminderNoBackup
        }

        let calendar = Calendar.current
        let latestDay = calendar.startOfDay(for: latestDate)
        let today = calendar.startOfDay(for: now)
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

    static func cleanupConfirmationMessage(
        usage: ProjectStorageUsage,
        category: ProjectStorageCleanupCategory,
        preview: CleanupImpactSummary,
        recoverableDate: Date,
        retentionDays: Int,
        backupReminderMessage: String
    ) -> String {
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
                dateText: Formatters.date.string(from: recoverableDate),
                retentionDays: retentionDays
            )
        )
        lines.append(backupReminderMessage)
        return lines.joined(separator: "\n")
    }
}
