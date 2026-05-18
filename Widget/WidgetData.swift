import Foundation

final class WidgetDataStore {
    static let suiteName = WidgetSharedDefaults.suiteName
    static let widgetDataKey = WidgetSharedDefaults.dataKey
    static let widgetUpdatedAtKey = WidgetSharedDefaults.updatedAtKey

    static var shared: WidgetExportData {
        decodeWidgetData(from: UserDefaults(suiteName: suiteName))
    }

    static var languageCode: String {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return resolvedSystemLanguageCode
        }
        if let code = defaults.string(forKey: WidgetSharedDefaults.languageCodeKey),
           !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if code == "system" {
                return resolvedSystemLanguageCode
            }
            return code
        }
        if let code = defaults.stringArray(forKey: WidgetSharedDefaults.appleLanguagesKey)?.first,
           !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return code
        }
        return resolvedSystemLanguageCode
    }

    private static var resolvedSystemLanguageCode: String {
        Locale.preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier
    }

    static func healthSnapshot() -> WidgetDataHealthSnapshot {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            WidgetStorageIssueLog.record(
                String(format: WidgetLocalizedText.string(for: "widget_storage_app_group_unavailable_format"), suiteName)
            )
            return WidgetDataHealthSnapshot(
                appGroupReadable: false,
                lastUpdatedAt: nil,
                projectCount: 0,
                pendingTodos: 0
            )
        }
        let data = decodeWidgetData(from: defaults)
        let timestamp = defaults.double(forKey: widgetUpdatedAtKey)
        let updatedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : data.lastUpdatedDate
        return WidgetDataHealthSnapshot(
            appGroupReadable: true,
            lastUpdatedAt: updatedAt,
            projectCount: data.projects.count,
            pendingTodos: data.pendingTodos
        )
    }

    private static func decodeWidgetData(from defaults: UserDefaults?) -> WidgetExportData {
        guard let defaults,
              let data = defaults.data(forKey: widgetDataKey),
              let widgetData = try? JSONDecoder().decode(WidgetExportData.self, from: data) else {
            return WidgetExportData(
                projects: [],
                pendingTodos: 0,
                materialStockCount: 0,
                lowStockCount: 0,
                missingReceiptCount: 0,
                priceSpikeCount: 0,
                backupOverdueCount: 0
            )
        }
        return widgetData
    }
}

private enum WidgetStorageIssueLog {
    private static let localFallbackKey = WidgetSharedDefaults.storageIssueLogKey
    private static let maxEntries = 120
    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func record(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if WidgetSharedStorageIssueLog.record(trimmed, source: "widget") {
            return
        }
        var entries = UserDefaults.standard.stringArray(forKey: localFallbackKey) ?? []
        entries.insert("[\(timestampFormatter.string(from: Date()))] \(trimmed)", at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        UserDefaults.standard.set(entries, forKey: localFallbackKey)
    }
}
