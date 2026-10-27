import Foundation
import OSLog

final class WidgetDataStore {
    static let suiteName = WidgetSharedDefaults.suiteName
    static let widgetDataKey = WidgetSharedDefaults.dataKey
    static let widgetUpdatedAtKey = WidgetSharedDefaults.updatedAtKey
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.chengjinfang.sitekeeper.widget",
        category: "WidgetDataStore"
    )

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

    private static func decodeWidgetData(from defaults: UserDefaults?) -> WidgetExportData {
        guard let defaults else {
            return emptyWidgetData()
        }
        guard let data = defaults.data(forKey: widgetDataKey) else {
            return emptyWidgetData()
        }
        do {
            return try JSONDecoder().decode(WidgetExportData.self, from: data)
        } catch {
            let errorSummary = decodeErrorSummary(error)
            WidgetStorageIssueLog.record(
                "Widget 数据解码失败：key=\(widgetDataKey), bytes=\(data.count), error=\(errorSummary)"
            )
            logger.error(
                "Widget decode failed. key=\(widgetDataKey, privacy: .public) bytes=\(data.count, privacy: .public) error=\(errorSummary, privacy: .public)"
            )
            return emptyWidgetData()
        }
    }

    private static func emptyWidgetData() -> WidgetExportData {
        WidgetExportData(
            projects: [],
            pendingTodos: 0,
            materialStockCount: 0,
            lowStockCount: 0,
            missingReceiptCount: 0,
            priceSpikeCount: 0,
            backupOverdueCount: 0
        )
    }

    private static func decodeErrorSummary(_ error: Error) -> String {
        switch error {
        case let DecodingError.dataCorrupted(context):
            return "dataCorrupted path=\(codingPath(context.codingPath)) desc=\(context.debugDescription)"
        case let DecodingError.keyNotFound(key, context):
            return "keyNotFound key=\(key.stringValue) path=\(codingPath(context.codingPath)) desc=\(context.debugDescription)"
        case let DecodingError.typeMismatch(_, context):
            return "typeMismatch path=\(codingPath(context.codingPath)) desc=\(context.debugDescription)"
        case let DecodingError.valueNotFound(_, context):
            return "valueNotFound path=\(codingPath(context.codingPath)) desc=\(context.debugDescription)"
        default:
            return String(describing: error)
        }
    }

    private static func codingPath(_ path: [CodingKey]) -> String {
        let value = path.map(\.stringValue).joined(separator: ".")
        return value.isEmpty ? "root" : value
    }
}

private enum WidgetStorageIssueLog {
    private static let localFallbackKey = WidgetSharedDefaults.storageIssueLogKey
    private static let localFallbackSuiteName = Bundle.main.bundleIdentifier ?? "com.chengjinfang.sitekeeper.widget.local"
    private static let maxEntries = 120

    static func record(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if WidgetSharedStorageIssueLog.record(trimmed, source: "widget") {
            return
        }
        guard let defaults = UserDefaults(suiteName: localFallbackSuiteName) else { return }
        var entries = defaults.stringArray(forKey: localFallbackKey) ?? []
        entries.insert("[\(timestampString(for: Date()))] \(trimmed)", at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        defaults.set(entries, forKey: localFallbackKey)
    }

    private static func timestampString(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
