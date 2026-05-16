import SwiftUI

struct BreakerSelectView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.breakerCurrent) private var calcCurrent = ""
    @AppStorage(UserPreferenceKeys.Calculator.breakerLoadType) private var loadTypeRawValue: String = LoadType.lighting.rawValue
    @State private var result = ""
    @State private var resultModel: CalculationResult?
    @FocusState private var isInputFocused: Bool

    private var loadType: LoadType {
        StringEnumFallback.value(loadTypeRawValue, default: LoadType.lighting)
    }

    var body: some View {
        Form {
            Section("负载参数") {
                LabeledContent("计算电流 (A)") { TextField("例如 32", text: $calcCurrent.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                CalculatorValidationHint(message: rangeMessage(calcCurrent, min: 0.1, max: 100_000, hint: "请输入 0.1–100000"))
                CalculatorPresetChips(title: "常用电流", options: ["16", "20", "25", "32", "40", "63"], selection: $calcCurrent)
                Picker("负载类型", selection: $loadTypeRawValue) {
                    ForEach(LoadType.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
                }
            }
            Section("选型参考") {
                Text("• 照明回路: 额定电流 × 1.0\n• 插座回路: 额定电流 × 1.25\n• 动力回路: 额定电流 × 1.5")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("选型") {
                    isInputFocused = false
                    select()
                }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
            }
            if let resultModel {
                Section("推荐") {
                    CalculatorResultCard(
                        title: "断路器推荐",
                        result: resultModel
                    )
                }
            }
        }
        .navigationTitle("空开/漏保选型").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
            }
        }
    }

    private func select() {
        guard let i = CalculatorInputParser.double(calcCurrent), i > 0 else {
            presentError("请输入计算电流")
            return
        }
        let rated = i * loadType.factor
        let standardBreakers = EngineeringCalculations.standardBreakerSizes
        let breaker = standardBreakers.first { Double($0) >= rated } ?? 250
        let rcdRecommended = loadType == .socket
        let warning = rated > 100
        resultModel = .singleSection(
            headline: "推荐 \(breaker)A / \(loadType.poles)",
            formula: "整定值 = 计算电流×负载系数；断路器规格取≥整定值的最小标准档",
            items: [
                CalculationResult.item("计算电流", "\(fmt(i)) A"),
                CalculationResult.item("推荐整定值", "\(fmt(rated)) A", status: warning ? .warning : .pass),
                CalculationResult.item("漏保建议", rcdRecommended ? "建议配置 30mA 漏电保护" : "按现场方案选配", status: rcdRecommended ? .pass : .normal),
            ]
        )
        result = """
        计算电流: \(fmt(i)) A
        推荐整定值: \(fmt(rated)) A
        断路器规格: \(breaker)A / \(loadType.poles)
        \(rcdRecommended ? "建议配置 30mA 漏电保护" : "")
        """
        store.appendCalculationHistory(
            tool: "空开选型",
            input: "\(fmt(i))A, \(loadType.displayName)",
            result: "\(breaker)A"
        )
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 1; f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: v)) ?? String(v)
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

enum LoadType: String, CaseIterable {
    case lighting
    case socket
    case power

    var displayName: String {
        switch self {
        case .lighting: "照明"
        case .socket: "插座"
        case .power: "动力"
        }
    }
    var factor: Double { switch self { case .lighting: 1.0; case .socket: 1.25; case .power: 1.5 } }
    var poles: String { switch self { case .lighting, .socket: "1P+N"; case .power: "3P" } }
}
