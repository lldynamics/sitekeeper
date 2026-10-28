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

    static func parseDateOrDateTime(_ value: BusinessDateValue, timeZone: TimeZone = .current) -> Date? {
        value.date(in: timeZone)
    }

    static func displayDateText(_ value: BusinessDateValue, timeZone: TimeZone = .current) -> String {
        guard value.includesTime, let date = value.date(in: timeZone) else { return value.storageText }
        return dateTimeFormatter(timeZone: timeZone).string(from: date)
    }

    static func isLater(_ lhs: BusinessDateValue, than rhs: BusinessDateValue) -> Bool { lhs > rhs }

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

    /// Local wall-clock text for people reading a generated document. Never persist it.
    static func displayNow() -> String { dateTimeFormatter().string(from: Date()) }

    static func displayDateText(_ text: String, timeZone: TimeZone = .current) -> String {
        guard text.contains(":"), let value = parseDateOrDateTime(text, timeZone: timeZone) else { return text }
        return dateTimeFormatter(timeZone: timeZone).string(from: value)
    }

    /// Friendly relative or short date for timeline and dashboard badges
    static func displayRelativeOrShortDate(_ value: BusinessDateValue, timeZone: TimeZone = .current) -> String {
        displayRelativeOrShortDate(value.storageText, timeZone: timeZone)
    }

    static func displayRelativeOrShortDate(_ text: String, timeZone: TimeZone = .current) -> String {
        guard let date = parseDateOrDateTime(text, timeZone: timeZone) else { return text }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            if text.contains(":") {
                let timeFormatter = formatterCache.formatter("HH:mm", timeZone: timeZone)
                return "\(AppLocalization.string("今天")) \(timeFormatter.string(from: date))"
            }
            return AppLocalization.string("今天")
        } else if calendar.isDateInYesterday(date) {
            if text.contains(":") {
                let timeFormatter = formatterCache.formatter("HH:mm", timeZone: timeZone)
                return "\(AppLocalization.string("昨天")) \(timeFormatter.string(from: date))"
            }
            return AppLocalization.string("昨天")
        } else {
            let monthDayFormatter = formatterCache.formatter(text.contains(":") ? "MM-dd HH:mm" : "MM-dd", timeZone: timeZone)
            return monthDayFormatter.string(from: date)
        }
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
    static func money(_ value: Decimal) -> String { money(decimal: value) }

    /// 中文大写金额转换（用于现场防手滑录错大写校验）
    static func chineseCurrencySpellout(_ text: String) -> String? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decimal = Decimal(string: clean), decimal >= 0, decimal < 100_000_000_000 else {
            return nil
        }
        if decimal == 0 { return "零元整" }

        let digits = ["零", "壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖"]
        let integerUnits = ["", "拾", "佰", "仟"]
        let sectionUnits = ["", "万", "亿"]

        var source = decimal
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &source, 2, .plain)

        let number = NSDecimalNumber(decimal: rounded)
        let totalCents = Int64((number.doubleValue * 100).rounded())
        let integerPart = totalCents / 100
        let jiao = Int((totalCents % 100) / 10)
        let fen = Int(totalCents % 10)

        var result = ""

        if integerPart > 0 {
            var tempInt = integerPart
            var sectionIndex = 0
            var intStr = ""

            while tempInt > 0 {
                let section = Int(tempInt % 10_000)
                if section > 0 {
                    var secStr = ""
                    var secTemp = section
                    var unitIndex = 0
                    var zeroFlag = false

                    while secTemp > 0 {
                        let digit = secTemp % 10
                        if digit == 0 {
                            if !zeroFlag && !secStr.isEmpty {
                                secStr = digits[0] + secStr
                                zeroFlag = true
                            }
                        } else {
                            secStr = digits[digit] + integerUnits[unitIndex] + secStr
                            zeroFlag = false
                        }
                        secTemp /= 10
                        unitIndex += 1
                    }
                    intStr = secStr + sectionUnits[sectionIndex] + intStr
                } else if !intStr.isEmpty && !intStr.hasPrefix(digits[0]) {
                    intStr = digits[0] + intStr
                }
                tempInt /= 10_000
                sectionIndex += 1
            }
            result += intStr + "元"
        }

        if jiao == 0 && fen == 0 {
            result += "整"
        } else {
            if jiao > 0 {
                result += digits[jiao] + "角"
            } else if integerPart > 0 && fen > 0 {
                result += "零"
            }
            if fen > 0 {
                result += digits[fen] + "分"
            } else if jiao > 0 {
                result += "整"
            }
        }
        return result
    }

    static func money(decimal value: Decimal) -> String {
        guard !value.isNaN else { return "" }
        var source = value
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &source, 2, .plain)
        let text = NSDecimalNumber(decimal: rounded).stringValue
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count == 1 { return text + ".00" }
        return text + String(repeating: "0", count: max(0, 2 - parts[1].count))
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
