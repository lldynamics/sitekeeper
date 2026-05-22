import SwiftUI

struct RebarCalcView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.rebarDia) private var dia = "12"
    @AppStorage(UserPreferenceKeys.Calculator.rebarLen) private var len = "9"
    @AppStorage(UserPreferenceKeys.Calculator.rebarQty) private var qty = "30"
    @AppStorage(UserPreferenceKeys.Calculator.rebarPrice) private var price = ""
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var diameterRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 4,
            max: 80,
            rangeMessage: calculatorLoc("请输入 4–80")
        )
    }

    private var lengthRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.5,
            max: 100,
            rangeMessage: calculatorLoc("请输入 0.5–100")
        )
    }

    private var quantityRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 1,
            max: 100_000,
            rangeMessage: calculatorLoc("请输入 1–100000"),
            wholeNumberOnly: true,
            wholeNumberMessage: calculatorLoc("请输入整数")
        )
    }

    private var priceRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .amount,
            requirement: .optionalNonNegative,
            min: 0.1,
            max: 100_000,
            rangeMessage: calculatorLoc("请输入 0.1–100000")
        )
    }

    private var diameterValidation: NumericInputFieldValidation {
        diameterRule.validate(dia)
    }

    private var lengthValidation: NumericInputFieldValidation {
        lengthRule.validate(len)
    }

    private var quantityValidation: NumericInputFieldValidation {
        quantityRule.validate(qty)
    }

    private var priceValidation: NumericInputFieldValidation {
        priceRule.validate(price)
    }

    var body: some View {
        CalculatorForm(title: CalculatorCopy.rebarTool, focus: $isInputFocused) {
            Section(CalculatorCopy.rebarSpecSection) {
                CalculatorInputField(
                    title: CalculatorCopy.rebarDiameter,
                    placeholder: "12",
                    unit: "mm",
                    text: $dia,
                    rule: diameterRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.rebarCommonDiameter, options: ["6", "8", "10", "12", "14", "16", "20"], selection: $dia)
                CalculatorInputField(
                    title: CalculatorCopy.rebarLengthEach,
                    placeholder: "9",
                    unit: "m",
                    text: $len,
                    rule: lengthRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.rebarCommonLength, options: ["6", "9", "12"], selection: $len)
                CalculatorInputField(
                    title: CalculatorCopy.rebarQuantity,
                    placeholder: "30",
                    unit: CalculatorCopy.unitRoots,
                    text: $qty,
                    rule: quantityRule,
                    keyboardType: .numberPad,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.rebarCommonQuantity, options: ["10", "20", "30", "50", "100"], selection: $qty)
                CalculatorInputField(
                    title: CalculatorCopy.unitPrice,
                    placeholder: CalculatorCopy.optionalPlaceholder,
                    unit: CalculatorCopy.unitYuanPerKilogram,
                    text: $price,
                    rule: priceRule,
                    showWhenEmpty: false,
                    focus: $isInputFocused
                )
            }
            Section {
                CalculatorPrimaryActionButton(title: CalculatorCopy.actionEstimate) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calc()
                }
            }
            if let resultModel {
                CalculatorResultPanel(cardTitle: CalculatorCopy.rebarResultTitle, result: resultModel)
            }
        }
    }

    private func calc() {
        guard let d = diameterValidation.doubleValue,
              let l = lengthValidation.doubleValue,
              let qValue = quantityValidation.doubleValue,
              priceValidation.errorMessage == nil else {
            resultModel = nil
            return
        }
        let q = qValue.rounded(.towardZero)
        let uw = d * d / 162
        let tw = uw * l * q
        var items: [CalculationResult.ResultItem] = [
            CalculationResult.item(CalculatorResultLabel.unitWeight, CalculatorFormatting.kilogramsPerMeter(uw)),
            CalculationResult.item(CalculatorResultLabel.totalWeight, CalculatorFormatting.kilograms(tw), status: .pass),
            CalculationResult.item(CalculatorResultLabel.tonnage, CalculatorFormatting.tons(tw / 1000)),
        ]
        if let p = priceValidation.doubleValue, p > 0 {
            items.append(CalculationResult.item(CalculatorResultLabel.estimatedCost, CalculatorFormatting.yuan(tw * p)))
        }
        resultModel = .singleSection(
            headline: "\(CalculatorCopy.totalWeightPrefix) \(CalculatorFormatting.kilograms(tw))",
            formula: CalculatorResultCopy.rebarFormula(),
            items: items
        )
        CalculatorHistorySupport.record(
            store: store,
            tool: CalculatorCopy.rebarTool,
            input: CalculatorFormatting.rebarSpec(diameter: dia, length: len, quantity: qty),
            result: CalculatorHistoryCopy.weightResult(prefix: CalculatorCopy.totalWeightPrefix, value: tw)
        )
        dia = NumericInputSupport.normalizedStorageText(dia, kind: .quantity, preservingInvalid: false)
        len = NumericInputSupport.normalizedStorageText(len, kind: .quantity, preservingInvalid: false)
        qty = NumericInputSupport.normalizedStorageText(qty, kind: .quantity, preservingInvalid: false)
        price = NumericInputSupport.normalizedStorageText(price, kind: .amount, preservingInvalid: false)
    }
}
