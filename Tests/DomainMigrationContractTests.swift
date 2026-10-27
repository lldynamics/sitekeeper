import Foundation
import SwiftUI
import Testing
import GRDB
import os
@testable import sitekeeper

struct DomainMigrationContractTests {
    private struct IndexedPayload: Equatable, Sendable {
        let id: String
        let payload: Data
        let position: Int
    }

    @Test(arguments: [2, 3])
    func legacyBackupKeepsDatesMissingValuesAndExactMoney(schema: Int) throws {
        let projectID = UUID()
        let raw = Data("""
        {"schemaVersion":\(schema),"projects":[{"id":"\(projectID)","name":"历史工程","startDate":"2024/5/1","expectedEndDate":"待确认","contractAmount":"9007199254740993.01"}],
        "projectFinancialRecords":[{"projectId":"\(projectID)","date":"2024-05-01 14:30:00","dueDate":"未确定","amount":"0.10"}],
        "materialItems":[{"name":"旧材料","quantity":"","unitPrice":"非法原值"}]}
        """.utf8)
        let snapshot = try BackupArchiveService.decodeJSONSnapshot(from: raw)
        let restored = try BackupArchiveService.decodeJSONSnapshot(from: BackupArchiveService.encodeMetadata(snapshot))
        #expect(restored.projects[0].contractAmount.optionalDecimal == Decimal(string: "9007199254740993.01"))
        #expect(restored.projects[0].startDate.storageText == "2024/5/1")
        #expect(restored.projects[0].expectedEndDate.storageText == "待确认")
        #expect(restored.projectFinancialRecords[0].date.storageText == "2024-05-01 14:30:00")
        #expect(restored.projectFinancialRecords[0].dueDate.storageText == "未确定")
        #expect(restored.materialItems[0].quantity.isEmpty)
        #expect(restored.materialItems[0].unitPrice.optionalDecimal == nil)
        #expect(restored.materialItems[0].unitPrice.wireText == "非法原值")
        #expect(restored.projects[0].paidAmount.isEmpty)
        #expect(restored.materialItems[0].arrivalDate.isEmpty)
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        let project = try #require((object["projects"] as? [[String: Any]])?.first)
        #expect(project["contractAmount"] as? String == "9007199254740993.01")
        #expect(project["startDate"] as? String == "2024/5/1")
    }

    @Test func formDateBindingsDoNotReplaceUnknownDatesUntilEdited() throws {
        let state = OSAllocatedUnfairLock(initialState: BusinessDateValue(legacyText: "待业主确认"))
        let binding = Binding(get: { state.withLock { $0 } }, set: { newValue in state.withLock { $0 = newValue } })
        _ = binding.daySelection.wrappedValue
        _ = binding.instantSelection.wrappedValue
        #expect(state.withLock { $0.storageText } == "待业主确认")
        let day = try #require(CalendarDay("2026-10-24"))
        binding.daySelection.wrappedValue = try #require(day.date(in: .current))
        #expect(state.withLock { $0 } == .day(day))
        let instant = Date(timeIntervalSince1970: 100)
        binding.instantSelection.wrappedValue = instant
        #expect(state.withLock { $0 } == .instant(instant))
    }

