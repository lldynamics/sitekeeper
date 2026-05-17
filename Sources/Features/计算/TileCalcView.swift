import SwiftUI

struct TileCalcView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.tileRoomLength) private var rl = "6"
    @AppStorage(UserPreferenceKeys.Calculator.tileRoomWidth) private var rw = "4"
    @AppStorage(UserPreferenceKeys.Calculator.tileTileLength) private var tl = "600"
    @AppStorage(UserPreferenceKeys.Calculator.tileTileWidth) private var tw = "600"
    @AppStorage(UserPreferenceKeys.Calculator.tileWaste) private var waste = "8"
    @AppStorage(UserPreferenceKeys.Calculator.tileBox) private var box = "4"
    @State private var result = ""
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
        Form {
            Section("房间") {
                CalculatorValidatedNumericField(
                    title: "长度",
                    placeholder: "6",
                    unit: "m",
                    text: $rl,
                    rule: roomDimensionRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: "长度预设", options: ["4", "6", "8", "10"], selection: $rl)
                CalculatorValidatedNumericField(
                    title: "宽度",
                    placeholder: "4",
                    unit: "m",
                    text: $rw,
                    rule: roomDimensionRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: "宽度预设", options: ["3", "4", "5", "6"], selection: $rw)
            }
            Section("瓷砖") {
                CalculatorValidatedNumericField(
                    title: "长度",
                    placeholder: "600",
                    unit: "mm",
                    text: $tl,
                    rule: tileDimensionRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: "常用长度", options: ["300", "600", "800"], selection: $tl)
                CalculatorValidatedNumericField(
                    title: "宽度",
                    placeholder: "600",
                    unit: "mm",
                    text: $tw,
                    rule: tileDimensionRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: "常用宽度", options: ["300", "600", "800"], selection: $tw)
                CalculatorValidatedNumericField(
                    title: "损耗",
                    placeholder: "8",
                    unit: "%",
                    text: $waste,
                    rule: wasteRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: "损耗预设", options: ["5", "8", "10", "12"], selection: $waste)
                CalculatorValidatedNumericField(
                    title: "每箱片数",
                    placeholder: "4",
                    unit: "片",
                    text: $box,
                    rule: boxRule,
                    keyboardType: .numberPad,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: "每箱片数", options: ["4", "6", "8", "10"], selection: $box)
            }
            Section {
                Button("估算") {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calc()
                }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
            }
            if let resultModel {
                Section("结果") {
                    CalculatorResultCard(
                        title: "地砖排料结果",
                        result: resultModel
                    )
                }
            }
        }
        .navigationTitle("地砖排料").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
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
            result = ""
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
            headline: "需瓷砖 \(count) 片 / \(boxes) 箱",
            formula: "片数=ceil(含损耗面积÷单片面积)；箱数=ceil(片数÷每箱片数)",
            items: [
                CalculationResult.item("地面面积", "\(fmt(area)) m²"),
                CalculationResult.item("含损耗面积", "\(fmt(ra)) m²"),
                CalculationResult.item("胶粘剂", "\(fmt(ra * 5)) kg"),
                CalculationResult.item("箱数", "\(boxes) 箱", status: .pass),
            ]
        )
        result = """
        地面面积: \(fmt(area)) m²
        含损耗: \(fmt(ra)) m²
        需瓷砖: \(count) 片
        需箱数: \(boxes) 箱
        胶粘剂: \(fmt(ra * 5)) kg
        """
        saveHistory("\(count) 片 / \(boxes) 箱")
        rl = NumericInputSupport.normalizedStorageText(rl, kind: .quantity, preservingInvalid: false)
        rw = NumericInputSupport.normalizedStorageText(rw, kind: .quantity, preservingInvalid: false)
        tl = NumericInputSupport.normalizedStorageText(tl, kind: .quantity, preservingInvalid: false)
        tw = NumericInputSupport.normalizedStorageText(tw, kind: .quantity, preservingInvalid: false)
        waste = NumericInputSupport.normalizedStorageText(waste, kind: .quantity, preservingInvalid: false)
        box = NumericInputSupport.normalizedStorageText(box, kind: .quantity, preservingInvalid: false)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 0; f.maximumFractionDigits = 3
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private func saveHistory(_ r: String) {
        store.appendCalculationHistory(
            tool: "地砖排料",
            input: "\(rl)×\(rw)m, \(tl)×\(tw)mm",
            result: r
        )
    }

}
