import Foundation
import Testing
@testable import sitekeeper

struct RepositoryContactTests {
    @Test(arguments: [false, true])
    func pagingSearchRoleAndRelatedProjects(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        let primary = snapshot.projects[0].id
        let related = snapshot.projects[1].id
        snapshot.projectContacts = (0..<103).map { index in
            ProjectContact(projectId: primary, relatedProjectIds: index < 3 ? [related] : [], name: "相同姓名",
                role: index < 3 ? .supplier : .owner, company: "CAFÉ %_", phone: "13800001234",
                note: String(repeating: "长备注", count: 300) + "末尾匹配")
        }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repo = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryQuery(collection: .projectContacts, project: .project(primary))
        let a = try await repo.page(query, after: nil, limit: 50)
        let b = try await repo.page(query, after: a.next, limit: 50)
        let c = try await repo.page(query, after: b.next, limit: 50)
        let ids = (a.items + b.items + c.items).map(\.id)
        #expect(ids.count == 103 && Set(ids).count == 103 && c.next == nil)
        #expect(ids.map(\.uuidString) == ids.map(\.uuidString).sorted())
        let backwards = try await repo.page(RepositoryQuery(collection: .projectContacts, order: .newestFirst), after: nil, limit: 200)
        #expect(backwards.items.map(\.id) == Array(ids.reversed()))
        for search in ["cafe", "%_", "13800001234", "末尾匹配"] {
            let matches = try await repo.page(RepositoryQuery(collection: .projectContacts, searchText: search), after: nil, limit: 200)
            #expect(matches.items.count == 103)
        }
        let shared = try await repo.page(RepositoryQuery(collection: .projectContacts, project: .project(related), contactRole: .supplier), after: nil, limit: 50)
        #expect(Set(shared.items.map(\.id)) == Set(snapshot.projectContacts.prefix(3).map(\.id)))
        #expect(try await repo.page(RepositoryQuery(collection: .projectContacts, project: .unassigned), after: nil, limit: 50).items.isEmpty)
        #expect(try await repo.page(RepositoryQuery(collection: .projects, contactRole: .owner), after: nil, limit: 50).items.isEmpty)
        #expect(try await repo.page(RepositoryQuery(collection: .projectContacts, searchText: "不存在"), after: nil, limit: 50).items.isEmpty)
        await #expect(throws: RepositoryError.invalidCursor) {
            try await repo.page(RepositoryQuery(collection: .projectContacts, contactRole: .supplier), after: a.next, limit: 50)
        }
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test(arguments: [false, true])
    func writesUpdateLinksAtomicallyAndInvalidateCursor(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.projectContacts.append(ProjectContact(projectId: snapshot.projects[0].id, name: "第二联系人"))
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repo = try await fixture.repository(sqlite: sqlite)
        let query = RepositoryQuery(collection: .projectContacts)
        let first = try await repo.page(query, after: nil, limit: 1)
        var value = snapshot.projectContacts[0]
        let oldPrimary = value.projectId
        value.projectId = snapshot.projects[1].id
        value.relatedProjectIds = []
        value.name = "更新姓名"
        value.company = "新单位"
        value.phone = "+86 (010) 1234 ext 2"
        value.note = String(repeating: "完整备注", count: 500)
        value.role = .team
        #expect(try await repo.apply([.putContact(value)], expectedRevision: 0) == 1)
        #expect(try await repo.page(RepositoryQuery(collection: .projectContacts, project: .project(oldPrimary)), after: nil, limit: 50).items.map(\.id) == [snapshot.projectContacts[1].id])
        let saved = try #require(try await repo.record(.projectContacts, id: value.id))
        #expect(try RepositoryJSON.object(saved) as NSDictionary == RepositoryJSON.object(JSONEncoder().encode(value)) as NSDictionary)
        await #expect(throws: RepositoryError.staleRevision) { try await repo.page(query, after: first.next, limit: 1) }
        await #expect(throws: RepositoryError.staleRevision) { try await repo.apply([.putContact(value)], expectedRevision: 0) }
        var bad = value
        bad.relatedProjectIds = [UUID()]
        await #expect(throws: (any Error).self) { try await repo.apply([.putProject(Project(name: "不应留下", location: "")), .putContact(bad)], expectedRevision: 1) }
        #expect(try await repo.revision() == 1)
        #expect(try await repo.exportSnapshot().projects.count == 2)
        #expect(try await repo.record(.projectContacts, id: value.id) == saved)
        bad = value
        bad.name = " \n "
        await #expect(throws: RepositoryError.invalidContactName) { try await repo.apply([.putContact(bad)], expectedRevision: 1) }
        bad = value
        bad.projectId = UUID()
        await #expect(throws: (any Error).self) { try await repo.apply([.putContact(bad)], expectedRevision: 1) }
        let new = ProjectContact(projectId: oldPrimary, relatedProjectIds: [value.projectId], name: "新增")
        #expect(try await repo.apply([.putContact(new)], expectedRevision: 1) == 2)
        #expect(try await repo.exportSnapshot().projectContacts.count == 3)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test func listMetadataIsBoundedButSearchAndPayloadRemainComplete() throws {
        let value = ProjectContact(projectId: UUID(), name: String(repeating: "名", count: 1000) + "姓名末尾",
            company: String(repeating: "司", count: 1000), phone: String(repeating: "1", count: 1000), note: "完整备注")
        let row = try RepositoryRecord(collection: .projectContacts, payload: JSONEncoder().encode(value), position: 0)
        #expect(row.title.count == 120 && row.sortKey.count == 240)
        #expect(row.contact?.company.count == 240 && row.contact?.phone.count == 120)
        #expect(row.matches(RepositoryQuery(collection: .projectContacts, searchText: "姓名末尾")))
        #expect(try JSONDecoder().decode(ProjectContact.self, from: row.payload).name == value.name)
    }

    @Test func draftKeepsAllFieldsAndLegacyBlankCanBeRepaired() throws {
        var record = RepositoryTestFixture.sample().projectContacts[0]
        record.name = ""
        var draft = RepositoryContactDraft(record: record)
        #expect(throws: RepositoryError.invalidContactName) { try draft.command() }
        draft.record.name = "补充姓名"
        guard case .putContact(let saved) = try draft.command() else { Issue.record("Wrong command")
        return }
        #expect(saved.projectId == record.projectId && saved.relatedProjectIds == record.relatedProjectIds)
    }
}
