import Testing
@testable import sitekeeper

struct StorageCleanupSectionCopyCategoryTests {
    @Test(arguments: [
        StorageCleanupSectionCopy.auditSummaryRestoreCleanupTrash,
        StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteCleanupTrash,
        StorageCleanupSectionCopy.auditSummaryRestoreQuarantinedFile,
        StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteQuarantinedFile,
        StorageCleanupSectionCopy.auditSummaryCleanupByProject,
        StorageCleanupSectionCopy.storageSummaryHeader,
        StorageCleanupSectionCopy.projectCleanupHeader,
        StorageCleanupSectionCopy.noProjectCleanupMessage,
        StorageCleanupSectionCopy.usagePhotoTitle,
        StorageCleanupSectionCopy.usageVideoTitle,
        StorageCleanupSectionCopy.usageDrawingTitle,
        StorageCleanupSectionCopy.usageTicketTitle,
        StorageCleanupSectionCopy.usageDrawingOriginalTitle,
        StorageCleanupSectionCopy.usageTicketDocumentTitle,
        StorageCleanupSectionCopy.usageBackupEstimateTitle,
        StorageCleanupSectionCopy.usageSummaryHeader,
        StorageCleanupSectionCopy.projectTotalUsageTitle,
        StorageCleanupSectionCopy.cleanupByTypeHeader,
        StorageCleanupSectionCopy.cleanupByTypeFooter,
        StorageCleanupSectionCopy.cleanupAllProjectFilesTitle,
        StorageCleanupSectionCopy.backupSpaceNote,
        StorageCleanupSectionCopy.backupEstimateCalculatingText,
        StorageCleanupSectionCopy.storageFileCategoryDisplayName(.photo),
        StorageCleanupSectionCopy.cleanupCategoryDisplayName(.photos),
        StorageCleanupSectionCopy.cleanupCategoryResultTitle(.all),
        StorageCleanupSectionCopy.centerNavigationTitle,
        StorageCleanupSectionCopy.cleanupProjectFilesAlertTitle,
        StorageCleanupSectionCopy.cancelActionTitle,
        StorageCleanupSectionCopy.cleanupAllConfirmationButtonTitle,
        StorageCleanupSectionCopy.cleanupConfirmationNoFileDeletion,
        StorageCleanupSectionCopy.cleanupConfirmationAffectedRecordsHeader,
        StorageCleanupSectionCopy.cleanupConfirmationNoRecordChange,
        StorageCleanupSectionCopy.cleanupConfirmationSampleSeparator,
        StorageCleanupSectionCopy.backupReminderNoBackup,
        StorageCleanupSectionCopy.trashRetentionLabel,
        StorageCleanupSectionCopy.trashPolicyHeader,
        StorageCleanupSectionCopy.trashPolicyFooter,
        StorageCleanupSectionCopy.globalTrashHeader,
        StorageCleanupSectionCopy.emptyTrashMessage,
        StorageCleanupSectionCopy.restoreActionTitle,
        StorageCleanupSectionCopy.permanentDeleteActionTitle,
        StorageCleanupSectionCopy.cleanupBatchLabel,
        StorageCleanupSectionCopy.quarantinedFileLabel,
        StorageCleanupSectionCopy.largeFileThresholdLabel,
        StorageCleanupSectionCopy.largeFileFooter,
        StorageCleanupSectionCopy.noLargeFilesTitle,
        StorageCleanupSectionCopy.noLargeFilesDescription,
    ])
    func copyIsPresent(_ value: String) {
        #expect(!value.isEmpty)
    }

    @Test func categoryDynamicCopyIncludesExpectedValues() {
        #expect(StorageCleanupSectionCopy.summaryItemCount(9).contains("9"))
        #expect(StorageCleanupSectionCopy.projectUsage("照片", sizeText: "12 MB").contains("12 MB"))
        #expect(StorageCleanupSectionCopy.projectBackupEstimate("32 MB").contains("32 MB"))
        #expect(StorageCleanupSectionCopy.cleanupCategoryTitle("图纸").contains("图纸"))
        #expect(StorageCleanupSectionCopy.backupEstimateCalculatingText.contains("计算"))
        #expect(StorageCleanupSectionCopy.storageFileCategoryDisplayName(.history).contains("历史"))
        #expect(StorageCleanupSectionCopy.storageFileCategoryStyle(.photo).icon == "photo.fill")
        #expect(StorageCleanupSectionCopy.storageFileCategoryStyle(.video).icon == "video.fill")
        #expect(StorageCleanupSectionCopy.storageFileCategoryStyle(.drawing).icon == "doc.viewfinder")
        #expect(StorageCleanupSectionCopy.storageFileCategoryStyle(.ticket).icon == "doc.text.fill")
        #expect(StorageCleanupSectionCopy.storageFileCategoryStyle(.backup).icon == "externaldrive.fill")
        #expect(StorageCleanupSectionCopy.storageFileCategoryStyle(.history).icon == "clock.arrow.circlepath")
        #expect(StorageCleanupSectionCopy.cleanupCategoryDisplayName(.tickets).contains("票据"))
        #expect(StorageCleanupSectionCopy.cleanupCategoryResultTitle(.all).contains("项目"))
        #expect(StorageCleanupSectionCopy.cleanupCategoryStyle(.photos).icon == "photo.fill")
        #expect(StorageCleanupSectionCopy.cleanupCategoryStyle(.videos).icon == "video.fill")
        #expect(StorageCleanupSectionCopy.cleanupCategoryStyle(.drawings).icon == "doc.viewfinder")
        #expect(StorageCleanupSectionCopy.cleanupCategoryStyle(.tickets).icon == "doc.text.fill")
        #expect(StorageCleanupSectionCopy.cleanupCategoryStyle(.all).icon == "trash")
    }
}
