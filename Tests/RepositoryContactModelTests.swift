import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct RepositoryContactModelTests {
    @Test func failedPageAndSupersededSearchKeepCorrectRows() async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.projectContacts.append(ProjectContact(projectId: snapshot.projects[0].id, name: "供应商", role: .supplier))
        let repo = try RepositoryControlledRepository(snapshot: snapshot)
        let model = RepositoryPageModel(repository: repo, query: RepositoryQuery(collection: .projectContacts), pageSize: 1)
        await model.reset()
        let initial = model.items
        await repo.failReads(true)
        await model.next()
        #expect(model.items == initial && model.pageNumber == 1 && model.errorMessage != nil)
        await repo.failReads(false)
        await model.next()
        #expect(model.pageNumber == 2)
        let stale = Task { await model.reset(to: RepositoryQuery(collection: .projectContacts, searchText: "hold")) }
        await repo.waitUntilBlocked()
        #expect(model.items.isEmpty)
        await model.reset(to: RepositoryQuery(collection: .projectContacts, contactRole: .supplier))
        await repo.release()
        await stale.value
        #expect(model.items.map(\.id) == [snapshot.projectContacts[1].id])
    }

    @Test func failedSaveConflictAndReloadPreserveDraftAndLinks() async throws {
        let snapshot = RepositoryTestFixture.sample()
        let repo = try RepositoryControlledRepository(snapshot: snapshot)
        let original = snapshot.projectContacts[0]
        let editor = RepositoryRecordEditor(repository: repo, collection: .projectContacts, id: original.id, initial: RepositoryContactDraft(record: original))
        await editor.load()
        editor.draft.record.name = ""
        #expect(await editor.save { try $0.command() } == false)
        editor.draft.record.name = "本地编辑"
        await repo.failWrites(true)
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.record.name == "本地编辑" && editor.revision == 0)
        await repo.failWrites(false)
        var remote = original
        remote.company = "远端单位"
        _ = try await repo.apply([.putContact(remote)], expectedRevision: 0)
        #expect(await editor.save { try $0.command() } == false)
        #expect(editor.draft.record.name == "本地编辑" && editor.draft.record.relatedProjectIds == original.relatedProjectIds)
        await editor.load()
        #expect(editor.draft.record.company == "远端单位")
        editor.draft.record.name = "核对后保存"
        #expect(await editor.save { try $0.command() })
        let saved = try #require(try await repo.record(.projectContacts, id: original.id))
        #expect(try JSONDecoder().decode(ProjectContact.self, from: saved).relatedProjectIds == original.relatedProjectIds)
    }
}
