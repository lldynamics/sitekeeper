import Foundation

enum StorageIssueCategory: String {
    case cloudBackup = "cloud-backup"
    case dataStore = "datastore"
    case zipArchive = "zip-archive"
    case fileStorage = "file-storage"
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

    static func recordEvent(
        _ event: String,
        category: StorageIssueCategory? = nil,
        details: [String: String] = [:],
        error: Error? = nil
    ) {
        let normalizedEvent = event.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEvent.isEmpty else { return }

        var components = ["event=\(sanitizedValue(normalizedEvent))"]
        for key in details.keys.sorted() {
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty else { continue }
            let value = details[key] ?? ""
            components.append("\(sanitizedValue(normalizedKey))=\(sanitizedValue(value))")
        }
        if let error {
            components.append("error=\(sanitizedValue(error.localizedDescription))")
        }
        record(components.joined(separator: " "), category: category)
    }

    private static func sanitizedValue(_ raw: String) -> String {
        let collapsedWhitespace = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsedWhitespace.isEmpty else { return "n/a" }
        return collapsedWhitespace
            .replacingOccurrences(of: "\"", with: "'")
    }
}
