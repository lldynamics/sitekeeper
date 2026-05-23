import Foundation

enum UnitDisplay {
    static func quantityWithUnit(_ quantity: String, unit: String, useMetric: Bool) -> String {
        guard !useMetric else { return "\(quantity) \(unit)" }
        guard let numericDecimal = DataValueParser.decimalValueIfPresent(from: quantity, requiresEntireString: true) else {
            return "\(quantity) \(translatedUnit(unit, useMetric: useMetric))"
        }
        let numeric = NSDecimalNumber(decimal: numericDecimal).doubleValue
        guard let converted = convert(value: numeric, from: unit) else {
            return "\(quantity) \(translatedUnit(unit, useMetric: useMetric))"
        }
        return "\(trim(converted.value)) \(converted.unit)"
    }

    static func translatedUnit(_ unit: String, useMetric: Bool) -> String {
        guard !useMetric else { return unit }
        if unit == "h" { return "hr" }
        return convert(value: 1, from: unit)?.unit ?? unit
    }

    private static func convert(value: Double, from unit: String) -> (value: Double, unit: String)? {
        switch unit {
        case "米", "m":
            return (value * 3.28084, "ft")
        case "厘米", "cm":
            return (value * 0.393701, "in")
        case "毫米", "mm":
            return (value * 0.0393701, "in")
        case "平方米", "m²":
            return (value * 10.7639, "ft²")
        case "立方米", "m³":
            return (value * 35.3147, "ft³")
        case "千克", "公斤", "kg":
            return (value * 2.20462, "lb")
        case "吨", "t":
            return (value * 1.10231, "ton")
        default:
            return nil
        }
    }

    private static func trim(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

enum InputValidator {
    static func nonNegativeNumber(_ text: String) -> Bool {
        guard let value = DataValueParser.decimalValueIfPresent(from: text, requiresEntireString: true) else {
            return false
        }
        return value >= .zero
    }

    static func validate(
        _ text: String,
        kind: NumericInputKind,
        requirement: NumericInputRequirement
    ) -> NumericInputValidation {
        NumericInputSupport.validate(text, kind: kind, requirement: requirement)
    }
}
