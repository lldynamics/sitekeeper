import Foundation

enum DataValueParser {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    static func decimalValue(from text: String) -> Decimal {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let range = normalized.range(
            of: #"[-+]?[0-9]+(\.[0-9]+)?"#,
            options: .regularExpression
        ) else {
            return .zero
        }
        let token = String(normalized[range])
        return Decimal(string: token, locale: posixLocale) ?? .zero
    }

    static func double(from text: String) -> Double {
        NSDecimalNumber(decimal: decimalValue(from: text)).doubleValue
    }

    static func decimal(from text: String) -> Double {
        double(from: text)
    }

    static func parseDate(_ text: String, preferredFormatter: DateFormatter? = nil) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let preferredFormatter, let date = preferredFormatter.date(from: value) {
            return date
        }
        return Formatters.parseDateOrDateTime(value)
    }
}
