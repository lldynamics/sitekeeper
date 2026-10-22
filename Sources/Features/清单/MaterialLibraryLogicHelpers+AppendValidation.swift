import Foundation

extension MaterialLibraryLogicHelpers {
    static func appendQuantityValidation(_ text: String) -> NumericInputValidation {
        let validation = NumericInputSupport.validate(text, kind: .quantity, requirement: .requiredPositive)
        let normalized = NumericInputSupport.normalizeSeparators(in: text).filter { !$0.isWhitespace }
        guard validation.isValid,
              DataValueParser.decimalValueIfPresent(from: normalized, requiresEntireString: true) == nil else {
            return validation
        }
        return NumericInputValidation(
            kind: .quantity,
            requirement: .requiredPositive,
            rawText: text,
            sanitizedText: normalized,
            decimalValue: nil,
            error: .invalidFormat
        )
    }
}
