import Foundation
import GRDB
import os
import Testing
@testable import sitekeeper

struct SQLiteFinancialTests {
    @Test func metadataOnlyReadsAndSingleRecordWriteSurviveRestart() async throws {
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
        let repository = try SQLiteBusinessRepository(candidateDirectory: candidate.directory, statementObserver: { sql in statements.withLock { $0.append(sql) } })
        statements.withLock { $0.removeAll() }
        let query = RepositoryQuery(collection: .projectFinancialRecords, project: .project(fixture.snapshot.projects[0].id))
        _ = try await repository.financialPage(query, after: nil, limit: 1)
        let reads = statements.withLock { $0 }
        #expect(reads.contains { $0.contains("LIMIT ?") })
        #expect(!reads.contains { $0.lowercased().contains("payload") || $0.lowercased().contains("sum(") || $0.contains("SELECT *") })
        var record = fixture.snapshot.projectFinancialRecords[0]
        record.amount = NumericInputSupport.money("123.45")
        record.invoiceNumber = "保留票号"
        record.dueDate = BusinessDateValue(legacyText: "2027-01-01")
        record.reminderStatus = .pending
        record.counterparty = "已编辑单位"
        record.status = .draft
        _ = try await repository.apply([.putFinancialRecord(record)], expectedRevision: 0)
        let writes = try await pool.read { try String.fetchAll($0, sql: "SELECT id FROM test_writes") }
        #expect(writes == [record.id.uuidString])
        try await repository.close()
        try pool.close()
        let reopened = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        let detail = try #require(try await reopened.detail(.projectFinancialRecords, id: record.id))
        let saved = try JSONDecoder().decode(ProjectFinancialRecord.self, from: detail.payload)
        #expect(saved.amount == record.amount && saved.invoiceNumber == record.invoiceNumber && saved.dueDate == record.dueDate)
        #expect(saved.linkedDocumentIds == record.linkedDocumentIds && saved.reminderStatus == .pending)
        let result = try await reopened.financialPage(query, after: nil, limit: 50)
        #expect(result.summary.activeCount == 2 && result.summary.income == Decimal(string: "0.20"))
        #expect(result.page.items.first { $0.id == record.id }?.financial?.status == .draft)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(try Data(contentsOf: candidate.directory.appendingPathComponent("source.json")) == fixture.raw)
        try await reopened.close()
    }

    @Test(arguments: [1000, 10000])
    func largeFinanceListKeepsBoundedPagesAndExactTotals(count: Int) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.projectFinancialRecords = (0..<count).map {
            ProjectFinancialRecord(projectId: snapshot.projects[0].id, date: BusinessDateValue(legacyText: "2026-10-24"), direction: .income, amount: NumericInputSupport.money("0.01"), note: "规模记录 \($0)")
        }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: true)
        let query = RepositoryQuery(collection: .projectFinancialRecords)
        let first = try await repository.financialPage(query, after: nil, limit: 50)
        let second = try await repository.financialPage(query, after: first.page.next, limit: 50)
        #expect(first.page.items.count == 50 && second.page.items.count == 50)
        #expect(Set(first.page.items.map(\.id)).isDisjoint(with: second.page.items.map(\.id)))
        #expect(first.summary == second.summary && first.summary.income == Decimal(count) / 100)
    }

    @Test func oldCandidateUpgradePreservesPayloadRevisionAndEditedAmounts() async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.projectFinancialRecords = (0..<401).map {
            ProjectFinancialRecord(projectId: snapshot.projects[0].id, amount: NumericInputSupport.money("0.1"), counterparty: "升级记录 \($0)", note: "搜索词 \($0)")
        }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let pool = try SQLiteRepositorySchema.makePool(at: candidate.directory.appendingPathComponent("candidate.sqlite"), create: false)
        let before = try await pool.read { try Data.fetchAll($0, sql: "SELECT payload FROM projectFinancialRecords ORDER BY id") }
        try await pool.write { db in
            try Self.downgrade(db)
            try db.execute(sql: "UPDATE repository_state SET revision = 7")
        }
        let repository = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        #expect(try await repository.revision() == 7)
        let result = try await repository.financialPage(RepositoryQuery(collection: .projectFinancialRecords, searchText: "搜索词 400"), after: nil, limit: 50)
        #expect(result.page.items.map(\.id) == [snapshot.projectFinancialRecords[400].id])
        #expect(result.page.items.first?.title == "升级记录 400" && result.summary.expense == Decimal(string: "0.1"))
        let after = try await pool.read { try Data.fetchAll($0, sql: "SELECT payload FROM projectFinancialRecords ORDER BY id") }
        #expect(before == after)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        try await repository.close()
        try pool.close()
    }

    @Test func failedUpgradeRollsBackSchemaAndKeepsOriginals() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let pool = try SQLiteRepositorySchema.makePool(at: candidate.directory.appendingPathComponent("candidate.sqlite"), create: false)
        try await pool.write { db in
            try Self.downgrade(db)
            try db.execute(sql: "UPDATE projectFinancialRecords SET payload = ?", arguments: [Data("{}".utf8)])
        }
        #expect(throws: (any Error).self) { try SQLiteBusinessRepository(candidateDirectory: candidate.directory) }
        let columns = try await pool.read { try $0.columns(in: "projectFinancialRecords").map(\.name) }
        #expect(!columns.contains("financial_status"))
        let migrationCount = try await pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM grdb_migrations WHERE identifier = 'candidate-v3-finance'") }
        #expect(migrationCount == 0)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(try Data(contentsOf: candidate.directory.appendingPathComponent("source.json")) == fixture.raw)
        try pool.close()
    }

    @Test func summaryAndPageShareSnapshotDuringConcurrentCommit() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let writer = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        let entered = DispatchSemaphore(value: 0)
        let committed = DispatchSemaphore(value: 0)
        let armed = OSAllocatedUnfairLock(initialState: false)
        let reader = try SQLiteBusinessRepository(candidateDirectory: candidate.directory, statementObserver: { sql in
            if sql.hasPrefix("SELECT amount, direction, financial_status FROM"), armed.withLock({ value in let old = value
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
            var value = fixture.snapshot.projectFinancialRecords[0]
            value.amount = NumericInputSupport.money("99.00")
            return try await writer.apply([.putFinancialRecord(value)], expectedRevision: 0)
        }
        let result = try await reader.financialPage(RepositoryQuery(collection: .projectFinancialRecords), after: nil, limit: 50)
        #expect(try await write.value == 1)
        #expect(result.page.revision == 0 && result.summary.income == Decimal(string: "0.30"))
        #expect(result.page.items.first { $0.id == fixture.snapshot.projectFinancialRecords[0].id }?.financial?.amount == fixture.snapshot.projectFinancialRecords[0].amount.wireText)
        #expect(try await reader.financialPage(RepositoryQuery(collection: .projectFinancialRecords), after: nil, limit: 50).summary.income == Decimal(string: "99.20"))
        try await reader.close()
        try await writer.close()
    }

    private static func downgrade(_ db: Database) throws {
        try db.execute(sql: "DROP INDEX financial_filtered_page")
        for column in ["financial_category", "financial_status", "counterparty"] {
            try db.execute(sql: "ALTER TABLE projectFinancialRecords DROP COLUMN \(column)")
        }
        try db.execute(sql: "UPDATE projectFinancialRecords SET title = '', search_text = ''")
        try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'candidate-v3-finance'")
    }
}
