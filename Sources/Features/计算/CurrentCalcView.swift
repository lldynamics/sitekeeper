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
            Section(String(localized: "输入参数")) {
                LabeledContent(String(localized: "功率 (kW)")) {
                    TextField(String(localized: "例如 10"), text: $power.numericInput(.quantity))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                CalculatorValidationHint(message: rangeMessage(power, min: 0.1, max: 5_000_000, hint: String(localized: "请输入 0.1–5000000")))
                CalculatorPresetChips(title: String(localized: "常用功率"), options: ["3", "5", "10", "20", "30", "50"], selection: $power)
                LabeledContent(String(localized: "电压 (V)")) {
                    TextField("220", text: $voltage.numericInput(.quantity))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                CalculatorValidationHint(message: rangeMessage(voltage, min: 12, max: 100_000, hint: String(localized: "请输入 12–100000")))
                CalculatorPresetChips(title: String(localized: "电压预设"), options: ["220", "380"], selection: $voltage)
                LabeledContent(String(localized: "功率因数")) {
                    TextField("0.85", text: $powerFactor.numericInput(.quantity))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                CalculatorValidationHint(message: rangeMessage(powerFactor, min: 0.01, max: 1, hint: String(localized: "请输入 0.01–1")))
                CalculatorPresetChips(title: String(localized: "功率因数"), options: ["0.80", "0.85", "0.90", "0.95"], selection: $powerFactor)
                Toggle(String(localized: "三相电"), isOn: $isThreePhase)
            }

            Section(String(localized: "公式")) {
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
                Button(String(localized: "计算")) {
                    isInputFocused = false
                    calc()
                }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }

            if let resultModel {
                Section(String(localized: "计算结果")) {
                    CalculatorResultCard(
                        title: String(localized: "电流计算结果"),
                        result: resultModel
                    )
                }
            }
        }
        .navigationTitle(String(localized: "电流计算"))
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
            presentError(String(localized: "请输入有效数值"))
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
        let phaseLabel = isThreePhase ? String(localized: "三相") : String(localized: "单相")
        resultModel = .singleSection(
            headline: String(format: String(localized: "电流 %@ A"), String(format: "%.2f", current)),
            formula: isThreePhase
                ? "I = P×1000 ÷ (√3×U×cosφ)"
                : "I = P×1000 ÷ (U×cosφ)",
            items: [
                CalculationResult.item(
                    String(localized: "功率"),
                    String(format: String(localized: "%@ kW"), String(format: "%.2f", p))
                ),
                CalculationResult.item(
                    String(localized: "电压"),
                    String(format: String(localized: "%@ V (%@)"), String(format: "%.0f", v), phaseLabel)
                ),
                CalculationResult.item(String(localized: "功率因数"), String(format: "%.2f", pf)),
                CalculationResult.item(
                    String(localized: "电流结果"),
                    String(format: String(localized: "%@ A"), String(format: "%.2f", current)),
                    status: warning ? .warning : .pass
                ),
            ]
        )
        resultText = """
        \(String(format: String(localized: "功率: %@ kW"), String(format: "%.2f", p)))
        \(String(format: String(localized: "电压: %@ V (%@)"), String(format: "%.0f", v), phaseLabel))
        \(String(format: String(localized: "电流: %@ A"), String(format: "%.2f", current)))
        """
        saveHistory("\(String(format: "%.2f", current)) A")
    }

    private func saveHistory(_ r: String) {
        store.appendCalculationHistory(
            tool: String(localized: "电流计算"),
            input: String(format: String(localized: "%@kW / %@V"), power, voltage),
            result: r
        )
    }

    private func rangeMessage(_ text: String, min: Double, max: Double, hint: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = CalculatorInputParser.double(trimmed) else {
            return String(localized: "请输入数值")
        }
        return (value >= min && value <= max) ? nil : hint
    }

    private func presentError(_ message: String) {
        resultText = message
        resultModel = .error(message)
    }
}
