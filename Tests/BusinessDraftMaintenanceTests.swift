import Foundation
import Testing
@testable import sitekeeper

@MainActor
@Suite(.serialized)
struct BusinessDraftMaintenanceTests {
    @Test func cancelledClearKeepsDraftMetadataPhotoAndBusinessRecords() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanup() }
        let project = Project(name: "取消清空时保留", location: "")
        fixture.store.appendProject(project)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return await fixture.store.clearAllBusinessDataAsync(deleteStoredFiles: true)
        }

        let cleared = await task.value

        #expect(!cleared)
        try fixture.expectDraftIntact()
        #expect(fixture.store.projects.map(\.id) == [project.id])
        #expect(!fixture.store.isApplyingBackup)
    }

    @Test func loadingAndFailedLoadRejectClearBeforeDeletingDraft() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanup() }
        for state in [DataStore.LoadState.loading, .failed] {
            fixture.store.setLoadState(state)

            let cleared = await fixture.store.clearAllBusinessDataAsync(deleteStoredFiles: true)

            #expect(!cleared)
            try fixture.expectDraftIntact()
            #expect(fixture.store.loadState == state)
        }
    }

    @Test func backupRestoreRejectsClearBeforeDeletingDraft() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanup() }
        fixture.store.isApplyingBackup = true

        let cleared = await fixture.store.clearAllBusinessDataAsync(deleteStoredFiles: true)

        #expect(!cleared)
        #expect(fixture.store.isApplyingBackup)
        try fixture.expectDraftIntact()
    }

    @Test func backupExportRejectsClearBeforeDeletingDraft() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanup() }
        try await fixture.store.withBackupExport {
            let cleared = await fixture.store.clearAllBusinessDataAsync(deleteStoredFiles: true)
            #expect(!cleared)
            #expect(fixture.store.isExportingBackup)
            try fixture.expectDraftIntact()
        }
        #expect(!fixture.store.isExportingBackup)
    }

    @Test func clearWithoutStoredFileDeletionPreservesDraftAcrossReload() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanup() }
        fixture.store.appendProject(Project(name: "仅清业务记录", location: ""))
        try await fixture.store.flushSaveOrThrow()

        let cleared = await fixture.store.clearAllBusinessDataAsync(deleteStoredFiles: false)

        #expect(cleared)
        #expect(fixture.store.projects.isEmpty)
        try fixture.expectDraftIntact()
        let loadedSnapshot = try await DataStorePersistenceActor(storeURL: fixture.store.storeURL).loadSnapshot()
        let persisted = try #require(loadedSnapshot)
        #expect(persisted.projects.isEmpty)
        let reopenedDrafts = BusinessDraftStore.scoped(to: fixture.store.storeURL)
        #expect(try reopenedDrafts.load(String.self, key: fixture.key) == fixture.text)
    }

    @Test func explicitDraftRemovalAffectsOnlyThisStoreDirectory() async throws {
        let fixture = try await Fixture()
        defer { fixture.cleanup() }
        let otherDirectory = fixture.root.appendingPathComponent("other-store", isDirectory: true)
        try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)
        let otherStoreURL = otherDirectory.appendingPathComponent("sitekeeper.json")
        let otherDrafts = BusinessDraftStore.scoped(to: otherStoreURL)
        let otherKey = BusinessDraftStore.Key.finance(projectID: UUID())
        try otherDrafts.save("其他账本草稿", key: otherKey)
        let sentinel = otherDirectory.appendingPathComponent("keep.bin")
        let sentinelBytes = Data([7, 8, 9])
        try sentinelBytes.write(to: sentinel)
        try BusinessDraftStore.scoped(to: fixture.store.storeURL).removeAll()

        #expect(!FileManager.default.fileExists(atPath: fixture.drafts.root.path))
        #expect(try otherDrafts.load(String.self, key: otherKey) == "其他账本草稿")
        #expect(try Data(contentsOf: sentinel) == sentinelBytes)
    }

    @MainActor
    private struct Fixture {
        let root: URL
        let store: DataStore
        let drafts: BusinessDraftStore
        let key = BusinessDraftStore.Key.daily(projectID: UUID())
        let photoID = UUID()
        let text = "未完成草稿\n  保留空白  "
        let photoBytes = Data([1, 2, 3])

        init() async throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("BusinessDraftMaintenanceTests-\(UUID().uuidString)", isDirectory: true)
            let directory = root.appendingPathComponent("primary-store", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let createdStore = DataStore(storageDirectory: directory)
            await createdStore.awaitInitialLoad()
            store = createdStore
            drafts = BusinessDraftStore.scoped(to: createdStore.storeURL)
            try drafts.save(text, key: key)
            // An opaque draft blob exercises preservation without creating a production photo.
            try drafts.savePhoto(photoBytes, id: photoID, key: key)
        }

        func expectDraftIntact() throws {
            #expect(try drafts.load(String.self, key: key) == text)
            #expect(try drafts.photo(id: photoID, key: key) == photoBytes)
        }

        func cleanup() {
            store.cancelScheduledSave()
            store.persistTask?.cancel()
            store.dataHealthScanTask?.cancel()
            try? FileManager.default.removeItem(at: root)
        }
    }
}
