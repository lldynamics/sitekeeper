import Testing
@testable import sitekeeper

struct StorageCleanupSectionCopyTrashTests {
    @Test func trashCopyIsPresent() {
        #expect(!StorageCleanupSectionCopy.trashRetentionLabel.isEmpty)
        #expect(!StorageCleanupSectionCopy.trashPolicyHeader.isEmpty)
        #expect(!StorageCleanupSectionCopy.trashPolicyFooter.isEmpty)
        #expect(!StorageCleanupSectionCopy.globalTrashHeader.isEmpty)
        #expect(!StorageCleanupSectionCopy.emptyTrashMessage.isEmpty)
        #expect(!StorageCleanupSectionCopy.restoreActionTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.permanentDeleteActionTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.cleanupBatchLabel.isEmpty)
        #expect(!StorageCleanupSectionCopy.quarantinedFileLabel.isEmpty)
        #expect(!StorageCleanupSectionCopy.largeFileThresholdLabel.isEmpty)
        #expect(!StorageCleanupSectionCopy.largeFileFooter.isEmpty)
        #expect(!StorageCleanupSectionCopy.noLargeFilesTitle.isEmpty)
        #expect(!StorageCleanupSectionCopy.noLargeFilesDescription.isEmpty)
    }

    @Test func trashDynamicCopyIncludesExpectedValues() {
        let hint = StorageCleanupSectionCopy.trashPolicyRecoveryHint(deadlineText: "2026-05-22")
        #expect(hint.contains("2026-05-22"))

        let footer = StorageCleanupSectionCopy.globalTrashFooter(retentionDays: 7)
        #expect(footer.contains("7"))

        let recoverable = StorageCleanupSectionCopy.recoverableUntil("2026-05-30")
        #expect(recoverable.contains("2026-05-30"))

        let largeFileHeader = StorageCleanupSectionCopy.largeFileHeader(12)
        #expect(largeFileHeader.contains("12"))

        let batchCount = StorageCleanupSectionCopy.cleanupBatchFileCount(5)
        #expect(batchCount.contains("5"))
    }
}
