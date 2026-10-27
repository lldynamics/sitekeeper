import Foundation
import Testing
import Observation
@testable import sitekeeper

@MainActor
struct DataStoreBoundaryTests {
    @Test func financePreferenceWritesUseDataStoreFacade() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("datastore-boundary-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DataStore(storageDirectory: directory)
        let previous = store.financeStore.materialPriceSpikeThreshold
        defer { store.setMaterialPriceSpikeThreshold(previous) }

        store.setMaterialPriceSpikeThreshold(0.23)

        #expect(abs(store.financeStore.materialPriceSpikeThreshold - 0.23) < 0.0001)
    }
}

@MainActor
struct DomainStorePersistenceTests {
    private func makeStore() async throws -> (DataStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("domain-persistence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        store.invalidateDataHealthScan()
        return (store, directory)
    }

    @Test func everyDomainCollectionNotifiesThePersistenceCoordinator() async throws {
        let (store, directory) = try await makeStore()
        defer {
            store.cancelScheduledSave()
            store.invalidateDataHealthScan()
            try? FileManager.default.removeItem(at: directory)
        }
        let writes: [(DataStore) -> Void] = [
            { $0.projectStore.setProjects([]) },
            { $0.projectStore.setDailyLogs([]) },
            { $0.projectStore.setHistoryRecords([]) },
            { $0.projectStore.setProgressTasks([]) },
            { $0.projectStore.setSiteTodos([]) },
            { $0.projectStore.setProjectDrawings([]) },
            { $0.projectStore.setProjectContacts([]) },
            { $0.projectStore.setProjectFinancialRecords([]) },
            { $0.projectStore.setProjectDocuments([]) },
            { $0.projectStore.setQuickNotes([]) },
            { $0.projectStore.setProjectWarehouseMovements([]) },
            { $0.financeStore.setMaterialItems([]) },
            { $0.financeStore.setQuoteItems([]) },
            { $0.financeStore.setLaborRecords([]) },
            { $0.materialLibraryStore.setTemplates([]) },
            { $0.materialLibraryStore.setMaterialPriceEntries([]) },
            { $0.materialLibraryStore.setMaterialSheetDrafts([]) },
            { $0.materialLibraryStore.setSupplierProfiles([]) },
            { $0.materialLibraryStore.setConstructionMethods([]) },
            { $0.materialLibraryStore.setUserMaterials([]) },
            { $0.materialLibraryStore.setDeletedUserMaterials([]) },
            { $0.materialLibraryPreferencesStore.setFavoriteMaterialKeys([]) },
            { $0.materialLibraryPreferencesStore.setRecentMaterialKeys([]) },
            { $0.materialLibraryPreferencesStore.setHiddenPresetKeys([]) }
        ]
        for write in writes {
            store.cancelScheduledSave()
            let revision = store.dataVersion
            write(store)
            #expect(store.dataVersion != revision)
            #expect(store.scheduledSaveTask != nil)
            #expect(store.autosaveLastMutationAt != nil)
        }
    }

    @Test func directChildWriteAutosavesWithoutAnExplicitSave() async throws {
        let (store, directory) = try await makeStore()
        defer {
            store.cancelScheduledSave()
            store.invalidateDataHealthScan()
            try? FileManager.default.removeItem(at: directory)
        }
        let todo = SiteTodo(title: "direct child write")
        store.projectStore.setSiteTodos([todo])
        store.materialLibraryPreferencesStore.setFavoriteMaterialKeys(["persisted-key"])
        await store.scheduledSaveTask?.value
        await store.persistTask?.value
        let snapshot = try #require(try await DataStorePersistenceActor(storeURL: store.storeURL).loadSnapshot())
        #expect(snapshot.siteTodos.map(\.id) == [todo.id])
        #expect(snapshot.favoriteMaterialKeys == ["persisted-key"])
    }

    @Test func loadingAndRestoreDoNotAutosaveIntermediateState() async throws {
        let (store, directory) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.setLoadState(.loading)
        store.projectStore.setSiteTodos([SiteTodo(title: "loading")])
        #expect(store.scheduledSaveTask == nil)
        store.setLoadState(.ready)
        store.isApplyingBackup = true
        store.projectStore.setSiteTodos([SiteTodo(title: "restoring")])
        #expect(store.scheduledSaveTask == nil)
        store.isApplyingBackup = false
        store.applyLoadedSnapshot(store.makeSnapshot(includePhotoFiles: false))
        #expect(store.scheduledSaveTask == nil)
        #expect(!FileManager.default.fileExists(atPath: store.storeURL.path))
    }

    @Test func facadeObservationTracksDirectChildWrites() async throws {
        let (store, directory) = try await makeStore()
        defer {
            store.cancelScheduledSave()
            store.invalidateDataHealthScan()
            try? FileManager.default.removeItem(at: directory)
        }
        let change = ObservationFlag()
        withObservationTracking {
            _ = store.siteTodos
        } onChange: {
            MainActor.assumeIsolated { change.changed = true }
        }
        store.projectStore.setSiteTodos([SiteTodo(title: "observed")])
        #expect(change.changed)
        #expect(store.siteTodos.first?.title == "observed")
    }

    @MainActor private final class ObservationFlag {
        var changed = false
    }
}
