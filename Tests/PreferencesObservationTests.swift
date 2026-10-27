import Foundation
import Observation
import Testing
@testable import sitekeeper

struct PreferencesObservationTests {
    @Test func serviceWritesInvalidateComputedPreferencesAndPersist() throws {
        let suite = "PreferencesObservationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = UserPreferencesStore(defaults: defaults)
        let changes = ChangeCounter()
        withObservationTracking {
            #expect(service.backupReminderDays == 7)
        } onChange: { changes.increment() }
        service.set(14, for: UserPreferenceKeys.backupHealthReminderDays)
        #expect(changes.value == 1)
        #expect(service.backupReminderDays == 14)
        #expect(UserPreferencesStore(defaults: defaults).backupReminderDays == 14)
    }

    @Test func externalDefaultsNotificationsAndRemovalInvalidateReaders() throws {
        let suite = "PreferencesObservationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = UserPreferencesStore(defaults: defaults)
        let changes = ChangeCounter()
        withObservationTracking {
            #expect(service.string("name", default: "Initial") == "Initial")
            #expect(service.data("avatar") == nil)
        } onChange: { changes.increment() }
        // This is the same notification path used by writes outside the service,
        // including @AppStorage; use an isolated suite, never real app preferences.
        defaults.set("Updated", forKey: "name")
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
        #expect(changes.value == 1)
        #expect(service.string("name") == "Updated")
        withObservationTracking {
            #expect(service.contains("name"))
        } onChange: { changes.increment() }
        service.removeObject(for: "name")
        #expect(changes.value == 2)
        #expect(service.string("name", default: "Initial") == "Initial")
    }

    private final class ChangeCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
        func increment() {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }
    }
}
