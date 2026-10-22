import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct BackupPersistenceSafetyTests {
    @Test func corruptStoreBlocksAutomaticAndExplicitSavesUntilSuccessfulRetry() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        let corrupt = Data("unreadable-json-original".utf8)
        try corrupt.write(to: url)
        let store = DataStore(storageDirectory: directory)
        store.replaceProjects([Project(name: "加载期间的修改", location: "", status: .active)])
        store.save()
        await store.awaitInitialLoad()
        #expect(store.loadState == .failed)
        store.save()
        await store.flushSave()
        #expect(try Data(contentsOf: url) == corrupt)
        #expect(store.persistenceErrorMessage != nil)

        let snapshot = emptySnapshot(projectName: "重试成功")
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        store.loadAsync()
        await store.awaitInitialLoad()
        #expect(store.loadState == .ready)
        #expect(store.persistenceErrorMessage == nil)
        #expect(store.projects.first?.name == "重试成功")
        try await store.flushSaveOrThrow()
        #expect(try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: url)).projects.first?.name == "重试成功")
    }

    @Test func failedCorruptCopyReportsFailureAndNeverClaimsPreservation() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        let corrupt = Data("corrupt".utf8)
        try corrupt.write(to: url)
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        store.preserveUnreadableData(corrupt) { _, _ in throw CocoaError(.fileWriteNoPermission) }
        #expect(store.persistenceErrorMessage?.contains("异常副本未能写入") == true)
        #expect(store.persistenceErrorMessage?.contains("已保留异常文件") == false)
        await store.flushSave()
        #expect(try Data(contentsOf: url) == corrupt)
    }

    @Test func unreadableMainFileCannotBeReplacedByAnEmptyAutosave() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let marker = url.appendingPathComponent("original-data")
        try Data([0xA1]).write(to: marker)
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        #expect(store.loadState == .failed)
        store.save()
        await store.flushSave()
        #expect(try Data(contentsOf: marker) == Data([0xA1]))
    }

    @Test func missingStoreAllowsFirstSave() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        #expect(store.loadState == .ready)
        store.replaceProjects([Project(name: "首次保存", location: "", status: .active)])
        try await store.flushSaveOrThrow()
        #expect(FileManager.default.fileExists(atPath: store.storeURL.path))
    }

    @Test func cancelledFlushPropagatesCancellationWithoutReportingFailureOrChangingSavedBytes() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        store.replaceProjects([Project(name: "Saved", location: "", status: .active)])
        try await store.flushSaveOrThrow()
        let originalData = try Data(contentsOf: store.storeURL)
        store.replaceProjects([Project(name: "Pending", location: "", status: .active)])

        let cancelledFlush = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.flushSaveOrThrow()
        }
        do {
            try await cancelledFlush.value
            Issue.record("A cancelled flush must propagate CancellationError")
        } catch is CancellationError {}

        #expect(store.persistenceErrorMessage == nil)
        #expect(store.loadState == .ready)
        #expect(try Data(contentsOf: store.storeURL) == originalData)
        try await store.flushSaveOrThrow()
        #expect(try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: store.storeURL)).projects.first?.name == "Pending")
    }

    @Test func cancelledFlushPreservesAnExistingRealWriteFailure() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        // Make the destination unwritable as a data file after a successful initial load.
        try FileManager.default.createDirectory(at: store.storeURL, withIntermediateDirectories: false)
        let originalFile = store.storeURL.appendingPathComponent("original-data")
        try Data([0xA1]).write(to: originalFile)
        do {
            try await store.flushSaveOrThrow()
            Issue.record("A directory at the destination must reject the save")
        } catch {}
        let writeFailure = try #require(store.persistenceErrorMessage)

        let cancelledFlush = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.flushSaveOrThrow()
        }
        do {
            try await cancelledFlush.value
            Issue.record("A cancelled flush must propagate CancellationError")
        } catch is CancellationError {}

        #expect(store.persistenceErrorMessage == writeFailure)
        #expect(try Data(contentsOf: originalFile) == Data([0xA1]))
    }

    @Test func confirmedRestorePreservesCorruptOriginalAndUnlocksSaving() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        let corrupt = Data("original-corrupt-bytes".utf8)
        try corrupt.write(to: url)
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        var snapshot = emptySnapshot(projectName: "备份恢复项目")
        snapshot.materialSheetDrafts = [MaterialSheetDraft(title: "备份草稿")]
        let archive = try BackupArchiveService.makeArchive(from: snapshot)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }
        let transaction = try BackupArchiveService.prepareEmbeddedFileRestore(from: archive.fileURL)
        _ = try await BackupImportCoordinator.commitAndPersistImport(
            restoreTransaction: transaction, importedSnapshot: snapshot,
            previousSnapshot: store.makeSnapshot(includePhotoFiles: false),
            importMode: .overwrite, store: store, sourceFileName: archive.fileURL.lastPathComponent
        )
        #expect(store.loadState == .ready)
        #expect(store.persistenceErrorMessage == nil)
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("sitekeeper_before_recovery_") }
        #expect(preserved.count == 1)
        #expect(try Data(contentsOf: #require(preserved.first)) == corrupt)
        let reloaded = DataStore(storageDirectory: directory)
        await reloaded.awaitInitialLoad()
        #expect(reloaded.projects.first?.name == "备份恢复项目")
        #expect(reloaded.materialSheetDrafts.first?.title == "备份草稿")
    }

    @Test func mergeDraftsKeepsLocalConflictsAndAddsIncomingIDs() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        let existing = MaterialSheetDraft(title: "本地版本")
        store.replaceMaterialSheetDrafts([existing])
        var snapshot = emptySnapshot(projectName: "草稿合并")
        snapshot.materialSheetDrafts = [MaterialSheetDraft(id: existing.id, title: "冲突版本"), MaterialSheetDraft(title: "新增草稿")]
        BackupImportCoordinator.applyImportMetadata(snapshot: snapshot, mode: .merge, store: store)
        #expect(store.materialSheetDrafts.map(\.title) == ["本地版本", "新增草稿"])
        try await store.flushSaveOrThrow()
        let reloaded = DataStore(storageDirectory: directory)
        await reloaded.awaitInitialLoad()
        #expect(reloaded.materialSheetDrafts.map(\.title) == ["本地版本", "新增草稿"])
    }

    @Test func persistenceRecreatesMissingFileWhenSnapshotMatchesCache() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        let actor = DataStorePersistenceActor(storeURL: url)
        let snapshot = emptySnapshot(projectName: "相同快照")
        #expect(try await actor.persist(snapshot: snapshot))
        try FileManager.default.removeItem(at: url)
        #expect(try await actor.persist(snapshot: snapshot))
        #expect(try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: url)).projects.first?.name == "相同快照")
    }

    @Test func persistenceDoesNotTreatExternallyReplacedBytesAsANoOp() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        let actor = DataStorePersistenceActor(storeURL: url)
        let snapshot = emptySnapshot(projectName: "应保存快照")
        #expect(try await actor.persist(snapshot: snapshot))
        try JSONEncoder().encode(emptySnapshot(projectName: "外部替换内容")).write(to: url, options: .atomic)
        #expect(try await actor.persist(snapshot: snapshot))
        #expect(try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: url)).projects.first?.name == "应保存快照")
        #expect(try await actor.persist(snapshot: snapshot) == false)
    }

    @Test func recoveryBypassesCacheAndPreservesExternallyChangedOriginal() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        let actor = DataStorePersistenceActor(storeURL: url)
        let snapshot = emptySnapshot(projectName: "恢复快照")
        #expect(try await actor.persist(snapshot: snapshot))
        let corrupt = Data("changed-original".utf8)
        try corrupt.write(to: url, options: .atomic)
        #expect(try await actor.persist(snapshot: snapshot, preservingExistingFile: true))
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("sitekeeper_before_recovery_") }
        #expect(preserved.count == 1)
        #expect(try Data(contentsOf: #require(preserved.first)) == corrupt)
    }

    @Test func failedReadInvalidatesCacheBeforeRecovery() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        let actor = DataStorePersistenceActor(storeURL: url)
        let snapshot = emptySnapshot(projectName: "读取失败后恢复")
        #expect(try await actor.persist(snapshot: snapshot))
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        do {
            _ = try await actor.loadSnapshot()
            Issue.record("Reading a directory as store data must fail")
        } catch {}
        // The original obstruction is resolved before retrying the same snapshot.
        try FileManager.default.removeItem(at: url)
        #expect(try await actor.persist(snapshot: snapshot, preservingExistingFile: true))
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("backup-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func emptySnapshot(projectName: String) -> BackupSnapshot {
        BackupSnapshot(materialItems: [], quoteItems: [], laborRecords: [],
                       projects: [Project(name: projectName, location: "", status: .active)],
                       dailyLogs: [], historyRecords: [], templates: [])
    }
}
