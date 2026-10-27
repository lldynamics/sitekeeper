import Foundation
import Observation

// UserDefaults and ObservationRegistrar support concurrent access. No mutable
// cache is kept here: @AppStorage and background services share the same values.
final class UserPreferencesStore: Observable, @unchecked Sendable {
    static let shared = UserPreferencesStore()

    private let defaults: UserDefaults
    private let observation = ObservationRegistrar()
    private var defaultsObserver: NSObjectProtocol?
    private var changeToken: Bool { false }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.invalidate()
        }
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    private func trackAccess() {
        observation.access(self, keyPath: \.changeToken)
    }

    private func invalidate() {
        observation.withMutation(of: self, keyPath: \.changeToken) {}
    }

    private func mutate(_ operation: () -> Void) {
        observation.withMutation(of: self, keyPath: \.changeToken, operation)
    }

    func contains(_ key: String) -> Bool {
        trackAccess()
        return defaults.object(forKey: key) != nil
    }

    func bool(_ key: String, default defaultValue: Bool) -> Bool {
        guard contains(key) else { return defaultValue }
        return defaults.bool(forKey: key)
    }

    func int(_ key: String, default defaultValue: Int) -> Int {
        guard contains(key) else { return defaultValue }
        return defaults.integer(forKey: key)
    }

    func optionalInt(_ key: String) -> Int? {
        trackAccess()
        return defaults.object(forKey: key) as? Int
    }

    func string(_ key: String, default defaultValue: String = "", trimWhitespace: Bool = true) -> String {
        trackAccess()
        let raw = defaults.string(forKey: key) ?? ""
        let normalized = trimWhitespace ? raw.trimmingCharacters(in: .whitespacesAndNewlines) : raw
        return normalized.isEmpty ? defaultValue : normalized
    }

    func double(_ key: String, default defaultValue: Double) -> Double {
        guard contains(key) else { return defaultValue }
        return defaults.double(forKey: key)
    }

    func optionalDouble(_ key: String) -> Double? {
        guard contains(key) else { return nil }
        return defaults.double(forKey: key)
    }

    func object(for key: String) -> Any? {
        trackAccess()
        return defaults.object(forKey: key)
    }

    func persistentDomain(forName name: String) -> [String: Any]? {
        trackAccess()
        return defaults.persistentDomain(forName: name)
    }

    func data(_ key: String) -> Data? {
        trackAccess()
        return defaults.data(forKey: key)
    }

    func stringArray(_ key: String, default defaultValue: [String] = []) -> [String] {
        trackAccess()
        return defaults.stringArray(forKey: key) ?? defaultValue
    }

    func set(_ value: Bool, for key: String) {
        mutate { defaults.set(value, forKey: key) }
    }

    func set(_ value: Int, for key: String) {
        mutate { defaults.set(value, forKey: key) }
    }

    func set(_ value: Double, for key: String) {
        mutate { defaults.set(value, forKey: key) }
    }

    func set(_ value: String, for key: String) {
        mutate { defaults.set(value, forKey: key) }
    }

    func set(_ value: [String], for key: String) {
        mutate { defaults.set(value, forKey: key) }
    }

    func set(_ value: Data, for key: String) {
        mutate { defaults.set(value, forKey: key) }
    }

    func removeObject(for key: String) {
        mutate { defaults.removeObject(forKey: key) }
    }

    /// Drops values for settings that no longer exist, so stale choices cannot resurface.
    func removeRetiredKeys() {
        removeObject(for: UserPreferenceKeys.retiredAutoSave)
    }

    func removePersistentDomain(forName name: String) {
        mutate { defaults.removePersistentDomain(forName: name) }
    }

    func synchronize() {
        defaults.synchronize()
    }

    func unixDate(for key: String) -> Date? {
        guard let raw = optionalDouble(key), raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    func setUnixDate(_ date: Date, for key: String) {
        set(date.timeIntervalSince1970, for: key)
    }

    var backupReminderDays: Int {
        let raw = int(UserPreferenceKeys.backupHealthReminderDays, default: 7)
        return max(1, raw == 0 ? 7 : raw)
    }

    var latestSuccessfulBackupDate: Date? {
        let localDate = unixDate(for: UserPreferenceKeys.localBackupLastSuccessAt)
        let cloudDate = unixDate(for: UserPreferenceKeys.cloudBackupLastSuccessAt)
        switch (localDate, cloudDate) {
        case let (lhs?, rhs?):
            return max(lhs, rhs)
        case let (lhs?, nil):
            return lhs
        case let (nil, rhs?):
            return rhs
        case (nil, nil):
            return nil
        }
    }
}
