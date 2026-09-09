import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct BackupExportLeaseTests {
    private enum TestFailure: Error { case expected }

    @Test func exportBlocksMaintenanceAndRestoreButAllowsOrdinarySave() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.awaitInitialLoad()
        store.appendProject(Project(name: "Keep", location: "", status: .active))
        let stage = directory.appendingPathComponent("unused-stage")
        let transaction = BackupArchiveService.EmbeddedFileRestoreTransaction(
            stageRoot: stage, photoStage: stage, drawingStage: stage, documentStage: stage,
            quickNoteStage: stage, counts: BackupEmbeddedRestoreCounts(
                photoFileCount: 0, drawingFileCount: 0, documentFileCount: 0, quickNoteAttachmentFileCount: 0
            )
        )
        try await store.withBackupExport {
            #expect(store.isExportingBackup)
            #expect(!store.clearAllBusinessData(deleteStoredFiles: false))
            let cleared = await store.clearAllBusinessDataAsync(deleteStoredFiles: false)
            #expect(!cleared)
            let snapshot = store.makeSnapshot(includePhotoFiles: false)
            do {
                _ = try await BackupImportCoordinator.commitAndPersistImport(
                    restoreTransaction: transaction, importedSnapshot: snapshot, previousSnapshot: snapshot,
                    importMode: .overwrite, store: store, sourceFileName: "blocked.zip"
                )
                Issue.record("Restore must not start while an export reads attachments")
            } catch is DataStore.PersistenceBlockedError { }
            #expect(!store.isApplyingBackup)
            try await store.flushSaveOrThrow()
            #expect(store.projects.first?.name == "Keep")
        }
        #expect(!store.isExportingBackup)
        try store.requireMaintenanceAllowed()
        #expect(FileManager.default.fileExists(atPath: store.storeURL.path))
    }

    @Test func restoreAndFailedLoadRejectExportBeforeTakingSnapshot() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.awaitInitialLoad()
        for isRestoring in [true, false] {
            store.isApplyingBackup = isRestoring
            store.setLoadState(isRestoring ? .ready : .failed)
            var operationStarted = false
            do {
                try await store.withBackupExport { operationStarted = true }
                Issue.record("Unsafe data state must reject export")
            } catch is DataStore.PersistenceBlockedError { }
            #expect(!operationStarted)
            #expect(!store.isExportingBackup)
        }
    }

    @Test func failureAndNestedExportsReleaseExactlyTheirOwnLease() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.awaitInitialLoad()
        try await store.withBackupExport {
            do {
                try await store.withBackupExport {
                    #expect(store.activeBackupExportCount == 2)
                    throw TestFailure.expected
                }
            } catch TestFailure.expected { }
            #expect(store.activeBackupExportCount == 1)
            #expect(throws: DataStore.PersistenceBlockedError.self) { try store.requireMaintenanceAllowed() }
        }
        #expect(store.activeBackupExportCount == 0)
        try store.requireMaintenanceAllowed()
    }

    @Test func cancellationKeepsLeaseUntilFileReaderActuallyStops() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.awaitInitialLoad()
        let reader = SuspendedReader()
        let task = Task {
            try await store.withBackupExport {
                await reader.wait()
                try Task.checkCancellation()
            }
        }
        while !reader.started { await Task.yield() }
        task.cancel()
        #expect(store.isExportingBackup)
        #expect(throws: DataStore.PersistenceBlockedError.self) { try store.requireMaintenanceAllowed() }
        reader.finish()
        do {
            try await task.value
            Issue.record("Expected cancellation after reader stopped")
        } catch is CancellationError { }
        #expect(!store.isExportingBackup)
        try store.requireMaintenanceAllowed()
    }

    private func makeStore() throws -> (DataStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("backup-export-lease-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (DataStore(storageDirectory: directory), directory)
    }

    @MainActor
    private final class SuspendedReader {
        private var continuation: CheckedContinuation<Void, Never>?
        var started = false

        func wait() async {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                started = true
            }
        }

        func finish() {
            continuation?.resume()
            continuation = nil
        }
    }
}
