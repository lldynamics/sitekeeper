import Foundation

func calculatorLoc(_ key: String) -> String {
    String(localized: String.LocalizationValue(stringLiteral: key))
}

func calculatorLocFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: calculatorLoc(key), locale: Locale.current, arguments: arguments)
}

enum CalculatorFormatting {
    static func decimal(
        _ value: Double,
        minFractionDigits: Int = 0,
        maxFractionDigits: Int = 3
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.minimumFractionDigits = minFractionDigits
        formatter.maximumFractionDigits = maxFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func fixed(_ value: Double, digits: Int) -> String {
        decimal(
            value,
            minFractionDigits: digits,
            maxFractionDigits: digits
        )
    }

    static func section(_ value: Double) -> String {
        decimal(
            value,
            minFractionDigits: 0,
            maxFractionDigits: value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1
        )
    }

    static func amperes(_ value: Double, digits: Int = 1) -> String {
        calculatorLocFormat("%@ A", fixed(value, digits: digits))
    }

    static func volts(_ value: Double, digits: Int = 0) -> String {
        calculatorLocFormat("%@ V", fixed(value, digits: digits))
    }

    static func ohms(_ value: Double, digits: Int = 3) -> String {
        calculatorLocFormat("%@ Ω", fixed(value, digits: digits))
    }

    static func meters(_ value: Double, digits: Int = 1) -> String {
        calculatorLocFormat("%@ m", fixed(value, digits: digits))
    }

    static func squareMeters(
        _ value: Double,
        minFractionDigits: Int = 0,
        maxFractionDigits: Int = 2
    ) -> String {
        calculatorLocFormat(
            "%@ m²",
            decimal(
                value,
                minFractionDigits: minFractionDigits,
                maxFractionDigits: maxFractionDigits
            )
        )
    }

    static func cubicMeters(
        _ value: Double,
        minFractionDigits: Int = 0,
        maxFractionDigits: Int = 3
    ) -> String {
        calculatorLocFormat(
            "%@ m³",
            decimal(
                value,
                minFractionDigits: minFractionDigits,
                maxFractionDigits: maxFractionDigits
            )
        )
    }

    static func squareMillimeters(
        _ value: Double,
        minFractionDigits: Int = 1,
        maxFractionDigits: Int = 2
    ) -> String {
        calculatorLocFormat(
            "%@ mm²",
            decimal(
                value,
                minFractionDigits: minFractionDigits,
                maxFractionDigits: maxFractionDigits
            )
        )
    }

    static func kilowatts(_ value: Double, digits: Int = 2) -> String {
        calculatorLocFormat("%@ kW", fixed(value, digits: digits))
    }

    static func kilogramsPerMeter(_ value: Double, digits: Int = 3) -> String {
        calculatorLocFormat(
            "%@ kg/m",
            decimal(value, minFractionDigits: 0, maxFractionDigits: digits)
        )
    }

    static func kilograms(_ value: Double, digits: Int = 3) -> String {
        calculatorLocFormat(
            "%@ kg",
            decimal(value, minFractionDigits: 0, maxFractionDigits: digits)
        )
    }

    static func tons(_ value: Double, digits: Int = 3) -> String {
        calculatorLocFormat(
            "%@ t",
            decimal(value, minFractionDigits: 0, maxFractionDigits: digits)
        )
    }

    static func percent(_ value: Double, digits: Int = 2) -> String {
        calculatorLocFormat(
            "%@%%",
            decimal(
                value,
                minFractionDigits: digits == 0 ? 0 : 1,
                maxFractionDigits: digits
            )
        )
    }

    static func pieces(_ value: Int) -> String {
        calculatorLocFormat("%lld 片", Int64(value))
    }

    static func packages(_ value: Int) -> String {
        calculatorLocFormat("%lld 箱", Int64(value))
    }

    static func bags(_ value: Int) -> String {
        calculatorLocFormat("%lld 袋", Int64(value))
    }

    static func yuan(_ value: Double, digits: Int = 2) -> String {
        calculatorLocFormat(
            "%@ 元",
            decimal(value, minFractionDigits: 0, maxFractionDigits: digits)
        )
    }

    static func valueWithUnit(
        _ value: Double,
        unit: String,
        minFractionDigits: Int = 0,
        maxFractionDigits: Int = 6
    ) -> String {
        calculatorLocFormat(
            "%@ %@",
            decimal(
                value,
                minFractionDigits: minFractionDigits,
                maxFractionDigits: maxFractionDigits
            ),
            unit
        )
    }

    static func valueWithUnitString(_ value: String, unit: String) -> String {
        calculatorLocFormat("%@ %@", value, unit)
    }

    static func diameterMillimeters(
        _ value: Double,
        digits: Int = 1
    ) -> String {
        calculatorLocFormat(
            "Φ%@ mm",
            decimal(value, minFractionDigits: 0, maxFractionDigits: digits)
        )
    }

    static func traySizeMillimeters(
        width: Double,
        height: Double,
        digits: Int = 1
    ) -> String {
        calculatorLocFormat(
            "%@ × %@ mm",
            decimal(width, minFractionDigits: 0, maxFractionDigits: digits),
            decimal(height, minFractionDigits: 0, maxFractionDigits: digits)
        )
    }

    static func rebarSpec(
        diameter: String,
        length: String,
        quantity: String
    ) -> String {
        calculatorLocFormat("Φ%@ mm, %@ m × %@ 根", diameter, length, quantity)
    }

    static func conduitSpec(
        conduitInnerDiameter: String,
        wireDiameter: String,
        wireCount: String
    ) -> String {
        calculatorLocFormat(
            "%@, %@ × %@ 根",
            diameterMillimetersText(conduitInnerDiameter),
            diameterMillimetersText(wireDiameter),
            wireCount
        )
    }

    static func traySpec(
        width: String,
        height: String,
        cableTypes: Int
    ) -> String {
        calculatorLocFormat("%@ × %@ mm, %lld 种电缆", width, height, Int64(cableTypes))
    }

    static func cableSpec(
        diameter: Double,
        count: Int
    ) -> String {
        calculatorLocFormat(
            "%@ × %lld 根",
            diameterMillimeters(diameter, digits: 0),
            Int64(count)
        )
    }

    static func diameterMillimetersText(_ value: String) -> String {
        calculatorLocFormat("Φ%@ mm", value)
    }
}
