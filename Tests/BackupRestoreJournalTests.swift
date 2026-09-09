import Foundation
import Testing
@testable import sitekeeper

struct BackupRestoreJournalTests {
    private enum SimulatedTermination: Error { case stopped }

    @Test func restartRollsBackEachPreMetadataInterruption() async throws {
        for point in [BackupArchiveRestoreJournal.FaultPoint.prepared, .afterReplace(0), .filesCommitted] {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let journal = try fixture.begin()
            do {
                _ = try journal.commitFiles { if $0 == point { throw SimulatedTermination.stopped } }
                Issue.record("Expected the injected interruption")
            } catch SimulatedTermination.stopped { }
            // A new persistence actor sees only disk state, not the abandoned transaction.
            let restarted = DataStorePersistenceActor(storeURL: fixture.storeURL)
            let loaded = try await restarted.loadSnapshot()
            #expect(loaded?.projects.first?.name == "Before")
            try fixture.expectOriginalFiles()
            #expect(!FileManager.default.fileExists(atPath: journal.root.path))
        }
    }

    @Test func restartFinalizesCommittedMetadataWithoutRollingBackAttachments() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let journal = try fixture.begin()
        try journal.commitFiles()
        // Simulate termination after the actual atomic metadata write but before finalize.
        try await DataStorePersistenceActor(storeURL: fixture.storeURL).persistPreparedBackup(data: fixture.after)
        let restarted = DataStorePersistenceActor(storeURL: fixture.storeURL)
        let loaded = try await restarted.loadSnapshot()
        #expect(loaded?.projects.first?.name == "After")
        for name in fixture.names {
            #expect(try Data(contentsOf: QuickNoteAttachmentStorage.fileURL(for: name)) == fixture.newFile)
        }
        #expect(!FileManager.default.fileExists(atPath: journal.root.path))
    }

    @Test func identicalMetadataStillRollsBackInterruptedFileCommit() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let journal = try fixture.begin(after: fixture.before)
        do {
            _ = try journal.commitFiles { if $0 == .afterReplace(0) { throw SimulatedTermination.stopped } }
        } catch SimulatedTermination.stopped { }
        _ = try await DataStorePersistenceActor(storeURL: fixture.storeURL).loadSnapshot()
        try fixture.expectOriginalFiles()
    }

    @Test func realRollbackIOFailureRetainsOriginalsAndRestartCanRetry() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let journal = try fixture.begin()
        try journal.commitFiles()
        try fixture.after.write(to: fixture.storeURL, options: .atomic)
        let blockedTarget = QuickNoteAttachmentStorage.fileURL(for: fixture.names[0])
        try FileManager.default.removeItem(at: blockedTarget)
        try FileManager.default.createDirectory(at: blockedTarget, withIntermediateDirectories: false)
        // rename(file, directory) fails. The durable rollingBack decision must survive even
        // though the on-disk metadata already equals after.json.
        #expect(throws: (any Error).self) { try journal.rollback() }
        #expect(FileManager.default.fileExists(atPath: journal.root.appendingPathComponent("rollback/0.bak").path))
        do {
            _ = try await DataStorePersistenceActor(storeURL: fixture.storeURL).loadSnapshot()
            Issue.record("Loading must fail closed while rollback still cannot finish")
        } catch { }
        #expect(FileManager.default.fileExists(atPath: journal.root.path))
        try FileManager.default.removeItem(at: blockedTarget)
        let loaded = try await DataStorePersistenceActor(storeURL: fixture.storeURL).loadSnapshot()
        #expect(loaded?.projects.first?.name == "Before")
        try fixture.expectOriginalFiles()
        #expect(!FileManager.default.fileExists(atPath: journal.root.path))
    }

    @Test func restartRemovesNewFilesAndRestoresAbsentMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try FileManager.default.removeItem(at: fixture.storeURL)
        for name in fixture.names { try FileManager.default.removeItem(at: QuickNoteAttachmentStorage.fileURL(for: name)) }
        let journal = try fixture.begin()
        try journal.commitFiles()
        let loaded = try await DataStorePersistenceActor(storeURL: fixture.storeURL).loadSnapshot()
        #expect(loaded == nil)
        for name in fixture.names { #expect(!QuickNoteAttachmentStorage.exists(fileName: name)) }
    }

    @MainActor
    @Test func failedFinalizationBlocksSavesUntilSuccessfulReload() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = DataStore(storageDirectory: fixture.root)
        await store.awaitInitialLoad()
        do {
            _ = try await BackupImportCoordinator.commitAndPersistImport(
                restoreTransaction: fixture.transaction(fault: { if $0 == .beforeFinalize { throw SimulatedTermination.stopped } }),
                importedSnapshot: JSONDecoder().decode(BackupSnapshot.self, from: fixture.after),
                previousSnapshot: store.makeSnapshot(includePhotoFiles: false),
                importMode: .overwrite, store: store, sourceFileName: "fault.zip"
            )
            Issue.record("Final journal write failure must be reported")
        } catch SimulatedTermination.stopped { }
        #expect(store.loadState == .failed)
        #expect(store.projects.first?.name == "After")
        do {
            try await store.flushSaveOrThrow()
            Issue.record("Further writes must be blocked")
        } catch { }
        #expect(!store.clearAllBusinessData(deleteStoredFiles: true))
        let cleared = await store.clearAllBusinessDataAsync(deleteStoredFiles: true)
        #expect(!cleared)
        #expect(store.projects.first?.name == "After")
        #expect(throws: (any Error).self) {
            _ = try StorageCleanupExecutionService.cleanupProjectFiles(
                store: store, projectId: UUID(), category: .all, retentionDays: 7,
                summary: "must reject", videoFileExtensions: [], drawingSourceFileExtensions: []
            )
        }
        store.loadAsync()
        await store.awaitInitialLoad()
        #expect(store.loadState == .ready)
        #expect(store.projects.first?.name == "After")
        #expect(try FileManager.default.contentsOfDirectory(
            at: BackupArchiveRestoreJournal.transactionsRoot(for: fixture.storeURL), includingPropertiesForKeys: nil
        ).isEmpty)
    }

    @Test func terminalCleanupFailureNeverRollsBackSubsequentMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let journal = try fixture.begin()
        try journal.commitFiles()
        try fixture.after.write(to: fixture.storeURL, options: .atomic)
        try journal.finish { if $0 == .beforeCleanup { throw SimulatedTermination.stopped } }
        #expect(FileManager.default.fileExists(atPath: journal.root.path))
        try await DataStorePersistenceActor(storeURL: fixture.storeURL).persist(snapshot: Fixture.snapshot("Later save"))
        let loaded = try await DataStorePersistenceActor(storeURL: fixture.storeURL).loadSnapshot()
        #expect(loaded?.projects.first?.name == "Later save")
        for name in fixture.names {
            #expect(try Data(contentsOf: QuickNoteAttachmentStorage.fileURL(for: name)) == fixture.newFile)
        }
    }

    @Test func journalPreparationFailureAfterStageMoveNeverChangesTargets() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        #expect(throws: SimulatedTermination.self) {
            _ = try BackupArchiveRestoreJournal.begin(
                stageRoot: fixture.stage, storeURL: fixture.storeURL, metadataAfter: fixture.after,
                policy: .restoreAll, fault: { if $0 == .beforeJournal { throw SimulatedTermination.stopped } }
            )
        }
        try fixture.expectOriginalFiles()
        #expect(try FileManager.default.contentsOfDirectory(
            at: BackupArchiveRestoreJournal.transactionsRoot(for: fixture.storeURL), includingPropertiesForKeys: nil
        ).isEmpty)
    }

    @MainActor
    @Test func maintenanceRejectsActiveRestoreBeforeTouchingFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let store = DataStore(storageDirectory: fixture.root)
        await store.awaitInitialLoad()
        store.isApplyingBackup = true
        defer { store.isApplyingBackup = false }
        #expect(!store.clearAllBusinessData(deleteStoredFiles: true))
        let cleared = await store.clearAllBusinessDataAsync(deleteStoredFiles: true)
        #expect(!cleared)
        #expect(throws: (any Error).self) { try store.requireMaintenanceAllowed() }
        try fixture.expectOriginalFiles()
    }

    @Test func concurrentLegacySessionsKeepIndependentRollbackOriginals() throws {
        let first = try Fixture()
        let second = try Fixture()
        defer { first.cleanup()
        second.cleanup() }
        let firstTransaction = first.transaction()
        let secondTransaction = second.transaction()
        try firstTransaction.commit()
        try secondTransaction.commit()
        #expect(firstTransaction.rollback())
        #expect(secondTransaction.rollback())
        try first.expectOriginalFiles()
        try second.expectOriginalFiles()
    }

    @Test func tamperedJournalCannotEscapeStorageFamily() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let journal = try fixture.begin()
        let recordURL = journal.root.appendingPathComponent("journal.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: recordURL)) as? [String: Any])
        var entries = try #require(object["entries"] as? [[String: Any]])
        entries[0]["destination"] = "../../outside.json"
        object["entries"] = entries
        try JSONSerialization.data(withJSONObject: object).write(to: recordURL, options: .atomic)
        do {
            _ = try await DataStorePersistenceActor(storeURL: fixture.storeURL).loadSnapshot()
            Issue.record("Unsafe journal must block loading")
        } catch { }
        #expect(FileManager.default.fileExists(atPath: journal.root.path))
        try fixture.expectOriginalFiles()
    }
}

