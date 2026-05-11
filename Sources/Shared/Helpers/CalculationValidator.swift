import Foundation

enum CalculationError: LocalizedError, Equatable {
    case invalidNumber(field: String)
    case notFinite(field: String)
    case mustBeNonNegative(field: String)
    case mustBeGreaterThanZero(field: String)
    case outOfRange(field: String, min: Double, max: Double)
    case countOutOfRange(field: String, min: Int, max: Int)

    var userMessage: String {
        switch self {
        case .invalidNumber(let field):
            return "\(field) 不是有效数字"
        case .notFinite(let field):
            return "\(field) 数值异常，请检查输入"
        case .mustBeNonNegative(let field):
            return "\(field) 不能小于 0"
        case .mustBeGreaterThanZero(let field):
            return "\(field) 必须大于 0"
        case .outOfRange(let field, let min, let max):
            return "\(field) 超出范围（\(Self.display(min)) - \(Self.display(max))）"
        case .countOutOfRange(let field, let min, let max):
            return "\(field) 超出范围（\(min) - \(max)）"
        }
    }

    var errorDescription: String? { userMessage }

    private static func display(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}

enum CalculationValidator {
    static func positive(_ value: Double, field: String, max: Double? = nil) -> Result<Double, CalculationError> {
        guard value.isFinite else { return .failure(.notFinite(field: field)) }
        guard value > 0 else { return .failure(.mustBeGreaterThanZero(field: field)) }
        if let max, value > max {
            return .failure(.outOfRange(field: field, min: 0, max: max))
        }
        return .success(value)
    }

    static func nonNegative(_ value: Double, field: String, max: Double? = nil) -> Result<Double, CalculationError> {
        guard value.isFinite else { return .failure(.notFinite(field: field)) }
        guard value >= 0 else { return .failure(.mustBeNonNegative(field: field)) }
        if let max, value > max {
            return .failure(.outOfRange(field: field, min: 0, max: max))
        }
        return .success(value)
    }

    static func within(
        _ value: Double,
        field: String,
        min: Double,
        max: Double,
        includeMin: Bool = true,
        includeMax: Bool = true
    ) -> Result<Double, CalculationError> {
        guard value.isFinite else { return .failure(.notFinite(field: field)) }
        let minValid = includeMin ? value >= min : value > min
        let maxValid = includeMax ? value <= max : value < max
        guard minValid, maxValid else {
            return .failure(.outOfRange(field: field, min: min, max: max))
        }
        return .success(value)
    }

    static func positiveCount(_ value: Int, field: String, max: Int) -> Result<Int, CalculationError> {
        guard value > 0, value <= max else {
            return .failure(.countOutOfRange(field: field, min: 1, max: max))
        }
        return .success(value)
    }
}
