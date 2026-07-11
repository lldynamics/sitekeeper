import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct StorageCleanupTrashStoreTests {
    @Test func storageCleanupTrashRestoresFiles() throws {
        let quickNoteFile = "storage-cleanup-restore-\(UUID().uuidString).bin"
        let drawingFile = "storage-cleanup-restore-\(UUID().uuidString).pdf"
        let quickNoteData = Data([0x10, 0x11, 0x12])
        let drawingData = Data([0x20, 0x21, 0x22])
        var batch: StorageCleanupTrashBatch?

        defer {
            if let batch {
                try? StorageCleanupTrashStore.permanentlyDelete(batch)
            }
            StorageCleanupTrashTestSupport.removeFileIfExists(QuickNoteAttachmentStorage.fileURL(for: quickNoteFile))
            StorageCleanupTrashTestSupport.removeFileIfExists(DrawingStorage.fileURL(for: drawingFile))
        }

        try StorageCleanupTrashTestSupport.write(quickNoteData, to: QuickNoteAttachmentStorage.fileURL(for: quickNoteFile))
        try StorageCleanupTrashTestSupport.write(drawingData, to: DrawingStorage.fileURL(for: drawingFile))

        batch = try StorageCleanupTrashStore.quarantine(
            plan: DeferredProjectFileCleanupPlan(
                quickNoteAttachmentFileNames: [quickNoteFile],
                drawingFileNames: [drawingFile]
            ),
            snapshot: StorageCleanupTrashTestSupport.emptyUndoSnapshot(),
            summary: "restore lifecycle",
            retentionDays: 3
        )

        let capturedBatch = try #require(batch)
        #expect(capturedBatch.fileCount == 2)
        #expect(capturedBatch.expiresAt > capturedBatch.createdAt)
        #expect(!QuickNoteAttachmentStorage.exists(fileName: quickNoteFile))
        #expect(!DrawingStorage.exists(fileName: drawingFile))
        #expect(StorageCleanupTrashStore.loadBatches().contains { $0.id == capturedBatch.id })

        try StorageCleanupTrashStore.restore(capturedBatch)

        #expect(QuickNoteAttachmentStorage.data(for: quickNoteFile) == quickNoteData)
        #expect(DrawingStorage.data(for: drawingFile) == drawingData)
        #expect(!StorageCleanupTrashStore.loadBatches().contains { $0.id == capturedBatch.id })
        batch = nil
    }

    @Test func storageCleanupTrashPermanentlyDeletesFiles() throws {
        let fileName = "storage-cleanup-delete-\(UUID().uuidString).bin"
        let fileData = Data([0x30, 0x31, 0x32])
        var batch: StorageCleanupTrashBatch?

        defer {
            if let batch {
                try? StorageCleanupTrashStore.permanentlyDelete(batch)
            }
            StorageCleanupTrashTestSupport.removeFileIfExists(QuickNoteAttachmentStorage.fileURL(for: fileName))
        }

        try StorageCleanupTrashTestSupport.write(fileData, to: QuickNoteAttachmentStorage.fileURL(for: fileName))
        batch = try StorageCleanupTrashStore.quarantine(
            plan: DeferredProjectFileCleanupPlan(quickNoteAttachmentFileNames: [fileName]),
            snapshot: StorageCleanupTrashTestSupport.emptyUndoSnapshot(),
            summary: "delete lifecycle",
            retentionDays: 3
        )

        let capturedBatch = try #require(batch)
        #expect(capturedBatch.fileCount == 1)
        #expect(!QuickNoteAttachmentStorage.exists(fileName: fileName))
        #expect(StorageCleanupTrashStore.loadBatches().contains { $0.id == capturedBatch.id })

        try StorageCleanupTrashStore.permanentlyDelete(capturedBatch)

        #expect(!QuickNoteAttachmentStorage.exists(fileName: fileName))
        #expect(!StorageCleanupTrashStore.loadBatches().contains { $0.id == capturedBatch.id })
        batch = nil
    }

    @Test func storageCleanupTrashEmptyPlanDoesNotCreateBatch() throws {
        let restoreManifest = try StorageCleanupTrashTestSupport.preserveManifest()
        defer { restoreManifest() }

        let beforeIDs = Set(StorageCleanupTrashStore.loadBatches().map(\.id))

        do {
            _ = try StorageCleanupTrashStore.quarantine(
                plan: DeferredProjectFileCleanupPlan(),
                snapshot: StorageCleanupTrashTestSupport.emptyUndoSnapshot(),
                summary: "empty cleanup",
                retentionDays: 3
            )
            Issue.record("预期空清理计划不会写入回收站批次")
        } catch let error as StorageCleanupTrashError {
            guard case .noFilesToTrash = error else {
                Issue.record("收到意外 StorageCleanupTrashError：\(error.localizedDescription)")
                return
            }
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }

        let afterIDs = Set(StorageCleanupTrashStore.loadBatches().map(\.id))
        #expect(afterIDs == beforeIDs)
    }

    @Test func storageCleanupTrashQuarantineRollsBackWhenManifestWriteFails() throws {
        let restoreManifest = try StorageCleanupTrashTestSupport.preserveManifest()
        let fileName = "storage-cleanup-manifest-fail-\(UUID().uuidString).bin"
        let fileData = Data([0x61, 0x62, 0x63])
        defer {
            restoreManifest()
            StorageCleanupTrashTestSupport.removeFileIfExists(QuickNoteAttachmentStorage.fileURL(for: fileName))
        }

        let manifestURL = try StorageCleanupTrashTestSupport.manifestURL()
        try FileManager.default.createDirectory(
            at: manifestURL,
            withIntermediateDirectories: true
        )
        try StorageCleanupTrashTestSupport.write(fileData, to: QuickNoteAttachmentStorage.fileURL(for: fileName))

        do {
            _ = try StorageCleanupTrashStore.quarantine(
                plan: DeferredProjectFileCleanupPlan(quickNoteAttachmentFileNames: [fileName]),
                snapshot: StorageCleanupTrashTestSupport.emptyUndoSnapshot(),
                summary: "manifest write failure",
                retentionDays: 3
            )
            Issue.record("预期清理回收站 manifest 写入失败")
        } catch let error as StorageCleanupTrashError {
            guard case .manifestWriteFailed = error else {
                Issue.record("收到意外 StorageCleanupTrashError：\(error.localizedDescription)")
                return
            }
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }

        #expect(QuickNoteAttachmentStorage.data(for: fileName) == fileData)
    }

    @Test func storageCleanupTrashRollbackFailurePreservesDiscoverableRecoveryBatch() throws {
        let fileName = "storage-cleanup-rollback-fail-\(UUID().uuidString).bin"
        let fileData = Data([0x64, 0x65, 0x66])
        let customRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-cleanup-rollback-root-\(UUID().uuidString)", isDirectory: true)
        defer {
            StorageCleanupTrashTestSupport.removeFileIfExists(customRoot)
            StorageCleanupTrashTestSupport.removeFileIfExists(QuickNoteAttachmentStorage.fileURL(for: fileName))
        }

        try StorageCleanupTrashTestSupport.write(fileData, to: QuickNoteAttachmentStorage.fileURL(for: fileName))
        try StorageCleanupTrashStore.withRootURLForTesting(customRoot) {
            try FileManager.default.createDirectory(at: customRoot, withIntermediateDirectories: true)
            let manifestURL = customRoot.appendingPathComponent("manifest.json")
            try FileManager.default.createDirectory(at: manifestURL, withIntermediateDirectories: true)

            do {
                try StorageCleanupTrashStore.withRollbackRestoreFailuresForTesting(fileNames: [fileName]) {
                    _ = try StorageCleanupTrashStore.quarantine(
                        plan: DeferredProjectFileCleanupPlan(quickNoteAttachmentFileNames: [fileName]),
                        snapshot: StorageCleanupTrashTestSupport.emptyUndoSnapshot(),
                        summary: "rollback restore failure",
                        retentionDays: 3
                    )
                }
                Issue.record("预期 manifest 写入和回滚恢复都失败")
            } catch let error as StorageCleanupTrashError {
                guard case .manifestWriteFailed = error else {
                    Issue.record("收到意外 StorageCleanupTrashError：\(error.localizedDescription)")
                    return
                }
            }

            #expect(!QuickNoteAttachmentStorage.exists(fileName: fileName))
            let recoveryBatch = try #require(StorageCleanupTrashStore.loadBatches().first)
            #expect(recoveryBatch.summary == "rollback restore failure")
            #expect(recoveryBatch.files.map(\.originalFileName) == [fileName])
            let recoveryFile = try #require(recoveryBatch.files.first)
            let trashedURL = customRoot
                .appendingPathComponent(recoveryBatch.id.uuidString, isDirectory: true)
                .appendingPathComponent(recoveryFile.kind.rawValue, isDirectory: true)
                .appendingPathComponent(recoveryFile.trashedFileName)
            #expect(try Data(contentsOf: trashedURL) == fileData)

            try FileManager.default.removeItem(at: manifestURL)
            try StorageCleanupTrashStore.restore(recoveryBatch)
            #expect(QuickNoteAttachmentStorage.data(for: fileName) == fileData)
            #expect(StorageCleanupTrashStore.loadBatches().isEmpty)
        }
    }

    @Test func storageCleanupTrashRestoreTargetConflictKeepsExistingFileAndClearsBatch() throws {
        let restoreManifest = try StorageCleanupTrashTestSupport.preserveManifest()
        let fileName = "storage-cleanup-restore-conflict-\(UUID().uuidString).bin"
        let trashedData = Data([0x71, 0x72, 0x73])
        let existingData = Data([0x81, 0x82, 0x83])
        var batch: StorageCleanupTrashBatch?
        defer {
            if let batch {
                try? StorageCleanupTrashStore.permanentlyDelete(batch)
            }
            restoreManifest()
            StorageCleanupTrashTestSupport.removeFileIfExists(QuickNoteAttachmentStorage.fileURL(for: fileName))
        }

        try StorageCleanupTrashTestSupport.write(trashedData, to: QuickNoteAttachmentStorage.fileURL(for: fileName))
        batch = try StorageCleanupTrashStore.quarantine(
            plan: DeferredProjectFileCleanupPlan(quickNoteAttachmentFileNames: [fileName]),
            snapshot: StorageCleanupTrashTestSupport.emptyUndoSnapshot(),
            summary: "restore conflict",
            retentionDays: 3
        )
        let capturedBatch = try #require(batch)
        try StorageCleanupTrashTestSupport.write(existingData, to: QuickNoteAttachmentStorage.fileURL(for: fileName))

        try StorageCleanupTrashStore.restore(capturedBatch)

        #expect(QuickNoteAttachmentStorage.data(for: fileName) == existingData)
        #expect(!StorageCleanupTrashStore.loadBatches().contains { $0.id == capturedBatch.id })
        batch = nil
    }

    @Test func storageCleanupTrashPermanentDeleteFailureKeepsBatchVisible() throws {
        let restoreManifest = try StorageCleanupTrashTestSupport.preserveManifest()
        let fileName = "storage-cleanup-delete-fail-\(UUID().uuidString).bin"
        var batch: StorageCleanupTrashBatch?
        defer {
            try? StorageCleanupTrashTestSupport.setRootPermissions(0o755)
            if let batch {
                try? StorageCleanupTrashStore.permanentlyDelete(batch)
            }
            restoreManifest()
            StorageCleanupTrashTestSupport.removeFileIfExists(QuickNoteAttachmentStorage.fileURL(for: fileName))
        }

        try StorageCleanupTrashTestSupport.write(Data([0x91, 0x92, 0x93]), to: QuickNoteAttachmentStorage.fileURL(for: fileName))
        batch = try StorageCleanupTrashStore.quarantine(
            plan: DeferredProjectFileCleanupPlan(quickNoteAttachmentFileNames: [fileName]),
            snapshot: StorageCleanupTrashTestSupport.emptyUndoSnapshot(),
            summary: "permanent delete failure",
            retentionDays: 3
        )
        let capturedBatch = try #require(batch)

        try StorageCleanupTrashTestSupport.setRootPermissions(0o555)
        do {
            try StorageCleanupTrashStore.permanentlyDelete(capturedBatch)
            Issue.record("预期清理回收站永久删除失败")
        } catch let error as StorageCleanupTrashError {
            guard case .permanentDeleteFailed = error else {
                Issue.record("收到意外 StorageCleanupTrashError：\(error.localizedDescription)")
                return
            }
        } catch {
            Issue.record("收到意外错误：\(error.localizedDescription)")
        }

        #expect(StorageCleanupTrashStore.loadBatches().contains { $0.id == capturedBatch.id })
    }

    @Test func storageCleanupTrashExpiredPurgeKeepsBatchWhenDeleteFails() throws {
        let restoreManifest = try StorageCleanupTrashTestSupport.preserveManifest()
        let fileName = "storage-cleanup-expired-purge-\(UUID().uuidString).bin"
        var batch: StorageCleanupTrashBatch?
        defer {
            try? StorageCleanupTrashTestSupport.setRootPermissions(0o755)
            if let batch {
                try? StorageCleanupTrashStore.permanentlyDelete(batch)
            }
            restoreManifest()
            StorageCleanupTrashTestSupport.removeFileIfExists(QuickNoteAttachmentStorage.fileURL(for: fileName))
        }

        try StorageCleanupTrashTestSupport.write(Data([0xA1, 0xA2, 0xA3]), to: QuickNoteAttachmentStorage.fileURL(for: fileName))
        batch = try StorageCleanupTrashStore.quarantine(
            plan: DeferredProjectFileCleanupPlan(quickNoteAttachmentFileNames: [fileName]),
            snapshot: StorageCleanupTrashTestSupport.emptyUndoSnapshot(),
            summary: "expired purge manifest failure",
            retentionDays: 3
        )
        let capturedBatch = try #require(batch)
        let expiredBatch = StorageCleanupTrashBatch(
            id: capturedBatch.id,
            summary: capturedBatch.summary,
            createdAt: capturedBatch.createdAt,
            expiresAt: Date(timeIntervalSinceNow: -60),
            snapshot: capturedBatch.snapshot,
            files: capturedBatch.files
        )
        try StorageCleanupTrashTestSupport.writeManifest([expiredBatch])

        try StorageCleanupTrashTestSupport.setRootPermissions(0o555)
        let purgedCount = StorageCleanupTrashStore.purgeExpiredBatches(now: Date())

        #expect(purgedCount == 0)
        #expect(StorageCleanupTrashStore.loadBatches().contains { $0.id == capturedBatch.id })
    }
}
