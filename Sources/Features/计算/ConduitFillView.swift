import SwiftUI

struct ConduitFillView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.conduitInnerDia) private var conduitInnerDia = "16"
    @AppStorage(UserPreferenceKeys.Calculator.conduitWireDia) private var wireDia = "2.5"
    @AppStorage(UserPreferenceKeys.Calculator.conduitWireCount) private var wireCount = "3"
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var conduitInnerDiaRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 6,
            max: 10_000,
            rangeMessage: CalculatorCopy.conduitInnerDiameterRange
        )
    }

    private var wireDiaRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.5,
            max: 100,
            rangeMessage: CalculatorCopy.conduitWireDiameterRange
        )
    }

    private var wireCountRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 1,
            max: 500,
            rangeMessage: CalculatorCopy.conduitWireCountRange,
            wholeNumberOnly: true,
            wholeNumberMessage: CalculatorCopy.integerRequired
        )
    }

    private var conduitInnerDiaValidation: NumericInputFieldValidation {
        conduitInnerDiaRule.validate(conduitInnerDia)
    }

    private var wireDiaValidation: NumericInputFieldValidation {
        wireDiaRule.validate(wireDia)
    }

    private var wireCountValidation: NumericInputFieldValidation {
        wireCountRule.validate(wireCount)
    }

    var body: some View {
        CalculatorForm(title: CalculatorCopy.conduitTool, focus: $isInputFocused) {
            Section(CalculatorCopy.conduitParameterSection) {
                CalculatorInputField(
                    title: CalculatorCopy.conduitInnerDiameter,
                    placeholder: "16",
                    unit: "mm",
                    text: $conduitInnerDia,
                    rule: conduitInnerDiaRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.conduitCommonDiameter, options: ["16", "20", "25", "32", "40", "50"], selection: $conduitInnerDia)
                CalculatorInputField(
                    title: CalculatorCopy.conduitWireDiameter,
                    placeholder: "2.5",
                    unit: "mm",
                    text: $wireDia,
                    rule: wireDiaRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.conduitCommonWireDiameter, options: ["2.5", "4", "6", "10", "16"], selection: $wireDia)
                CalculatorInputField(
                    title: CalculatorCopy.conduitWireCount,
                    placeholder: "3",
                    unit: CalculatorCopy.unitRoots,
                    text: $wireCount,
                    rule: wireCountRule,
                    keyboardType: .numberPad,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.conduitCommonWireCount, options: ["2", "3", "4", "6", "8", "12"], selection: $wireCount)
            }
            Section(CalculatorCopy.conduitReferenceSection) {
                CalculatorInlineNotice(message: CalculatorCopy.conduitFillNotice)
            }
            Section {
                CalculatorPrimaryActionButton(title: CalculatorCopy.actionCalculate) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calc()
                }
            }
            if let resultModel {
                CalculatorResultPanel(cardTitle: CalculatorCopy.conduitResultTitle, result: resultModel)
            }
        }
    }

    private func calc() {
        guard let cd = conduitInnerDiaValidation.doubleValue,
              let wd = wireDiaValidation.doubleValue,
              let wcValue = wireCountValidation.doubleValue else {
            resultModel = nil
            return
        }
        let wc = Int(wcValue.rounded(.towardZero))
        let fillRate: Double
        switch EngineeringCalculations.conduitFillRateValidated(conduitInnerDiameter: cd, wireDiameter: wd, wireCount: wc) {
        case .success(let value):
            fillRate = value
        case .failure(let error):
            presentError(error.userMessage)
            return
        }
        let conduitArea = EngineeringCalculations.circleArea(diameter: cd)
        let wireArea = EngineeringCalculations.circleArea(diameter: wd) * Double(wc)
        let rate = fillRate * 100
        let recommended = EngineeringCalculations.recommendedConduitDiameter(wireDiameter: wd, wireCount: wc)
        let pass = rate <= 40
        resultModel = .singleSection(
            headline: CalculatorResultCopy.conduitFillHeadline(rate: rate),
            formula: CalculatorResultCopy.conduitFillFormula(),
            items: [
                CalculationResult.item(
                    CalculatorResultLabel.conduitArea,
                    CalculatorFormatting.squareMillimeters(
                        conduitArea,
                        minFractionDigits: 1,
                        maxFractionDigits: 2
                    )
                ),
                CalculationResult.item(
                    CalculatorResultLabel.wireArea,
                    CalculatorFormatting.squareMillimeters(
                        wireArea,
                        minFractionDigits: 1,
                        maxFractionDigits: 2
                    )
                ),
                CalculationResult.item(
                    CalculatorResultLabel.complianceCheck,
                    CalculatorResultCopy.conduitComplianceText(pass: pass),
                    status: pass ? .pass : .warning
                ),
                CalculationResult.item(
                    CalculatorResultLabel.recommendedConduit,
                    recommended.map {
                        CalculatorFormatting.diameterMillimeters($0, digits: 2)
                    } ?? CalculatorCopy.conduitUnsupportedSize,
                    status: pass ? .normal : .warning
                ),
            ]
        )
        CalculatorHistorySupport.record(
            store: store,
            tool: CalculatorCopy.conduitTool,
            input: CalculatorFormatting.conduitSpec(
                conduitInnerDiameter: conduitInnerDia,
                wireDiameter: wireDia,
                wireCount: wireCount
            ),
            result: CalculatorFormatting.percent(rate)
        )
        conduitInnerDia = NumericInputSupport.normalizedStorageText(conduitInnerDia, kind: .quantity, preservingInvalid: false)
        wireDia = NumericInputSupport.normalizedStorageText(wireDia, kind: .quantity, preservingInvalid: false)
        wireCount = NumericInputSupport.normalizedStorageText(wireCount, kind: .quantity, preservingInvalid: false)
    }

    private func presentError(_ message: String) {
        resultModel = .error(message)
    }
}
