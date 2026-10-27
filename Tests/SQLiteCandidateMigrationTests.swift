import Foundation
import GRDB
import Testing
@testable import sitekeeper

struct SQLiteCandidateMigrationTests {
    private enum Injected: Error { case interruption }

    @Test(arguments: [2, 3])
    func migratesAllCollectionsWithoutChangingSource(version: Int) async throws {
        let fixture = try RepositoryTestFixture(version: version)
        defer { fixture.cleanup() }
        let decoded = try JSONDecoder().decode(BackupSnapshot.self, from: fixture.raw)
        let audit = DateProvenanceAuditFile(entries: decoded.legacyDateProvenance.map { .init(provenance: $0, missingSince: Date(timeIntervalSince1970: 1)) })
        let auditData = try JSONEncoder().encode(audit)
        let auditURL = DateProvenanceAuditFile.fileURL(forStore: fixture.source)
        try auditData.write(to: auditURL)
        let result = try await fixture.candidate()
        #expect(result.manifest.phase == .ready)
        #expect(result.manifest.sourceSHA256 == CandidateFiles.hash(fixture.raw))
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(try Data(contentsOf: auditURL) == auditData)
        #expect(try Data(contentsOf: result.directory.appendingPathComponent("date-audit.json")) == auditData)
        let repository = try SQLiteBusinessRepository(candidateDirectory: result.directory)
        let actual = try await repository.exportSnapshot()
        #expect(try RepositoryDataset(snapshot: actual) == RepositoryDataset(snapshot: decoded))
        for collection in RepositoryCollection.allCases {
            #expect((result.manifest.recordCounts[collection.rawValue] ?? 0) > 0)
        }
        let assets = try JSONDecoder().decode([SQLiteCandidateAsset].self, from: Data(contentsOf: result.directory.appendingPathComponent("assets.json")))
        #expect(assets.count == 5)
        let pool = try SQLiteRepositorySchema.makePool(at: result.directory.appendingPathComponent("candidate.sqlite"), create: false)
        defer { try? pool.close() }
        try await pool.read { (db: Database) throws -> Void in
            #expect(try String.fetchOne(db, sql: "PRAGMA journal_mode") == "wal")
            #expect(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM record_links WHERE field = 'relatedProjectIds'") == 1)
            let original = fixture.snapshot.projectFinancialRecords[0]
            let stored = try String.fetchOne(db, sql: "SELECT amount FROM projectFinancialRecords WHERE id = ?", arguments: [original.id.uuidString])
            #expect(stored == original.amount.wireText)
        }
        try await repository.close()
    }

    static let interruptionPoints: [SQLiteCandidateFaultPoint] = [
        .beforePreservation, .preserved, .schemaCreated, .beforeCommit, .importCommitted, .verified, .beforeReady
    ] + RepositoryCollection.allCases.map { .imported($0) }

