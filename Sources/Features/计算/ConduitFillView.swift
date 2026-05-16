import SwiftUI

struct ConduitFillView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.conduitInnerDia) private var conduitInnerDia = "16"
    @AppStorage(UserPreferenceKeys.Calculator.conduitWireDia) private var wireDia = "2.5"
    @AppStorage(UserPreferenceKeys.Calculator.conduitWireCount) private var wireCount = "3"
    @State private var result = ""
    @State private var resultModel: CalculationResult?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Form {
            Section("参数") {
                LabeledContent("线管内径 (mm)") { TextField("16", text: $conduitInnerDia.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(conduitInnerDia, min: 6, max: 10_000, hint: "请输入 6–10000"))
                CalculatorPresetChips(title: "常用管径", options: ["16", "20", "25", "32", "40", "50"], selection: $conduitInnerDia)
                LabeledContent("单根导线外径 (mm)") { TextField("2.5", text: $wireDia.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(wireDia, min: 0.5, max: 100, hint: "请输入 0.5–100"))
                CalculatorPresetChips(title: "常用线径", options: ["2.5", "4", "6", "10", "16"], selection: $wireDia)
                LabeledContent("导线根数 (根)") { TextField("3", text: $wireCount.numericInput(.quantity)).keyboardType(.numberPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: countMessage(wireCount, min: 1, max: 500, hint: "请输入 1–500"))
                CalculatorPresetChips(title: "常用根数", options: ["2", "3", "4", "6", "8", "12"], selection: $wireCount)
            }
            Section("参考") {
                Text("规范要求穿线率 ≤ 40%").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("计算") {
                    isInputFocused = false
                    calc()
                }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
            }
            if let resultModel {
                Section("结果") {
                    CalculatorResultCard(
                        title: "线管穿线率",
                        result: resultModel
                    )
                }
            }
        }
        .navigationTitle("线管穿线率").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
            }
        }
    }

    private func calc() {
        guard let cd = CalculatorInputParser.double(conduitInnerDia),
              let wd = CalculatorInputParser.double(wireDia),
              let wc = CalculatorInputParser.int(wireCount) else {
            presentError("请输入有效数值")
            return
        }
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
            headline: "穿线率 \(fmt(rate))%",
            formula: "穿线率 = (导线总截面积 ÷ 线管截面积)×100%",
            items: [
                CalculationResult.item("线管截面积", "\(fmt(conduitArea)) mm²"),
                CalculationResult.item("导线总截面积", "\(fmt(wireArea)) mm²"),
                CalculationResult.item("规范校核", pass ? "符合规范（≤40%）" : "已超出规范（>40%）", status: pass ? .pass : .warning),
                CalculationResult.item("推荐管内径", recommended.map { "Φ\(fmt($0)) mm" } ?? "超出常用规格", status: pass ? .normal : .warning),
            ]
        )
        result = """
        线管截面积: \(fmt(conduitArea)) mm²
        导线总截面积: \(fmt(wireArea)) mm²
        穿线率: \(fmt(rate)) %
        \(rate <= 40 ? "符合规范" : "超过 40%，请增大管径或减少根数")
        推荐管内径: \(recommended.map { "Φ\(fmt($0)) mm" } ?? "超出常用规格")
        """
        store.appendCalculationHistory(
            tool: "线管穿线率",
            input: "Φ\(conduitInnerDia)mm, Φ\(wireDia)mm × \(wireCount)根",
            result: "\(fmt(rate))%"
        )
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 1; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private func rangeMessage(_ text: String, min: Double, max: Double, hint: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = CalculatorInputParser.double(trimmed) else { return "请输入数值" }
        return (value >= min && value <= max) ? nil : hint
    }

    private func countMessage(_ text: String, min: Int, max: Int, hint: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = CalculatorInputParser.int(trimmed) else { return "请输入整数" }
        return (value >= min && value <= max) ? nil : hint
    }

    private func presentError(_ message: String) {
        result = message
        resultModel = .error(message)
    }
}
