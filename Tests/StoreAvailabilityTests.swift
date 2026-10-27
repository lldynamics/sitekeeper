import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct StoreAvailabilityTests {
    @Test func corruptSourceRejectsCreationAndKeepsOriginalBytesUntilRecovery() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let corrupt = Data("{unreadable ledger".utf8)
        try corrupt.write(to: fixture.source)
        let store = DataStore(storageDirectory: fixture.directory)
        await store.awaitInitialLoad()
        #expect(store.loadState == .failed)
        #expect(!store.canEditBusinessData)
        #expect(throws: DataStore.PersistenceBlockedError.self) { try store.createProject(Project(name: "不能假装保存", location: "")) }
        #expect(store.projects.isEmpty)
        #expect(try Data(contentsOf: fixture.source) == corrupt)
        store.persistenceErrorMessage = nil
        #expect(!store.canEditBusinessData)
        #expect(throws: DataStore.PersistenceBlockedError.self) { try store.createProject(Project(name: "关闭提示后仍应阻止", location: "")) }

        try fixture.raw.write(to: fixture.source)
        store.loadAsync()
        await store.awaitInitialLoad()
        #expect(store.canEditBusinessData)
        let project = Project(name: "恢复后新建", location: "")
        try store.createProject(project)
        try await store.flushSaveOrThrow()
        let reloaded = DataStore(storageDirectory: fixture.directory)
        await reloaded.awaitInitialLoad()
        #expect(reloaded.projects.filter { $0.id == project.id }.count == 1)
        #expect(reloaded.projects.contains { $0.id == fixture.snapshot.projects[0].id })
    }

    @Test func loadingAndRestoreRejectCreationWithoutChangingExistingRecords() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let store = DataStore(storageDirectory: fixture.directory)
        await store.awaitInitialLoad()
        let ids = store.projects.map(\.id)
        store.setLoadState(.loading)
        #expect(throws: DataStore.PersistenceBlockedError.self) { try store.createProject(Project(name: "读取中", location: "")) }
        store.setLoadState(.ready)
        store.isApplyingBackup = true
        #expect(!store.canEditBusinessData)
        #expect(throws: DataStore.PersistenceBlockedError.self) { try store.createProject(Project(name: "恢复中", location: "")) }
        store.isApplyingBackup = false
        #expect(store.canEditBusinessData)
        #expect(store.projects.map(\.id) == ids)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }
}
