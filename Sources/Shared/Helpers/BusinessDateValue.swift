import Foundation

/// A civil day is independent of a time zone. Resolve it only for a calendar
/// operation, never by inventing an original capture time.
struct CalendarDay: Hashable, Sendable, Comparable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    init?(_ text: String) {
        guard text.range(of: #"^\d{4}[-/]\d{1,2}[-/]\d{1,2}$"#, options: .regularExpression) != nil else { return nil }
        let parts = text.split(whereSeparator: { $0 == "-" || $0 == "/" }).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        year = calendar.component(.year, from: date)
        month = calendar.component(.month, from: date)
        day = calendar.component(.day, from: date)
    }

    var storageText: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var description: String { storageText }

    func date(in timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

/// Typed business date with a narrow, lossless legacy wire boundary. Valid
/// historical values keep their exact source text until a native edit replaces
/// them. Unknown text remains unresolved and never becomes today's date.
struct BusinessDateValue: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    private enum Kind: Hashable, Sendable {
        case empty
        case day(CalendarDay)
        case instant(Date)
        case unresolved(String)
    }

    private let kind: Kind
    private let legacyEncoding: String?

    private init(kind: Kind, legacyEncoding: String? = nil) {
        self.kind = kind
        self.legacyEncoding = legacyEncoding
    }

    static let empty = Self(kind: .empty)
    static func day(_ day: CalendarDay) -> Self { Self(kind: .day(day)) }
    static func instant(_ date: Date) -> Self {
        // The v3 wire contract represents new clock instants to milliseconds.
        let normalized = Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
        return Self(kind: .instant(normalized))
    }
    static func unresolved(_ text: String) -> Self { Self(kind: .unresolved(text)) }
    static func now() -> Self { .instant(Date()) }
    static func today(timeZone: TimeZone = .current) -> Self { .day(CalendarDay(date: Date(), timeZone: timeZone)) }

    /// Used only when input or legacy JSON crosses into the domain.
    init(legacyText: String) {
        let text = legacyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            self.init(kind: .empty, legacyEncoding: legacyText.isEmpty ? nil : legacyText)
        } else if let day = CalendarDay(text) {
            self.init(kind: .day(day), legacyEncoding: legacyText)
        } else if text.contains(":"), let date = Formatters.parseDateOrDateTime(text) {
            self.init(kind: .instant(date), legacyEncoding: legacyText)
        } else {
            self.init(kind: .unresolved(legacyText))
        }
    }

    var isEmpty: Bool {
        if case .empty = kind { return true }
        return false
    }

    var isResolved: Bool {
        switch kind {
        case .day, .instant: return true
        case .empty, .unresolved: return false
        }
    }

    var includesTime: Bool {
        if case .instant = kind { return true }
        return false
    }

    var storageText: String { legacyEncoding ?? canonicalText }
    var description: String { storageText }

    private var canonicalText: String {
        switch kind {
        case .empty: return ""
        case let .day(day): return day.storageText
        case let .instant(date):
            return Self.isoCodec.string(from: date)
        case let .unresolved(text): return text
        }
    }

    /// Stable storage/query ordering, independent of legacy separators or offsets.
    var sortKey: String {
        switch kind {
        case .empty: return ""
        case let .unresolved(text): return "!" + text
        case .day, .instant: return canonicalText
        }
    }

    func date(in timeZone: TimeZone = .current) -> Date? {
        switch kind {
        case let .day(day): return day.date(in: timeZone)
        case let .instant(date): return date
        case .empty, .unresolved: return nil
        }
    }

    func calendarDay(in timeZone: TimeZone = .current) -> CalendarDay? {
        switch kind {
        case let .day(day): return day
        case let .instant(date): return CalendarDay(date: date, timeZone: timeZone)
        case .empty, .unresolved: return nil
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.kind == rhs.kind }
    func hash(into hasher: inout Hasher) { hasher.combine(kind) }
    static func < (lhs: Self, rhs: Self) -> Bool {
        switch (lhs.kind, rhs.kind) {
        case let (.day(left), .day(right)): return left < right
        case let (.instant(left), .instant(right)): return left < right
        case (.empty, .empty): return false
        case (.empty, _): return true
        case (_, .empty): return false
        case let (.unresolved(left), .unresolved(right)): return left < right
        case (.unresolved, _): return true
        case (_, .unresolved): return false
        default:
            let utc = TimeZone(secondsFromGMT: 0)!
            guard let left = lhs.date(in: utc), let right = rhs.date(in: utc) else { return false }
            if left != right { return left < right }
            if case .day = lhs.kind { return true }
            return false
        }
    }

    private static let isoCodec = ISOCodec()
    private final class ISOCodec: @unchecked Sendable {
        private let lock = NSLock()
        private let formatter: ISO8601DateFormatter
        init() {
            formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        }
        func string(from date: Date) -> String {
            lock.lock()
            defer { lock.unlock() }
            return formatter.string(from: date)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(legacyText: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storageText)
    }
}

extension DateFormatter {
    /// Typed dates already carry their meaning; no string parse is performed.
    func date(from value: BusinessDateValue) -> Date? {
        value.date(in: timeZone ?? .current)
    }
}
