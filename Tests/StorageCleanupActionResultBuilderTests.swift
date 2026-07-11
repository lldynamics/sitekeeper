import Foundation
import Testing
@testable import sitekeeper

struct StorageCleanupActionResultBuilderTests {
    @Test func cleanupTrashRestoreEventsKeepAuditAndStatusFields() {
        let batch = makeTrashBatch(summary: "项目A · 图纸", fileCount: 2)

        let started = StorageCleanupActionResultBuilder.restoreCleanupTrashStarted(batch)
        #expect(started.action == .restore)
        #expect(started.summary == StorageCleanupSectionCopy.auditSummaryRestoreCleanupTrash)
        #expect(started.detail == batch.summary)

        let succeeded = StorageCleanupActionResultBuilder.restoreCleanupTrashSucceeded(batch)
        #expect(succeeded.action == .restore)
        #expect(succeeded.summary == StorageCleanupSectionCopy.auditSummaryRestoreCleanupTrash)
        #expect(succeeded.detail.contains(batch.summary))
        #expect(succeeded.detail.contains("restored=2"))
        #expect(succeeded.statusMessage.contains(batch.summary))

        let failed = StorageCleanupActionResultBuilder.restoreCleanupTrashFailed(batch, error: TestError.message("restore failed"))
        #expect(failed.action == .restore)
        #expect(failed.detail.contains(batch.summary))
        #expect(failed.detail.contains("error=restore failed"))
        #expect(failed.statusMessage.contains("restore failed"))
    }

    @Test func cleanupTrashPermanentDeleteEventsKeepCleanupAuditFields() {
        let batch = makeTrashBatch(summary: "项目B · 票据", fileCount: 3)

        let started = StorageCleanupActionResultBuilder.permanentlyDeleteCleanupTrashStarted(batch)
        #expect(started.action == .cleanup)
        #expect(started.summary == StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteCleanupTrash)
        #expect(started.detail == batch.summary)

        let succeeded = StorageCleanupActionResultBuilder.permanentlyDeleteCleanupTrashSucceeded(batch)
        #expect(succeeded.action == .cleanup)
        #expect(succeeded.detail.contains(batch.summary))
        #expect(succeeded.detail.contains("deleted=3"))
        #expect(succeeded.statusMessage.contains(batch.summary))

        let failed = StorageCleanupActionResultBuilder.permanentlyDeleteCleanupTrashFailed(
            batch,
            error: TestError.message("delete failed")
        )
        #expect(failed.action == .cleanup)
        #expect(failed.detail.contains("error=delete failed"))
        #expect(failed.statusMessage.contains("delete failed"))
    }

    @Test func quarantinedFileEventsUseStableCategoryAndFileDetail() {
        let entry = FileQuarantineEntry(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            category: .projectDocument,
            originalPath: "/tmp/contract.pdf",
            originalFileName: "contract.pdf",
            quarantinedRelativePath: "project-document/contract.pdf",
            createdAt: Date(timeIntervalSince1970: 1_800),
            expiresAt: Date(timeIntervalSince1970: 2_800)
        )
        let expectedDetail = "project-document · contract.pdf"

        let restoreStarted = StorageCleanupActionResultBuilder.restoreQuarantinedFileStarted(entry)
        #expect(restoreStarted.action == .restore)
        #expect(restoreStarted.summary == StorageCleanupSectionCopy.auditSummaryRestoreQuarantinedFile)
        #expect(restoreStarted.detail == expectedDetail)

        let restoreSucceeded = StorageCleanupActionResultBuilder.restoreQuarantinedFileSucceeded(entry)
        #expect(restoreSucceeded.action == .restore)
        #expect(restoreSucceeded.detail == expectedDetail)
        #expect(restoreSucceeded.statusMessage.contains("contract.pdf"))

        let deleteStarted = StorageCleanupActionResultBuilder.permanentlyDeleteQuarantinedFileStarted(entry)
        #expect(deleteStarted.action == .cleanup)
        #expect(deleteStarted.summary == StorageCleanupSectionCopy.auditSummaryPermanentlyDeleteQuarantinedFile)
        #expect(deleteStarted.detail == expectedDetail)

        let deleteFailed = StorageCleanupActionResultBuilder.permanentlyDeleteQuarantinedFileFailed(
            entry,
            error: TestError.message("permission denied")
        )
        #expect(deleteFailed.action == .cleanup)
        #expect(deleteFailed.detail.contains(expectedDetail))
        #expect(deleteFailed.detail.contains("error=permission denied"))
        #expect(deleteFailed.statusMessage.contains("permission denied"))
    }