    @Test func numericValidationRejectsGarbageAndArithmeticNeverRoundsSilently() throws {
        #expect(!NumericInputSupport.validate("12oops", kind: .amount, requirement: .requiredNonNegative).isValid)
        let missing = MoneyValue.empty
        #expect(!missing.isZero)
        #expect(missing != .zero)
        #expect(missing < .zero)
        let invalid = NumericInputSupport.money("invalid")
        #expect((invalid + 1).optionalDecimal == nil)
        let quote = QuoteItem(name: "非法折扣", unitPrice: 1, quantity: 1, unit: "项", notes: "",
                              taxRate: 0, discountRate: NumericInputSupport.quantity("invalid"))
        #expect(ReportBuilder.quoteGrandTotal(quote).optionalDecimal == nil)
        let labor = LaborRecord(date: .empty, workers: 1, hours: 1, unitRate: invalid, note: "")
        #expect(ReportBuilder.laborLineTotal(labor).optionalDecimal == nil)
        var project = Project(name: "非法金额", location: "")
        project.contractAmount = invalid
        #expect(ProjectFinancialMetrics.unpaidAmount(project: project, records: []).optionalDecimal == nil)
        let large = MoneyValue(try #require(Decimal(string: String(repeating: "9", count: 38))))
        #expect((large * Decimal(string: "1.1")!).optionalDecimal == nil)
        #expect((MoneyValue(Decimal(string: "0.1")!) + MoneyValue(Decimal(string: "0.2")!)).decimal == Decimal(string: "0.3"))
    }

    @Test(arguments: [-100, -1, 0, 1, 100])
    func exactArithmeticHandlesSignedFractionsAndZeros(_ left: Int) throws {
        for right in [-100, -1, 0, 1, 100] {
            let lhs = Decimal(left) / 100, rhs = Decimal(right) / 100
            #expect(DecimalMath.add(lhs, rhs) == lhs + rhs)
            #expect(DecimalMath.subtract(lhs, rhs) == lhs - rhs)
            #expect(DecimalMath.multiply(lhs, rhs) == lhs * rhs)
        }
        #expect(DecimalMath.divide(1, by: 3).isNaN)
        #expect(DecimalMath.divide(12, by: 100) == Decimal(string: "0.12"))
        #expect(DecimalMath.add(Decimal(string: "1e100")!, Decimal(string: "0.01")!).isNaN)
    }

    @Test func legacyDraftDateNumberIsReadOnlyAtDraftBoundary() throws {
        struct DraftDate: Codable { @LegacyDraftDate var date: BusinessDateValue }
        let old = try JSONDecoder().decode(DraftDate.self, from: Data(#"{"date":100}"#.utf8))
        #expect(old.date.date() == Date(timeIntervalSinceReferenceDate: 100))
        let restored = try JSONDecoder().decode(DraftDate.self, from: JSONEncoder().encode(old))
        #expect(restored.date == old.date)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(BusinessDateValue.self, from: Data("100".utf8))
        }
    }

    @Test func databaseDateUpgradeChangesOnlyIndexAndOrdersOffsetsCorrectly() async throws {
        var snapshot = RepositoryTestFixture.sample()
        let pid = snapshot.projects[0].id
        snapshot.dailyLogs = ["2026/10/23", "2026-10-24T01:00:00+08:00", "2026-10-23T18:00:00Z"].map {
            DailyLog(date: BusinessDateValue(legacyText: $0), weather: "", content: $0, workers: .empty, projectId: pid)
        }
        let fixture = try RepositoryTestFixture(snapshot: snapshot)
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let pool = try SQLiteRepositorySchema.makePool(at: candidate.directory.appendingPathComponent("candidate.sqlite"), create: false)
        defer { try? pool.close() }
        let before = try await pool.read { db in
            try Row.fetchAll(db, sql: "SELECT id, payload, position FROM dailyLogs ORDER BY id").map { row in
                IndexedPayload(id: row["id"], payload: row["payload"], position: row["position"])
            }
        }
        let revision = try await pool.read { try Int.fetchOne($0, sql: "SELECT revision FROM repository_state") }
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'candidate-v7-domain-dates'")
            try db.execute(sql: "UPDATE dailyLogs SET sort_key = 'old-index'")
        }
        try SQLiteRepositorySchema.create(in: pool)
        let after = try await pool.read { db in
            try Row.fetchAll(db, sql: "SELECT id, payload, position FROM dailyLogs ORDER BY id").map { row in
                IndexedPayload(id: row["id"], payload: row["payload"], position: row["position"])
            }
        }
        #expect(before == after)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(try await pool.read { try Int.fetchOne($0, sql: "SELECT revision FROM repository_state") } == revision)
        let ids = try await pool.read { try String.fetchAll($0, sql: "SELECT id FROM dailyLogs ORDER BY sort_key, id") }
        #expect(ids == snapshot.dailyLogs.map { $0.id.uuidString })
        // A failed upgrade must roll back earlier index writes as one transaction.
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier = 'candidate-v7-domain-dates'")
            try db.execute(sql: "UPDATE dailyLogs SET sort_key = 'before-failure'")
            try db.execute(sql: "UPDATE quickNotes SET payload = ?", arguments: [Data("{invalid".utf8)])
        }
        #expect(throws: (any Error).self) { try SQLiteRepositorySchema.create(in: pool) }
        #expect(try await pool.read { try String.fetchAll($0, sql: "SELECT DISTINCT sort_key FROM dailyLogs") } == ["before-failure"])
    }
}
