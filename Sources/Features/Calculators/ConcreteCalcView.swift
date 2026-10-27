import SwiftUI

struct ConcreteCalcView: View {
    @State private var length = "10"
    @State private var width = "8"
    @State private var thickness = "12"
    @State private var waste = "5"
    @State private var gradeRawValue = ConcreteGrade.c25.rawValue
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var grade: ConcreteGrade {
        StringEnumFallback.value(gradeRawValue, default: ConcreteGrade.c25)
    }

    private var lengthValidation: NumericInputFieldValidation {
        InputValidator.validateField(
            length,
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.1,
            max: 10_000,
            rangeMessage: CalculatorCopy.concreteLengthRange
        )
    }

    private var widthValidation: NumericInputFieldValidation {
        InputValidator.validateField(
            width,
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.1,
            max: 10_000,
            rangeMessage: CalculatorCopy.concreteLengthRange
        )
    }

    private var thicknessValidation: NumericInputFieldValidation {
        InputValidator.validateField(
            thickness,
            kind: .quantity,
            requirement: .requiredPositive,
            min: 1,
            max: 200,
            rangeMessage: CalculatorCopy.concreteThicknessRange
        )
    }

    private var wasteValidation: NumericInputFieldValidation {
        InputValidator.validateField(
            waste,
            kind: .quantity,
            requirement: .requiredNonNegative,
            min: 0,
            max: 40,
            rangeMessage: CalculatorCopy.concreteWasteRange
        )
    }

    var body: some View {
        CalculatorForm(title: CalculatorCopy.concreteTool, focus: $isInputFocused) {
            Section(CalculatorCopy.concreteDimensionSection) {
                CalculatorInputField(
                    title: CalculatorCopy.concreteLength,
                    placeholder: "10",
                    unit: "m",
                    text: $length,
                    rule: CalculatorNumericFieldRule(
                        kind: .quantity,
                        requirement: .requiredPositive,
                        min: 0.1,
                        max: 10_000,
                        rangeMessage: CalculatorCopy.concreteLengthRange
                    ),
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.lengthPreset, options: ["6", "8", "10", "12", "15"], selection: $length)
                CalculatorInputField(
                    title: CalculatorCopy.concreteWidth,
                    placeholder: "8",
                    unit: "m",
                    text: $width,
                    rule: CalculatorNumericFieldRule(
                        kind: .quantity,
                        requirement: .requiredPositive,
                        min: 0.1,
                        max: 10_000,
                        rangeMessage: CalculatorCopy.concreteLengthRange
                    ),
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.widthPreset, options: ["4", "6", "8", "10"], selection: $width)
                CalculatorInputField(
                    title: CalculatorCopy.concreteThickness,
                    placeholder: "12",
                    unit: "cm",
                    text: $thickness,
                    rule: CalculatorNumericFieldRule(
                        kind: .quantity,
                        requirement: .requiredPositive,
                        min: 1,
                        max: 200,
                        rangeMessage: CalculatorCopy.concreteThicknessRange
                    ),
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.concreteThicknessPreset, options: ["10", "12", "15", "18"], selection: $thickness)
                CalculatorInputField(
                    title: CalculatorCopy.concreteWaste,
                    placeholder: "5",
                    unit: "%",
                    text: $waste,
                    rule: CalculatorNumericFieldRule(
                        kind: .quantity,
                        requirement: .requiredNonNegative,
                        min: 0,
                        max: 40,
                        rangeMessage: CalculatorCopy.concreteWasteRange
                    ),
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.wastePreset, options: ["3", "5", "8", "10"], selection: $waste)
                Picker(CalculatorCopy.concreteGrade, selection: $gradeRawValue) {
                    ForEach(ConcreteGrade.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
                }
                CalculatorInlineNotice(message: CalculatorCopy.concreteMixNotice)
            }
            Section {
                CalculatorPrimaryActionButton(title: CalculatorCopy.actionEstimate) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calc()
                }
            }
            if let resultModel {
                CalculatorResultPanel(cardTitle: CalculatorCopy.concreteResultTitle, result: resultModel)
            }
        }
    }

    private func calc() {
        guard let l = lengthValidation.doubleValue,
              let w = widthValidation.doubleValue,
              let t = thicknessValidation.doubleValue,
              let ws = wasteValidation.doubleValue else {
            resultModel = nil
            return
        }
        let net = l * w * t / 100
        let total = net * (1 + ws / 100)
        let cement = total * grade.cementKgPerM3
        let sand = total * grade.sandM3PerM3
        let gravel = total * grade.gravelM3PerM3
        resultModel = .singleSection(
            headline: CalculatorResultCopy.concreteHeadline(total: total),
            formula: CalculatorResultCopy.concreteFormula(),
            items: [
                CalculationResult.item(
                    CalculatorResultLabel.netVolume,
                    CalculatorFormatting.cubicMeters(net)
                ),
                CalculationResult.item(
                    CalculatorResultLabel.cement,
                    CalculatorResultCopy.concreteCementWithBags(cement: cement),
                    status: .pass
                ),
                CalculationResult.item(
                    CalculatorResultLabel.sand,
                    CalculatorFormatting.cubicMeters(sand)
                ),
                CalculationResult.item(
                    CalculatorResultLabel.gravel,
                    CalculatorFormatting.cubicMeters(gravel)
                ),
            ]
        )
        resultModel?.historyDraft = .init(
            tool: CalculatorCopy.concreteTool,
            input: CalculatorHistoryCopy.concreteInput(
                length: length,
                width: width,
                thickness: thickness,
                grade: grade.displayName
            ),
            result: CalculatorHistoryCopy.volumeResult(
                prefix: CalculatorResultLabel.netVolume,
                value: net
            )
        )
    }
}

enum ConcreteGrade: String, CaseIterable {
    case c20 = "C20"
    case c25 = "C25"
    case c30 = "C30"

    var displayName: String { rawValue }

    var cementKgPerM3: Double { switch self { case .c20: 320
    case .c25: 350
    case .c30: 380 } }
    var sandM3PerM3: Double { switch self { case .c20: 0.53
    case .c25: 0.50
    case .c30: 0.47 } }
    var gravelM3PerM3: Double { switch self { case .c20: 0.84
    case .c25: 0.80
    case .c30: 0.77 } }
}
