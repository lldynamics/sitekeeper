import SwiftUI

struct RebarCalcView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.rebarDia) private var dia = "12"
    @AppStorage(UserPreferenceKeys.Calculator.rebarLen) private var len = "9"
    @AppStorage(UserPreferenceKeys.Calculator.rebarQty) private var qty = "30"
    @AppStorage(UserPreferenceKeys.Calculator.rebarPrice) private var price = ""
    @State private var result = ""
    @State private var resultModel: CalculationResult?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Form {
            Section("钢筋规格") {
                LabeledContent("直径 (mm)") { TextField("12", text: $dia).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(dia, min: 4, max: 80, hint: "请输入 4–80"))
                CalculatorPresetChips(title: "常用直径", options: ["6", "8", "10", "12", "14", "16", "20"], selection: $dia)
                LabeledContent("每根长 (m)") { TextField("9", text: $len).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(len, min: 0.5, max: 100, hint: "请输入 0.5–100"))
                CalculatorPresetChips(title: "常用长度", options: ["6", "9", "12"], selection: $len)
                LabeledContent("根数 (根)") { TextField("30", text: $qty).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(qty, min: 1, max: 100_000, hint: "请输入 1–100000"))
                CalculatorPresetChips(title: "常用根数", options: ["10", "20", "30", "50", "100"], selection: $qty)
                LabeledContent("单价 (元/kg)") { TextField("选填", text: $price).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: optionalRangeMessage(price, min: 0.1, max: 100_000, hint: "请输入 0.1–100000"))
            }
            Section {
                Button("估算") {
                    isInputFocused = false
                    calc()
                }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
            }
            if let resultModel {
                Section("结果") {
                    CalculatorResultCard(
                        title: "钢筋重量估算",
                        result: resultModel
                    )
                }
            }
        }
        .navigationTitle("钢筋重量").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
            }
        }
    }

    private func calc() {
        guard let d = CalculatorInputParser.double(dia), d > 0,
              let l = CalculatorInputParser.double(len), l > 0,
              let q = CalculatorInputParser.double(qty), q > 0 else {
            presentError("请输入有效数值")
            return
        }
        let uw = d * d / 162
        let tw = uw * l * q
        var lines = ["单位重: \(fmt(uw)) kg/m", "总重: \(fmt(tw)) kg", "吨位: \(fmt(tw/1000)) t"]
        if let p = CalculatorInputParser.double(price), p > 0 { lines.append("造价: \(fmt(tw * p)) 元") }
        var items: [CalculationResult.ResultItem] = [
            CalculationResult.item("单位重", "\(fmt(uw)) kg/m"),
            CalculationResult.item("总重", "\(fmt(tw)) kg", status: .pass),
            CalculationResult.item("吨位", "\(fmt(tw / 1000)) t"),
        ]
        if let p = CalculatorInputParser.double(price), p > 0 {
            items.append(CalculationResult.item("造价", "\(fmt(tw * p)) 元"))
        }
        resultModel = .singleSection(
            headline: "总重 \(fmt(tw)) kg",
            formula: "单位重(kg/m)=d²÷162；总重=单位重×长度×根数",
            items: items
        )
        result = lines.joined(separator: "\n")
        saveHistory("总重 \(fmt(tw)) kg")
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 0; f.maximumFractionDigits = 3
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private func saveHistory(_ r: String) {
        store.appendCalculationHistory(
            tool: "钢筋重量",
            input: "Φ\(dia)mm, \(len)m × \(qty)根",
            result: r
        )
    }

    private func rangeMessage(_ text: String, min: Double, max: Double, hint: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = CalculatorInputParser.double(trimmed) else { return "请输入数值" }
        return (value >= min && value <= max) ? nil : hint
    }

    private func optionalRangeMessage(_ text: String, min: Double, max: Double, hint: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return rangeMessage(trimmed, min: min, max: max, hint: hint)
    }

    private func presentError(_ message: String) {
        result = message
        resultModel = .error(message)
    }
}
