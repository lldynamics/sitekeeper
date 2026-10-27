import Foundation
import GRDB
import os
import Testing
@testable import sitekeeper

struct SQLiteLaborTests {
    @Test func metadataReadsAndTargetOnlyWriteSurviveRestart() async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.laborRecords = [RepositoryLaborTests.item(project: snapshot.projects[0].id)]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
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
        let query = RepositoryQuery(collection: .laborRecords)
        _ = try await repo.laborPage(query, after: nil, limit: 1)
        let reads = statements.withLock { $0 }
        #expect(reads.contains { $0.contains("LIMIT ?") })
        #expect(!reads.contains { $0.lowercased().contains("payload") || $0.lowercased().contains("sum(") || $0.contains("SELECT *") })
        var record = snapshot.laborRecords[0]
        record.unitRate = MoneyValue(20)
        record.workloadUnit = .workday
        record.teamName = "更新班组"
        record.workType = "电工"
        record.note = "完整保留的备注"
        record.isSettled = true
        record.date = BusinessDateValue(legacyText: "历史未知日期")
        _ = try await repo.apply([.putLaborRecord(record)], expectedRevision: 0)
        #expect(try await pool.read { try String.fetchAll($0, sql: "SELECT id FROM test_writes") } == [record.id.uuidString])
        try await repo.close()
        try pool.close()
        let reopened = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        let payload = try #require(try await reopened.record(.laborRecords, id: record.id))
        #expect(try RepositoryJSON.object(payload) as NSDictionary == RepositoryJSON.object(JSONEncoder().encode(record)) as NSDictionary)
        let page = try await reopened.laborPage(query, after: nil, limit: 50)
        #expect(page.summary.total == 12 && page.summary.unsettled == 0)
        #expect(page.page.items.first?.labor?.workloadUnit == .workday)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(try Data(contentsOf: candidate.directory.appendingPathComponent("source.json")) == fixture.raw)
        try await reopened.close()
    }

    @Test(arguments: [1000, 10000])
    func largeListHasBoundedPagesAndExactTotals(count: Int) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.laborRecords = (0..<count).map { _ in RepositoryLaborTests.item() }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repo = try await fixture.repository(sqlite: true)
        let query = RepositoryQuery(collection: .laborRecords)
        let first = try await repo.laborPage(query, after: nil, limit: 50)
        let second = try await repo.laborPage(query, after: first.page.next, limit: 50)
        #expect(first.page.items.count == 50 && second.page.items.count == 50)
        #expect(Set(first.page.items.map(\.id)).isDisjoint(with: second.page.items.map(\.id)))
        #expect(first.summary == second.summary && first.summary.total == Decimal(count) * Decimal(string: "0.06")!)
    }

    @Test func v7UpgradePreservesPayloadRevisionAndMissingUnit() async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.laborRecords = (0..<401).map { index in
            var record = RepositoryLaborTests.item(unit: .legacyUnspecified)
            record.teamName = "旧班组 \(index)"
            return record
        }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let pool = try SQLiteRepositorySchema.makePool(at: candidate.directory.appendingPathComponent("candidate.sqlite"), create: false)
        try await pool.write { db in
            try Self.downgrade(db)
            let rows = try Row.fetchAll(db, sql: "SELECT id, payload FROM laborRecords")
            for row in rows {
                var object = try RepositoryJSON.object(row["payload"])
                object.removeValue(forKey: "workloadUnit")
                try db.execute(sql: "UPDATE laborRecords SET payload = ? WHERE id = ?", arguments: [try JSONSerialization.data(withJSONObject: object), row["id"] as String])
            }
            try db.execute(sql: "UPDATE repository_state SET revision = 7")
        }
        let before = try await pool.read { try Data.fetchAll($0, sql: "SELECT payload FROM laborRecords ORDER BY id") }
        let repo = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        #expect(try await repo.revision() == 7)
        let result = try await repo.laborPage(RepositoryQuery(collection: .laborRecords, searchText: "旧班组 400", laborUnit: .legacyUnspecified), after: nil, limit: 50)
        #expect(result.page.items.map(\.id) == [snapshot.laborRecords[400].id])
        #expect(result.summary.total == Decimal(string: "0.06") && result.summary.unconfirmedUnitCount == 1)
        #expect(try await pool.read { try Data.fetchAll($0, sql: "SELECT payload FROM laborRecords ORDER BY id") } == before)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        try await repo.close()
        try pool.close()
    }

    @Test(arguments: [false, true])
    func failedUpgradeRollsBackSchemaAndPreservesOriginal(mismatchedID: Bool) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.laborRecords = [RepositoryLaborTests.item()]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let pool = try SQLiteRepositorySchema.makePool(at: candidate.directory.appendingPathComponent("candidate.sqlite"), create: false)
        try await pool.write { db in
            try Self.downgrade(db)
            var object = try RepositoryJSON.object(JSONEncoder().encode(fixture.snapshot.laborRecords[0]))
            if mismatchedID { object["id"] = UUID().uuidString } else { object["workloadUnit"] = "invalid unit" }
            try db.execute(sql: "UPDATE laborRecords SET payload = ?", arguments: [try JSONSerialization.data(withJSONObject: object)])
        }
        #expect(throws: (any Error).self) { try SQLiteBusinessRepository(candidateDirectory: candidate.directory) }
        #expect(try await pool.read { try $0.columns(in: "laborRecords").map(\.name) }.contains("unit_rate") == false)
        #expect(try await pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM grdb_migrations WHERE identifier = 'candidate-v8-labor'") } == 0)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(try Data(contentsOf: candidate.directory.appendingPathComponent("source.json")) == fixture.raw)
        try pool.close()
    }

    @Test func summaryAndPageShareSnapshotDuringConcurrentCommit() async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.laborRecords = [RepositoryLaborTests.item()]
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let writer = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        let entered = DispatchSemaphore(value: 0)
        let committed = DispatchSemaphore(value: 0)
        let armed = OSAllocatedUnfairLock(initialState: false)
        let reader = try SQLiteBusinessRepository(candidateDirectory: candidate.directory, statementObserver: { sql in
            if sql.hasPrefix("SELECT workers, hours, unit_rate, workload_unit, is_settled FROM"), armed.withLock({ value in let old = value
            value = false
            return old }) {
                entered.signal()
                _ = committed.wait(timeout: .now() + 10)
            }
        })
        armed.withLock { $0 = true }
        let write = Task.detached(priority: .high) {
            let started = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: entered.wait(timeout: .now() + 10) == .success)
                }
            }
            guard started else { throw RepositoryError.integrityFailure }
            defer { committed.signal() }
            var value = fixture.snapshot.laborRecords[0]
            value.unitRate = NumericInputSupport.money("4")
            return try await writer.apply([.putLaborRecord(value)], expectedRevision: 0)
        }
        let result = try await reader.laborPage(RepositoryQuery(collection: .laborRecords), after: nil, limit: 50)
        #expect(try await write.value == 1)
        #expect(result.page.revision == 0 && result.summary.total == Decimal(string: "0.06"))
        #expect(result.page.items.first { $0.id == fixture.snapshot.laborRecords[0].id }?.labor?.unitRate == fixture.snapshot.laborRecords[0].unitRate.wireText)
        #expect(try await reader.laborPage(RepositoryQuery(collection: .laborRecords), after: nil, limit: 50).summary.total == Decimal(string: "2.4"))
        try await reader.close()
        try await writer.close()
    }

    private static func downgrade(_ db: Database) throws {
        try db.execute(sql: "DROP INDEX labor_filtered_page")
        for column in ["workers", "hours", "unit_rate", "workload_unit", "team_name", "work_type", "is_settled"] {
            try db.execute(sql: "ALTER TABLE laborRecords DROP COLUMN \(column)")
        }
        try db.execute(sql: "UPDATE laborRecords SET title = '', search_text = '', sort_key = ''")
        try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'candidate-v8-labor'")
    }
}