    @Test(arguments: interruptionPoints)
    func interruptedMigrationIsNotPublishedAndRetryIsIndependent(point: SQLiteCandidateFaultPoint) async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let options = SQLiteCandidateOptions(fault: { if $0 == point { throw Injected.interruption } })
        await #expect(throws: Injected.self) { try await fixture.candidate(options: options) }
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        let failed = try candidateDirectories(fixture)[0]
        let manifest = try JSONDecoder().decode(SQLiteCandidateManifest.self, from: Data(contentsOf: failed.appendingPathComponent("candidate.json")))
        #expect(manifest.phase == .failed)
        #expect(throws: RepositoryError.invalidCandidate) { try SQLiteBusinessRepository(candidateDirectory: failed) }
        if case .imported = point { try assertRolledBackRows(failed) }
        if point == .beforeCommit { try assertRolledBackRows(failed) }
        // A new coordinator models restart: never reuses ambiguous/interrupted artifacts.
        let retried = try await SQLiteCandidateBuilder().build(sourceURL: fixture.source, assetDirectories: fixture.assets)
        #expect(retried.directory != failed)
        #expect(retried.manifest.phase == .ready)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    @Test func rollbackPristineCandidateBlocksExistingHandlesAndKeepsOriginal() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let repository = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        try await SQLiteCandidateBuilder().rollback(candidateDirectory: candidate.directory)
        await #expect(throws: RepositoryError.invalidCandidate) { try await repository.revision() }
        #expect(throws: RepositoryError.invalidCandidate) { try SQLiteBusinessRepository(candidateDirectory: candidate.directory) }
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        #expect(try Data(contentsOf: candidate.directory.appendingPathComponent("source.json")) == fixture.raw)
        try await repository.close()
        // Repeated rollback remains harmless; it does not delete or rewrite source data.
        try await SQLiteCandidateBuilder().rollback(candidateDirectory: candidate.directory)
    }

    @Test func rollbackRefusesCandidateWithNewWrites() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let candidate = try await fixture.candidate()
        let repository = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        _ = try await repository.apply([.setTodoCompletion(fixture.snapshot.siteTodos[0].id, true, at: BusinessDateValue(legacyText: "2026-10-24"))], expectedRevision: 0)
        await #expect(throws: RepositoryError.candidateHasNewWrites) { try await SQLiteCandidateBuilder().rollback(candidateDirectory: candidate.directory) }
        #expect(try await repository.revision() == 1)
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        try await repository.close()
        let reopened = try SQLiteBusinessRepository(candidateDirectory: candidate.directory)
        #expect(try await reopened.exportSnapshot().siteTodos[0].isDone == true)
        try await reopened.close()
    }

    @Test func diskFullPreflightAndSQLiteFullPreserveOriginal() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        await #expect(throws: CocoaError.self) { try await fixture.candidate(options: SQLiteCandidateOptions(availableBytes: { _ in 0 })) }
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        var large = fixture.snapshot
        large.dailyLogs[0].content = String(repeating: "large-body", count: 100_000)
        let fullFixture = try RepositoryTestFixture(snapshot: large)
        defer { fullFixture.cleanup() }
        do {
            _ = try await fullFixture.candidate(options: SQLiteCandidateOptions(maximumPageCount: 1))
            Issue.record("SQLite must report SQLITE_FULL")
        } catch let error as DatabaseError {
            #expect(error.resultCode == .SQLITE_FULL)
        }
        #expect(try Data(contentsOf: fullFixture.source) == fullFixture.raw)
        try assertRolledBackRows(try candidateDirectories(fullFixture)[0])
    }

    @Test func sourceOrAssetChangedBeforeReadyIsRejected() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let newBytes = fixture.raw + Data(" ".utf8)
        let source = fixture.source
        await #expect(throws: RepositoryError.sourceChanged) {
            try await fixture.candidate(options: SQLiteCandidateOptions(fault: { point in
                if point == .beforeReady { try newBytes.write(to: source) }
            }))
        }
        #expect(try Data(contentsOf: source) == newBytes)
        let asset = try #require(fixture.assets[.photos]).appendingPathComponent("shared.jpg")
        await #expect(throws: RepositoryError.sourceChanged) {
            try await fixture.candidate(options: SQLiteCandidateOptions(fault: { point in
                if point == .beforeReady { try Data("changed".utf8).write(to: asset) }
            }))
        }
        #expect(try Data(contentsOf: source) == newBytes)
    }

    @Test func corruptDuplicateMissingIDAndDanglingReferencesFailClosed() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let root = try RepositoryJSON.object(fixture.raw)
        let logs = try #require(root["dailyLogs"] as? [[String: Any]])
        var duplicate = root
        duplicate["dailyLogs"] = logs + [logs[0]]
        var missingID = root
        var noID = logs[0]
        noID.removeValue(forKey: "id")
        missingID["dailyLogs"] = [noID]
        var dangling = root
        var orphan = logs[0]
        orphan["projectId"] = UUID().uuidString
        dangling["dailyLogs"] = [orphan]
        var wrongSchema = root
        wrongSchema["schemaVersion"] = 999
        let cases = try [duplicate, missingID, dangling, wrongSchema].map { try JSONSerialization.data(withJSONObject: $0) } + [Data("broken".utf8)]
        for bytes in cases {
            try bytes.write(to: fixture.source)
            await #expect(throws: (any Error).self) { try await fixture.candidate() }
            #expect(try Data(contentsOf: fixture.source) == bytes)
        }
    }

    @Test func pendingRestoreAndCorruptAuditAreLeftUntouched() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let root = BackupArchiveRestoreJournal.transactionsRoot(for: fixture.source)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let marker = root.appendingPathComponent("in-progress")
        try Data("journal evidence".utf8).write(to: marker)
        await #expect(throws: RepositoryError.pendingRestore) { try await fixture.candidate() }
        #expect(try String(contentsOf: marker, encoding: .utf8) == "journal evidence")
        try FileManager.default.removeItem(at: marker)
        let audit = DateProvenanceAuditFile.fileURL(forStore: fixture.source)
        try Data("broken audit".utf8).write(to: audit)
        await #expect(throws: (any Error).self) { try await fixture.candidate() }
        #expect(try String(contentsOf: audit, encoding: .utf8) == "broken audit")
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }

    private func candidateDirectories(_ fixture: RepositoryTestFixture) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: fixture.directory.appendingPathComponent(".sqlite-candidates"), includingPropertiesForKeys: nil)
    }

    private func assertRolledBackRows(_ directory: URL) throws {
        let pool = try SQLiteRepositorySchema.makePool(at: directory.appendingPathComponent("candidate.sqlite"), create: false)
        defer { try? pool.close() }
        try pool.read { (db: Database) throws -> Void in
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM record_keys") == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT count(*) FROM snapshot_fields") == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT revision FROM repository_state") == 0)
        }
    }
}

extension SQLiteCandidateMigrationTests {
    @Test func cancellationBeforePublicationDoesNotMakeCandidateReady() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        let task = Task {
            try await fixture.candidate(options: SQLiteCandidateOptions(fault: { point in
                if point == .beforeReady { withUnsafeCurrentTask { $0?.cancel() } }
            }))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
        let candidates = try FileManager.default.contentsOfDirectory(at: fixture.directory.appendingPathComponent(".sqlite-candidates"), includingPropertiesForKeys: nil)
        let candidate = try #require(candidates.first)
        #expect(throws: RepositoryError.invalidCandidate) { try SQLiteBusinessRepository(candidateDirectory: candidate) }
    }

    @Test func missingAssetRootAndSymlinkAreRejected() async throws {
        let fixture = try RepositoryTestFixture()
        defer { fixture.cleanup() }
        await #expect(throws: RepositoryError.self) { try await SQLiteCandidateBuilder().build(sourceURL: fixture.source) }
        let sourceLink = fixture.directory.appendingPathComponent("linked.json")
        try FileManager.default.createSymbolicLink(at: sourceLink, withDestinationURL: fixture.source)
        await #expect(throws: RepositoryError.self) { try await SQLiteCandidateBuilder().build(sourceURL: sourceLink) }
        #expect(try Data(contentsOf: fixture.source) == fixture.raw)
    }
}
