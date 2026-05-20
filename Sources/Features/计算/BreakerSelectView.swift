import SwiftUI

struct BreakerSelectView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.breakerCurrent) private var calcCurrent = ""
    @AppStorage(UserPreferenceKeys.Calculator.breakerLoadType) private var loadTypeRawValue: String = LoadType.socket.rawValue
    @State private var result = ""
    @State private var resultModel: CalculationResult?
    @FocusState private var isInputFocused: Bool

    private var loadType: LoadType {
        StringEnumFallback.value(loadTypeRawValue, default: LoadType.socket)
    }

    var body: some View {
        Form {
            Section(String(localized: "负载参数")) {
                LabeledContent(String(localized: "计算电流 (A)")) {
                    TextField(String(localized: "例如 32"), text: $calcCurrent.numericInput(.quantity))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                CalculatorValidationHint(
                    message: rangeMessage(
                        calcCurrent,
                        min: 0.1,
                        max: 100_000,
                        hint: String(localized: "请输入 0.1–100000")
                    )
                )
                CalculatorPresetChips(
                    title: String(localized: "常用电流"),
                    options: ["16", "20", "25", "32", "40", "63"],
                    selection: $calcCurrent
                )
                Picker(String(localized: "负载类型"), selection: $loadTypeRawValue) {
                    ForEach(LoadType.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
                }
            }
            Section(String(localized: "选型参考")) {
                Text(String(localized: "• 插座回路: 额定电流 × 1.25\n• 动力回路: 额定电流 × 1.5"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button(String(localized: "选型")) {
                    isInputFocused = false
                    select()
                }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
            }
            if let resultModel {
                Section(String(localized: "推荐")) {
                    CalculatorResultCard(
                        title: String(localized: "断路器推荐"),
                        result: resultModel
                    )
                }
            }
        }
        .navigationTitle(String(localized: "空开/漏保选型")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
            }
        }
    }

    private func select() {
        guard let i = CalculatorInputParser.double(calcCurrent), i > 0 else {
            presentError(String(localized: "请输入计算电流"))
            return
        }
        let rated = i * loadType.factor
        let standardBreakers = EngineeringCalculations.standardBreakerSizes
        let breaker = standardBreakers.first { Double($0) >= rated } ?? 250
        let rcdRecommended = loadType == .socket
        let warning = rated > 100
        resultModel = .singleSection(
            headline: String(
                format: String(localized: "推荐 %lldA / %@"),
                Int64(breaker),
                loadType.poles
            ),
            formula: String(localized: "整定值 = 计算电流×负载系数；断路器规格取≥整定值的最小标准档"),
            items: [
                CalculationResult.item(
                    String(localized: "计算电流"),
                    String(format: String(localized: "%@ A"), fmt(i))
                ),
                CalculationResult.item(
                    String(localized: "推荐整定值"),
                    String(format: String(localized: "%@ A"), fmt(rated)),
                    status: warning ? .warning : .pass
                ),
                CalculationResult.item(
                    String(localized: "漏保建议"),
                    rcdRecommended ? String(localized: "建议配置 30mA 漏电保护") : String(localized: "按现场方案选配"),
                    status: rcdRecommended ? .pass : .normal
                ),
            ]
        )
        let rcdAdvice = rcdRecommended ? String(localized: "建议配置 30mA 漏电保护") : ""
        result = """
        \(String(format: String(localized: "计算电流: %@ A"), fmt(i)))
        \(String(format: String(localized: "推荐整定值: %@ A"), fmt(rated)))
        \(String(format: String(localized: "断路器规格: %lldA / %@"), Int64(breaker), loadType.poles))
        \(rcdAdvice)
        """
        store.appendCalculationHistory(
            tool: String(localized: "空开选型"),
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
        guard let value = CalculatorInputParser.double(trimmed) else { return String(localized: "请输入数值") }
        return (value >= min && value <= max) ? nil : hint
    }

    private func presentError(_ message: String) {
        result = message
        resultModel = .error(message)
    }
}

enum LoadType: String, CaseIterable {
    case socket
    case power

    var displayName: String {
        switch self {
        case .socket: String(localized: "插座")
        case .power: String(localized: "动力")
        }
    }
    var factor: Double { switch self { case .socket: 1.25; case .power: 1.5 } }
    var poles: String { switch self { case .socket: "1P+N"; case .power: "3P" } }
}
