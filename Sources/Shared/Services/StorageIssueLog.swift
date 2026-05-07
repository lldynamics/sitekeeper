import Foundation

enum StorageIssueLog {
    private static let key = "storageIssueLogEntries"
    private static let maxEntries = 120

    static func record(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var entries = UserDefaults.standard.stringArray(forKey: key) ?? []
        entries.insert("[\(Formatters.now())] \(trimmed)", at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        UserDefaults.standard.set(entries, forKey: key)
    }

    static func entries() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
