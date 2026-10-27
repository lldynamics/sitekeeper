import Foundation
import Testing
@testable import sitekeeper

@Suite(.serialized)
struct LargeDataOptimizationTests {
    @Test func cacheMemoryBudgetEvictsLargeFragmentsWithoutLosingData() throws {
        let value = snapshot(count: 100)
        var encoder = SnapshotSectionEncoder(maximumCachedBytes: 1024)
        let canonical = try BackupArchiveRestoreJournal.encodeMetadata(value)
        #expect(try encoder.encode(value, versions: [:]) == canonical)
        #expect(encoder.cachedByteCount <= 1024)
        #expect(try encoder.encode(value, versions: [:]) == canonical)
        #expect(encoder.encodedCollections.contains("projectFinancialRecords"))
        #expect(encoder.cachedByteCount <= 1024)
    }

    @Test func backupMetadataRoundTripPreservesPlansOriginsAndAllocations() throws {
        var value = snapshot()
        let projectID = value.projects[0].id
        let plan = ProjectPaymentPlan(title: "Supplier", direction: .expense, counterparty: "A", installments: [
            ProjectPaymentInstallment(title: "Retention", dueDate: .today(), amount: 100, isRetention: true)
        ])
        value.projects[0].paymentPlans = [plan]
        let material = MaterialItem(name: "Cable", quantity: 10, unit: "m", projectId: projectID)
        value.materialItems = [material]
        let movement = ProjectWarehouseMovement(projectId: projectID, materialName: "Cable", unit: "m", quantity: 4,
            origin: BusinessRecordOrigin(materialItemID: material.id, warehouseMovementID: nil, unitPrice: 2))
        value.projectWarehouseMovements = [movement]
        let record = ProjectFinancialRecord(projectId: projectID, amount: 8,
            origin: BusinessRecordOrigin(materialItemID: material.id, warehouseMovementID: movement.id, unitPrice: 2),
            paymentAllocation: ProjectPaymentAllocation(planID: plan.id, installmentID: plan.installments[0].id))
        value.projectFinancialRecords = [record]
        let restored = try JSONDecoder().decode(BackupSnapshot.self, from: BackupArchiveRestoreJournal.encodeMetadata(value))
        #expect(restored.projects[0].paymentPlans == [plan])
        #expect(restored.projectWarehouseMovements[0].origin == movement.origin)
        #expect(restored.projectFinancialRecords[0].origin == record.origin)
        #expect(restored.projectFinancialRecords[0].paymentAllocation == record.paymentAllocation)
        #expect(restored.materialItems[0].quantity == 10)
    }
    private func snapshot(count: Int = 0) -> BackupSnapshot {
        let project = Project(name: "Large project", location: "")
        let records = (0 ..< count).map { index in
            ProjectFinancialRecord(projectId: project.id, date: .today(), direction: .expense, category: .material,
                amount: NumericInputSupport.money("1.25"), counterparty: "Supplier \(index % 25)", note: "Record \(index)")
        }
        return BackupSnapshot(materialItems: [], quoteItems: [], laborRecords: [], projects: [project], dailyLogs: [],
            historyRecords: [], progressTasks: [], siteTodos: [], projectDrawings: [], projectContacts: [],
            projectFinancialRecords: records, projectDocuments: [], quickNotes: [], templates: [])
    }

    @Test func pageBoundsDeletionAndFilterShrinkRemainCorrect() {
        let records = Array(0 ..< 101)
        #expect(RecordPage(records, index: -1).items == Array(0 ..< 50))
        #expect(RecordPage(records, index: 1).items == Array(50 ..< 100))
        #expect(RecordPage(records, index: 99).items == [100])
        #expect(RecordPage([42], index: 99).items == [42])
        #expect(RecordPage([Int](), index: 99).count == 1)
        #expect(RecordPage(records, index: 1, size: 0).items == [1])
        // Offsets belong to the displayed page, including deletion on the final page.
        #expect(RecordPage(records, index: 1).items[0] == 50)
    }

    @Test func sectionCacheMatchesCanonicalJSONAndReencodesOnlyChangedCollections() throws {
        var value = snapshot(count: 10)
        var encoder = SnapshotSectionEncoder()
        let first = try encoder.encode(value, versions: [:])
        #expect(first == (try BackupArchiveRestoreJournal.encodeMetadata(value)))
        #expect(encoder.encodedCollections.contains("projectFinancialRecords"))
        value.projects[0].name = "Changed"
        let second = try encoder.encode(value, versions: ["projects": 1])
        #expect(second == (try BackupArchiveRestoreJournal.encodeMetadata(value)))
        #expect(encoder.encodedCollections == ["projects"])
        _ = try encoder.encode(value, versions: ["projects": 1])
        #expect(encoder.encodedCollections.isEmpty)
        value.projectFinancialRecords[0].amount = 5
        let third = try encoder.encode(value, versions: ["projects": 1, "projectFinancialRecords": 1])
        #expect(third == (try BackupArchiveRestoreJournal.encodeMetadata(value)))
        #expect(encoder.encodedCollections == ["projectFinancialRecords"])
    }

