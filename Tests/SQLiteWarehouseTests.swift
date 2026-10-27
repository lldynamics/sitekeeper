import Foundation
import GRDB
import os
import Testing
@testable import sitekeeper

struct SQLiteWarehouseTests {
    @Test func metadataQueriesAndTargetOnlyWritePreserveLinksAndMaterialList() async throws {
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
        _ = try await repository.page(RepositoryQuery(collection: .projectWarehouseMovements), after: nil, limit: 50)
        _ = try await repository.stockPage(RepositoryStockQuery(projectID: fixture.snapshot.projects[0].id), after: nil, limit: 50)
        let reads = statements.withLock { $0 }
        #expect(reads.contains { $0.contains("LIMIT ?") })
        #expect(!reads.contains { $0.lowercased().contains("payload") || $0.lowercased().contains("sum(") || $0.contains("SELECT *") })
        var movement = fixture.snapshot.projectWarehouseMovements[0]
        movement.quantity = NumericInputSupport.quantity("12.34")
        movement.handler = "已核对经手人"
        movement.counterparty = "供应商A"
        movement.note = "增量修改"
        movement.movementType = .outbound
        _ = try await repository.apply([.putWarehouseMovement(movement)], expectedRevision: 0)
        #expect(try await pool.read { try String.fetchAll($0, sql: "SELECT id FROM test_writes") } == [movement.id.uuidString])
        try await repository.close()
        let reopened = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        let detail = try #require(try await reopened.detail(.projectWarehouseMovements, id: movement.id))
        let saved = try JSONDecoder().decode(ProjectWarehouseMovement.self, from: detail.payload)
        #expect(saved.quantity == movement.quantity && saved.movementType == .outbound && saved.handler == movement.handler)
        #expect(saved.linkedDocumentIds == movement.linkedDocumentIds && saved.createdAt == movement.createdAt)
        #expect(try await reopened.stockPage(RepositoryStockQuery(projectID: movement.projectId), after: nil, limit: 50).items[0].balance == Decimal(string: "-12.34"))
        let material = try #require(try await reopened.record(.materialItems, id: fixture.snapshot.materialItems[0].id))
        #expect(try JSONDecoder().decode(MaterialItem.self, from: material).quantity == fixture.snapshot.materialItems[0].quantity)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(try Data(contentsOf: candidate.directory.appendingPathComponent("source.json")) == fixture.raw)
        try await reopened.close()
        try pool.close()
    }

    @Test(arguments: [1000, 10000])
    func largeWarehousePagesKeepMovementsAndStockBounded(count: Int) async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.projectWarehouseMovements = (0..<count).map {
            ProjectWarehouseMovement(projectId: snapshot.projects[0].id, materialName: "材料 \($0 / 2)", quantity: NumericInputSupport.quantity("0.01"))
        }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let repository = try await fixture.repository(sqlite: true)
        let query = RepositoryStockQuery(projectID: snapshot.projects[0].id)
        let first = try await repository.stockPage(query, after: nil, limit: 50)
        let second = try await repository.stockPage(query, after: first.next, limit: 50)
        #expect(first.totalMaterials == count / 2 && first.items.count == 50 && second.items.count == 50)
        #expect(first.items.allSatisfy { $0.balance == Decimal(string: "0.02") && $0.movementCount == 2 })
        #expect(Set(first.items.map(\.id)).isDisjoint(with: second.items.map(\.id)))
        for order in RepositoryOrder.allCases {
            let movements = RepositoryQuery(collection: .projectWarehouseMovements, order: order)
            var cursor: RepositoryCursor?
            var ids = Set<UUID>()
            repeat {
                let page = try await repository.page(movements, after: cursor, limit: 200)
                #expect(page.items.count <= 200)
                for item in page.items { #expect(ids.insert(item.id).inserted) }
                cursor = page.next
            } while cursor != nil
            #expect(ids.count == count)
        }
    }

