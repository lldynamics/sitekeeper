import SwiftUI

struct ConduitFillView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.conduitInnerDia) private var conduitInnerDia = "16"
    @AppStorage(UserPreferenceKeys.Calculator.conduitWireDia) private var wireDia = "2.5"
    @AppStorage(UserPreferenceKeys.Calculator.conduitWireCount) private var wireCount = "3"
    @State private var result = ""
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var conduitInnerDiaRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 6,
            max: 10_000,
            rangeMessage: calculatorLoc("请输入 6–10000")
        )
    }

    private var wireDiaRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.5,
            max: 100,
            rangeMessage: calculatorLoc("请输入 0.5–100")
        )
    }

    private var wireCountRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 1,
            max: 500,
            rangeMessage: calculatorLoc("请输入 1–500"),
            wholeNumberOnly: true,
            wholeNumberMessage: calculatorLoc("请输入整数")
        )
    }

    private var conduitInnerDiaValidation: NumericInputFieldValidation {
        conduitInnerDiaRule.validate(conduitInnerDia)
    }

    private var wireDiaValidation: NumericInputFieldValidation {
        wireDiaRule.validate(wireDia)
    }

    private var wireCountValidation: NumericInputFieldValidation {
        wireCountRule.validate(wireCount)
    }

    var body: some View {
        Form {
            Section("参数") {
                CalculatorValidatedNumericField(
                    title: "线管内径",
                    placeholder: "16",
                    unit: "mm",
                    text: $conduitInnerDia,
                    rule: conduitInnerDiaRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: "常用管径", options: ["16", "20", "25", "32", "40", "50"], selection: $conduitInnerDia)
                CalculatorValidatedNumericField(
                    title: "单根导线外径",
                    placeholder: "2.5",
                    unit: "mm",
                    text: $wireDia,
                    rule: wireDiaRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: "常用线径", options: ["2.5", "4", "6", "10", "16"], selection: $wireDia)
                CalculatorValidatedNumericField(
                    title: "导线根数",
                    placeholder: "3",
                    unit: "根",
                    text: $wireCount,
                    rule: wireCountRule,
                    keyboardType: .numberPad,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: "常用根数", options: ["2", "3", "4", "6", "8", "12"], selection: $wireCount)
            }
            Section("参考") {
                Text("规范要求穿线率 ≤ 40%").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("计算") {
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
        guard let cd = conduitInnerDiaValidation.doubleValue,
              let wd = wireDiaValidation.doubleValue,
              let wcValue = wireCountValidation.doubleValue else {
            result = ""
            resultModel = nil
            return
        }
        let wc = Int(wcValue.rounded(.towardZero))
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
        conduitInnerDia = NumericInputSupport.normalizedStorageText(conduitInnerDia, kind: .quantity, preservingInvalid: false)
        wireDia = NumericInputSupport.normalizedStorageText(wireDia, kind: .quantity, preservingInvalid: false)
        wireCount = NumericInputSupport.normalizedStorageText(wireCount, kind: .quantity, preservingInvalid: false)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 1; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private func presentError(_ message: String) {
        result = message
        resultModel = .error(message)
    }
}
