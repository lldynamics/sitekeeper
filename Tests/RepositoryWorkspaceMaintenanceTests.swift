import Foundation
import Testing
@testable import sitekeeper

struct RepositoryWorkspaceMaintenanceTests {
    @Test func clearRemovesAllCandidateArtifactsOnlyBesideSelectedLedger() async throws {
        let fixture = try RepositoryTestFixture()
        let other = try RepositoryTestFixture()
        defer { fixture.cleanup()
        other.cleanup() }
        let candidate = try await fixture.candidate()
        let otherCandidate = try await other.candidate()
        let raw = try Data(contentsOf: candidate.directory.appendingPathComponent("source.json"))
        let summary = try RepositoryWorkspaceMaintenance.summary(beside: fixture.source)
        #expect(summary.count == 1)
        #expect(summary.bytes > Int64(raw.count))
        let plan = try RepositoryWorkspaceMaintenance.prepareClear(beside: fixture.source, expectedCount: 1)
        try plan.removeAll()
        #expect(!FileManager.default.fileExists(atPath: candidate.directory.path))
        #expect(FileManager.default.fileExists(atPath: otherCandidate.directory.path))
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(try Data(contentsOf: other.source) == other.raw)
    }

    @Test func everyOpenHandlePreventsDeletionAndFailedLeaseDoesNotReleaseReaders() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let first = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        let second = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        for _ in 0..<3 {
            #expect(throws: RepositoryWorkspaceMaintenanceError.self) { try RepositoryWorkspaceMaintenance.prepareClear(beside: fixture.source) }
        }
        try await first.close()
        #expect(throws: RepositoryWorkspaceMaintenanceError.self) { try RepositoryWorkspaceMaintenance.prepareClear(beside: fixture.source) }
        #expect(try await second.page(RepositoryQuery(collection: .projects), after: nil, limit: 50).items.count == 2)
        try await second.close()
        let plan = try RepositoryWorkspaceMaintenance.prepareClear(beside: fixture.source)
        #expect(throws: RepositoryWorkspaceMaintenanceError.self) { try SQLiteBusinessRepository(candidateDirectory: candidate.directory) }
        try plan.removeAll()
    }

    @Test func changedPreviewRefusesDeletionAndReleasesExclusiveLease() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        #expect(throws: RepositoryWorkspaceMaintenanceError.self) { try RepositoryWorkspaceMaintenance.prepareClear(beside: fixture.source, expectedCount: 0) }
        let repository = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        try await repository.close()
        #expect(FileManager.default.fileExists(atPath: candidate.directory.path))
    }

    @Test func symbolicLinkToOtherLedgerIsRejectedWithoutDeletingTarget() async throws {
        let fixture = try RepositoryTestFixture()
        let other = try RepositoryTestFixture()
        defer { fixture.cleanup()
        other.cleanup() }
        let candidate = try await other.candidate()
        try FileManager.default.createSymbolicLink(at: RepositoryWorkspaceMaintenance.root(beside: fixture.source), withDestinationURL: RepositoryWorkspaceMaintenance.root(beside: other.source))
        #expect(throws: RepositoryWorkspaceMaintenanceError.self) { try RepositoryWorkspaceMaintenance.summary(beside: fixture.source) }
        #expect(throws: RepositoryWorkspaceMaintenanceError.self) { try RepositoryWorkspaceMaintenance.prepareClear(beside: fixture.source) }
        #expect(FileManager.default.fileExists(atPath: candidate.directory.path))
        #expect(try Data(contentsOf: other.source) == other.raw)
    }

    @Test func unexpectedFilesAndChangesAfterPreviewFailClosed() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let plan = try RepositoryWorkspaceMaintenance.prepareClear(beside: fixture.source)
        let unexpected = plan.root.appendingPathComponent("keep-me.txt")
        try Data("preserve".utf8).write(to: unexpected)
        #expect(throws: RepositoryWorkspaceMaintenanceError.self) { try plan.removeAll() }
        #expect(try String(contentsOf: unexpected, encoding: .utf8) == "preserve")
        #expect(FileManager.default.fileExists(atPath: candidate.directory.path))
    }

    @Test func exportRetainsIndependentChangesAndIndividualDeleteRetainsOtherCopy() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let catalog = RepositoryWorkspaceCatalog()
        let first = try await catalog.create(source: fixture.source, assets: fixture.assets)
        let second = try await catalog.create(source: fixture.source, assets: fixture.assets)
        let repository = try await catalog.open(first)
        var project = fixture.snapshot.projects[0]
        project.name = "只存在于副本的修改"
        _ = try await repository.apply([.putProject(project)], expectedRevision: 0)
        try await repository.close()
        let exported = try await RepositoryWorkspaceExport.prepare(first, catalog: catalog)
        defer { ExportFileURLPreparer.cleanup(fileURL: exported.preparedFileURL) }
        let preview = try BackupArchiveService.previewBackup(from: exported.preparedFileURL)
        #expect(preview.snapshot.projects.contains { $0.name == project.name })
        try RepositoryWorkspaceMaintenance.remove(first, beside: fixture.source)
        #expect(try await catalog.entries(beside: fixture.source).map(\.id) == [second.id])
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test @MainActor func activeCopyStopsWholeDataClearBeforeTouchingLedgerOrDrafts() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let store = DataStore(storageDirectory: fixture.directory)
        await store.awaitInitialLoad()
        let candidate = try await fixture.candidate()
        let repository = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        let drafts = BusinessDraftStore.scoped(to: fixture.source)
        let key = BusinessDraftStore.Key.finance(projectID: fixture.snapshot.projects[0].id)
        try drafts.save("未提交的草稿", key: key)
        #expect(await store.clearAllBusinessDataAsync(deleteStoredFiles: true) == false)
        #expect(store.projects.count == fixture.snapshot.projects.count)
        #expect(try drafts.load(String.self, key: key) == "未提交的草稿")
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        try await repository.close()
    }

    @Test @MainActor func cancelledClearAndMetadataOnlyClearRetainCopies() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let store = DataStore(storageDirectory: fixture.directory)
        await store.awaitInitialLoad()
        let candidate = try await fixture.candidate()
        let cancelled = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await store.clearAllBusinessDataAsync(deleteStoredFiles: true)
        }
        #expect(await cancelled.value == false)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(await store.clearAllBusinessDataAsync(deleteStoredFiles: false))
        #expect(FileManager.default.fileExists(atPath: candidate.directory.path))
        #expect(try RepositoryWorkspaceMaintenance.summary(beside: fixture.source).count == 1)
    }

    @Test @MainActor func synchronousClearRefusesToSilentlyLeaveCopiesBehind() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let store = DataStore(storageDirectory: fixture.directory)
        await store.awaitInitialLoad()
        _ = try await fixture.candidate()
        #expect(!store.clearAllBusinessData())
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test @MainActor func sampleImportStopsWhenCandidatePreventsClearing() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let store = DataStore(storageDirectory: fixture.directory)
        await store.awaitInitialLoad()
        let candidate = try await fixture.candidate()
        #expect(store.loadSampleFixtureSnapshot() != nil)
        #expect(!store.importSampleData(replacingExisting: true))
        #expect(store.persistenceErrorMessage == AppLocalization.string("包含试用副本，请通过设置中的清空流程处理。"))
        #expect(store.projects.map(\.id) == fixture.snapshot.projects.map(\.id))
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(FileManager.default.fileExists(atPath: candidate.directory.path))
    }
}