    @MainActor @Test func everyDomainMutationAndBulkLoadAdvanceAuthoritativeGenerations() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("generations-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DataStore(storageDirectory: root)
        await store.awaitInitialLoad()
        store.applyLoadedSnapshot(snapshot())
        let allKeys = Set(store.persistenceVersions.keys)
        #expect(allKeys == ["materialItems", "quoteItems", "laborRecords", "projects", "dailyLogs", "historyRecords",
            "progressTasks", "siteTodos", "projectDrawings", "projectContacts", "projectFinancialRecords", "projectDocuments",
            "quickNotes", "projectWarehouseMovements", "templates", "materialPriceEntries", "materialSheetDrafts", "supplierProfiles",
            "constructionMethods", "favoriteMaterialKeys", "recentMaterialKeys", "userMaterials", "deletedUserMaterials", "hiddenPresetKeys"])
        let versions = store.persistenceVersions
        // Direct child-store writes must invalidate the same cached collection.
        store.financeStore.setMaterialItems([MaterialItem(name: "A", quantity: 1, unit: "m")])
        #expect(store.persistenceVersions["materialItems"] == versions["materialItems", default: 0] + 1)
        #expect(store.persistenceVersions["projects"] == versions["projects"])
        store.cancelScheduledSave()
    }

    @MainActor @Test func snapshotApplicationBuildsActivityIndexOnceAndKeepsQueriesCorrect() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("batch-load-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DataStore(storageDirectory: root)
        await store.awaitInitialLoad()
        let before = store.projectStore.activityIndexBuildCount
        let value = snapshot(count: 1000)
        store.applyLoadedSnapshot(value)
        #expect(store.projectStore.activityIndexBuildCount == before + 1)
        #expect(store.projectStore.projectFinancialRecords(for: value.projects[0].id).count == 1000)
        store.projectStore.withBatchUpdates {
            store.projectStore.withBatchUpdates { store.projectStore.setProjectFinancialRecords([]) }
            store.projectStore.setProjectFinancialRecords(value.projectFinancialRecords)
        }
        #expect(store.projectStore.activityIndexBuildCount == before + 2)
        store.cancelScheduledSave()
    }

    @Test func preparedRestoreInvalidatesCachedFragmentsAndExternalReplacementIsRepaired() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cache-restore-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("sitekeeper.json")
        let actor = DataStorePersistenceActor(storeURL: url)
        let first = snapshot(count: 1)
        _ = try await actor.persist(snapshot: first, versions: [:])
        let restored = snapshot(count: 2)
        _ = try await actor.persistPreparedBackup(data: BackupArchiveRestoreJournal.encodeMetadata(restored))
        _ = try await actor.persist(snapshot: restored, versions: [:])
        #expect(try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: url)).projectFinancialRecords.count == 2)
        try Data("external bytes".utf8).write(to: url, options: .atomic)
        _ = try await actor.persist(snapshot: restored, versions: [:])
        #expect(try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: url)).projectFinancialRecords.count == 2)
        _ = try await actor.loadSnapshot()
        _ = try await actor.persist(snapshot: first, versions: [:])
        #expect(try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: url)).projectFinancialRecords.count == 1)
    }

    @Test func failedAtomicWriteCannotPoisonFutureCache() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("failed-cache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let actor = DataStorePersistenceActor(storeURL: root.appendingPathComponent("sitekeeper.json"))
        let value = snapshot(count: 5)
        await #expect(throws: (any Error).self) { _ = try await actor.persist(snapshot: value, versions: [:]) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = try await actor.persist(snapshot: value, versions: [:])
        #expect(try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: root.appendingPathComponent("sitekeeper.json"))).projectFinancialRecords.count == 5)
    }

    @Test func largeSampleEncodingLoadingAndBoundedPages() throws {
        let clock = ContinuousClock()
        for count in [1000, 10000, 100000] {
            var value = snapshot(count: count)
            var encoder = SnapshotSectionEncoder()
            let initial = try encoder.encode(value, versions: [:])
            value.projects[0].name = "Updated project"
            var canonical = Data()
            let full = try clock.measure { canonical = try BackupArchiveRestoreJournal.encodeMetadata(value) }
            var cached = Data()
            let incremental = try clock.measure { cached = try encoder.encode(value, versions: ["projects": 1]) }
            #expect(cached == canonical)
            #expect(encoder.encodedCollections == ["projects"])
            var loaded: BackupSnapshot?
            let load = try clock.measure { loaded = try JSONDecoder().decode(BackupSnapshot.self, from: cached) }
            let decoded = try #require(loaded)
            #expect(decoded.projectFinancialRecords.count == count)
            #expect(RecordPage(decoded.projectFinancialRecords, index: count / 50 - 1).items.count == 50)
            #expect(initial.count > 0)
            print("LARGE_DATA count=\(count) bytes=\(cached.count) full=\(full) cached=\(incremental) decode=\(load) renderedRows=50 encodedCollections=projects")
        }
    }
}
