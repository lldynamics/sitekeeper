import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct DateProvenanceAuditTests {
    private let noteID = UUID()
    private let projectID = UUID()
    private let day: TimeInterval = 24 * 60 * 60
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func legacySnapshot(schemaVersion: Int = 2, includeNote: Bool = true) -> BackupSnapshot {
        let note = QuickNote(id: noteID, title: "v2", createdAt: BusinessDateValue(legacyText: "2026-10-12 17:30"), updatedAt: BusinessDateValue(legacyText: "2026-10-12 17:30"))
        return BackupSnapshot(
            schemaVersion: schemaVersion,
            backupCreatedAt: "2026-10-12 18:30",
            materialItems: [], quoteItems: [], laborRecords: [],
            projects: [Project(id: projectID, name: "Legacy", location: "", status: .active, startDate: BusinessDateValue(legacyText: "2026-10-12"))],
            dailyLogs: [], historyRecords: [],
            quickNotes: includeNote ? [note] : [],
            templates: []
        )
    }

    private func audit(in storeURL: URL) throws -> [DateProvenanceAuditFile.Entry] {
        try JSONDecoder().decode(
            DateProvenanceAuditFile.self,
            from: Data(contentsOf: DateProvenanceAuditFile.fileURL(forStore: storeURL))
        ).entries
    }

    private func entry(_ path: String, missingSince: Date? = nil) -> DateProvenanceAuditFile.Entry {
        DateProvenanceAuditFile.Entry(
            provenance: LegacyDateProvenance(path: path, originalText: "2026-10-12", interpretation: "legacy-UTC", sourceSchemaVersion: 2),
            missingSince: missingSince
        )
    }

    @Test func entriesForAbsentRecordsAgeOutAfterThirtyDaysAndReviveWhenRestored() {
        let live = UUID()
        let gone = UUID()
        let returned = UUID()
        let now = start.addingTimeInterval(40 * day)
        let file = [
            entry("quickNotes/\(live)/createdAt"),
            entry("quickNotes/\(gone)/createdAt"),
            entry("quickNotes/\(gone)/updatedAt", missingSince: now.addingTimeInterval(-29 * day)),
            entry("projects/\(gone)/startDate", missingSince: now.addingTimeInterval(-30 * day)),
            entry("quickNotes/\(returned)/createdAt", missingSince: now.addingTimeInterval(-10 * day)),
            entry("snapshot/backupCreatedAt", missingSince: now.addingTimeInterval(-90 * day))
        ]
        let reconciled = DateProvenanceAuditFile.reconciled(
            file: file,
            inline: [file[0].provenance, entry("unknownCollection/\(gone)/date").provenance],
            liveRecordIDs: ["quickNotes": [live, returned], "projects": []],
            now: now
        )
        let byPath = Dictionary(uniqueKeysWithValues: reconciled.map { ($0.provenance.path, $0.missingSince) })
        #expect(reconciled.count == 6)
        #expect(byPath["quickNotes/\(live)/createdAt"] == .some(nil))
        #expect(byPath["quickNotes/\(gone)/createdAt"] == .some(now))
        #expect(byPath["quickNotes/\(gone)/updatedAt"] == .some(now.addingTimeInterval(-29 * day)))
        #expect(byPath["projects/\(gone)/startDate"] == nil)
        #expect(byPath["quickNotes/\(returned)/createdAt"] == .some(nil))
        #expect(byPath["snapshot/backupCreatedAt"] == .some(nil))
        #expect(byPath["unknownCollection/\(gone)/date"] == .some(nil))
    }

    @Test func deletedRecordKeepsItsAuditThroughTheRetentionWindowAcrossLaunches() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        try JSONEncoder().encode(legacySnapshot()).write(to: url)

        let first = DataStorePersistenceActor(storeURL: url, now: { [start] in start })
        let loaded = try #require(try await first.loadSnapshot())
        #expect(loaded.legacyDateProvenance.contains { $0.recordOwner?.id == noteID })
        var deleted = loaded
        deleted.quickNotes = []
        _ = try await first.persist(snapshot: deleted)
        #expect(try audit(in: url).allSatisfy { $0.missingSince == nil })

        let nextDay = start.addingTimeInterval(day)
        let second = DataStorePersistenceActor(storeURL: url, now: { nextDay })
        let reloaded = try #require(try await second.loadSnapshot())
        #expect(reloaded.legacyDateProvenance.contains { $0.recordOwner?.id == noteID })
        _ = try await second.persist(snapshot: reloaded)
        #expect(try audit(in: url).filter { $0.provenance.recordOwner?.id == noteID }.allSatisfy { $0.missingSince == nextDay })

        let expired = nextDay.addingTimeInterval(DateProvenanceAuditFile.missingRecordRetention)
        let third = DataStorePersistenceActor(storeURL: url, now: { expired })
        let afterRetention = try #require(try await third.loadSnapshot())
        #expect(!afterRetention.legacyDateProvenance.contains { $0.recordOwner?.id == noteID })
        #expect(afterRetention.legacyDateProvenance.contains { $0.recordOwner?.id == projectID })
        _ = try await third.persist(snapshot: afterRetention)
        #expect(try !audit(in: url).contains { $0.provenance.recordOwner?.id == noteID })
    }

    @Test func missingAuditIsRecreatedBeforeTheInlineCopyIsDropped() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        try JSONEncoder().encode(legacySnapshot()).write(to: url)
        let actor = DataStorePersistenceActor(storeURL: url)
        let loaded = try #require(try await actor.loadSnapshot())
        _ = try await actor.persist(snapshot: loaded)

        let auditURL = DateProvenanceAuditFile.fileURL(forStore: url)
        try FileManager.default.removeItem(at: auditURL)
        var changed = loaded
        changed.backupCreatedAt = "2026-10-22 00:00:00Z"
        #expect(try await actor.persist(snapshot: changed))
        #expect(try audit(in: url).map(\.provenance) == loaded.legacyDateProvenance)
    }

    @Test func externallyReplacedAuditIsPreservedAndProvenanceStaysInline() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        try JSONEncoder().encode(legacySnapshot()).write(to: url)
        let actor = DataStorePersistenceActor(storeURL: url)
        let loaded = try #require(try await actor.loadSnapshot())
        _ = try await actor.persist(snapshot: loaded)
        let replacement = Data("unreadable external audit".utf8)
        let auditURL = DateProvenanceAuditFile.fileURL(forStore: url)
        try replacement.write(to: auditURL, options: .atomic)

        _ = try await actor.persist(snapshot: loaded)

        #expect(try Data(contentsOf: auditURL) == replacement)
        let saved = try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: url))
        #expect(saved.legacyDateProvenance == loaded.legacyDateProvenance)
    }

    @Test func storeWrittenByEarlierV3BuildMovesItsEmbeddedAuditOut() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        let migrated = try BackupArchiveService.decodeJSONSnapshot(from: JSONEncoder().encode(legacySnapshot()))
        #expect(!migrated.legacyDateProvenance.isEmpty)
        try BackupArchiveRestoreJournal.encodeMetadata(migrated).write(to: url)

        let actor = DataStorePersistenceActor(storeURL: url)
        let loaded = try #require(try await actor.loadSnapshot())
        #expect(loaded.legacyDateProvenance == migrated.legacyDateProvenance)
        _ = try await actor.persist(snapshot: loaded)
        let stored = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        #expect(stored?["legacyDateProvenance"] == nil)
        #expect(try audit(in: url).map(\.provenance) == migrated.legacyDateProvenance)
    }

    @Test func auditWriteFailureKeepsTheAuditInsideTheStoreUntilALaterSaveSucceeds() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        try JSONEncoder().encode(legacySnapshot()).write(to: url)
        let failing = DataStorePersistenceActor(storeURL: url, writeDateProvenance: { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        })
        let loaded = try #require(try await failing.loadSnapshot())
        #expect(try await failing.persist(snapshot: loaded))
        let inline = try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: url))
        #expect(inline.legacyDateProvenance == loaded.legacyDateProvenance)
        #expect(!FileManager.default.fileExists(atPath: DateProvenanceAuditFile.fileURL(forStore: url).path))

        let healthy = DataStorePersistenceActor(storeURL: url)
        let reloaded = try #require(try await healthy.loadSnapshot())
        #expect(reloaded.legacyDateProvenance == loaded.legacyDateProvenance)
        _ = try await healthy.persist(snapshot: reloaded)
        #expect(try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: url)).legacyDateProvenance.isEmpty)
        #expect(try audit(in: url).map(\.provenance) == loaded.legacyDateProvenance)
    }

    @Test func restoreAddsToTheAuditUntilTheNextOrdinarySaveReplacesIt() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        try JSONEncoder().encode(legacySnapshot()).write(to: url)
        let actor = DataStorePersistenceActor(storeURL: url)
        let previous = try #require(try await actor.loadSnapshot())
        _ = try await actor.persist(snapshot: previous)

        let restoredEntry = entry("quickNotes/\(UUID())/createdAt").provenance
        var restored = previous
        restored.legacyDateProvenance = [restoredEntry]
        let prepared = try BackupArchiveRestoreJournal.encodeMetadata(restored)
        _ = try await actor.persistPreparedBackup(data: prepared, dateProvenance: restored.legacyDateProvenance)
        #expect(try audit(in: url).map(\.provenance) == previous.legacyDateProvenance + [restoredEntry])

        _ = try await actor.persist(snapshot: restored)
        #expect(try audit(in: url).map(\.provenance) == [restoredEntry])
    }

    @Test func unreadableAuditIsSetAsideInsteadOfOverwritten() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        try JSONEncoder().encode(legacySnapshot()).write(to: url)
        let garbage = Data("not json".utf8)
        try garbage.write(to: DateProvenanceAuditFile.fileURL(forStore: url))

        let actor = DataStorePersistenceActor(storeURL: url)
        let loaded = try #require(try await actor.loadSnapshot())
        _ = try await actor.persist(snapshot: loaded)
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("sitekeeper_date_provenance_unreadable_") }
        #expect(preserved.count == 1)
        #expect(try Data(contentsOf: #require(preserved.first)) == garbage)
        #expect(try audit(in: url).map(\.provenance) == loaded.legacyDateProvenance)
    }
}
