import Foundation

enum NumericInputKind: CaseIterable {
    case amount
    case quantity
    case days
    case taxRate
    case discountRate
    case laborRate

    var fieldName: String {
        switch self {
        case .amount:
            return String(localized: "金额")
        case .quantity:
            return String(localized: "数量")
        case .days:
            return String(localized: "天数")
        case .taxRate:
            return String(localized: "税率")
        case .discountRate:
            return String(localized: "折扣")
        case .laborRate:
            return String(localized: "人工费")
        }
    }

    var maximumFractionDigits: Int {
        switch self {
        case .amount, .laborRate:
            return 2
        case .taxRate, .discountRate:
            return 3
        case .quantity, .days:
            return 4
        }
    }
}

enum NumericInputRequirement {
    case requiredNonNegative
    case optionalNonNegative
    case requiredPositive

    var allowsEmpty: Bool {
        switch self {
        case .optionalNonNegative:
            return true
        case .requiredNonNegative, .requiredPositive:
            return false
        }
    }

    var requiresPositive: Bool {
        self == .requiredPositive
    }
}

struct NumericInputValidation {
    enum ErrorKind: Equatable {
        case emptyRequired
        case invalidFormat
        case negativeNotAllowed
        case notPositive
    }

    let kind: NumericInputKind
    let requirement: NumericInputRequirement
    let rawText: String
    let sanitizedText: String
    let decimalValue: Decimal?
    let error: ErrorKind?

    var isValid: Bool {
        error == nil
    }

    var isEmpty: Bool {
        sanitizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var errorMessage: String? {
        guard let error else { return nil }
        switch error {
        case .emptyRequired:
            return String(format: String(localized: "请输入%@"), kind.fieldName)
        case .invalidFormat:
            return String(format: String(localized: "%@格式不正确"), kind.fieldName)
        case .negativeNotAllowed:
            return String(format: String(localized: "%@不能为负数"), kind.fieldName)
        case .notPositive:
            return String(format: String(localized: "%@必须大于0"), kind.fieldName)
        }
    }
}

enum NumericInputSupport {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    static func sanitize(_ text: String, kind _: NumericInputKind) -> String {
        let normalizedSeparators = normalizeSeparators(in: text)
        var result = ""
        var didConsumePrefix = false
        var signCaptured = false

        for char in normalizedSeparators {
            if char.isWhitespace { continue }

            if (char == "-" || char == "+"), !didConsumePrefix, !signCaptured {
                result.append(char)
                signCaptured = true
                didConsumePrefix = true
                continue
            }

            didConsumePrefix = true

            if char.isNumber || char == "." || char == "," {
                result.append(char)
            }
        }

        return result
    }

    static func validate(
        _ text: String,
        kind: NumericInputKind,
        requirement: NumericInputRequirement = .requiredNonNegative
    ) -> NumericInputValidation {
        let sanitized = sanitize(text, kind: kind)
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            if requirement.allowsEmpty {
                return NumericInputValidation(
                    kind: kind,
                    requirement: requirement,
                    rawText: text,
                    sanitizedText: sanitized,
                    decimalValue: nil,
                    error: nil
                )
            }
            return NumericInputValidation(
                kind: kind,
                requirement: requirement,
                rawText: text,
                sanitizedText: sanitized,
                decimalValue: nil,
                error: .emptyRequired
            )
        }

        guard let decimal = DataValueParser.decimalValueIfPresent(
            from: trimmed,
            requiresEntireString: true
        ) else {
            return NumericInputValidation(
                kind: kind,
                requirement: requirement,
                rawText: text,
                sanitizedText: sanitized,
                decimalValue: nil,
                error: .invalidFormat
            )
        }

        if decimal < .zero {
            return NumericInputValidation(
                kind: kind,
                requirement: requirement,
                rawText: text,
                sanitizedText: sanitized,
                decimalValue: decimal,
                error: .negativeNotAllowed
            )
        }

        if requirement.requiresPositive, decimal <= .zero {
            return NumericInputValidation(
                kind: kind,
                requirement: requirement,
                rawText: text,
                sanitizedText: sanitized,
                decimalValue: decimal,
                error: .notPositive
            )
        }

        return NumericInputValidation(
            kind: kind,
            requirement: requirement,
            rawText: text,
            sanitizedText: sanitized,
            decimalValue: decimal,
            error: nil
        )
    }

    static func decimalValueIfPresent(_ text: String, kind: NumericInputKind) -> Decimal? {
        let validation = validate(text, kind: kind, requirement: .optionalNonNegative)
        return validation.decimalValue
    }

    static func normalizedStorageText(
        _ text: String,
        kind: NumericInputKind,
        preservingInvalid: Bool = true
    ) -> String {
        let validation = validate(text, kind: kind, requirement: .optionalNonNegative)
        if let decimal = validation.decimalValue {
            return format(decimal, kind: kind)
        }
        let trimmed = validation.sanitizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return preservingInvalid ? trimmed : ""
    }

    static func firstNumberString(in text: String, kind: NumericInputKind, defaultValue: String = "") -> String {
        let normalizedSeparators = normalizeSeparators(in: text)
        guard let decimal = DataValueParser.decimalValueIfPresent(
            from: normalizedSeparators,
            requiresEntireString: false
        ) else {
            return defaultValue
        }
        return format(decimal, kind: kind)
    }

