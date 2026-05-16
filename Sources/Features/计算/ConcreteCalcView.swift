import SwiftUI

struct ConcreteCalcView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.concreteLength) private var length = "10"
    @AppStorage(UserPreferenceKeys.Calculator.concreteWidth) private var width = "8"
    @AppStorage(UserPreferenceKeys.Calculator.concreteThickness) private var thickness = "12"
    @AppStorage(UserPreferenceKeys.Calculator.concreteWaste) private var waste = "5"
    @AppStorage(UserPreferenceKeys.Calculator.concreteGrade) private var gradeRawValue = ConcreteGrade.c25.rawValue
    @State private var result = ""
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var grade: ConcreteGrade {
        StringEnumFallback.value(gradeRawValue, default: ConcreteGrade.c25)
    }

    private var lengthValidation: NumericInputFieldValidation {
        InputValidator.validateField(
            length,
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.1,
            max: 10_000,
            rangeMessage: calculatorLoc("请输入 0.1–10000")
        )
    }

    private var widthValidation: NumericInputFieldValidation {
        InputValidator.validateField(
            width,
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.1,
            max: 10_000,
            rangeMessage: calculatorLoc("请输入 0.1–10000")
        )
    }

    private var thicknessValidation: NumericInputFieldValidation {
        InputValidator.validateField(
            thickness,
            kind: .quantity,
            requirement: .requiredPositive,
            min: 1,
            max: 200,
            rangeMessage: calculatorLoc("请输入 1–200")
        )
    }

    private var wasteValidation: NumericInputFieldValidation {
        InputValidator.validateField(
            waste,
            kind: .quantity,
            requirement: .requiredNonNegative,
            min: 0,
            max: 40,
            rangeMessage: calculatorLoc("请输入 0–40")
        )
    }

    var body: some View {
        Form {
            Section("板面尺寸") {
                LabeledContent("长度 (m)") { TextField("10", text: $length.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                NumericInputFieldValidationHint(validation: lengthValidation, showWhenEmpty: didAttemptSubmit)
                CalculatorPresetChips(title: "长度预设", options: ["6", "8", "10", "12", "15"], selection: $length)
                LabeledContent("宽度 (m)") { TextField("8", text: $width.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                NumericInputFieldValidationHint(validation: widthValidation, showWhenEmpty: didAttemptSubmit)
                CalculatorPresetChips(title: "宽度预设", options: ["4", "6", "8", "10"], selection: $width)
                LabeledContent("厚度 (cm)") { TextField("12", text: $thickness.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                NumericInputFieldValidationHint(validation: thicknessValidation, showWhenEmpty: didAttemptSubmit)
                CalculatorPresetChips(title: "厚度预设", options: ["10", "12", "15", "18"], selection: $thickness)
                LabeledContent("损耗 (%)") { TextField("5", text: $waste.numericInput(.quantity)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($isInputFocused) }
                NumericInputFieldValidationHint(validation: wasteValidation, showWhenEmpty: didAttemptSubmit)
                CalculatorPresetChips(title: "损耗预设", options: ["3", "5", "8", "10"], selection: $waste)
                Picker("标号", selection: $gradeRawValue) {
                    ForEach(ConcreteGrade.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
                }
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
                        title: "混凝土估算",
                        result: resultModel
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
        guard let l = lengthValidation.doubleValue,
              let w = widthValidation.doubleValue,
              let t = thicknessValidation.doubleValue,
              let ws = wasteValidation.doubleValue else {
            result = ""
            resultModel = nil
            return
        }
        let net = l * w * t / 100
        let total = net * (1 + ws / 100)
        let cement = total * grade.cementKgPerM3
        let sand = total * grade.sandM3PerM3
        let gravel = total * grade.gravelM3PerM3
        resultModel = .singleSection(
            headline: "含损耗 \(fmt(total)) m³",
            formula: "净方量 = 长×宽×厚(cm)÷100；含损耗 = 净方量×(1+损耗%)",
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
}

enum ConcreteGrade: String, CaseIterable {
    case c20 = "C20"; case c25 = "C25"; case c30 = "C30"

    var displayName: String { rawValue }

    var cementKgPerM3: Double { switch self { case .c20: 320; case .c25: 350; case .c30: 380 } }
    var sandM3PerM3: Double { switch self { case .c20: 0.53; case .c25: 0.50; case .c30: 0.47 } }
    var gravelM3PerM3: Double { switch self { case .c20: 0.84; case .c25: 0.80; case .c30: 0.77 } }
}
