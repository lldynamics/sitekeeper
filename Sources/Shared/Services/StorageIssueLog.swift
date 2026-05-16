import Foundation

enum StorageIssueCategory: String {
    case cloudBackup = "cloud-backup"
    case dataStore = "datastore"
    case zipArchive = "zip-archive"
}

enum StorageIssueLog {
    private static let key = "storageIssueLogEntries"
    private static let maxEntries = 120

    static func record(_ message: String, category: StorageIssueCategory? = nil) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let taggedMessage = category.map { "[\($0.rawValue)] \(trimmed)" } ?? trimmed
        var entries = UserDefaults.standard.stringArray(forKey: key) ?? []
        entries.insert("[\(Formatters.now())] \(taggedMessage)", at: 0)
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
