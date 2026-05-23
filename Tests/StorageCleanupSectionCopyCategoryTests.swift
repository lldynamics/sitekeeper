import Testing
@testable import sitekeeper

struct StorageCleanupSectionCopyCategoryTests {
    @Test func categoryCopyIsPresent() {
        #expect(!StorageCleanupSectionCopy.storageSummaryHeader.isEmpty)
        #expect(!StorageCleanupSectionCopy.projectCleanupHeader.isEmpty)
        #expect(!StorageCleanupSectionCopy.noProjectCleanupMessage.isEmpty)
        #expect(!StorageCleanupSectionCopy.usagePhotoTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.usageVideoTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.usageDrawingTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.usageTicketTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.usageDrawingOriginalTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.usageTicketDocumentTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.usageBackupEstimateTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.usageSummaryHeader.isEmpty)
        #expect(!StorageCleanupSectionCopy.projectTotalUsageTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.cleanupByTypeHeader.isEmpty)
        #expect(!StorageCleanupSectionCopy.cleanupByTypeFooter.isEmpty)
        #expect(!StorageCleanupSectionCopy.cleanupAllProjectFilesTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.backupSpaceNote.isEmpty)
        #expect(!StorageCleanupSectionCopy.backupEstimateCalculatingText.isEmpty)
        #expect(!StorageCleanupSectionCopy.storageFileCategoryDisplayName(.photo).isEmpty)
        #expect(!StorageCleanupSectionCopy.cleanupCategoryDisplayName(.photos).isEmpty)
        #expect(!StorageCleanupSectionCopy.cleanupCategoryResultTitle(.all).isEmpty)
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
