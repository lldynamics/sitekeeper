import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct LegacyDateMigrationTests {
    private func legacyData() throws -> Data {
        let note = QuickNote(title: "v2", content: "unchanged", createdAt: "2026-10-12 17:30", updatedAt: "2026-10-12 17:30")
        let snapshot = BackupSnapshot(schemaVersion: 2, backupCreatedAt: "2026-10-12 18:30",
                                      materialItems: [], quoteItems: [], laborRecords: [],
                                      projects: [Project(name: "Legacy", location: "", status: .active,
                                                         startDate: "2026-10-12", expectedEndDate: "待确认")],
                                      dailyLogs: [], historyRecords: [], quickNotes: [note], templates: [])
        return try JSONEncoder().encode(snapshot)
    }

    @Test func v2DecodePreservesTextAndRecordsItsMeaningWithoutRepeatedMigration() throws {
        let original = try legacyData()
        let migrated = try BackupArchiveService.decodeJSONSnapshot(from: original)
        #expect(migrated.schemaVersion == 3)
        #expect(migrated.quickNotes[0].createdAt == "2026-10-12 17:30")
        #expect(migrated.projects[0].startDate == "2026-10-12")
        #expect(migrated.projects[0].expectedEndDate == "待确认")
        let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
        #expect(Formatters.displayDateText(migrated.quickNotes[0].createdAt, timeZone: shanghai) == "2026-10-13 01:30")
        #expect(Formatters.displayDateText("2026-10-12", timeZone: shanghai) == "2026-10-12")
        #expect(migrated.legacyDateProvenance.contains { $0.originalText == "2026-10-12 17:30" && $0.interpretation == "legacy-UTC" })
        #expect(migrated.legacyDateProvenance.contains { $0.originalText == "2026-10-12" && $0.interpretation == "calendar-day-preserved-origin-unverified" })
        let again = try JSONDecoder().decode(BackupSnapshot.self, from: JSONEncoder().encode(migrated))
        #expect(again.legacyDateProvenance == migrated.legacyDateProvenance)
        #expect(again.quickNotes[0].createdAt == migrated.quickNotes[0].createdAt)
    }

    @Test(arguments: ["Asia/Shanghai", "America/Los_Angeles", "UTC"])
    func legacyAndNewTimestampsKeepTheSameInstantAcrossZones(_ zoneID: String) throws {
        let zone = try #require(TimeZone(identifier: zoneID))
        let expected = try #require(ISO8601DateFormatter().date(from: "2026-10-12T17:30:00Z"))
        #expect(Formatters.parseDateOrDateTime("2026-10-12 17:30", timeZone: zone) == expected)
        #expect(Formatters.parseDateOrDateTime(Formatters.timestamp(expected), timeZone: zone) == expected)
        #expect(Formatters.parseDateOrDateTime("2026-10-13T01:30:00+08:00", timeZone: zone) == expected)
        #expect(Formatters.isLater("2026-10-12 18:00", than: "2026-10-13T01:30:00+08:00"))
        let later = expected.addingTimeInterval(60)
        #expect(Formatters.timestamp(later) > "2026-10-12 17:30")
        #expect(Formatters.parseDateOrDateTime(Formatters.timestamp(later), timeZone: zone)! > expected)
    }

    @Test func localLoadDoesNotWriteAndFirstSavePreservesExactV2Bytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        let original = try legacyData()
        try original.write(to: url)
        let actor = DataStorePersistenceActor(storeURL: url)
        let loaded = try #require(try await actor.loadSnapshot())
        #expect(try Data(contentsOf: url) == original)
        _ = try await actor.persist(snapshot: loaded)
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("sitekeeper_before_schema3_") }
        #expect(preserved.count == 1)
        #expect(try Data(contentsOf: #require(preserved.first)) == original)
        let persisted = try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: url))
        #expect(persisted.schemaVersion == 3)
        #expect(persisted.legacyDateProvenance == loaded.legacyDateProvenance)
        _ = try await actor.persist(snapshot: loaded)
        #expect(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count == 2)
    }

    @Test func migrationBackupFailureLeavesOriginalStoreUntouched() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sitekeeper.json")
        let original = try legacyData()
        try original.write(to: url)
        let actor = DataStorePersistenceActor(storeURL: url, writeMigrationBackup: { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        let loaded = try #require(try await actor.loadSnapshot())
        do {
            _ = try await actor.persist(snapshot: loaded)
            Issue.record("Saving must fail if the pre-migration backup cannot be written")
        } catch {
            #expect((error as? CocoaError)?.code == .fileWriteNoPermission)
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test func provenanceSurvivesLoadMergeOverwriteAndExport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        let migrated = try BackupArchiveService.decodeJSONSnapshot(from: legacyData())
        store.applyLoadedSnapshot(migrated)
        BackupImportCoordinator.applyImportMetadata(snapshot: migrated, mode: .merge, store: store)
        #expect(store.legacyDateProvenance == migrated.legacyDateProvenance)
        let exported = store.makeSnapshot(includePhotoFiles: false)
        #expect(exported.legacyDateProvenance == migrated.legacyDateProvenance)
        BackupImportCoordinator.applyImportMetadata(snapshot: migrated, mode: .overwrite, store: store)
        #expect(store.quickNotes[0].createdAt == "2026-10-12 17:30")
        #expect(store.legacyDateProvenance == migrated.legacyDateProvenance)
    }

    @Test func missingLegacyFieldsDoNotFabricateProvenance() throws {
        let json = """
        {"schemaVersion":2,"quickNotes":[{"id":"\(UUID().uuidString)","content":"Original"}]}
        """
        let snapshot = try BackupArchiveService.decodeJSONSnapshot(from: Data(json.utf8))
        #expect(snapshot.legacyDateProvenance.isEmpty)
        #expect(snapshot.quickNotes[0].content == "Original")
    }

    @Test func v2ManifestRemainsReadableAndUnknownSchemasAreRejected() throws {
        let manifest = BackupArchiveManifest(schemaVersion: 2, metadataPath: BackupArchiveService.metadataPath)
        #expect(try BackupArchiveService.decodeManifest(from: JSONEncoder().encode(manifest)).schemaVersion == 2)
        for version in [1, 4, 999] {
            let data = Data("{\"schemaVersion\":\(version)}".utf8)
            #expect(throws: (any Error).self) { try BackupArchiveService.decodeJSONSnapshot(from: data) }
        }
    }
}
