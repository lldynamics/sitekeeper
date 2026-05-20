import SwiftUI

struct RebarCalcView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.rebarDia) private var dia = "12"
    @AppStorage(UserPreferenceKeys.Calculator.rebarLen) private var len = "9"
    @AppStorage(UserPreferenceKeys.Calculator.rebarQty) private var qty = "30"
    @AppStorage(UserPreferenceKeys.Calculator.rebarPrice) private var price = ""
    @State private var result = ""
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var diameterRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 4,
            max: 80,
            rangeMessage: calculatorLoc("请输入 4–80")
        )
    }

    private var lengthRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.5,
            max: 100,
            rangeMessage: calculatorLoc("请输入 0.5–100")
        )
    }

    private var quantityRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 1,
            max: 100_000,
            rangeMessage: calculatorLoc("请输入 1–100000"),
            wholeNumberOnly: true,
            wholeNumberMessage: calculatorLoc("请输入整数")
        )
    }

    private var priceRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .amount,
            requirement: .optionalNonNegative,
            min: 0.1,
            max: 100_000,
            rangeMessage: calculatorLoc("请输入 0.1–100000")
        )
    }

    private var diameterValidation: NumericInputFieldValidation {
        diameterRule.validate(dia)
    }

    private var lengthValidation: NumericInputFieldValidation {
        lengthRule.validate(len)
    }

    private var quantityValidation: NumericInputFieldValidation {
        quantityRule.validate(qty)
    }

    private var priceValidation: NumericInputFieldValidation {
        priceRule.validate(price)
    }

    var body: some View {
        Form {
            Section("钢筋规格") {
                CalculatorValidatedNumericField(
                    title: "直径",
                    placeholder: "12",
                    unit: "mm",
                    text: $dia,
                    rule: diameterRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: "常用直径", options: ["6", "8", "10", "12", "14", "16", "20"], selection: $dia)
                CalculatorValidatedNumericField(
                    title: "每根长",
                    placeholder: "9",
                    unit: "m",
                    text: $len,
                    rule: lengthRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: "常用长度", options: ["6", "9", "12"], selection: $len)
                CalculatorValidatedNumericField(
                    title: "根数",
                    placeholder: "30",
                    unit: "根",
                    text: $qty,
                    rule: quantityRule,
                    keyboardType: .numberPad,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: "常用根数", options: ["10", "20", "30", "50", "100"], selection: $qty)
                CalculatorValidatedNumericField(
                    title: "单价",
                    placeholder: "选填",
                    unit: "元/kg",
                    text: $price,
                    rule: priceRule,
                    showWhenEmpty: false,
                    focus: $isInputFocused
                )
            }
            Section {
                Button("估算") {
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
        guard let d = diameterValidation.doubleValue,
              let l = lengthValidation.doubleValue,
              let qValue = quantityValidation.doubleValue,
              priceValidation.errorMessage == nil else {
            result = ""
            resultModel = nil
            return
        }
        let q = qValue.rounded(.towardZero)
        let uw = d * d / 162
        let tw = uw * l * q
        var lines = ["单位重: \(fmt(uw)) kg/m", "总重: \(fmt(tw)) kg", "吨位: \(fmt(tw/1000)) t"]
        if let p = priceValidation.doubleValue, p > 0 { lines.append("造价: \(fmt(tw * p)) 元") }
        var items: [CalculationResult.ResultItem] = [
            CalculationResult.item("单位重", "\(fmt(uw)) kg/m"),
            CalculationResult.item("总重", "\(fmt(tw)) kg", status: .pass),
            CalculationResult.item("吨位", "\(fmt(tw / 1000)) t"),
        ]
        if let p = priceValidation.doubleValue, p > 0 {
            items.append(CalculationResult.item("造价", "\(fmt(tw * p)) 元"))
        }
        resultModel = .singleSection(
            headline: "总重 \(fmt(tw)) kg",
            formula: "单位重(kg/m)=d²÷162；总重=单位重×长度×根数",
            items: items
        )
        result = lines.joined(separator: "\n")
        saveHistory("总重 \(fmt(tw)) kg")
        dia = NumericInputSupport.normalizedStorageText(dia, kind: .quantity, preservingInvalid: false)
        len = NumericInputSupport.normalizedStorageText(len, kind: .quantity, preservingInvalid: false)
        qty = NumericInputSupport.normalizedStorageText(qty, kind: .quantity, preservingInvalid: false)
        price = NumericInputSupport.normalizedStorageText(price, kind: .amount, preservingInvalid: false)
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

}