private extension BackupRestoreJournalTests {
    struct Fixture {
        let root: URL
        let storeURL: URL
        let stage: URL
        let names: [String]
        let before: Data
        let after: Data
        let oldFile = Data("old attachment".utf8)
        let newFile = Data("new attachment".utf8)

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("restore-journal-test-\(UUID().uuidString)")
            storeURL = root.appendingPathComponent("sitekeeper.json")
            stage = root.appendingPathComponent("backup-restore-stage")
            names = (0..<2).map { _ in "journal-test-\(UUID().uuidString).bin" }.sorted()
            before = try BackupArchiveRestoreJournal.encodeMetadata(Self.snapshot("Before"))
            after = try BackupArchiveRestoreJournal.encodeMetadata(Self.snapshot("After"))
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try before.write(to: storeURL, options: .atomic)
            for family in BackupArchiveRestoreJournal.Family.allCases {
                try FileManager.default.createDirectory(at: stage.appendingPathComponent(family.stageDirectory), withIntermediateDirectories: true)
            }
            for name in names {
                _ = try QuickNoteAttachmentStorage.saveDataOrThrow(oldFile, fileName: name)
                try newFile.write(to: stage.appendingPathComponent("quick-note-attachments").appendingPathComponent(name))
            }
        }

        func begin(after metadata: Data? = nil) throws -> BackupArchiveRestoreJournal {
            try BackupArchiveRestoreJournal.begin(stageRoot: stage, storeURL: storeURL,
                                                  metadataAfter: metadata ?? after, policy: .restoreAll)
        }

