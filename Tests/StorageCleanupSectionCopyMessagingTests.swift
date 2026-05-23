import Testing
@testable import sitekeeper

struct StorageCleanupSectionCopyMessagingTests {
    @Test func messagingCopyIsPresent() {
        #expect(!StorageCleanupSectionCopy.centerNavigationTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.cleanupProjectFilesAlertTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.cancelActionTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.cleanupAllConfirmationButtonTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.cleanupConfirmationNoFileDeletion.isEmpty)
        #expect(!StorageCleanupSectionCopy.cleanupConfirmationAffectedRecordsHeader.isEmpty)
        #expect(!StorageCleanupSectionCopy.cleanupConfirmationNoRecordChange.isEmpty)
        #expect(!StorageCleanupSectionCopy.cleanupConfirmationSampleSeparator.isEmpty)
        #expect(!StorageCleanupSectionCopy.backupReminderNoBackup.isEmpty)
    }

    @Test func messagingDynamicCopyIncludesExpectedValues() {
        #expect(StorageCleanupSectionCopy.cloudBackupReadFailed("oops").contains("oops"))
        #expect(StorageCleanupSectionCopy.largeFileRuleSuggestion(photo: "5MB", video: "50MB", ticket: "20MB").contains("50MB"))
        #expect(StorageCleanupSectionCopy.cleanupConfirmationDeletedFileCount(8).contains("8"))
        #expect(StorageCleanupSectionCopy.cleanupConfirmationFileLine(title: "图纸", count: 3).contains("图纸"))
        #expect(StorageCleanupSectionCopy.cleanupConfirmationButtonTitle(categoryDisplayName: "票据资料").contains("票据资料"))
        #expect(StorageCleanupSectionCopy.cleanupConfirmationRecordLine(title: "记录", count: 5).contains("5"))
        #expect(StorageCleanupSectionCopy.cleanupConfirmationSampleFiles("a.jpg、b.pdf").contains("a.jpg"))
        #expect(StorageCleanupSectionCopy.cleanupPhotosConfirmationMessage(projectName: "项目A").contains("项目A"))
        #expect(StorageCleanupSectionCopy.cleanupVideosConfirmationMessage(projectName: "项目B").contains("项目B"))
        #expect(StorageCleanupSectionCopy.cleanupDrawingsConfirmationMessage(projectName: "项目C").contains("项目C"))
        #expect(StorageCleanupSectionCopy.cleanupTicketsConfirmationMessage(projectName: "项目D").contains("项目D"))
        #expect(StorageCleanupSectionCopy.cleanupAllFilesConfirmationMessage(projectName: "项目E").contains("项目E"))
        #expect(StorageCleanupSectionCopy.cleanupConfirmationRecoverableHint(dateText: "2026-06-01", retentionDays: 7).contains("2026-06-01"))
        #expect(StorageCleanupSectionCopy.backupReminderExpired(dateText: "2026-05-01", daysSinceBackup: 21).contains("21"))
        #expect(StorageCleanupSectionCopy.backupReminderRecent(dateText: "2026-05-22").contains("2026-05-22"))
    }
}
