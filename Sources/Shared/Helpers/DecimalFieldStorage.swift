import Foundation

/// Only the wire boundary knows about legacy text. Empty and malformed historical
/// values remain distinct from a real zero and survive a decode/encode cycle.
enum DecimalFieldStorage: Hashable, Sendable, Codable, Comparable {
    case value(Decimal)
    case empty
    case unresolved(String)

    init(text: String) {
        let normalized = NumericInputSupport.normalizeSeparators(in: text).filter { !$0.isWhitespace }
        if normalized.isEmpty {
            self = .empty
        } else if let value = DataValueParser.decimalValueIfPresent(from: normalized, requiresEntireString: true), !value.isNaN {
            self = .value(value)
        } else {
            self = .unresolved(text)
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.value(left), .value(right)): return left < right
        case (.empty, .empty): return false
        case (.empty, _): return true
        case (_, .empty): return false
        case let (.unresolved(left), .unresolved(right)): return left < right
        case (.unresolved, .value): return true
        case (.value, .unresolved): return false
        }
    }

    var value: Decimal? {
        guard case let .value(value) = self else { return nil }
        return value
    }

    var text: String {
        switch self {
        case let .value(value): return NSDecimalNumber(decimal: value).stringValue
        case .empty: return ""
        case let .unresolved(text): return text
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .empty
        } else if let text = try? container.decode(String.self) {
            self.init(text: text)
        } else {
            self = .value(try container.decode(Decimal.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}

protocol DecimalDomainValue: Codable, Hashable, Sendable {
    var storage: DecimalFieldStorage { get }
    init(storage: DecimalFieldStorage)
}

extension DecimalDomainValue {
    static var empty: Self { Self(storage: .empty) }
    var optionalDecimal: Decimal? { storage.value }
    var decimal: Decimal { storage.value ?? .zero }
    var calculationValue: Decimal {
        switch storage {
        case let .value(value): return value
        case .empty: return .zero
        case .unresolved: return .nan
        }
    }
    var isEmpty: Bool { storage == .empty }
    var isValid: Bool { optionalDecimal != nil }
    var isZero: Bool { optionalDecimal == .zero }
    var isPositive: Bool { optionalDecimal.map { $0 > .zero } ?? false }
    var isNegative: Bool { optionalDecimal.map { $0 < .zero } ?? false }
    var wireText: String { storage.text }

    init(from decoder: Decoder) throws {
        self.init(storage: try DecimalFieldStorage(from: decoder))
    }

    func encode(to encoder: Encoder) throws { try storage.encode(to: encoder) }
}

/// The domain field stays a MoneyValue or QuantityValue. A rejected assignment
/// is retained as an explicit unresolved value; it never keeps the previous one.
@propertyWrapper
struct NonNegativeDecimal<Value: DecimalDomainValue>: Codable, Hashable, Sendable {
    private var value: Value

    var wrappedValue: Value {
        get { value }
        set { value = Self.checked(newValue) }
    }

    init(wrappedValue: Value = .empty) { value = Self.checked(wrappedValue) }

    private static func checked(_ value: Value) -> Value {
        guard let number = value.optionalDecimal, number < .zero || number.isNaN else { return value }
        return Value(storage: .unresolved(value.wireText))
    }

    init(from decoder: Decoder) throws { value = Self.checked(try Value(from: decoder)) }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
