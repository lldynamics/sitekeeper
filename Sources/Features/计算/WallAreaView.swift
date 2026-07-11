import SwiftUI

struct WallAreaView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.wallL1) private var l1 = ""
    @AppStorage(UserPreferenceKeys.Calculator.wallL2) private var l2 = ""
    @AppStorage(UserPreferenceKeys.Calculator.wallL3) private var l3 = ""
    @AppStorage(UserPreferenceKeys.Calculator.wallL4) private var l4 = ""
    @AppStorage(UserPreferenceKeys.Calculator.wallHeight) private var height = "2.8"
    @AppStorage(UserPreferenceKeys.Calculator.wallDoors) private var doors = ""
    @AppStorage(UserPreferenceKeys.Calculator.wallWindows) private var windows = ""
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var wallLengthRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredNonNegative,
            min: 0,
            max: 10_000,
            rangeMessage: CalculatorCopy.wallLengthRange
        )
    }

    private var heightRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 1.8,
            max: 20,
            rangeMessage: CalculatorCopy.wallHeightRange
        )
    }

    private var openingAreaRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredNonNegative,
            min: 0,
            max: 5_000,
            rangeMessage: CalculatorCopy.wallOpeningRange
        )
    }

    var body: some View {
        CalculatorForm(title: CalculatorCopy.wallTool, focus: $isInputFocused) {
            Section(CalculatorCopy.wallDimensionSection) {
                CalculatorInputField(title: CalculatorCopy.wallLength1, placeholder: "0", unit: "m", text: $l1, rule: wallLengthRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused)
                CalculatorInputField(title: CalculatorCopy.wallLength2, placeholder: "0", unit: "m", text: $l2, rule: wallLengthRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused)
                CalculatorInputField(title: CalculatorCopy.wallLength3, placeholder: "0", unit: "m", text: $l3, rule: wallLengthRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused)
                CalculatorInputField(title: CalculatorCopy.wallLength4, placeholder: "0", unit: "m", text: $l4, rule: wallLengthRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused)
                CalculatorInputField(title: CalculatorCopy.wallHeight, placeholder: "2.8", unit: "m", text: $height, rule: heightRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused)
                CalculatorPresetChips(title: CalculatorCopy.wallHeightPreset, options: ["2.6", "2.8", "3.0", "3.2", "3.6"], selection: $height)
                if let wallLengthMessage {
                    CalculatorInlineNotice(message: wallLengthMessage, tone: .warning)
                }
            }
            Section(CalculatorCopy.wallOpeningSection) {
                CalculatorInputField(title: CalculatorCopy.wallDoorArea, placeholder: "0", unit: "m²", text: $doors, rule: openingAreaRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused)
                CalculatorInputField(title: CalculatorCopy.wallWindowArea, placeholder: "0", unit: "m²", text: $windows, rule: openingAreaRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused)
            }
            Section {
                CalculatorPrimaryActionButton(title: CalculatorCopy.actionCalculate) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calc()
                }
            }
            if let resultModel {
                CalculatorResultPanel(cardTitle: CalculatorCopy.wallResultTitle, result: resultModel)
            }
        }
    }

    private func calc() {
        let rawWalls = [l1, l2, l3, l4]
        let walls = rawWalls.compactMap { rawValue -> Double? in
            let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return wallLengthRule.validate(rawValue).doubleValue
        }
        guard rawWalls.allSatisfy({ rawValue in
            rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || wallLengthRule.validate(rawValue).isValid
        }), !walls.isEmpty else {
            presentError(CalculatorCopy.wallLengthRequired)
            return
        }
        guard let h = heightRule.validate(height).doubleValue else {
            presentError(CalculatorCopy.wallHeightRange)
            return
        }
        guard let d = optionalOpeningArea(doors), let w = optionalOpeningArea(windows) else {
            presentError(CalculatorCopy.wallOpeningRange)
            return
        }
        let perimeter = walls.reduce(0, +)
        let gross = perimeter * h
        let net = max(gross - d - w, 0)
        resultModel = .singleSection(
            headline: calculatorLocFormat("净面积 %@", CalculatorFormatting.squareMeters(net)),
            formula: CalculatorResultCopy.wallAreaFormula(),
            items: [
                CalculationResult.item(CalculatorResultLabel.perimeter, CalculatorFormatting.meters(perimeter, digits: 2)),
                CalculationResult.item(CalculatorResultLabel.grossArea, CalculatorFormatting.squareMeters(gross)),
                CalculationResult.item(CalculatorResultLabel.deductionArea, CalculatorFormatting.squareMeters(d + w)),
                CalculationResult.item(CalculatorResultLabel.netArea, CalculatorFormatting.squareMeters(net), status: .pass),
            ]
        )
        CalculatorHistorySupport.record(
            store: store,
            tool: CalculatorCopy.wallTool,
            input: CalculatorHistoryCopy.wallHeightInput(height),
            result: CalculatorHistoryCopy.areaResult(
                prefix: CalculatorResultLabel.netArea,
                value: net
            )
        )
    }

    private func optionalOpeningArea(_ rawValue: String) -> Double? {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        return openingAreaRule.validate(rawValue).doubleValue
    }

    private var wallLengthMessage: String? {
        let values = [l1, l2, l3, l4]
            .compactMap { CalculatorInputParser.double($0) }
            .filter { $0 > 0 }
        return values.isEmpty ? CalculatorCopy.wallLengthRequiredHint : nil
    }

    private func presentError(_ message: String) {
        resultModel = .error(message)
    }
}
