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
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Form {
            Section("房间") {
                LabeledContent("长度 (m)") { TextField("6", text: $rl).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(rl, min: 0.5, max: 10_000, hint: "请输入 0.5–10000"))
                CalculatorPresetChips(title: "长度预设", options: ["4", "6", "8", "10"], selection: $rl)
                LabeledContent("宽度 (m)") { TextField("4", text: $rw).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(rw, min: 0.5, max: 10_000, hint: "请输入 0.5–10000"))
                CalculatorPresetChips(title: "宽度预设", options: ["3", "4", "5", "6"], selection: $rw)
            }
            Section("瓷砖") {
                LabeledContent("长度 (mm)") { TextField("600", text: $tl).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(tl, min: 100, max: 2000, hint: "请输入 100–2000"))
                CalculatorPresetChips(title: "常用长度", options: ["300", "600", "800"], selection: $tl)
                LabeledContent("宽度 (mm)") { TextField("600", text: $tw).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(tw, min: 100, max: 2000, hint: "请输入 100–2000"))
                CalculatorPresetChips(title: "常用宽度", options: ["300", "600", "800"], selection: $tw)
                LabeledContent("损耗 (%)") { TextField("8", text: $waste).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(waste, min: 0, max: 30, hint: "请输入 0–30"))
                CalculatorPresetChips(title: "损耗预设", options: ["5", "8", "10", "12"], selection: $waste)
                LabeledContent("每箱片数 (片)") { TextField("4", text: $box).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(box, min: 1, max: 200, hint: "请输入 1–200"))
                CalculatorPresetChips(title: "每箱片数", options: ["4", "6", "8", "10"], selection: $box)
            }
            Section {
                Button("估算") {
                    isInputFocused = false
                    calc()
                }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
            }
            if !result.isEmpty, let resultModel {
                Section("结果") {
                    CalculatorResultCard(
                        title: "地砖排料结果",
                        result: resultModel,
                        copyText: result
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
        guard let rl = CalculatorInputParser.double(rl), rl > 0,
              let rw = CalculatorInputParser.double(rw), rw > 0,
              let tl = CalculatorInputParser.double(tl), tl > 0,
              let tw = CalculatorInputParser.double(tw), tw > 0,
              let ws = CalculatorInputParser.double(waste), ws >= 0,
              let bp = CalculatorInputParser.double(box), bp > 0 else {
            presentError("请输入有效数值")
            return
        }
        let area = rl * rw
        let ra = area * (1 + ws / 100)
        let ta = (tl / 1000) * (tw / 1000)
        let count = Int(ceil(ra / ta))
        let boxes = Int(ceil(Double(count) / bp))
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

    private func rangeMessage(_ text: String, min: Double, max: Double, hint: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = CalculatorInputParser.double(trimmed) else { return "请输入数值" }
        return (value >= min && value <= max) ? nil : hint
    }

    private func presentError(_ message: String) {
        result = message
        resultModel = .error(message)
    }
}
