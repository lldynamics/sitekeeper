import Foundation
import Observation

@Observable
final class UserPreferencesStore {
    static let shared = UserPreferencesStore()

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func contains(_ key: String) -> Bool {
        defaults.object(forKey: key) != nil
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
        defaults.object(forKey: key) as? Int
    }

    func string(_ key: String, default defaultValue: String = "", trimWhitespace: Bool = true) -> String {
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
        defaults.object(forKey: key)
    }

    func data(_ key: String) -> Data? {
        defaults.data(forKey: key)
    }

    func stringArray(_ key: String, default defaultValue: [String] = []) -> [String] {
        defaults.stringArray(forKey: key) ?? defaultValue
    }

    func set(_ value: Bool, for key: String) {
        defaults.set(value, forKey: key)
    }

    func set(_ value: Int, for key: String) {
        defaults.set(value, forKey: key)
    }

    func set(_ value: Double, for key: String) {
        defaults.set(value, forKey: key)
    }

    func set(_ value: String, for key: String) {
        defaults.set(value, forKey: key)
    }

    func set(_ value: [String], for key: String) {
        defaults.set(value, forKey: key)
    }

    func set(_ value: Data, for key: String) {
        defaults.set(value, forKey: key)
    }

    func removeObject(for key: String) {
        defaults.removeObject(forKey: key)
    }

    func removePersistentDomain(forName name: String) {
        defaults.removePersistentDomain(forName: name)
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
