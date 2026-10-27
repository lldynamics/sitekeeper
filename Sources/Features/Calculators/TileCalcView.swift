import SwiftUI

struct TileCalcView: View {
    @State private var rl = "6"
    @State private var rw = "4"
    @State private var tl = "600"
    @State private var tw = "600"
    @State private var waste = "8"
    @State private var box = "4"
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var roomDimensionRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.5,
            max: 10_000,
            rangeMessage: calculatorLoc("请输入 0.5–10000")
        )
    }

    private var tileDimensionRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 100,
            max: 2_000,
            rangeMessage: calculatorLoc("请输入 100–2000")
        )
    }

    private var wasteRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredNonNegative,
            min: 0,
            max: 30,
            rangeMessage: calculatorLoc("请输入 0–30")
        )
    }

    private var boxRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 1,
            max: 200,
            rangeMessage: calculatorLoc("请输入 1–200"),
            wholeNumberOnly: true,
            wholeNumberMessage: calculatorLoc("请输入整数")
        )
    }

    private var roomLengthValidation: NumericInputFieldValidation {
        roomDimensionRule.validate(rl)
    }

    private var roomWidthValidation: NumericInputFieldValidation {
        roomDimensionRule.validate(rw)
    }

    private var tileLengthValidation: NumericInputFieldValidation {
        tileDimensionRule.validate(tl)
    }

    private var tileWidthValidation: NumericInputFieldValidation {
        tileDimensionRule.validate(tw)
    }

    private var wasteValidation: NumericInputFieldValidation {
        wasteRule.validate(waste)
    }

    private var boxValidation: NumericInputFieldValidation {
        boxRule.validate(box)
    }

    var body: some View {
        CalculatorForm(title: CalculatorCopy.tileTool, focus: $isInputFocused) {
            Section(CalculatorCopy.tileRoomSection) {
                CalculatorInputField(
                    title: CalculatorCopy.tileRoomLength,
                    placeholder: "6",
                    unit: "m",
                    text: $rl,
                    rule: roomDimensionRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.lengthPreset, options: ["4", "6", "8", "10"], selection: $rl)
                CalculatorInputField(
                    title: CalculatorCopy.tileRoomWidth,
                    placeholder: "4",
                    unit: "m",
                    text: $rw,
                    rule: roomDimensionRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.widthPreset, options: ["3", "4", "5", "6"], selection: $rw)
            }
            Section(CalculatorCopy.tileMaterialSection) {
                CalculatorInputField(
                    title: CalculatorCopy.tileLength,
                    placeholder: "600",
                    unit: "mm",
                    text: $tl,
                    rule: tileDimensionRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.commonLength, options: ["300", "600", "800"], selection: $tl)
                CalculatorInputField(
                    title: CalculatorCopy.tileWidth,
                    placeholder: "600",
                    unit: "mm",
                    text: $tw,
                    rule: tileDimensionRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.commonWidth, options: ["300", "600", "800"], selection: $tw)
                CalculatorInputField(
                    title: CalculatorCopy.tileWaste,
                    placeholder: "8",
                    unit: "%",
                    text: $waste,
                    rule: wasteRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.wastePreset, options: ["5", "8", "10", "12"], selection: $waste)
                CalculatorInputField(
                    title: CalculatorCopy.tileBoxPieces,
                    placeholder: "4",
                    unit: CalculatorCopy.unitPieces,
                    text: $box,
                    rule: boxRule,
                    keyboardType: .numberPad,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.tileBoxPieces, options: ["4", "6", "8", "10"], selection: $box)
            }
            Section {
                CalculatorPrimaryActionButton(title: CalculatorCopy.actionEstimate) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calc()
                }
            }
            if let resultModel {
                CalculatorResultPanel(cardTitle: CalculatorCopy.tileResultTitle, result: resultModel)
            }
        }
    }

    private func calc() {
        guard let roomLength = roomLengthValidation.doubleValue,
              let roomWidth = roomWidthValidation.doubleValue,
              let tileLength = tileLengthValidation.doubleValue,
              let tileWidth = tileWidthValidation.doubleValue,
              let wastePercent = wasteValidation.doubleValue,
              let boxPiecesValue = boxValidation.doubleValue else {
            resultModel = nil
            return
        }
        let boxPieces = Int(boxPiecesValue.rounded(.towardZero))
        let area = roomLength * roomWidth
        let ra = area * (1 + wastePercent / 100)
        let ta = (tileLength / 1000) * (tileWidth / 1000)
        let count = Int(ceil(ra / ta))
        let boxes = Int(ceil(Double(count) / Double(boxPieces)))
        resultModel = .singleSection(
            headline: "\(CalculatorCopy.tileHeadlinePrefix) \(CalculatorFormatting.pieces(count)) / \(CalculatorFormatting.packages(boxes))",
            formula: CalculatorResultCopy.tileFormula(),
            items: [
                CalculationResult.item(CalculatorResultLabel.floorArea, CalculatorFormatting.squareMeters(area)),
                CalculationResult.item(CalculatorResultLabel.adjustedArea, CalculatorFormatting.squareMeters(ra)),
                CalculationResult.item(CalculatorResultLabel.adhesive, CalculatorFormatting.kilograms(ra * 5)),
                CalculationResult.item(CalculatorResultLabel.packageCount, CalculatorFormatting.packages(boxes), status: .pass),
            ]
        )
        resultModel?.historyDraft = .init(
            tool: CalculatorCopy.tileTool,
            input: CalculatorHistoryCopy.tileInput(
                roomLength: rl,
                roomWidth: rw,
                tileLength: tl,
                tileWidth: tw
            ),
            result: CalculatorHistoryCopy.tileResult(
                pieceCount: count,
                packageCount: boxes
            )
        )
        rl = NumericInputSupport.normalizedStorageText(rl, kind: .quantity, preservingInvalid: false)
        rw = NumericInputSupport.normalizedStorageText(rw, kind: .quantity, preservingInvalid: false)
        tl = NumericInputSupport.normalizedStorageText(tl, kind: .quantity, preservingInvalid: false)
        tw = NumericInputSupport.normalizedStorageText(tw, kind: .quantity, preservingInvalid: false)
        waste = NumericInputSupport.normalizedStorageText(waste, kind: .quantity, preservingInvalid: false)
        box = NumericInputSupport.normalizedStorageText(box, kind: .quantity, preservingInvalid: false)
    }
}
