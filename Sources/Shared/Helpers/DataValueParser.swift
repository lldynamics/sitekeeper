import Foundation

enum DataValueParser {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    static func decimalValue(from text: String) -> Decimal {
        decimalValueIfPresent(from: text) ?? .zero
    }

    static func decimalValueIfPresent(from text: String, requiresEntireString: Bool = false) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(
            of: #"[-+]?[0-9][0-9,.]*"#,
            options: .regularExpression
        ) else {
            return nil
        }

        guard !requiresEntireString || range == trimmed.startIndex..<trimmed.endIndex else {
            return nil
        }

        let token = normalizedDecimalToken(String(trimmed[range]))
        guard token.range(
            of: #"[-+]?[0-9]+(\.[0-9]*)?"#,
            options: .regularExpression
        ) == token.startIndex..<token.endIndex else {
            return nil
        }
        return Decimal(string: token, locale: posixLocale)
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

    private static func normalizedDecimalToken(_ token: String) -> String {
        let commaCount = token.filter { $0 == "," }.count
        let dotCount = token.filter { $0 == "." }.count

        if commaCount > 0, dotCount > 0 {
            guard let lastComma = token.lastIndex(of: ","),
                  let lastDot = token.lastIndex(of: ".") else { return token }
            if lastComma > lastDot {
                return token
                    .replacingOccurrences(of: ".", with: "")
                    .replacingOccurrences(of: ",", with: ".")
            }
            return token.replacingOccurrences(of: ",", with: "")
        }

        if commaCount > 0 {
            return normalizedSingleSeparatorToken(token, separator: ",", decimalSeparator: ".")
        }

        if dotCount > 1, isGroupedIntegerToken(token, separator: ".") {
            return token.replacingOccurrences(of: ".", with: "")
        }

        return token
    }

    private static func normalizedSingleSeparatorToken(
        _ token: String,
        separator: Character,
        decimalSeparator: String
    ) -> String {
        guard isGroupedIntegerToken(token, separator: separator) else {
            return token.split(separator: separator, omittingEmptySubsequences: false)
                .joined(separator: decimalSeparator)
        }
        return token.replacingOccurrences(of: String(separator), with: "")
    }

    private static func isGroupedIntegerToken(_ token: String, separator: Character) -> Bool {
        let groups = token.split(separator: separator, omittingEmptySubsequences: false).map(String.init)
        guard groups.count >= 2, let first = groups.first else { return false }
        let leadingDigits = String(first.dropLeadingSign())
        guard (1...3).contains(leadingDigits.count), leadingDigits.allSatisfy(\.isNumber) else {
            return false
        }
        return groups.dropFirst().allSatisfy { group in
            group.count == 3 && group.allSatisfy(\.isNumber)
        }
    }
}

private extension String {
    func dropLeadingSign() -> Substring {
        guard let first = first, first == "-" || first == "+" else { return self[...] }
        return dropFirst()
    }
}
