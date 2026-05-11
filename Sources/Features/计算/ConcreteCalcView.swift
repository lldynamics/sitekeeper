import SwiftUI

struct ConcreteCalcView: View {
    @Environment(DataStore.self) private var store
    @AppStorage("calc.concrete.length") private var length = "10"
    @AppStorage("calc.concrete.width") private var width = "8"
    @AppStorage("calc.concrete.thickness") private var thickness = "12"
    @AppStorage("calc.concrete.waste") private var waste = "5"
    @AppStorage("calc.concrete.grade") private var gradeRawValue = ConcreteGrade.c25.rawValue
    @State private var result = ""
    @State private var resultModel: CalculationResult?
    @FocusState private var isInputFocused: Bool

    private var grade: ConcreteGrade {
        StringEnumFallback.value(gradeRawValue, default: ConcreteGrade.c25)
    }

    var body: some View {
        Form {
            Section("板面尺寸") {
                LabeledContent("长度 (m)") { TextField("10", text: $length).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(length, min: 0.1, max: 10_000, hint: "请输入 0.1–10000"))
                CalculatorPresetChips(title: "长度预设", options: ["6", "8", "10", "12", "15"], selection: $length)
                LabeledContent("宽度 (m)") { TextField("8", text: $width).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(width, min: 0.1, max: 10_000, hint: "请输入 0.1–10000"))
                CalculatorPresetChips(title: "宽度预设", options: ["4", "6", "8", "10"], selection: $width)
                LabeledContent("厚度 (cm)") { TextField("12", text: $thickness).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(thickness, min: 1, max: 200, hint: "请输入 1–200"))
                CalculatorPresetChips(title: "厚度预设", options: ["10", "12", "15", "18"], selection: $thickness)
                LabeledContent("损耗 (%)") { TextField("5", text: $waste).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(waste, min: 0, max: 40, hint: "请输入 0–40"))
                CalculatorPresetChips(title: "损耗预设", options: ["3", "5", "8", "10"], selection: $waste)
                Picker("标号", selection: $gradeRawValue) {
                    ForEach(ConcreteGrade.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
                }
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
                        title: "混凝土估算",
                        result: resultModel,
                        copyText: result
                    )
                }
            }
        }
        .navigationTitle("混凝土算量").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
            }
        }
    }

    private func calc() {
        guard let l = CalculatorInputParser.double(length), l > 0,
              let w = CalculatorInputParser.double(width), w > 0,
              let t = CalculatorInputParser.double(thickness), t > 0,
              let ws = CalculatorInputParser.double(waste), ws >= 0 else {
            presentError("请输入有效数值")
            return
        }
        let net = l * w * t / 100
        let total = net * (1 + ws / 100)
        let cement = total * grade.cementKgPerM3
        let sand = total * grade.sandM3PerM3
        let gravel = total * grade.gravelM3PerM3
        resultModel = .singleSection(
            headline: "含损耗 \(fmt(total)) m³",
            items: [
                CalculationResult.item("净方量", "\(fmt(net)) m³"),
                CalculationResult.item("水泥", "\(fmt(cement)) kg (\(Int(ceil(cement / 50))) 袋)", status: .pass),
                CalculationResult.item("砂", "\(fmt(sand)) m³"),
                CalculationResult.item("碎石", "\(fmt(gravel)) m³"),
            ]
        )
        result = """
        净方量: \(fmt(net)) m³
        含损耗: \(fmt(total)) m³
        水泥: \(fmt(cement)) kg (\(Int(ceil(cement/50))) 袋)
        砂: \(fmt(sand)) m³
        碎石: \(fmt(gravel)) m³
        """
        saveHistory("净方量 \(fmt(net)) m³")
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 0; f.maximumFractionDigits = 3
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private func saveHistory(_ r: String) {
        store.appendCalculationHistory(
            tool: "混凝土算量",
            input: "\(length)×\(width)m, \(thickness)cm, \(grade.displayName)",
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

enum ConcreteGrade: String, CaseIterable {
    case c20 = "C20"; case c25 = "C25"; case c30 = "C30"

    var displayName: String { rawValue }

    var cementKgPerM3: Double { switch self { case .c20: 320; case .c25: 350; case .c30: 380 } }
    var sandM3PerM3: Double { switch self { case .c20: 0.53; case .c25: 0.50; case .c30: 0.47 } }
    var gravelM3PerM3: Double { switch self { case .c20: 0.84; case .c25: 0.80; case .c30: 0.77 } }
}
