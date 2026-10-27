import Foundation
import GRDB
import os
import Testing
@testable import sitekeeper

struct SQLiteQuoteTests {
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
        let query = RepositoryQuery(collection: .quoteItems, project: .project(fixture.snapshot.projects[0].id))
        _ = try await repository.quotePage(query, after: nil, limit: 1)
        let reads = statements.withLock { $0 }
        #expect(reads.contains { $0.contains("LIMIT ?") })
        #expect(!reads.contains { $0.lowercased().contains("payload") || $0.lowercased().contains("sum(") || $0.contains("SELECT *") })
        var record = fixture.snapshot.quoteItems[0]
        record.quantity = NumericInputSupport.quantity("0.2")
        record.unitPrice = NumericInputSupport.money("12.34")
        record.name = "已编辑报价"
        record.notes = "保留备注"
        record.taxRate = NumericInputSupport.quantity("13")
        record.discountRate = NumericInputSupport.quantity("5")
        record.versionName = "V2"
        record.contractAmount = NumericInputSupport.money("9999")
        record.customerConfirmedDate = BusinessDateValue(legacyText: "2027-01-01")
        record.status = .confirmed
        _ = try await repository.apply([.putQuoteItem(record)], expectedRevision: 0)
        let writes = try await pool.read { try String.fetchAll($0, sql: "SELECT id FROM test_writes") }
        #expect(writes == [record.id.uuidString])
        try await repository.close()
        try pool.close()
        let reopened = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        let detail = try #require(try await reopened.detail(.quoteItems, id: record.id))
        let saved = try JSONDecoder().decode(QuoteItem.self, from: detail.payload)
        #expect(saved.quantity == record.quantity && saved.unitPrice == record.unitPrice && saved.name == record.name)
        #expect(saved.notes == record.notes && saved.taxRate == record.taxRate && saved.discountRate == record.discountRate)
        #expect(saved.versionName == record.versionName && saved.contractAmount == record.contractAmount)
        #expect(saved.projectId == record.projectId && saved.customerConfirmedDate == record.customerConfirmedDate)
        let result = try await reopened.quotePage(query, after: nil, limit: 50)
        #expect(result.summary.count == 1 && result.summary.amounts?.total == Decimal(string: "2.66544"))
        #expect(result.page.items.first?.quote?.status == .confirmed)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(try Data(contentsOf: candidate.directory.appendingPathComponent("source.json")) == fixture.raw)
        try await reopened.close()
    }

    @Test(arguments: [1000, 10000])
    func largeQuotesListKeepsBoundedPagesAndExactTotals(count: Int) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.quoteItems = (0..<count).map {
            RepositoryQuoteTests.item(name: "规模记录 \($0)", quantity: "0.1", price: "0.1", project: snapshot.projects[0].id)
        }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: true)
        let query = RepositoryQuery(collection: .quoteItems)
        let first = try await repository.quotePage(query, after: nil, limit: 50)
        let second = try await repository.quotePage(query, after: first.page.next, limit: 50)
        #expect(first.page.items.count == 50 && second.page.items.count == 50)
        #expect(Set(first.page.items.map(\.id)).isDisjoint(with: second.page.items.map(\.id)))
        #expect(first.summary == second.summary && first.summary.amounts?.total == Decimal(count) * Decimal(string: "0.0108")!)
    }

    @Test func oldCandidateUpgradePreservesPayloadRevisionAndEditedAmounts() async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.quoteItems = (0..<401).map {
            RepositoryQuoteTests.item(name: "升级记录 \($0)", quantity: "1", price: "0.1", tax: "0", discount: "0", version: "搜索词 \($0)", project: snapshot.projects[0].id, date: "2026-10-24")
        }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let pool = try SQLiteRepositorySchema.makePool(at: candidate.directory.appendingPathComponent("candidate.sqlite"), create: false)
        let before = try await pool.read { try Data.fetchAll($0, sql: "SELECT payload FROM quoteItems ORDER BY id") }
        try await pool.write { db in
            try Self.downgrade(db)
            try db.execute(sql: "UPDATE repository_state SET revision = 7")
        }
        let repository = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        #expect(try await repository.revision() == 7)
        let result = try await repository.quotePage(RepositoryQuery(collection: .quoteItems, searchText: "搜索词 400"), after: nil, limit: 50)
        #expect(result.page.items.map(\.id) == [snapshot.quoteItems[400].id])
        #expect(result.page.items.first?.title == "升级记录 400" && result.summary.amounts?.total == Decimal(string: "0.1"))
        let after = try await pool.read { try Data.fetchAll($0, sql: "SELECT payload FROM quoteItems ORDER BY id") }
        #expect(before == after)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        try await repository.close()
        try pool.close()
    }

    @Test(arguments: [false, true])
    func failedUpgradeRollsBackSchemaAndKeepsOriginals(mismatchedID: Bool) async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let pool = try SQLiteRepositorySchema.makePool(at: candidate.directory.appendingPathComponent("candidate.sqlite"), create: false)
        try await pool.write { db in
            try Self.downgrade(db)
            let payload: Data
            if mismatchedID {
                var object = try RepositoryJSON.object(try #require(try Data.fetchOne(db, sql: "SELECT payload FROM quoteItems LIMIT 1")))
                object["id"] = UUID().uuidString
                payload = try JSONSerialization.data(withJSONObject: object)
            } else { payload = Data("{}".utf8) }
            try db.execute(sql: "UPDATE quoteItems SET payload = ?", arguments: [payload])
        }
        #expect(throws: (any Error).self) { try SQLiteBusinessRepository(candidateDirectory: candidate.directory) }
        let columns = try await pool.read { try $0.columns(in: "quoteItems").map(\.name) }
        #expect(!columns.contains("quote_status"))
        let migrationCount = try await pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM grdb_migrations WHERE identifier = 'candidate-v6-quotes'") }
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
            if sql.hasPrefix("SELECT quantity, unit_price, tax_rate, discount_rate FROM"), armed.withLock({ value in let old = value
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
            var value = fixture.snapshot.quoteItems[0]
            value.unitPrice = NumericInputSupport.money("4")
            return try await writer.apply([.putQuoteItem(value)], expectedRevision: 0)
        }
        let result = try await reader.quotePage(RepositoryQuery(collection: .quoteItems), after: nil, limit: 50)
        #expect(try await write.value == 1)
        #expect(result.page.revision == 0 && result.summary.amounts?.total == Decimal(string: "7.05"))
        #expect(result.page.items.first { $0.id == fixture.snapshot.quoteItems[0].id }?.quote?.unitPrice == fixture.snapshot.quoteItems[0].unitPrice.wireText)
        #expect(try await reader.quotePage(RepositoryQuery(collection: .quoteItems), after: nil, limit: 50).summary.amounts?.total == 12)
        try await reader.close()
        try await writer.close()
    }

    private static func downgrade(_ db: Database) throws {
        try db.execute(sql: "DROP INDEX quote_filtered_page")
        for column in ["quantity", "unit_price", "unit", "tax_rate", "discount_rate", "version_name", "quote_status"] {
            try db.execute(sql: "ALTER TABLE quoteItems DROP COLUMN \(column)")
        }
        try db.execute(sql: "UPDATE quoteItems SET title = '', search_text = '', sort_key = ''")
        try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'candidate-v6-quotes'")
    }
}
