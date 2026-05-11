import Foundation

@propertyWrapper
struct NonNegativeNumberText: Codable, Hashable, Sendable {
    private var storage: String

    var wrappedValue: String {
        get { storage }
        set {
            let normalized = Self.normalize(newValue)
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !normalized.isEmpty {
                storage = normalized
            }
        }
    }

    var projectedValue: Double {
        DataValueParser.double(from: storage)
    }

    init(wrappedValue: String = "") {
        storage = Self.normalize(wrappedValue)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            storage = Self.normalize(text)
            return
        }
        if let number = try? container.decode(Double.self) {
            storage = Self.normalize(String(number))
            return
        }
        if let integer = try? container.decode(Int.self) {
            storage = Self.normalize(String(integer))
            return
        }
        storage = ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storage)
    }

    private static func normalize(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        var normalized = trimmed.replacingOccurrences(of: " ", with: "")
        let hasComma = normalized.contains(",")
        let hasDot = normalized.contains(".")

        if hasComma && hasDot {
            normalized = normalized.replacingOccurrences(of: ",", with: "")
        } else if hasComma {
            let isThousandsGrouped = normalized.range(
                of: #"^\d{1,3}(,\d{3})+$"#,
                options: .regularExpression
            ) != nil
            if isThousandsGrouped {
                normalized = normalized.replacingOccurrences(of: ",", with: "")
            } else {
                normalized = normalized.replacingOccurrences(of: ",", with: ".")
            }
        }

        guard normalized.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 0 else {
            return ""
        }

        return NSDecimalNumber(decimal: decimal).stringValue
    }
}
