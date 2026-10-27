import Foundation

/// Exact base-ten coefficients verify Foundation arithmetic without rounding.
/// This is a bounded verifier (Decimal operands have at most 128-bit mantissas),
/// not an alternative numeric storage format.
struct ExactDecimalCoefficient: Equatable {
    private let negative: Bool
    private let digits: [Int]
    private let exponent: Int

    init?(_ value: Decimal) {
        guard !value.isNaN else { return nil }
        let text = NSDecimalNumber(decimal: value).stringValue.lowercased()
        let parts = text.split(separator: "e")
        let coefficient = String(parts[0])
        let fractionCount = coefficient.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
        self.init(negative: coefficient.hasPrefix("-"),
                  digits: coefficient.compactMap(\.wholeNumberValue),
                  exponent: (parts.count == 2 ? Int(parts[1]) ?? 0 : 0) - fractionCount)
    }

    private init(negative: Bool, digits: [Int], exponent: Int) {
        var normalized = Array(digits.drop(while: { $0 == 0 }))
        var power = exponent
        while normalized.last == 0 { normalized.removeLast()
        power += 1 }
        self.digits = normalized.isEmpty ? [0] : normalized
        self.negative = !normalized.isEmpty && negative
        self.exponent = normalized.isEmpty ? 0 : power
    }

    var fitsStoragePrecision: Bool { digits.count <= 38 }

    func adding(_ other: Self, subtract: Bool = false) -> Self {
        let power = min(exponent, other.exponent)
        let left = Array((digits + Array(repeating: 0, count: exponent - power)).drop(while: { $0 == 0 }))
        let right = Array((other.digits + Array(repeating: 0, count: other.exponent - power)).drop(while: { $0 == 0 }))
        let rightNegative = other.negative != subtract
        if negative == rightNegative {
            return Self(negative: negative, digits: Self.add(left, right), exponent: power)
        }
        let leftIsLarger = left.count != right.count ? left.count > right.count : right.lexicographicallyPrecedes(left)
        return Self(negative: leftIsLarger ? negative : rightNegative,
                    digits: Self.subtract(leftIsLarger ? left : right, leftIsLarger ? right : left), exponent: power)
    }

    func multiplied(by other: Self) -> Self {
        var result = Array(repeating: 0, count: digits.count + other.digits.count)
        for left in digits.indices.reversed() {
            for right in other.digits.indices.reversed() {
                let index = left + right + 1
                let sum = result[index] + digits[left] * other.digits[right]
                result[index] = sum % 10
                result[index - 1] += sum / 10
            }
        }
        return Self(negative: negative != other.negative, digits: result, exponent: exponent + other.exponent)
    }

    private static func add(_ lhs: [Int], _ rhs: [Int]) -> [Int] {
        let left = Array(lhs.reversed()), right = Array(rhs.reversed())
        var result: [Int] = [], carry = 0
        for index in 0..<max(left.count, right.count) {
            let sum = (index < left.count ? left[index] : 0) + (index < right.count ? right[index] : 0) + carry
            result.append(sum % 10)
            carry = sum / 10
        }
        if carry > 0 { result.append(carry) }
        return result.reversed()
    }

    /// The larger absolute coefficient is passed first.
    private static func subtract(_ lhs: [Int], _ rhs: [Int]) -> [Int] {
        let left = Array(lhs.reversed()), right = Array(rhs.reversed())
        var result: [Int] = [], borrow = 0
        for index in left.indices {
            let difference = left[index] - (index < right.count ? right[index] : 0) - borrow
            result.append(difference < 0 ? difference + 10 : difference)
            borrow = difference < 0 ? 1 : 0
        }
        return result.reversed()
    }
}