        func expectOriginalFiles() throws {
            for name in names {
                #expect(try Data(contentsOf: QuickNoteAttachmentStorage.fileURL(for: name)) == oldFile)
            }
            #expect(try Data(contentsOf: storeURL) == before)
        }

        func transaction(fault: BackupArchiveRestoreJournal.FaultInjector? = nil) -> BackupArchiveService.EmbeddedFileRestoreTransaction {
            BackupArchiveService.EmbeddedFileRestoreTransaction(
                stageRoot: stage,
                photoStage: stage.appendingPathComponent("photos"),
                drawingStage: stage.appendingPathComponent("drawings"),
                documentStage: stage.appendingPathComponent("project-documents"),
                quickNoteStage: stage.appendingPathComponent("quick-note-attachments"),
                counts: BackupEmbeddedRestoreCounts(photoFileCount: 0, drawingFileCount: 0,
                                                   documentFileCount: 0, quickNoteAttachmentFileCount: 2),
                fault: fault
            )
        }

        func cleanup() {
            for name in names { try? FileManager.default.removeItem(at: QuickNoteAttachmentStorage.fileURL(for: name)) }
            try? FileManager.default.removeItem(at: root)
        }

        static func snapshot(_ name: String) -> BackupSnapshot {
            BackupSnapshot(materialItems: [], quoteItems: [], laborRecords: [],
                           projects: [Project(name: name, location: "", status: .active)],
                           dailyLogs: [], historyRecords: [], templates: [])
        }
    }
}
