import SwiftUI

extension Binding where Value == String {
    func numericInput(_ kind: NumericInputKind) -> Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = NumericInputSupport.sanitize($0, kind: kind) }
        )
    }
}

struct NumericInputFieldValidation {
    let validation: NumericInputValidation
    let rangeErrorMessage: String?

    var isValid: Bool {
        errorMessage == nil
    }

    var isEmpty: Bool {
        validation.isEmpty
    }

    var decimalValue: Decimal? {
        guard isValid else { return nil }
        return validation.decimalValue
    }

    var doubleValue: Double? {
        guard let decimalValue else { return nil }
        return NSDecimalNumber(decimal: decimalValue).doubleValue
    }

    var errorMessage: String? {
        validation.errorMessage ?? rangeErrorMessage
    }
}

extension InputValidator {
    static func validateField(
        _ text: String,
        kind: NumericInputKind,
        requirement: NumericInputRequirement,
        min: Double? = nil,
        max: Double? = nil,
        rangeMessage: String? = nil
    ) -> NumericInputFieldValidation {
        let base = validate(text, kind: kind, requirement: requirement)
        guard base.error == nil,
              let decimal = base.decimalValue else {
            return NumericInputFieldValidation(validation: base, rangeErrorMessage: nil)
        }

        let value = NSDecimalNumber(decimal: decimal).doubleValue
        let lowerBoundValid = min.map { value >= $0 } ?? true
        let upperBoundValid = max.map { value <= $0 } ?? true
        let rangeError = lowerBoundValid && upperBoundValid ? nil : rangeMessage

        return NumericInputFieldValidation(validation: base, rangeErrorMessage: rangeError)
    }
}

struct NumericInputValidationHint: View {
    let validation: NumericInputValidation
    var showWhenEmpty = false
    var alignment: TextAlignment = .trailing

    var body: some View {
        if let message = validation.errorMessage,
           showWhenEmpty || validation.error != .emptyRequired {
            Text(message)
                .font(.caption2)
                .foregroundStyle(.appRisk)
                .multilineTextAlignment(alignment)
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        }
    }
}

struct NumericInputFieldValidationHint: View {
    let validation: NumericInputFieldValidation
    var showWhenEmpty = false
    var alignment: TextAlignment = .trailing

    var body: some View {
        if let message = validation.errorMessage,
           showWhenEmpty || validation.validation.error != .emptyRequired {
            Text(message)
                .font(.caption2)
                .foregroundStyle(.appRisk)
                .multilineTextAlignment(alignment)
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        }
    }
}
