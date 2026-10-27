import Foundation
import GRDB
import os
import Testing
@testable import sitekeeper

struct SQLiteContactTests {
    @Test func metadataOnlyPagesAndTargetOnlyWriteSurviveRestart() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let pool = try SQLiteRepositorySchema.makePool(at: candidate.directory.appendingPathComponent("candidate.sqlite"), create: false)
        try await pool.write { db in
            try db.execute(sql: "CREATE TABLE test_writes(id TEXT)")
            for collection in RepositoryCollection.allCases {
                try db.execute(sql: "CREATE TRIGGER test_\(collection.rawValue) AFTER UPDATE ON \(collection.rawValue) BEGIN INSERT INTO test_writes VALUES (NEW.id); END")
            }
        }
        let statements = OSAllocatedUnfairLock(initialState: [String]())
        let repo = try SQLiteBusinessRepository(candidateDirectory: candidate.directory, statementObserver: { sql in statements.withLock { $0.append(sql) } })
        statements.withLock { $0.removeAll() }
        _ = try await repo.page(RepositoryQuery(collection: .projectContacts, project: .project(fixture.snapshot.projects[1].id), contactRole: .owner), after: nil, limit: 50)
        let reads = statements.withLock { $0 }
        #expect(reads.contains { $0.contains("LIMIT ?") })
        #expect(!reads.contains { $0.lowercased().contains("payload") || $0.contains("SELECT *") })
        var value = fixture.snapshot.projectContacts[0]
        value.company = "更新单位"
        value.phone = "010-1234"
        value.role = .supplier
        _ = try await repo.apply([.putContact(value)], expectedRevision: 0)
        #expect(try await pool.read { try String.fetchAll($0, sql: "SELECT id FROM test_writes") } == [value.id.uuidString])
        try await repo.close()
        try pool.close()
        let reopened = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        let payload = try #require(try await reopened.record(.projectContacts, id: value.id))
        #expect(try RepositoryJSON.object(payload) as NSDictionary == RepositoryJSON.object(JSONEncoder().encode(value)) as NSDictionary)
        #expect(try await reopened.page(RepositoryQuery(collection: .projectContacts, project: .project(value.relatedProjectIds[0]), contactRole: .supplier), after: nil, limit: 50).items.first?.contact?.company == "更新单位")
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(try Data(contentsOf: candidate.directory.appendingPathComponent("source.json")) == fixture.raw)
        try await reopened.close()
    }

    @Test(arguments: [1000, 10000])
    func largeListsStayPaged(count: Int) async throws {
        var snapshot = RepositoryTestFixture.sample()
        let project = snapshot.projects[0].id
        snapshot.projectContacts = (0..<count).map { ProjectContact(projectId: project, name: String(format: "联系人 %05d", $0)) }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repo = try await fixture.repository(sqlite: true)
        let query = RepositoryQuery(collection: .projectContacts)
        let first = try await repo.page(query, after: nil, limit: 50)
        let second = try await repo.page(query, after: first.next, limit: 50)
        #expect(first.items.count == 50 && second.items.count == 50)
        #expect(Set(first.items.map(\.id)).isDisjoint(with: second.items.map(\.id)))
        #expect(first.items.first?.title == "联系人 00000" && second.items.first?.title == "联系人 00050")
    }

    @Test func v8UpgradePreservesPayloadLinksRevisionAndSearchesFullText() async throws {
        var snapshot = RepositoryTestFixture.sample()
        let primary = snapshot.projects[0].id
        let related = snapshot.projects[1].id
        snapshot.projectContacts = (0..<401).map { ProjectContact(projectId: primary, relatedProjectIds: [related], name: "旧联系人 \($0)", role: .supplier, note: String(repeating: "备注", count: 300) + "末尾匹配") }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let pool = try SQLiteRepositorySchema.makePool(at: candidate.directory.appendingPathComponent("candidate.sqlite"), create: false)
        try await pool.write { db in
            try Self.downgrade(db)
            var legacy = try RepositoryJSON.object(JSONEncoder().encode(fixture.snapshot.projectContacts[0]))
            for key in ["role", "company", "phone"] { legacy.removeValue(forKey: key) }
            try db.execute(sql: "UPDATE projectContacts SET payload = ? WHERE id = ?", arguments: [try JSONSerialization.data(withJSONObject: legacy), fixture.snapshot.projectContacts[0].id.uuidString])
            try db.execute(sql: "UPDATE repository_state SET revision = 8")
        }
        let before = try await pool.read { try Data.fetchAll($0, sql: "SELECT payload FROM projectContacts ORDER BY id") }
        let repo = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        #expect(try await repo.revision() == 8)
        let result = try await repo.page(RepositoryQuery(collection: .projectContacts, project: .project(related), searchText: "旧联系人 400", contactRole: .supplier), after: nil, limit: 50)
        #expect(result.items.map(\.id) == [snapshot.projectContacts[400].id])
        let legacy = try await repo.page(RepositoryQuery(collection: .projectContacts, contactRole: .owner), after: nil, limit: 50)
        #expect(legacy.items.map(\.id) == [snapshot.projectContacts[0].id])
        #expect(legacy.items.first?.contact?.company == "" && legacy.items.first?.contact?.phone == "")
        #expect(try await repo.page(RepositoryQuery(collection: .projectContacts, searchText: "末尾匹配"), after: nil, limit: 50).next != nil)
        #expect(try await pool.read { try Data.fetchAll($0, sql: "SELECT payload FROM projectContacts ORDER BY id") } == before)
        #expect(try await pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM record_links WHERE owner_collection = 'projectContacts'") } == 401)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        try await repo.close()
        try pool.close()
    }

    @Test(arguments: ["id", "role", "company", "relatedProjectIds", "projectId", "linkMismatch"])
    func badLegacyPayloadRollsBackUpgrade(field: String) async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let pool = try SQLiteRepositorySchema.makePool(at: candidate.directory.appendingPathComponent("candidate.sqlite"), create: false)
        try await pool.write { db in
            try Self.downgrade(db)
            var object = try RepositoryJSON.object(JSONEncoder().encode(fixture.snapshot.projectContacts[0]))
            switch field {
            case "id": object[field] = UUID().uuidString
            case "role": object[field] = "无效角色"
            case "company": object[field] = 42
            case "projectId": object[field] = fixture.snapshot.projects[1].id.uuidString
            case "linkMismatch": object["relatedProjectIds"] = []
            default: object[field] = ["not-a-uuid"]
            }
            try db.execute(sql: "UPDATE projectContacts SET payload = ?", arguments: [try JSONSerialization.data(withJSONObject: object)])
        }
        let payloads = try await pool.read { try Data.fetchAll($0, sql: "SELECT payload FROM projectContacts ORDER BY id") }
        #expect(throws: (any Error).self) { try SQLiteBusinessRepository(candidateDirectory: candidate.directory) }
        #expect(try await pool.read { try $0.columns(in: "projectContacts").map(\.name) }.contains("contact_role") == false)
        #expect(try await pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM grdb_migrations WHERE identifier = 'candidate-v9-contacts'") } == 0)
        #expect(try await pool.read { try Data.fetchAll($0, sql: "SELECT payload FROM projectContacts ORDER BY id") } == payloads)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(try Data(contentsOf: candidate.directory.appendingPathComponent("source.json")) == fixture.raw)
        try pool.close()
    }

    private static func downgrade(_ db: Database) throws {
        try db.execute(sql: "DROP INDEX contact_filtered_page; DROP INDEX contact_project_page")
        for column in ["contact_role", "company", "phone"] { try db.execute(sql: "ALTER TABLE projectContacts DROP COLUMN \(column)") }
        try db.execute(sql: "UPDATE projectContacts SET title = '', sort_key = '', search_text = ''")
        try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'candidate-v9-contacts'")
    }
}
