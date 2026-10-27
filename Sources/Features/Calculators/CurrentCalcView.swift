import SwiftUI

struct CurrentCalcView: View {
    @State private var power: String = ""
    @State private var voltage: String = "220"
    @State private var powerFactor: String = "0.85"
    @State private var isThreePhase: Bool = false

    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var powerRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.1,
            max: 5_000_000,
            rangeMessage: CalculatorCopy.currentPowerRange
        )
    }

    private var voltageRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 12,
            max: 100_000,
            rangeMessage: CalculatorCopy.currentVoltageRange
        )
    }

    private var powerFactorRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.01,
            max: 1,
            rangeMessage: CalculatorCopy.currentPowerFactorRange
        )
    }

    private var powerValidation: NumericInputFieldValidation {
        powerRule.validate(power)
    }

    private var voltageValidation: NumericInputFieldValidation {
        voltageRule.validate(voltage)
    }

    private var powerFactorValidation: NumericInputFieldValidation {
        powerFactorRule.validate(powerFactor)
    }

    var body: some View {
        CalculatorForm(title: CalculatorCopy.currentTool, focus: $isInputFocused) {
            Section(CalculatorCopy.currentInputSection) {
                CalculatorInputField(
                    title: CalculatorCopy.currentPower,
                    placeholder: CalculatorCopy.currentPowerPlaceholder,
                    unit: "kW",
                    text: $power,
                    rule: powerRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.currentCommonPower, options: ["3", "5", "10", "20", "30", "50"], selection: $power)
                CalculatorInputField(
                    title: CalculatorCopy.currentVoltage,
                    placeholder: "220",
                    unit: "V",
                    text: $voltage,
                    rule: voltageRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.currentVoltagePreset, options: ["220", "380"], selection: $voltage)
                CalculatorInputField(
                    title: CalculatorCopy.currentPowerFactor,
                    placeholder: "0.85",
                    text: $powerFactor,
                    rule: powerFactorRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.currentPowerFactorPreset, options: ["0.80", "0.85", "0.90", "0.95"], selection: $powerFactor)
                Toggle(CalculatorCopy.currentThreePhase, isOn: $isThreePhase)
            }

            Section(CalculatorCopy.currentFormulaSection) {
                CalculatorInlineNotice(
                    message: CalculatorResultCopy.currentFormulaNote(isThreePhase: isThreePhase)
                )
            }

            Section {
                CalculatorPrimaryActionButton(title: CalculatorCopy.actionCalculate) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calc()
                }
            }

            if let resultModel {
                CalculatorResultPanel(
                    sectionTitle: CalculatorCopy.resultSection,
                    cardTitle: CalculatorCopy.currentResultTitle,
                    result: resultModel
                )
            }
        }
        .onChange(of: isThreePhase) { _, enabled in
            voltage = enabled ? "380" : "220"
        }
    }

    private func calc() {
        guard let p = powerValidation.doubleValue,
              let v = voltageValidation.doubleValue,
              let pf = powerFactorValidation.doubleValue else {
            presentError(CalculatorCopy.currentInvalidNumber)
            return
        }
        let current: Double
        switch EngineeringCalculations.circuitCurrentValidated(
            powerKW: p,
            voltage: v,
            powerFactor: pf,
            isThreePhase: isThreePhase
        ) {
        case .success(let value):
            current = value
        case .failure(let error):
            presentError(error.userMessage)
            return
        }
        let warning = current > 100
        resultModel = .singleSection(
            headline: CalculatorResultCopy.currentHeadline(current),
            formula: CalculatorResultCopy.currentFormula(isThreePhase: isThreePhase),
            items: [
                CalculationResult.item(
                    CalculatorResultLabel.power,
                    CalculatorFormatting.kilowatts(p, digits: 2)
                ),
                CalculationResult.item(
                    CalculatorResultLabel.voltage,
                    CalculatorResultCopy.currentVoltageDisplay(voltage: v, isThreePhase: isThreePhase)
                ),
                CalculationResult.item(
                    CalculatorResultLabel.powerFactor,
                    CalculatorFormatting.fixed(pf, digits: 2)
                ),
                CalculationResult.item(
                    CalculatorResultLabel.currentResult,
                    CalculatorFormatting.amperes(current, digits: 2),
                    status: warning ? .warning : .pass
                ),
            ]
        )
        resultModel?.historyDraft = .init(
            tool: CalculatorCopy.currentTool,
            input: CalculatorHistoryCopy.currentInput(power: power, voltage: voltage),
            result: CalculatorFormatting.amperes(current, digits: 2)
        )
    }

    private func presentError(_ message: String) {
        resultModel = .error(message)
    }
}
