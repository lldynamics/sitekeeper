import Foundation
import Testing
import GRDB
import os
@testable import sitekeeper

struct RepositoryPagingTests {
    @Test(arguments: [false, true])
    func completePagesSearchAndStableDescendingOrder(sqlite: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        let project = snapshot.projects[0].id
        snapshot.dailyLogs = (0..<151).map { index in
            DailyLog(date: BusinessDateValue(legacyText: index < 100 ? "2026-10-23" : "2026-10-24"), weather: "", content: "日志 \(index)", workers: NumericInputSupport.quantity(""), projectId: project)
        }
        snapshot.dailyLogs[10].content = String(repeating: "正文", count: 150) + " CAFÉ %_ 目标"
        snapshot.projects[0].location = "特殊项目地址"
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: sqlite)
        for order in RepositoryOrder.allCases {
            var cursor: RepositoryCursor?
            var ids: [UUID] = []
            let query = RepositoryQuery(collection: .dailyLogs, project: .project(project), order: order)
            repeat {
                let page = try await repository.page(query, after: cursor, limit: 50)
                #expect(page.items.count <= 50)
                ids += page.items.map(\.id)
                cursor = page.next
            } while cursor != nil
            let expected = snapshot.dailyLogs.sorted {
                order == .oldestFirst ? ($0.date, $0.id.uuidString) < ($1.date, $1.id.uuidString) : ($0.date, $0.id.uuidString) > ($1.date, $1.id.uuidString)
            }.map(\.id)
            #expect(ids == expected)
            #expect(Set(ids).count == 151)
        }
        let search = RepositoryQuery(collection: .dailyLogs, project: .project(project), searchText: "cafe %_ 目标", order: .newestFirst)
        #expect(try await repository.page(search, after: nil, limit: 50).items.map(\.id) == [snapshot.dailyLogs[10].id])
        #expect(try await repository.page(RepositoryQuery(collection: .projects, searchText: "特殊项目地址"), after: nil, limit: 50).items.count == 1)
        let first = try await repository.page(RepositoryQuery(collection: .dailyLogs), after: nil, limit: 1)
        await #expect(throws: RepositoryError.invalidCursor) {
            try await repository.page(RepositoryQuery(collection: .dailyLogs, order: .newestFirst), after: first.next, limit: 1)
        }
    }

    @Test(arguments: [1000, 10000])
    func largeListReadsBoundedPagesWithoutDuplicates(count: Int) async throws {
        var snapshot = RepositoryTestFixture.sample()
        let projectID = snapshot.projects[0].id
        snapshot.dailyLogs = (0..<count).map {
            DailyLog(date: BusinessDateValue(legacyText: "2026-10-24"), weather: "", content: "规模日志 \($0)", workers: NumericInputSupport.quantity(""), projectId: projectID)
        }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let repository = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        var cursor: RepositoryCursor?
        var ids = Set<UUID>()
        repeat {
            let page = try await repository.page(RepositoryQuery(collection: .dailyLogs, project: .project(projectID), order: .newestFirst), after: cursor, limit: 50)
            #expect(page.items.count <= 50)
            for item in page.items { #expect(ids.insert(item.id).inserted) }
            cursor = page.next
        } while cursor != nil
        #expect(ids.count == count)
        try await repository.close()
    }

    @Test func listDoesNotReadBodiesAndEditTouchesOnlyTargetRecord() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let database = try SQLiteRepositorySchema.makePool(at: candidate.directory.appendingPathComponent("candidate.sqlite"), create: false)
        try await database.write { db in
            try db.execute(sql: "CREATE TABLE test_writes(id TEXT)")
            for table in ["projects", "dailyLogs"] {
                try db.execute(sql: "CREATE TRIGGER test_\(table) AFTER UPDATE ON \(table) BEGIN INSERT INTO test_writes VALUES (NEW.id); END")
            }
        }
        let statements = OSAllocatedUnfairLock(initialState: [String]())
        let repository = try SQLiteBusinessRepository(candidateDirectory: candidate.directory, statementObserver: { sql in statements.withLock { $0.append(sql) } })
        statements.withLock { $0.removeAll() }
        _ = try await repository.page(RepositoryQuery(collection: .dailyLogs, order: .newestFirst), after: nil, limit: 2)
        let reads = statements.withLock { $0 }
        #expect(reads.contains { $0.contains("LIMIT ?") })
        #expect(!reads.contains { $0.lowercased().contains("payload") || $0.contains("SELECT *") })
        var log = fixture.snapshot.dailyLogs[0]
        log.content = "只更新这条记录"
        _ = try await repository.apply([.putDailyLog(log)], expectedRevision: 0)
        let written = try await database.read { try String.fetchAll($0, sql: "SELECT id FROM test_writes") }
        #expect(written == [log.id.uuidString])
        try await repository.close()
        try database.close()
        let reopened = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        let detail = try #require(try await reopened.detail(.dailyLogs, id: log.id))
        #expect(detail.revision == 1)
        let saved = try JSONDecoder().decode(DailyLog.self, from: detail.payload)
        #expect(saved.content == log.content)
        #expect(saved.allPhotoFileNames == log.allPhotoFileNames)
        #expect(saved.linkedConstructionMethodIDs == log.linkedConstructionMethodIDs)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        try await reopened.close()
    }

    @Test func existingV1CandidateUpgradesSearchWithoutChangingPayloads() async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.dailyLogs = (0..<401).map { DailyLog(date: BusinessDateValue(legacyText: "2026-10-24"), weather: "", content: "升级记录 \($0)", workers: NumericInputSupport.quantity(""), projectId: snapshot.projects[0].id) }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let pool = try SQLiteRepositorySchema.makePool(at: candidate.directory.appendingPathComponent("candidate.sqlite"), create: false)
        try await pool.write { db in
            for collection in RepositoryCollection.allCases {
                try db.execute(sql: "DROP INDEX \(collection.rawValue)_position")
                try db.execute(sql: "ALTER TABLE \(collection.rawValue) DROP COLUMN search_text")
            }
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'candidate-v2-search'")
        }
        try pool.close()
        let repository = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        #expect(try await repository.revision() == 0)
        let page = try await repository.page(RepositoryQuery(collection: .dailyLogs, searchText: "升级记录 400"), after: nil, limit: 10)
        #expect(page.items.map(\.id) == [snapshot.dailyLogs[400].id])
        #expect(try RepositoryDataset(snapshot: await repository.exportSnapshot()) == RepositoryDataset(snapshot: snapshot))
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        try await repository.close()
    }
}
