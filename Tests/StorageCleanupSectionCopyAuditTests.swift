import Testing
@testable import sitekeeper

struct StorageCleanupSectionCopyAuditTests {
    @Test func auditCopyIsPresent() {
        #expect(!StorageCleanupSectionCopy.auditSummaryRestoreCleanupTrash.isEmpty)
        #expect(!StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteCleanupTrash.isEmpty)
        #expect(!StorageCleanupSectionCopy.auditSummaryRestoreQuarantinedFile.isEmpty)
        #expect(!StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteQuarantinedFile.isEmpty)
        #expect(!StorageCleanupSectionCopy.auditSummaryCleanupByProject.isEmpty)
    }

    @Test func auditDynamicCopyIncludesExpectedValues() {
        #expect(StorageCleanupSectionCopy.restoredCleanupTrashStatus("A").contains("A"))
        #expect(StorageCleanupSectionCopy.restoreCleanupTrashFailedStatus("E").contains("E"))
        #expect(StorageCleanupSectionCopy.permanentlyDeletedCleanupTrashStatus("B").contains("B"))
        #expect(StorageCleanupSectionCopy.permanentlyDeleteCleanupTrashFailedStatus("E").contains("E"))
        #expect(StorageCleanupSectionCopy.restoredQuarantinedFileStatus("C").contains("C"))
        #expect(StorageCleanupSectionCopy.restoreQuarantinedFileFailedStatus("E").contains("E"))
        #expect(StorageCleanupSectionCopy.permanentlyDeletedQuarantinedFileStatus("D").contains("D"))
        #expect(StorageCleanupSectionCopy.permanentlyDeleteQuarantinedFileFailedStatus("E").contains("E"))
        #expect(StorageCleanupSectionCopy.projectCleanupAuditDetail(projectName: "P", categoryDisplayName: "票据").contains("票据"))
        #expect(StorageCleanupSectionCopy.projectCleanupSummary(projectName: "P", categoryResultTitle: "图纸").contains("图纸"))
        #expect(
            StorageCleanupSectionCopy.projectFilesMovedToTrashStatus(
                projectName: "项目A",
                categoryResultTitle: "照片",
                fileCount: 3,
                recoverableDateText: "2026-06-01"
            ).contains("2026-06-01")
        )
        #expect(StorageCleanupSectionCopy.cleanupTrashWriteFailedStatus("ERR").contains("ERR"))
        #expect(StorageCleanupSectionCopy.auditDetailWithError("x", errorDescription: "y").contains("error=y"))
        #expect(StorageCleanupSectionCopy.auditDetailRestoredCleanupBatch("x", fileCount: 1).contains("restored=1"))
        #expect(StorageCleanupSectionCopy.auditDetailDeletedCleanupBatch("x", fileCount: 2).contains("deleted=2"))
        #expect(StorageCleanupSectionCopy.auditDetailWithRetention("x", fileCount: 3, retentionDays: 14).contains("retentionDays=14"))
    }
}
