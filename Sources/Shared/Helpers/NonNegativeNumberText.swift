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
        if let number = try? container.decode(Decimal.self), !number.isNaN, number >= .zero {
            storage = NSDecimalNumber(decimal: number).stringValue
            return
        }
        storage = ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(storage)
    }

    private static func normalize(_ input: String) -> String {
        let normalized = NumericInputSupport.normalizeSeparators(in: input).filter { !$0.isWhitespace }
        guard let decimal = DataValueParser.decimalValueIfPresent(from: normalized, requiresEntireString: true),
              !decimal.isNaN, decimal >= .zero else {
            return ""
        }

        return NSDecimalNumber(decimal: decimal).stringValue
    }
}
