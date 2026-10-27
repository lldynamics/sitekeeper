import Foundation
import Testing
@testable import sitekeeper

@MainActor
struct AutosavePreferenceTests {
    @Test func recordsAreSavedEvenWhenTheRetiredToggleWasTurnedOff() async throws {
        // Earlier versions skipped autosave while this value was false.
        UserPreferencesStore.shared.set(false, for: UserPreferenceKeys.retiredAutoSave)
        defer { UserPreferencesStore.shared.removeObject(for: UserPreferenceKeys.retiredAutoSave) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        let project = Project(name: "Autosave", location: "", status: .active)
        store.appendProject(project)
        store.scheduleSave()
        let scheduled = try #require(store.scheduledSaveTask)
        await scheduled.value
        await store.persistTask?.value

        let saved = try JSONDecoder().decode(BackupSnapshot.self, from: Data(contentsOf: store.storeURL))
        #expect(saved.projects.contains { $0.id == project.id })
    }

    @Test func launchCleanupRemovesOnlyRetiredSettings() throws {
        let suite = "autosave-retired-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = UserPreferencesStore(defaults: defaults)
        preferences.set(false, for: UserPreferenceKeys.retiredAutoSave)
        preferences.set(true, for: UserPreferenceKeys.useMetric)

        preferences.removeRetiredKeys()

        #expect(!preferences.contains(UserPreferenceKeys.retiredAutoSave))
        #expect(preferences.bool(UserPreferenceKeys.useMetric, default: false))
    }
}