    @Test func projectCleanupEventsKeepContextRetentionAndRecoverableDate() {
        let usage = ProjectStorageUsage(
            projectId: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            projectName: "项目C",
            photoBytes: 10,
            videoBytes: 20,
            drawingBytes: 30,
            ticketBytes: 40,
            backupEstimatedBytes: nil
        )
        let context = StorageCleanupActionResultBuilder.projectCleanupContext(
            usage: usage,
            category: .drawings
        )
        let batch = makeTrashBatch(
            summary: context.cleanupSummary,
            fileCount: 4,
            expiresAt: Date(timeIntervalSince1970: 2_000_000)
        )

        #expect(context.auditDetail.contains("项目C"))
        #expect(context.auditDetail.contains(ProjectStorageCleanupCategory.drawings.displayName))
        #expect(context.cleanupSummary.contains(ProjectStorageCleanupCategory.drawings.resultTitle))

        let started = StorageCleanupActionResultBuilder.cleanupProjectFilesStarted(context)
        #expect(started.action == .cleanup)
        #expect(started.summary == StorageCleanupSectionCopy.auditSummaryCleanupByProject)
        #expect(started.detail == context.auditDetail)

        let succeeded = StorageCleanupActionResultBuilder.cleanupProjectFilesSucceeded(
            context,
            batch: batch,
            retentionDays: 14
        )
        #expect(succeeded.action == .cleanup)
        #expect(succeeded.detail.contains(context.auditDetail))
        #expect(succeeded.detail.contains("trashed=4"))
        #expect(succeeded.detail.contains("retentionDays=14"))
        #expect(succeeded.statusMessage.contains("项目C"))
        #expect(succeeded.statusMessage.contains(ProjectStorageCleanupCategory.drawings.resultTitle))
        #expect(succeeded.statusMessage.contains("4"))
        #expect(succeeded.statusMessage.contains(Formatters.date.string(from: batch.expiresAt)))

        let failed = StorageCleanupActionResultBuilder.cleanupProjectFilesFailed(
            context,
            error: TestError.message("trash write failed")
        )
        #expect(failed.action == .cleanup)
        #expect(failed.detail.contains(context.auditDetail))
        #expect(failed.detail.contains("error=trash write failed"))
        #expect(failed.statusMessage.contains("trash write failed"))
    }

    @Test func auditServiceRecordsBuilderEventsAndReturnsStatusMessage() {
        OperationAuditLog.clear()
        defer { OperationAuditLog.clear() }

        let source = "StorageCleanupActionResultBuilderTests"
        let batch = makeTrashBatch(summary: "项目D · 照片", fileCount: 1)
        let started = StorageCleanupActionResultBuilder.restoreCleanupTrashStarted(batch)
        let succeeded = StorageCleanupActionResultBuilder.restoreCleanupTrashSucceeded(batch)

        StorageCleanupAuditService.record(started, source: source)
        let statusMessage = StorageCleanupAuditService.completeSucceeded(succeeded, source: source)

        #expect(statusMessage == succeeded.statusMessage)

        let entries = OperationAuditLog.entries().filter { $0.source == source }
        #expect(entries.count == 2)
        #expect(entries.contains { entry in
            entry.action == .restore
                && entry.outcome == .started
                && entry.summary == started.summary
                && entry.detail == started.detail
        })
        #expect(entries.contains { entry in
            entry.action == .restore
                && entry.outcome == .succeeded
                && entry.summary == succeeded.summary
                && entry.detail == succeeded.detail
        })
    }

    private func makeTrashBatch(
        summary: String,
        fileCount: Int,
        expiresAt: Date = Date(timeIntervalSince1970: 86_400)
    ) -> StorageCleanupTrashBatch {
        StorageCleanupTrashBatch(
            id: UUID(),
            summary: summary,
            createdAt: Date(timeIntervalSince1970: 0),
            expiresAt: expiresAt,
            snapshot: StorageCleanupUndoSnapshot(
                dailyLogs: [],
                siteTodos: [],
                quickNotes: [],
                projectDrawings: [],
                projectDocuments: [],
                projectFinancialRecords: [],
                projectWarehouseMovements: []
            ),
            files: (0..<fileCount).map { index in
                StorageCleanupTrashFile(
                    id: UUID(),
                    kind: .projectDocument,
                    originalFileName: "file-\(index).pdf",
                    trashedFileName: "trashed-\(index).pdf"
                )
            }
        )
    }
}

private enum TestError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case let .message(message):
            message
        }
    }
}
