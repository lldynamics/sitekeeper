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

@MainActor
extension BackupExportLeaseTests {
    @Test func earlierExportKeepsReusedAttachmentWhenLaterSnapshotDoesNotContainIt() async throws {
        let (store, directory) = try makeStore()
        defer {
            store.cancelScheduledSave()
            try? FileManager.default.removeItem(at: directory)
        }
        await store.awaitInitialLoad()
        let name = "lease-distinct-snapshots-\(UUID().uuidString).bin"
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x41]), fileName: name)
        let fileURL = QuickNoteAttachmentStorage.fileURL(for: name)
        defer {
            StorageCleanupTrashTestSupport.removeFileIfExists(fileURL)
            for entry in FileQuarantineStore.loadEntries() where entry.originalFileName == name {
                try? FileQuarantineStore.permanentlyDelete(entry)
            }
        }
        let note = QuickNote(attachments: [QuickNoteAttachment(kind: .file, fileName: name)])
        store.replaceQuickNotes([note])
        let firstReader = SuspendedReader()
        let laterReader = SuspendedReader()
        let firstExport = Task {
            try await store.withBackupExport {
                let snapshot = store.makeSnapshot(includePhotoFiles: false)
                #expect(snapshot.quickNotes.first?.attachments.first?.fileName == name)
                await firstReader.wait()
            }
        }
        while !firstReader.started { await Task.yield() }
        store.replaceQuickNotes([])
        try QuickNoteAttachmentStorage.deleteOrThrow(fileName: name)
        let laterExport = Task {
            try await store.withBackupExport {
                let snapshot = store.makeSnapshot(includePhotoFiles: false)
                #expect(snapshot.quickNotes.isEmpty)
                await laterReader.wait()
            }
        }
        while !laterReader.started { await Task.yield() }
        #expect(store.activeBackupExportCount == 2)
        store.replaceQuickNotes([note])
        firstReader.finish()
        try await firstExport.value
        #expect(store.activeBackupExportCount == 1)
        #expect(QuickNoteAttachmentStorage.exists(fileName: name))
        #expect(!FileQuarantineStore.isQuarantineDeferred(for: fileURL))
        laterReader.finish()
        try await laterExport.value
        #expect(QuickNoteAttachmentStorage.data(for: name) == Data([0x41]))
    }

    @Test func ordinaryDeletionKeepsSnapshotAttachmentUntilArchiveFinishes() async throws {
        let (store, directory) = try makeStore()
        defer { store.cancelScheduledSave()
        try? FileManager.default.removeItem(at: directory) }
        await store.awaitInitialLoad()
        let name = "lease-delete-\(UUID().uuidString).bin"
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([0x31, 0x32]), fileName: name)
        defer {
            StorageCleanupTrashTestSupport.removeFileIfExists(QuickNoteAttachmentStorage.fileURL(for: name))
            for entry in FileQuarantineStore.loadEntries() where entry.originalFileName == name { try? FileQuarantineStore.permanentlyDelete(entry) }
        }
        let note = QuickNote(attachments: [QuickNoteAttachment(kind: .file, fileName: name)])
        store.replaceQuickNotes([note])
        try await store.withBackupExport {
            let snapshot = store.makeSnapshot(includePhotoFiles: false)
            let deletion = store.removeQuickNotes(ids: [note.id], deferredFileCleanup: .quickNoteAttachments(note.attachments, summary: "lease test"))
            deletion.performDeferredFileCleanup()
            #expect(store.quickNotes.isEmpty)
            #expect(QuickNoteAttachmentStorage.exists(fileName: name))
            let archive = try BackupArchiveService.makeArchive(from: snapshot)
            defer { try? FileManager.default.removeItem(at: archive.fileURL) }
            #expect(archive.missingFiles.isEmpty)
            let restored = try BackupArchiveService.decodeBackup(from: archive.fileURL)
            #expect(restored.quickNoteAttachmentFiles.contains { $0.fileName == name && $0.data == Data([0x31, 0x32]) })
        }
        #expect(!QuickNoteAttachmentStorage.exists(fileName: name))
        #expect(FileQuarantineStore.loadEntries().contains { $0.originalFileName == name })
    }

    @Test func reusingAttachmentBeforeExportEndsCancelsDeferredRemoval() async throws {
        let (store, directory) = try makeStore()
        defer { store.cancelScheduledSave()
        try? FileManager.default.removeItem(at: directory) }
        await store.awaitInitialLoad()
        let name = "lease-reuse-\(UUID().uuidString).bin"
        _ = try QuickNoteAttachmentStorage.saveDataOrThrow(Data([7]), fileName: name)
        defer { StorageCleanupTrashTestSupport.removeFileIfExists(QuickNoteAttachmentStorage.fileURL(for: name)) }
        let attachment = QuickNoteAttachment(kind: .file, fileName: name)
        store.replaceQuickNotes([QuickNote(attachments: [attachment])])
        try await store.withBackupExport {
            store.replaceQuickNotes([])
            try QuickNoteAttachmentStorage.deleteOrThrow(fileName: name)
            store.replaceQuickNotes([QuickNote(content: "new owner", attachments: [attachment])])
        }
        #expect(QuickNoteAttachmentStorage.exists(fileName: name))
        #expect(!FileQuarantineStore.isQuarantineDeferred(for: QuickNoteAttachmentStorage.fileURL(for: name)))
    }

    @Test func cloudBackupRejectsMissingAttachmentBeforeAccessingICloud() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        await store.awaitInitialLoad()
        store.replaceQuickNotes([QuickNote(attachments: [QuickNoteAttachment(kind: .file, fileName: "missing-\(UUID().uuidString).bin")])])
        do {
            _ = try await CloudBackupCoordinator.shared.backupToCloud(snapshot: store.makeSnapshot(includePhotoFiles: false))
            Issue.record("Incomplete archive must not be uploaded")
        } catch let error as CloudBackupPreparationError {
            #expect(error == .missingFiles(1))
        }
    }
}
