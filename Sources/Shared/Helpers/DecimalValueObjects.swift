import Foundation

enum DecimalMath {
    static func add(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
        NSDecimalNumber(decimal: lhs).adding(NSDecimalNumber(decimal: rhs)).decimalValue
    }

    static func subtract(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
        NSDecimalNumber(decimal: lhs).subtracting(NSDecimalNumber(decimal: rhs)).decimalValue
    }

    static func multiply(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
        NSDecimalNumber(decimal: lhs).multiplying(by: NSDecimalNumber(decimal: rhs)).decimalValue
    }

    static func divide(_ lhs: Decimal, by rhs: Decimal) -> Decimal {
        guard rhs != .zero else { return .zero }
        return NSDecimalNumber(decimal: lhs).dividing(by: NSDecimalNumber(decimal: rhs)).decimalValue
    }
}

struct MoneyValue: Hashable, Sendable, Comparable {
    static let zero = MoneyValue()
    let decimal: Decimal

    init(_ decimal: Decimal = .zero) {
        self.decimal = decimal
    }

    init(text: String) {
        decimal = DataValueParser.decimalValue(from: text)
    }

    var doubleValue: Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }

    var isZero: Bool {
        decimal == .zero
    }

    var isPositive: Bool {
        decimal > .zero
    }

    static func < (lhs: MoneyValue, rhs: MoneyValue) -> Bool {
        lhs.decimal < rhs.decimal
    }

    static func + (lhs: MoneyValue, rhs: MoneyValue) -> MoneyValue {
        MoneyValue(DecimalMath.add(lhs.decimal, rhs.decimal))
    }

    static func - (lhs: MoneyValue, rhs: MoneyValue) -> MoneyValue {
        MoneyValue(DecimalMath.subtract(lhs.decimal, rhs.decimal))
    }

    static func * (lhs: MoneyValue, rhs: Decimal) -> MoneyValue {
        MoneyValue(DecimalMath.multiply(lhs.decimal, rhs))
    }
}

struct QuantityValue: Hashable, Sendable, Comparable {
    static let zero = QuantityValue()
    let decimal: Decimal

    init(_ decimal: Decimal = .zero) {
        self.decimal = decimal
    }

    init(text: String) {
        decimal = DataValueParser.decimalValue(from: text)
    }

    var doubleValue: Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }

    var isZero: Bool {
        decimal == .zero
    }

    var isPositive: Bool {
        decimal > .zero
    }

    var ratioFromPercent: Decimal {
        DecimalMath.divide(decimal, by: 100)
    }

    static func < (lhs: QuantityValue, rhs: QuantityValue) -> Bool {
        lhs.decimal < rhs.decimal
    }

    static func + (lhs: QuantityValue, rhs: QuantityValue) -> QuantityValue {
        QuantityValue(DecimalMath.add(lhs.decimal, rhs.decimal))
    }

    static func * (lhs: QuantityValue, rhs: QuantityValue) -> QuantityValue {
        QuantityValue(DecimalMath.multiply(lhs.decimal, rhs.decimal))
    }

    static func * (lhs: QuantityValue, rhs: MoneyValue) -> MoneyValue {
        MoneyValue(DecimalMath.multiply(lhs.decimal, rhs.decimal))
    }

    static func * (lhs: MoneyValue, rhs: QuantityValue) -> MoneyValue {
        MoneyValue(DecimalMath.multiply(lhs.decimal, rhs.decimal))
    }
}
