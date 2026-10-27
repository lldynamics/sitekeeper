import Foundation

enum DecimalMath {
    static func add(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
        var lhs = lhs, rhs = rhs, result = Decimal.zero
        guard NSDecimalAdd(&result, &lhs, &rhs, .plain) == .noError,
              let left = ExactDecimalCoefficient(lhs), let right = ExactDecimalCoefficient(rhs),
              let actual = ExactDecimalCoefficient(result), actual.fitsStoragePrecision,
              actual == left.adding(right) else { return .nan }
        return result
    }

    static func subtract(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
        var lhs = lhs, rhs = rhs, result = Decimal.zero
        guard NSDecimalSubtract(&result, &lhs, &rhs, .plain) == .noError,
              let left = ExactDecimalCoefficient(lhs), let right = ExactDecimalCoefficient(rhs),
              let actual = ExactDecimalCoefficient(result), actual.fitsStoragePrecision,
              actual == left.adding(right, subtract: true) else { return .nan }
        return result
    }

    static func multiply(_ lhs: Decimal, _ rhs: Decimal) -> Decimal {
        var lhs = lhs, rhs = rhs, result = Decimal.zero
        guard NSDecimalMultiply(&result, &lhs, &rhs, .plain) == .noError,
              let left = ExactDecimalCoefficient(lhs), let right = ExactDecimalCoefficient(rhs),
              let actual = ExactDecimalCoefficient(result), actual.fitsStoragePrecision,
              actual == left.multiplied(by: right) else { return .nan }
        return result
    }

    static func divide(_ lhs: Decimal, by rhs: Decimal) -> Decimal {
        var lhs = lhs, rhs = rhs, result = Decimal.zero
        guard NSDecimalDivide(&result, &lhs, &rhs, .plain) == .noError,
              let left = ExactDecimalCoefficient(lhs), let right = ExactDecimalCoefficient(rhs),
              let quotient = ExactDecimalCoefficient(result), quotient.fitsStoragePrecision,
              quotient.multiplied(by: right) == left else { return .nan }
        return result
    }
}

struct MoneyValue: DecimalDomainValue, Comparable, CustomStringConvertible, ExpressibleByIntegerLiteral {
    static let zero = MoneyValue()
    let storage: DecimalFieldStorage

    init(_ decimal: Decimal = .zero) {
        storage = decimal.isNaN ? .unresolved("NaN") : .value(decimal)
    }

    init(storage: DecimalFieldStorage) { self.storage = storage }
    init(integerLiteral value: Int) { storage = .value(Decimal(value)) }
    var description: String { wireText }
    var magnitude: MoneyValue { MoneyValue(calculationValue.magnitude) }

    static func += (lhs: inout MoneyValue, rhs: MoneyValue) { lhs = lhs + rhs }
    static func -= (lhs: inout MoneyValue, rhs: MoneyValue) { lhs = lhs - rhs }

    /// A ratio is dimensionless. Decimal division rounds a repeating quotient
    /// only for ratio comparisons; it never changes a stored currency amount.
    static func / (lhs: MoneyValue, rhs: MoneyValue) -> Decimal {
        guard rhs.isPositive else { return .nan }
        return lhs.calculationValue / rhs.calculationValue
    }

    static func < (lhs: MoneyValue, rhs: MoneyValue) -> Bool {
        lhs.storage < rhs.storage
    }

    static func + (lhs: MoneyValue, rhs: MoneyValue) -> MoneyValue {
        MoneyValue(DecimalMath.add(lhs.calculationValue, rhs.calculationValue))
    }

    static func - (lhs: MoneyValue, rhs: MoneyValue) -> MoneyValue {
        MoneyValue(DecimalMath.subtract(lhs.calculationValue, rhs.calculationValue))
    }

    static func * (lhs: MoneyValue, rhs: Decimal) -> MoneyValue {
        MoneyValue(DecimalMath.multiply(lhs.calculationValue, rhs))
    }
}

struct QuantityValue: DecimalDomainValue, Comparable, CustomStringConvertible, ExpressibleByIntegerLiteral {
    static let zero = QuantityValue()
    let storage: DecimalFieldStorage

    init(_ decimal: Decimal = .zero) {
        storage = decimal.isNaN ? .unresolved("NaN") : .value(decimal)
    }

    init(storage: DecimalFieldStorage) { self.storage = storage }
    init(integerLiteral value: Int) { storage = .value(Decimal(value)) }
    var description: String { wireText }

    var ratioFromPercent: Decimal {
        DecimalMath.divide(calculationValue, by: 100)
    }

    static func < (lhs: QuantityValue, rhs: QuantityValue) -> Bool {
        lhs.storage < rhs.storage
    }

    static func + (lhs: QuantityValue, rhs: QuantityValue) -> QuantityValue {
        QuantityValue(DecimalMath.add(lhs.calculationValue, rhs.calculationValue))
    }

    static func - (lhs: QuantityValue, rhs: QuantityValue) -> QuantityValue {
        QuantityValue(DecimalMath.subtract(lhs.calculationValue, rhs.calculationValue))
    }

    static func * (lhs: QuantityValue, rhs: QuantityValue) -> QuantityValue {
        QuantityValue(DecimalMath.multiply(lhs.calculationValue, rhs.calculationValue))
    }

    static func * (lhs: QuantityValue, rhs: MoneyValue) -> MoneyValue {
        MoneyValue(DecimalMath.multiply(lhs.calculationValue, rhs.calculationValue))
    }

    static func * (lhs: MoneyValue, rhs: QuantityValue) -> MoneyValue {
        MoneyValue(DecimalMath.multiply(lhs.calculationValue, rhs.calculationValue))
    }
}
