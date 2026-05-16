import SwiftUI

struct CurrentCalcView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.currentPower) private var power: String = ""
    @AppStorage(UserPreferenceKeys.Calculator.currentVoltage) private var voltage: String = "220"
    @AppStorage(UserPreferenceKeys.Calculator.currentPowerFactor) private var powerFactor: String = "0.85"
    @AppStorage(UserPreferenceKeys.Calculator.currentIsThreePhase) private var isThreePhase: Bool = false

    @State private var resultText: String = ""
    @State private var resultModel: CalculationResult?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        Form {
            Section("输入参数") {
                LabeledContent("功率 (kW)") {
                    TextField("例如 10", text: $power.numericInput(.quantity))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                CalculatorValidationHint(message: rangeMessage(power, min: 0.1, max: 5_000_000, hint: "请输入 0.1–5000000"))
                CalculatorPresetChips(title: "常用功率", options: ["3", "5", "10", "20", "30", "50"], selection: $power)
                LabeledContent("电压 (V)") {
                    TextField("220", text: $voltage.numericInput(.quantity))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                CalculatorValidationHint(message: rangeMessage(voltage, min: 12, max: 100_000, hint: "请输入 12–100000"))
                CalculatorPresetChips(title: "电压预设", options: ["220", "380"], selection: $voltage)
                LabeledContent("功率因数") {
                    TextField("0.85", text: $powerFactor.numericInput(.quantity))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                CalculatorValidationHint(message: rangeMessage(powerFactor, min: 0.01, max: 1, hint: "请输入 0.01–1"))
                CalculatorPresetChips(title: "功率因数", options: ["0.80", "0.85", "0.90", "0.95"], selection: $powerFactor)
                Toggle("三相电", isOn: $isThreePhase)
            }

            Section("公式") {
                VStack(alignment: .leading, spacing: 4) {
                    Group {
                        if isThreePhase {
                            Text("I = P / (√3 × U × cosφ)").font(.system(.caption, design: .monospaced))
                            Text("P → W (kW × 1000)").font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("I = P / (U × cosφ)").font(.system(.caption, design: .monospaced))
                            Text("P → W (kW × 1000)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
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
                Section("计算结果") {
                    CalculatorResultCard(
                        title: "电流计算结果",
                        result: resultModel
                    )
                }
            }
        }
        .navigationTitle("电流计算")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
            }
        }
        .onChange(of: isThreePhase) { _, enabled in
            voltage = enabled ? "380" : "220"
        }
    }

    private func calc() {
        guard let p = CalculatorInputParser.double(power),
              let v = CalculatorInputParser.double(voltage),
              let pf = CalculatorInputParser.double(powerFactor) else {
            presentError("请输入有效数值")
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
            headline: "电流 \(String(format: "%.2f", current)) A",
            formula: isThreePhase
                ? "I = P×1000 ÷ (√3×U×cosφ)"
                : "I = P×1000 ÷ (U×cosφ)",
            items: [
                CalculationResult.item("功率", "\(String(format: "%.2f", p)) kW"),
                CalculationResult.item("电压", "\(String(format: "%.0f", v)) V (\(isThreePhase ? "三相" : "单相"))"),
                CalculationResult.item("功率因数", String(format: "%.2f", pf)),
                CalculationResult.item("电流结果", "\(String(format: "%.2f", current)) A", status: warning ? .warning : .pass),
            ]
        )
        resultText = """
        功率: \(String(format: "%.2f", p)) kW
        电压: \(String(format: "%.0f", v)) V (\(isThreePhase ? "三相" : "单相"))
        电流: \(String(format: "%.2f", current)) A
        """
        saveHistory("\(String(format: "%.2f", current)) A")
    }

    private func saveHistory(_ r: String) {
        store.appendCalculationHistory(
            tool: "电流计算",
            input: "\(power)kW / \(voltage)V",
            result: r
        )
    }

    private func rangeMessage(_ text: String, min: Double, max: Double, hint: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = CalculatorInputParser.double(trimmed) else {
            return "请输入数值"
        }
        return (value >= min && value <= max) ? nil : hint
    }

    private func presentError(_ message: String) {
        resultText = message
        resultModel = .error(message)
    }
}
