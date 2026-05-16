import Foundation

/// 全局格式化工具，消除各计算器视图中的 fmt() / now() 重复
enum Formatters {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let stableTimeZone = TimeZone(secondsFromGMT: 0)!
    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = stableTimeZone
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = stableTimeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    private static let fallbackDateFormatters: [DateFormatter] = [
        makeFormatter("yyyy-MM-dd HH:mm:ss"),
        makeFormatter("yyyy-M-d HH:mm:ss"),
        makeFormatter("yyyy-M-d HH:mm"),
        makeFormatter("yyyy-M-d"),
        makeFormatter("yyyy/MM/dd HH:mm:ss"),
        makeFormatter("yyyy/MM/dd HH:mm"),
        makeFormatter("yyyy/MM/dd")
    ]

    static let dateTime: DateFormatter = {
        makeFormatter("yyyy-MM-dd HH:mm")
    }()

    static let date: DateFormatter = {
        makeFormatter("yyyy-MM-dd")
    }()

    /// 兼容 yyyy-MM-dd 与 yyyy-MM-dd HH:mm
    static func parseDateOrDateTime(_ text: String) -> Date? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if let value = dateTime.date(from: normalized) { return value }
        if let value = date.date(from: normalized) { return value }
        for formatter in fallbackDateFormatters {
            if let value = formatter.date(from: normalized) { return value }
        }
        if let value = iso8601WithFractionalSeconds.date(from: normalized) { return value }
        if let value = iso8601.date(from: normalized) { return value }
        return nil
    }

    /// 当前时间字符串
    static func now() -> String { dateTime.string(from: Date()) }

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

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = posixLocale
        formatter.timeZone = stableTimeZone
        formatter.dateFormat = format
        return formatter
    }
}
