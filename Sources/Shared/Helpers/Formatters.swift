import Foundation

/// 全局格式化工具，消除各计算器视图中的 fmt() / now() 重复
enum Formatters {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let formatterCache = BusinessDateFormatterCache()
    private static let fallbackDateFormats = [
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-M-d HH:mm:ss",
        "yyyy-M-d HH:mm",
        "yyyy-M-d",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy/MM/dd HH:mm",
        "yyyy/MM/dd"
    ]

    // Local UI display and calendar-day entry. Use timestamp(_:) to persist instants;
    // a zone-less display string must never become a new storage timestamp.
    static var dateTime: DateFormatter { dateTimeFormatter() }
    static var date: DateFormatter { dateFormatter() }

    static func dateFormatter(timeZone: TimeZone = .current) -> DateFormatter {
        formatterCache.formatter("yyyy-MM-dd", timeZone: timeZone)
    }

    static func dateTimeFormatter(timeZone: TimeZone = .current) -> DateFormatter {
        formatterCache.formatter("yyyy-MM-dd HH:mm", timeZone: timeZone)
    }

    /// Zone-less date-times were written as UTC by v2. Keep that interpretation
    /// regardless of the current device zone; date-only values are calendar days.
    static func parseDateOrDateTime(_ text: String, timeZone: TimeZone = .current) -> Date? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if normalized.contains("T") {
            for fractional in [true, false] {
                if let value = makeISO8601Formatter(includeFractionalSeconds: fractional).date(from: normalized) {
                    return value
                }
            }
            return nil
        }
        let utc = TimeZone(secondsFromGMT: 0)!
        let timestampFormatter = formatterCache.formatter("yyyy-MM-dd HH:mm:ss'Z'", timeZone: utc)
        if normalized.hasSuffix("Z"), let value = timestampFormatter.date(from: normalized) { return value }
        let formats = ["yyyy-MM-dd HH:mm", "yyyy-MM-dd"] + fallbackDateFormats
        for format in formats {
            let zone = format.contains("HH") ? utc : timeZone
            let formatter = formatterCache.formatter(format, timeZone: zone)
            if let value = formatter.date(from: normalized) { return value }
        }
        return nil
    }

    /// Explicit UTC storage timestamp. Its prefix remains sortable with legacy UTC text.
    static func timestamp(_ date: Date) -> String {
        formatterCache.formatter("yyyy-MM-dd HH:mm:ss'Z'", timeZone: TimeZone(secondsFromGMT: 0)!).string(from: date)
    }

    static func now() -> String { timestamp(Date()) }

    static func displayDateText(_ text: String, timeZone: TimeZone = .current) -> String {
        guard text.contains(":"), let value = parseDateOrDateTime(text, timeZone: timeZone) else { return text }
        return dateTimeFormatter(timeZone: timeZone).string(from: value)
    }

    static func isLater(_ lhs: String, than rhs: String) -> Bool {
        (parseDateOrDateTime(lhs) ?? .distantPast) > (parseDateOrDateTime(rhs) ?? .distantPast)
    }

    /// 数字格式化（小数位可配）
    static func number(_ v: Double, minFraction: Int = 0, maxFraction: Int = 3) -> String {
        let f = NumberFormatter()
        f.locale = posixLocale
        f.numberStyle = .decimal
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = minFraction
        f.maximumFractionDigits = maxFraction
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    /// 两位小数金额
    static func money(_ v: Double) -> String { String(format: "%.2f", v) }

    static func localizedCurrency(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? money(value)
    }

    // DateFormatter supports concurrent formatting. The lock protects cache creation;
    // callers treat returned formatters as read-only, as with the previous static formatters.
    private final class BusinessDateFormatterCache: @unchecked Sendable {
        private let lock = NSLock()
        private var formatters: [String: DateFormatter] = [:]

        func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
            lock.lock()
            defer { lock.unlock() }
            let key = timeZone.identifier + "|" + format
            if let cached = formatters[key] { return cached }
            let formatter = DateFormatter()
            formatter.locale = posixLocale
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            formatters[key] = formatter
            return formatter
        }
    }

    private static func makeISO8601Formatter(includeFractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = includeFractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }
}
