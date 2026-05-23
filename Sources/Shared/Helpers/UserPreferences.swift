enum UserPreferences {
    static func bool(_ key: String, default defaultValue: Bool) -> Bool {
        UserPreferencesStore.shared.bool(key, default: defaultValue)
    }

    static func string(_ key: String, default defaultValue: String = "") -> String {
        UserPreferencesStore.shared.string(key, default: defaultValue)
    }

    static func int(_ key: String, default defaultValue: Int) -> Int {
        UserPreferencesStore.shared.int(key, default: defaultValue)
    }

    static func double(_ key: String, default defaultValue: Double) -> Double {
        UserPreferencesStore.shared.double(key, default: defaultValue)
    }

    static func optionalDouble(_ key: String) -> Double? {
        UserPreferencesStore.shared.optionalDouble(key)
    }

    static func set(_ value: Bool, for key: String) {
        UserPreferencesStore.shared.set(value, for: key)
    }

    static func set(_ value: Int, for key: String) {
        UserPreferencesStore.shared.set(value, for: key)
    }

    static func set(_ value: Double, for key: String) {
        UserPreferencesStore.shared.set(value, for: key)
    }

    static func set(_ value: String, for key: String) {
        UserPreferencesStore.shared.set(value, for: key)
    }
}
