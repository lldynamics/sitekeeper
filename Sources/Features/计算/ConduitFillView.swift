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
            rangeMessage: calculatorLoc(String(localized: "请输入 6–10000"))
        )
    }

    private var wireDiaRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.5,
            max: 100,
            rangeMessage: calculatorLoc(String(localized: "请输入 0.5–100"))
        )
    }

    private var wireCountRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 1,
            max: 500,
            rangeMessage: calculatorLoc(String(localized: "请输入 1–500")),
            wholeNumberOnly: true,
            wholeNumberMessage: calculatorLoc(String(localized: "请输入整数"))
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
            Section(String(localized: "参数")) {
                CalculatorValidatedNumericField(
                    title: String(localized: "线管内径"),
                    placeholder: "16",
                    unit: "mm",
                    text: $conduitInnerDia,
                    rule: conduitInnerDiaRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: String(localized: "常用管径"), options: ["16", "20", "25", "32", "40", "50"], selection: $conduitInnerDia)
                CalculatorValidatedNumericField(
                    title: String(localized: "单根导线外径"),
                    placeholder: "2.5",
                    unit: "mm",
                    text: $wireDia,
                    rule: wireDiaRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: String(localized: "常用线径"), options: ["2.5", "4", "6", "10", "16"], selection: $wireDia)
                CalculatorValidatedNumericField(
                    title: String(localized: "导线根数"),
                    placeholder: "3",
                    unit: String(localized: "根"),
                    text: $wireCount,
                    rule: wireCountRule,
                    keyboardType: .numberPad,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: String(localized: "常用根数"), options: ["2", "3", "4", "6", "8", "12"], selection: $wireCount)
            }
            Section(String(localized: "参考")) {
                Text(String(localized: "规范要求穿线率 ≤ 40%")).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button(String(localized: "计算")) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calc()
                }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
            }
            if let resultModel {
                Section(String(localized: "结果")) {
                    CalculatorResultCard(
                        title: String(localized: "线管穿线率"),
                        result: resultModel
                    )
                }
            }
        }
        .navigationTitle(String(localized: "线管穿线率")).navigationBarTitleDisplayMode(.inline)
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
            headline: String(format: String(localized: "穿线率 %@%%"), fmt(rate)),
            formula: String(localized: "穿线率 = (导线总截面积 ÷ 线管截面积)×100%"),
            items: [
                CalculationResult.item(
                    String(localized: "线管截面积"),
                    String(format: String(localized: "%@ mm²"), fmt(conduitArea))
                ),
                CalculationResult.item(
                    String(localized: "导线总截面积"),
                    String(format: String(localized: "%@ mm²"), fmt(wireArea))
                ),
                CalculationResult.item(
                    String(localized: "规范校核"),
                    pass ? String(localized: "符合规范（≤40%）") : String(localized: "已超出规范（>40%）"),
                    status: pass ? .pass : .warning
                ),
                CalculationResult.item(
                    String(localized: "推荐管内径"),
                    recommended.map { String(format: String(localized: "Φ%@ mm"), fmt($0)) } ?? String(localized: "超出常用规格"),
                    status: pass ? .normal : .warning
                ),
            ]
        )
        let recommendedText = recommended.map { String(format: String(localized: "Φ%@ mm"), fmt($0)) } ?? String(localized: "超出常用规格")
        result = """
        \(String(format: String(localized: "线管截面积: %@ mm²"), fmt(conduitArea)))
        \(String(format: String(localized: "导线总截面积: %@ mm²"), fmt(wireArea)))
        \(String(format: String(localized: "穿线率: %@ %%"), fmt(rate)))
        \(rate <= 40 ? String(localized: "符合规范") : String(localized: "超过 40%，请增大管径或减少根数"))
        \(String(format: String(localized: "推荐管内径: %@"), recommendedText))
        """
        store.appendCalculationHistory(
            tool: String(localized: "线管穿线率"),
            input: String(
                format: String(localized: "Φ%@mm, Φ%@mm × %@根"),
                conduitInnerDia,
                wireDia,
                wireCount
            ),
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
