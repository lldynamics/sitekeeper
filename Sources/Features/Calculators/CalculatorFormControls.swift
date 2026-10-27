import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct CalculatorNumericFieldRule {
    let kind: NumericInputKind
    let requirement: NumericInputRequirement
    let min: Double?
    let max: Double?
    let rangeMessage: String?
    let wholeNumberOnly: Bool
    let wholeNumberMessage: String?

    init(
        kind: NumericInputKind,
        requirement: NumericInputRequirement,
        min: Double? = nil,
        max: Double? = nil,
        rangeMessage: String? = nil,
        wholeNumberOnly: Bool = false,
        wholeNumberMessage: String? = nil
    ) {
        self.kind = kind
        self.requirement = requirement
        self.min = min
        self.max = max
        self.rangeMessage = rangeMessage
        self.wholeNumberOnly = wholeNumberOnly
        self.wholeNumberMessage = wholeNumberMessage
    }

    func validate(_ text: String) -> NumericInputFieldValidation {
        let base = InputValidator.validateField(
            text,
            kind: kind,
            requirement: requirement,
            min: min,
            max: max,
            rangeMessage: rangeMessage
        )

        guard wholeNumberOnly,
              base.validation.error == nil,
              base.rangeErrorMessage == nil,
              let decimal = base.decimalValue else {
            return base
        }

        let value = NSDecimalNumber(decimal: decimal).doubleValue
        guard value.rounded(.towardZero) != value else {
            return base
        }

        return NumericInputFieldValidation(
            validation: base.validation,
            rangeErrorMessage: wholeNumberMessage ?? calculatorLoc("请输入整数")
        )
    }
}

struct CalculatorValidatedNumericField: View {
    let title: String
    let placeholder: String
    let unit: String?
    let rule: CalculatorNumericFieldRule
    let keyboardType: UIKeyboardType
    let showWhenEmpty: Bool

    @Binding private var text: String
    private let focusBinding: FocusState<Bool>.Binding?

    init(
        title: String,
        placeholder: String,
        unit: String? = nil,
        text: Binding<String>,
        rule: CalculatorNumericFieldRule,
        keyboardType: UIKeyboardType = .decimalPad,
        showWhenEmpty: Bool = false,
        focus: FocusState<Bool>.Binding? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self.unit = unit
        _text = text
        self.rule = rule
        self.keyboardType = keyboardType
        self.showWhenEmpty = showWhenEmpty
        focusBinding = focus
    }

    var validation: NumericInputFieldValidation {
        rule.validate(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                HStack(spacing: 6) {
                    field
                    if let unit, !unit.isEmpty {
                        Text(unit)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            shouldShowError ? Color.appRisk.opacity(0.55) : Color.clear,
                            lineWidth: 1
                        )
                )
            } label: {
                Text(title)
            }

            NumericInputFieldValidationHint(
                validation: validation,
                showWhenEmpty: showWhenEmpty
            )
        }
    }

    private var shouldShowError: Bool {
        guard validation.errorMessage != nil else { return false }
        return showWhenEmpty || !validation.isEmpty
    }

    @ViewBuilder
    private var field: some View {
        if let focusBinding {
            TextField(placeholder, text: $text.numericInput(rule.kind))
                .keyboardType(keyboardType)
                .multilineTextAlignment(.trailing)
                .focused(focusBinding)
        } else {
            TextField(placeholder, text: $text.numericInput(rule.kind))
                .keyboardType(keyboardType)
                .multilineTextAlignment(.trailing)
        }
    }
}

typealias CalculatorInputField = CalculatorValidatedNumericField

struct CalculatorPrimaryActionButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .frame(maxWidth: .infinity)
            .fontWeight(.semibold)
    }
}

struct CalculatorInlineNotice: View {
    let message: String
    var tone: InlineNoticeTone = .info

    var body: some View {
        InlineNotice(
            title: calculatorLoc("提示"),
            message: message,
            tone: tone
        )
    }
}

struct CalculatorResultPanel: View {
    let sectionTitle: String
    let cardTitle: String
    let result: CalculationResult

    init(
        sectionTitle: String = calculatorLoc("结果"),
        cardTitle: String,
        result: CalculationResult
    ) {
        self.sectionTitle = sectionTitle
        self.cardTitle = cardTitle
        self.result = result
    }

    var body: some View {
        Section(sectionTitle) {
            CalculatorResultCard(
                title: cardTitle,
                result: result
            )
        }
    }
}

struct CalculatorForm<Content: View>: View {
    let title: String
    private let focusBinding: FocusState<Bool>.Binding?
    @ViewBuilder let content: Content

    init(
        title: String,
        focus: FocusState<Bool>.Binding? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        focusBinding = focus
        self.content = content()
    }

    var body: some View {
        Form {
            content
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .appKeyboardToolbar {
            if let focusBinding {
                KeyboardDismissToolbar {
                    focusBinding.wrappedValue = false
                }
            }
        }
    }
}

struct CalculatorPresetChips: View {
    let title: String
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.tight) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 5)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        Button(option) {
                            selection = option
                            AppHaptics.impact(.light, intensity: 0.65)
                        }
                        .font(.caption2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selection == option ? Color.appPrimaryAction : Color(uiColor: .secondarySystemGroupedBackground))
                        .foregroundStyle(selection == option ? .white : .primary)
                        .clipShape(Capsule())
                        .accessibilityLabel("\(title) \(option)")
                        .accessibilityValue(selection == option ? calculatorLoc("已选中") : calculatorLoc("未选中"))
                        .accessibilityHint(calculatorLoc("双击切换"))
                    }
                }
            }
        }
    }
}
