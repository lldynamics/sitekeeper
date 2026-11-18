import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct BackupPersistenceSafetyTests {
    @Test func unsafeMetadataOnlyAttachmentCannotMutateAnExistingStore() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        let original = Project(name: "原有项目", location: "", status: .active)
        store.replaceProjects([original])
        try await store.flushSaveOrThrow()
        let originalBytes = try Data(contentsOf: store.storeURL)
        let previous = store.makeSnapshot(includePhotoFiles: false)
        let archive = try BackupArchiveService.makeArchive(from: previous)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }

        var imported = TestFixtures.projectSnapshot(projectName: "导入项目")
        imported.quickNotes = [QuickNote(attachments: [
            QuickNoteAttachment(kind: .file, fileName: "../BusinessDrafts/draft.json")
        ])]
        for mode in [ImportMode.overwrite, .merge] {
            let transaction = try BackupArchiveService.prepareEmbeddedFileRestore(from: archive.fileURL)
            defer { transaction.cancel() }
            do {
                _ = try await BackupImportCoordinator.commitAndPersistImport(
                    restoreTransaction: transaction, importedSnapshot: imported,
                    previousSnapshot: previous, importMode: mode, store: store,
                    sourceFileName: archive.fileURL.lastPathComponent
                )
                Issue.record("不安全附件路径必须在导入之前被拒绝")
            } catch FileStorageError.unsafeAttachmentPath {
            } catch {
                Issue.record("收到意外错误：\(error)")
            }
            #expect(store.projects.map(\.id) == [original.id])
            #expect(store.quickNotes.isEmpty)
            #expect(try Data(contentsOf: store.storeURL) == originalBytes)
            #expect(store.loadState == .ready)
        }
    }

    @Test func duplicateIDsAreRejectedBeforePreviewAndOverwrite() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        let originalProject = Project(name: "原有项目", location: "", status: .active)
        store.replaceProjects([originalProject])
        try await store.flushSaveOrThrow()
        let originalBytes = try Data(contentsOf: store.storeURL)
        let previous = store.makeSnapshot(includePhotoFiles: false)
        let validArchive = try BackupArchiveService.makeArchive(from: previous)
        defer { try? FileManager.default.removeItem(at: validArchive.fileURL) }

        var duplicateProjects = TestFixtures.projectSnapshot(projectName: "导入项目")
        duplicateProjects.projects.append(duplicateProjects.projects[0])
        var duplicateDocuments = TestFixtures.projectSnapshot(projectName: "导入项目")
        let document = ProjectDocument(projectId: duplicateDocuments.projects[0].id, title: "资料", fileName: "")
        duplicateDocuments.projectDocuments = [document, document]
        var duplicateFinancialRecords = TestFixtures.projectSnapshot(projectName: "导入项目")
        let record = ProjectFinancialRecord(projectId: duplicateFinancialRecords.projects[0].id)
        duplicateFinancialRecords.projectFinancialRecords = [record, record]
        var duplicateMethods = TestFixtures.projectSnapshot(projectName: "导入项目")
        let method = ConstructionMethod(title: "工艺")
        duplicateMethods.constructionMethods = [method, method]

        for incoming in [duplicateProjects, duplicateDocuments, duplicateFinancialRecords, duplicateMethods] {
            let archive = try BackupArchiveService.makeArchive(from: incoming)
            defer { try? FileManager.default.removeItem(at: archive.fileURL) }
            #expect(throws: BackupSnapshotIdentifierError.self) {
                try BackupArchiveService.previewBackup(from: archive.fileURL)
            }
            #expect(throws: BackupSnapshotIdentifierError.self) {
                try BackupArchiveService.decodeBackup(from: archive.fileURL)
            }
            #expect(throws: BackupSnapshotIdentifierError.self) {
                try BackupArchiveService.prepareEmbeddedFileRestore(from: archive.fileURL)
            }

            // Also exercise constructed snapshots that bypass decoding in both import modes.
            for mode in [ImportMode.overwrite, .merge] {
                let transaction = try BackupArchiveService.prepareEmbeddedFileRestore(from: validArchive.fileURL)
                defer { transaction.cancel() }
                do {
                    _ = try await BackupImportCoordinator.commitAndPersistImport(
                        restoreTransaction: transaction, importedSnapshot: incoming,
                        previousSnapshot: previous, importMode: mode, store: store,
                        sourceFileName: archive.fileURL.lastPathComponent
                    )
                    Issue.record("重复记录 ID 必须在导入之前被拒绝")
                } catch is BackupSnapshotIdentifierError {
                } catch {
                    Issue.record("收到意外错误：\(error)")
                }
            }
            #expect(store.projects.map(\.id) == [originalProject.id])
            #expect(try Data(contentsOf: store.storeURL) == originalBytes)
            #expect(store.loadState == .ready)
        }
    }

    @Test func duplicateIDsInExistingStoreEnterRecoveryWithoutChangingOriginalBytes() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        var invalid = TestFixtures.projectSnapshot(projectName: "异常项目")
        let document = ProjectDocument(projectId: invalid.projects[0].id, title: "资料", fileName: "")
        invalid.projectDocuments = [document, document]
        let original = try JSONEncoder().encode(invalid)
        try original.write(to: url)

        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        #expect(store.loadState == .failed)
        #expect(store.persistenceErrorMessage != nil)
        store.save()
        await store.flushSave()
        #expect(try Data(contentsOf: url) == original)
        let copies = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("sitekeeper_corrupt_") }
        #expect(copies.count == 1)
        #expect(try Data(contentsOf: #require(copies.first)) == original)

        let valid = TestFixtures.projectSnapshot(projectName: "恢复项目")
        let archive = try BackupArchiveService.makeArchive(from: valid)
        defer { try? FileManager.default.removeItem(at: archive.fileURL) }
        let transaction = try BackupArchiveService.prepareEmbeddedFileRestore(from: archive.fileURL)
        _ = try await BackupImportCoordinator.commitAndPersistImport(
            restoreTransaction: transaction, importedSnapshot: valid,
            previousSnapshot: store.makeSnapshot(includePhotoFiles: false),
            importMode: .overwrite, store: store, sourceFileName: archive.fileURL.lastPathComponent
        )
        #expect(store.loadState == .ready)
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("sitekeeper_before_recovery_") }
        #expect(try Data(contentsOf: #require(preserved.first)) == original)
        let reloaded = DataStore(storageDirectory: directory)
        await reloaded.awaitInitialLoad()
        #expect(reloaded.loadState == .ready)
        #expect(reloaded.projects.first?.name == "恢复项目")
    }

    @Test func identifierValidationScopesNestedRecordsToTheirOwner() throws {
        let sharedID = UUID()
        let installment = ProjectPaymentInstallment(id: sharedID, title: "首期", dueDate: .today(), amount: 100)
        let firstPlan = ProjectPaymentPlan(title: "计划一", direction: .income, counterparty: "", installments: [installment])
        let secondPlan = ProjectPaymentPlan(title: "计划二", direction: .income, counterparty: "", installments: [installment])
        var snapshot = TestFixtures.projectSnapshot(projectName: "项目")
        snapshot.projects[0].paymentPlans = [firstPlan, secondPlan]
        snapshot.projectDocuments = [ProjectDocument(id: sharedID, projectId: snapshot.projects[0].id, title: "资料", fileName: "")]
        let validBytes = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(BackupSnapshot.self, from: validBytes)
        #expect(decoded.projects[0].paymentPlans.count == 2)
        #expect(decoded.projectDocuments.first?.id == sharedID)

        snapshot.projects[0].paymentPlans[0].installments.append(installment)
        for schemaVersion in BackupSnapshot.supportedSchemaVersions {
            snapshot.schemaVersion = schemaVersion
            let invalidBytes = try JSONEncoder().encode(snapshot)
            #expect(throws: BackupSnapshotIdentifierError.self) {
                try JSONDecoder().decode(BackupSnapshot.self, from: invalidBytes)
            }
        }

        snapshot.projects[0].paymentPlans[0].installments.removeLast()
        let item = MaterialSheetDraftItem(name: "重复材料")
        snapshot.materialSheetDrafts = [MaterialSheetDraft(title: "草稿", items: [item, item])]
        #expect(throws: BackupSnapshotIdentifierError.self) {
            try JSONDecoder().decode(BackupSnapshot.self, from: JSONEncoder().encode(snapshot))
        }
    }

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

        let snapshot = TestFixtures.projectSnapshot(projectName: "重试成功")
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
        var snapshot = TestFixtures.projectSnapshot(projectName: "备份恢复项目")
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
        var snapshot = TestFixtures.projectSnapshot(projectName: "草稿合并")
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
        let snapshot = TestFixtures.projectSnapshot(projectName: "相同快照")
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
        let snapshot = TestFixtures.projectSnapshot(projectName: "应保存快照")
        #expect(try await actor.persist(snapshot: snapshot))
        try JSONEncoder().encode(TestFixtures.projectSnapshot(projectName: "外部替换内容")).write(to: url, options: .atomic)
        #expect(try await actor.persist(snapshot: snapshot))
        #expect(try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: url)).projects.first?.name == "应保存快照")
        #expect(try await actor.persist(snapshot: snapshot) == false)
    }

    @Test func recoveryBypassesCacheAndPreservesExternallyChangedOriginal() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        let actor = DataStorePersistenceActor(storeURL: url)
        let snapshot = TestFixtures.projectSnapshot(projectName: "恢复快照")
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
        let snapshot = TestFixtures.projectSnapshot(projectName: "读取失败后恢复")
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

    @Test func cancelledFlushSaveReArmsAutosaveForUnpersistedMutations() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()

        store.replaceProjects([Project(name: "取消刷新仍需保存", location: "", status: .active)])
        #expect(store.hasUnpersistedMutations)

        let cancelledTask = Task { @MainActor in
            await store.flushSave()
        }
        cancelledTask.cancel()
        await cancelledTask.value

        if store.hasUnpersistedMutations {
            #expect(store.scheduledSaveTask != nil)
            try await store.flushSaveOrThrow()
        }
        #expect(!store.hasUnpersistedMutations)
        let persisted = try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: store.storeURL))
        #expect(persisted.projects.first?.name == "取消刷新仍需保存")
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("backup-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