    static func splitNumberAndUnit(
        in text: String,
        kind: NumericInputKind,
        defaultNumber: String = "1",
        defaultUnit: String = "个"
    ) -> (number: String, unit: String) {
        let normalized = normalizeSeparators(in: text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let numberRange = normalized.range(
            of: #"[-+]?[0-9][0-9,.]*"#,
            options: .regularExpression
        ) else {
            let compactUnit = normalized.replacingOccurrences(of: " ", with: "")
            return (defaultNumber, compactUnit.isEmpty ? defaultUnit : compactUnit)
        }

        let numberToken = String(normalized[numberRange])
        let numberValue = firstNumberString(in: numberToken, kind: kind, defaultValue: defaultNumber)

        let prefix = String(normalized[..<numberRange.lowerBound])
        let suffix = String(normalized[numberRange.upperBound...])
        let unit = (prefix + suffix)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")

        return (numberValue.isEmpty ? defaultNumber : numberValue, unit.isEmpty ? defaultUnit : unit)
    }

    static func parseMaterialTemplateLine(
        _ line: String,
        defaultNumber: String = "1",
        defaultUnit: String = "个"
    ) -> (name: String, quantity: String, unit: String) {
        let normalized = normalizeTemplateText(line)
        guard !normalized.isEmpty else {
            return ("", defaultNumber, defaultUnit)
        }

        if let separatorRange = normalized.range(of: #"[×xX＊*✕✖]"#, options: .regularExpression) {
            let rawName = String(normalized[..<separatorRange.lowerBound])
            let quantityChunk = String(normalized[separatorRange.upperBound...])
            let parsed = splitNumberAndUnit(
                in: quantityChunk,
                kind: .quantity,
                defaultNumber: defaultNumber,
                defaultUnit: defaultUnit
            )
            return (
                normalizeTemplateName(rawName),
                parsed.number,
                normalizeTemplateUnit(parsed.unit, defaultUnit: defaultUnit)
            )
        }

        guard let numberRange = normalized.range(of: #"[-+]?[0-9][0-9,.]*"#, options: .regularExpression) else {
            return (normalizeTemplateName(normalized), defaultNumber, defaultUnit)
        }

        let rawName = String(normalized[..<numberRange.lowerBound])
        let quantityChunk = String(normalized[numberRange.lowerBound...])
        let parsed = splitNumberAndUnit(
            in: quantityChunk,
            kind: .quantity,
            defaultNumber: defaultNumber,
            defaultUnit: defaultUnit
        )
        return (
            normalizeTemplateName(rawName),
            parsed.number,
            normalizeTemplateUnit(parsed.unit, defaultUnit: defaultUnit)
        )
    }

    static func parseQuotationTemplateLine(
        _ line: String,
        defaultPrice: String = "0"
    ) -> (name: String, price: String, unit: String?) {
        let normalized = normalizeTemplateText(line)
        guard !normalized.isEmpty else {
            return ("", defaultPrice, nil)
        }

        let scoped = splitQuotationTemplateScope(normalized)
        let price = firstNumberString(in: scoped.amountChunk, kind: .amount, defaultValue: defaultPrice)
        let unit = extractQuotationUnit(from: scoped.amountChunk)
        return (normalizeTemplateName(scoped.nameChunk), price, unit)
    }

    static func format(_ decimal: Decimal, kind: NumericInputKind) -> String {
        let formatter = NumberFormatter()
        formatter.locale = posixLocale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = kind.maximumFractionDigits
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? NSDecimalNumber(decimal: decimal).stringValue
    }

    private static func normalizeSeparators(in text: String) -> String {
        text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "．", with: ".")
    }

    private static func normalizeTemplateText(_ text: String) -> String {
        normalizeSeparators(in: text)
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeTemplateName(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[：:;\-–—·•|]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(单价|价格|金额|报价)$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeTemplateUnit(_ text: String, defaultUnit: String) -> String {
        let compact = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        let stripped = compact.replacingOccurrences(
            of: #"^(数量|qty|Qty|QTY|约|大约|约为|每|\/|:|：|=|≈|~)+"#,
            with: "",
            options: .regularExpression
        )
        return stripped.isEmpty ? defaultUnit : stripped
    }

    private static func splitQuotationTemplateScope(_ line: String) -> (nameChunk: String, amountChunk: String) {
        if let currencyRange = line.range(of: #"[¥￥]"#, options: .regularExpression) {
            return (
                String(line[..<currencyRange.lowerBound]),
                String(line[currencyRange.upperBound...])
            )
        }

        for keyword in ["单价", "价格"] {
            if let keywordRange = line.range(of: keyword) {
                return (
                    String(line[..<keywordRange.lowerBound]),
                    String(line[keywordRange.upperBound...])
                )
            }
        }

        if let colonRange = line.range(of: #"[：:]"#, options: .regularExpression) {
            let rhs = String(line[colonRange.upperBound...])
            if DataValueParser.decimalValueIfPresent(from: rhs, requiresEntireString: false) != nil {
                return (
                    String(line[..<colonRange.lowerBound]),
                    rhs
                )
            }
        }

        if let firstNumberRange = line.range(of: #"[-+]?[0-9][0-9,.]*"#, options: .regularExpression) {
            return (
                String(line[..<firstNumberRange.lowerBound]),
                String(line[firstNumberRange.lowerBound...])
            )
        }

        return (line, line)
    }

    private static func extractQuotationUnit(from amountChunk: String) -> String? {
        let normalized = normalizeTemplateText(amountChunk)
        guard let numberRange = normalized.range(of: #"[-+]?[0-9][0-9,.]*"#, options: .regularExpression) else {
            return nil
        }

        var unit = String(normalized[numberRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        unit = unit.replacingOccurrences(
            of: #"^(元|人民币|RMB|CNY|￥|¥)+"#,
            with: "",
            options: .regularExpression
        )
        unit = unit.replacingOccurrences(
            of: #"^(\/|每|per)+"#,
            with: "",
            options: .regularExpression
        )
        unit = unit.replacingOccurrences(of: " ", with: "")
        return unit.isEmpty ? nil : unit
    }
}