    @Test func oldCandidateUpgradeKeepsPayloadsAndRevision() async throws {
        var snapshot = RepositoryTestFixture.sample()
        snapshot.projectWarehouseMovements = (0..<401).map {
            ProjectWarehouseMovement(projectId: snapshot.projects[0].id, materialName: "材料 \($0)", quantity: NumericInputSupport.quantity("0.1"), note: "旧记录 \($0)")
        }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let pool = try SQLiteRepositorySchema.makePool(at: candidate.directory.appendingPathComponent("candidate.sqlite"), create: false)
        let before = try await pool.read { try Data.fetchAll($0, sql: "SELECT payload FROM projectWarehouseMovements ORDER BY id") }
        try await pool.write { db in try Self.downgrade(db)
        try db.execute(sql: "UPDATE repository_state SET revision = 7") }
        let repository = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        #expect(try await repository.revision() == 7)
        let page = try await repository.page(RepositoryQuery(collection: .projectWarehouseMovements, searchText: "旧记录 400"), after: nil, limit: 50)
        #expect(page.items.map(\.id) == [snapshot.projectWarehouseMovements[400].id] && page.items[0].title == "材料 400")
        #expect(try await repository.stockPage(RepositoryStockQuery(projectID: snapshot.projects[0].id), after: nil, limit: 50).totalMaterials == 401)
        #expect(try await pool.read { try Data.fetchAll($0, sql: "SELECT payload FROM projectWarehouseMovements ORDER BY id") } == before)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        try await repository.close()
        try pool.close()
    }

    @Test func failedUpgradeRollsBackNewColumnsWithoutTouchingSource() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let pool = try SQLiteRepositorySchema.makePool(at: candidate.directory.appendingPathComponent("candidate.sqlite"), create: false)
        try await pool.write { db in
            try Self.downgrade(db)
            try db.execute(sql: "UPDATE projectWarehouseMovements SET payload = ?", arguments: [Data("{}".utf8)])
        }
        #expect(throws: (any Error).self) { try SQLiteBusinessRepository(candidateDirectory: candidate.directory) }
        #expect(try await pool.read { try $0.columns(in: "projectWarehouseMovements").map(\.name).contains("stock_key") } == false)
        #expect(try await pool.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM grdb_migrations WHERE identifier = 'candidate-v4-warehouse'") } == 0)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(try Data(contentsOf: candidate.directory.appendingPathComponent("source.json")) == fixture.raw)
        try pool.close()
    }

    @Test func stockRowsAndGroupCountShareSnapshotDuringConcurrentWrite() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let writer = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        let entered = DispatchSemaphore(value: 0)
        let committed = DispatchSemaphore(value: 0)
        let armed = OSAllocatedUnfairLock(initialState: false)
        let reader = try SQLiteBusinessRepository(candidateDirectory: candidate.directory, statementObserver: { sql in
            if sql.hasPrefix("SELECT quantity, movement_type FROM"), armed.withLock({ value in let old = value
            value = false
            return old }) {
                entered.signal()
                _ = committed.wait(timeout: .now() + 10)
            }
        })
        armed.withLock { $0 = true }
        let write = Task.detached(priority: .high) {
            let started = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: entered.wait(timeout: .now() + 10) == .success) }
            }
            guard started else { throw RepositoryError.integrityFailure }
            defer { committed.signal() }
            var value = fixture.snapshot.projectWarehouseMovements[0]
            value.quantity = NumericInputSupport.quantity("99")
            let added = ProjectWarehouseMovement(projectId: value.projectId, materialName: "新材料", quantity: NumericInputSupport.quantity("1"))
            return try await writer.apply([.putWarehouseMovement(value), .putWarehouseMovement(added)], expectedRevision: 0)
        }
        let query = RepositoryStockQuery(projectID: fixture.snapshot.projects[0].id)
        let result = try await reader.stockPage(query, after: nil, limit: 50)
        #expect(try await write.value == 1)
        #expect(result.revision == 0 && result.totalMaterials == 1 && result.items[0].balance == Decimal(string: "2.5"))
        let refreshed = try await reader.stockPage(query, after: nil, limit: 50)
        #expect(refreshed.revision == 1 && refreshed.totalMaterials == 2 && refreshed.items.contains { $0.balance == 99 })
        try await reader.close()
        try await writer.close()
    }

    private static func downgrade(_ db: Database) throws {
        try db.execute(sql: "DROP INDEX warehouse_stock; DROP INDEX warehouse_type_page")
        for column in ["material_name", "specification", "unit", "quantity", "movement_type", "stock_search", "stock_key"] {
            try db.execute(sql: "ALTER TABLE projectWarehouseMovements DROP COLUMN \(column)")
        }
        try db.execute(sql: "UPDATE projectWarehouseMovements SET title = '', search_text = ''")
        try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'candidate-v4-warehouse'")
    }
}
