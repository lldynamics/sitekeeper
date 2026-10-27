import Foundation

enum UnitDisplay {
    static func quantityWithUnit(_ quantity: QuantityValue, unit: String, useMetric: Bool) -> String {
        guard !useMetric, let conversion = conversion(from: unit), let number = quantity.optionalDecimal else {
            return "\(quantity) \(translatedUnit(unit, useMetric: useMetric))"
        }
        let converted = DecimalMath.multiply(number, conversion.factor)
        return "\(converted.formatted(.number.grouping(.never).precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX")))) \(conversion.unit)"
    }

    static func translatedUnit(_ unit: String, useMetric: Bool) -> String {
        guard !useMetric else { return unit }
        if unit == "h" { return "hr" }
        return conversion(from: unit)?.unit ?? unit
    }

    /// Unit-price conversion is a display operation; a repeating quotient is
    /// rounded at Decimal precision here, while stored prices remain exact.
    static func displayedUnitPrice(_ price: MoneyValue, unit: String, useMetric: Bool) -> MoneyValue {
        guard !useMetric, let conversion = conversion(from: unit), var source = price.optionalDecimal else { return price }
        var factor = conversion.factor
        var result = Decimal.zero
        let error = NSDecimalDivide(&result, &source, &factor, .plain)
        guard error == .noError || error == .lossOfPrecision else { return MoneyValue(.nan) }
        return MoneyValue(result)
    }

    private static func conversion(from unit: String) -> (factor: Decimal, unit: String)? {
        let values: (String, String)
        switch unit {
        case "米", "m": values = ("3.28084", "ft")
        case "厘米", "cm": values = ("0.393701", "in")
        case "毫米", "mm": values = ("0.0393701", "in")
        case "平方米", "m²": values = ("10.7639", "ft²")
        case "立方米", "m³": values = ("35.3147", "ft³")
        case "千克", "公斤", "kg": values = ("2.20462", "lb")
        case "吨", "t": values = ("1.10231", "ton")
        default: return nil
        }
        guard let factor = Decimal(string: values.0, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return (factor, values.1)
    }
}

enum InputValidator {
    static func nonNegativeNumber<Value: DecimalDomainValue>(_ value: Value) -> Bool {
        value.optionalDecimal.map { $0 >= .zero } ?? false
    }

    static func validate<Value: DecimalDomainValue>(
        _ value: Value, kind: NumericInputKind, requirement: NumericInputRequirement
    ) -> NumericInputValidation {
        NumericInputSupport.validate(value, kind: kind, requirement: requirement)
    }

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
