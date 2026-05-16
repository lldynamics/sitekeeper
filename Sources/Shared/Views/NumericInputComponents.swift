import SwiftUI

extension Binding where Value == String {
    func numericInput(_ kind: NumericInputKind) -> Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = NumericInputSupport.sanitize($0, kind: kind) }
        )
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
