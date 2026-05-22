import Foundation

struct OperationAuditEntry: Codable, Identifiable {
    enum Action: String, Codable {
        case `import`
        case restore
        case cleanup
        case repair
        case delete
    }

    enum Outcome: String, Codable {
        case started
        case succeeded
        case failed
        case cancelled
    }

    let id: UUID
    let timestamp: TimeInterval
    let action: Action
    let outcome: Outcome
    let summary: String
    let detail: String
    let source: String
}

enum OperationAuditLog {
    private static let key = UserPreferenceKeys.operationAuditLogEntries
    private static let maxEntries = 240

    static func record(
        action: OperationAuditEntry.Action,
        outcome: OperationAuditEntry.Outcome,
        summary: String,
        detail: String = "",
        source: String = ""
    ) {
        let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSummary.isEmpty else { return }

        let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)

        var entries = loadEntries()
        entries.insert(
            OperationAuditEntry(
                id: UUID(),
                timestamp: Date().timeIntervalSince1970,
                action: action,
                outcome: outcome,
                summary: normalizedSummary,
                detail: normalizedDetail,
                source: normalizedSource
            ),
            at: 0
        )
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        saveEntries(entries)
    }

    static func entries() -> [OperationAuditEntry] {
        loadEntries().sorted { lhs, rhs in
            if lhs.timestamp == rhs.timestamp {
                return lhs.id.uuidString > rhs.id.uuidString
            }
            return lhs.timestamp > rhs.timestamp
        }
    }

    static func clear() {
        UserPreferencesStore.shared.removeObject(for: key)
    }

    private static func loadEntries() -> [OperationAuditEntry] {
        let preferenceStore = UserPreferencesStore.shared
        guard let data = preferenceStore.data(key), !data.isEmpty else {
            return []
        }
        do {
            return try JSONDecoder().decode([OperationAuditEntry].self, from: data)
        } catch {
            StorageIssueLog.recordEvent(
                "operation_audit.load_failed",
                category: .dataStore,
                details: ["store": key],
                error: error
            )
            preferenceStore.removeObject(for: key)
            return []
        }
    }

    private static func saveEntries(_ entries: [OperationAuditEntry]) {
        let preferenceStore = UserPreferencesStore.shared
        do {
            let data = try JSONEncoder().encode(entries)
            preferenceStore.set(data, for: key)
        } catch {
            StorageIssueLog.recordEvent(
                "operation_audit.save_failed",
                category: .dataStore,
                details: ["store": key],
                error: error
            )
        }
    }
}
