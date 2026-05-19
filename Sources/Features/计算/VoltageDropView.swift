import SwiftUI

struct VoltageDropView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.voltageDropCurrent) private var current: String = ""
    @AppStorage(UserPreferenceKeys.Calculator.voltageDropLength) private var length: String = ""
    @AppStorage(UserPreferenceKeys.Calculator.voltageDropMaterial) private var materialRawValue: String = WireMaterial.copper.rawValue
    @AppStorage(UserPreferenceKeys.Calculator.voltageDropSection) private var section: String = "2.5"
    @AppStorage(UserPreferenceKeys.Calculator.voltageDropVoltage) private var voltage: String = "220"
    @AppStorage(UserPreferenceKeys.Calculator.voltageDropIsLoopLength) private var isLoopLength: Bool = false  // true = loop length(round trip included), false = one-way length

    @State private var resultText: String = ""
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private let resistivityCopper: Double = 0.0175
    private let resistivityAluminum: Double = 0.0283

    let commonSections = EngineeringCalculations.standardWireSections.map { String(format: $0.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", $0) }
    private var material: WireMaterial {
        StringEnumFallback.value(materialRawValue, default: WireMaterial.copper)
    }

    private var currentRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.1,
            max: 100_000,
            rangeMessage: calculatorLoc(String(localized: "请输入 0.1–100000"))
        )
    }

    private var lengthRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 1,
            max: 1_000_000,
            rangeMessage: calculatorLoc(String(localized: "请输入 1–1000000"))
        )
    }

    private var sectionRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 1,
            max: 20_000,
            rangeMessage: calculatorLoc(String(localized: "请输入 1–20000"))
        )
    }

    private var voltageRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 12,
            max: 100_000,
            rangeMessage: calculatorLoc(String(localized: "请输入 12–100000"))
        )
    }

    private var currentValidation: NumericInputFieldValidation {
        currentRule.validate(current)
    }

    private var lengthValidation: NumericInputFieldValidation {
        lengthRule.validate(length)
    }

    private var sectionValidation: NumericInputFieldValidation {
        sectionRule.validate(section)
    }

    private var voltageValidation: NumericInputFieldValidation {
        voltageRule.validate(voltage)
    }

    var body: some View {
        Form {
            Section(String(localized: "线路参数")) {
                CalculatorValidatedNumericField(
                    title: String(localized: "电流"),
                    placeholder: String(localized: "例如 20"),
                    unit: "A",
                    text: $current,
                    rule: currentRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: String(localized: "常用电流"), options: ["10", "16", "20", "32", "50", "63"], selection: $current)
                CalculatorValidatedNumericField(
                    title: String(localized: "长度"),
                    placeholder: String(localized: "例如 100"),
                    unit: "m",
                    text: $length,
                    rule: lengthRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: String(localized: "常用长度"), options: ["20", "50", "80", "100", "150", "200"], selection: $length)
                Toggle(String(localized: "回路长度（已含来/回）"), isOn: $isLoopLength)
                Picker(String(localized: "材质"), selection: $materialRawValue) {
                    Text(String(localized: "铜")).tag(WireMaterial.copper.rawValue)
                    Text(String(localized: "铝")).tag(WireMaterial.aluminum.rawValue)
                }
                CalculatorValidatedNumericField(
                    title: String(localized: "截面积"),
                    placeholder: "2.5",
                    unit: "mm²",
                    text: $section,
                    rule: sectionRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(commonSections, id: \.self) { s in
                            Button(s) {
                                section = s
                                AppHaptics.impact(.light, intensity: 0.65)
                            }
                                .font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
                                .background(section == s ? Color.appPrimaryAction : Color(uiColor: .secondarySystemGroupedBackground))
                                .foregroundStyle(section == s ? .white : .primary)
                                .clipShape(Capsule())
                        }
                    }
                }
                CalculatorValidatedNumericField(
                    title: String(localized: "额定电压"),
                    placeholder: "220",
                    unit: "V",
                    text: $voltage,
                    rule: voltageRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: String(localized: "电压预设"), options: ["220", "380"], selection: $voltage)
            }

            Section(String(localized: "载流量参考")) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(EngineeringCalculations.standardWireSections, id: \.self) { item in
                            VStack(spacing: 2) {
                                Text(formatSection(item)).font(.caption2)
                                Text("\(Int(EngineeringCalculations.ampacity(for: item, isCopper: material == .copper)))A")
                                    .font(.caption.weight(.medium)).foregroundStyle(Color.appDoc)
                            }
                            .padding(6)
                            .background(formatSection(item) == section ? Color.appDocSurfaceSubtle : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            Section {
                Button(String(localized: "计算")) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calcAndSave()
                }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }

            if let resultModel {
                Section(String(localized: "计算结果")) {
                    CalculatorResultCard(
                        title: String(localized: "压降评估"),
                        result: resultModel
                    )
                }
            }
        }
        .navigationTitle(String(localized: "电缆压降"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
            }
        }
    }

    private func calc() {
        guard let i = currentValidation.doubleValue,
              let l = lengthValidation.doubleValue,
              let s = sectionValidation.doubleValue,
              let v = voltageValidation.doubleValue else {
            resultText = ""
            resultModel = nil
            return
        }
        let isCopper = material == .copper
        let rho = isCopper ? resistivityCopper : resistivityAluminum
        let effectiveLength = isLoopLength ? l : l * 2
        let drop: EngineeringCalculations.VoltageDropMetrics
        switch EngineeringCalculations.voltageDropValidated(
            current: i,
            length: l,
            section: s,
            voltage: v,
            isLoopLength: isLoopLength,
            resistivity: rho
        ) {
        case .success(let metrics):
            drop = metrics
        case .failure(let error):
            presentError(error.userMessage)
            return
        }
        let recommended = EngineeringCalculations.recommendedWireSection(current: i, length: l, voltage: v, isLoopLength: isLoopLength, isCopper: isCopper)
        let ampacity = EngineeringCalculations.ampacity(for: s, isCopper: isCopper)
        let ampNote: String
        ampNote = i <= ampacity
            ? String(format: String(localized: "载流量: %lldA，满足"), Int64(ampacity))
            : String(format: String(localized: "载流量: %lldA，电流偏大"), Int64(ampacity))
        let recNote = recommended.map {
            String(format: String(localized: "推荐截面: %@ mm²"), formatSection($0))
        } ?? String(localized: "推荐截面: 超出常用规格，请复核设计")
        let dropPercent = drop.dropPercent
        let warning = dropPercent > 5
        let materialName = material == .copper ? String(localized: "铜") : String(localized: "铝")
        resultModel = .singleSection(
            headline: String(format: String(localized: "压降 %@%%"), String(format: "%.2f", dropPercent)),
            formula: String(localized: "ΔU = I×(ρ×L有效÷S)，压降% = (ΔU÷U)×100%"),
            items: [
                CalculationResult.item(String(localized: "材质"), materialName),
                CalculationResult.item(
                    String(localized: "有效长度"),
                    String(format: String(localized: "%@ m"), String(format: "%.1f", effectiveLength))
                ),
                CalculationResult.item(
                    String(localized: "线路电阻"),
                    String(format: String(localized: "%@ Ω"), String(format: "%.3f", drop.resistance))
                ),
                CalculationResult.item(
                    String(localized: "电压降"),
                    String(format: String(localized: "%@ V"), String(format: "%.2f", drop.dropV)),
                    status: warning ? .warning : .pass
                ),
                CalculationResult.item(String(localized: "载流量校核"), ampNote, status: i <= ampacity ? .pass : .warning),
                CalculationResult.item(String(localized: "推荐截面"), recNote, status: warning ? .warning : .normal),
            ]
        )

        let lengthModeText = isLoopLength ? String(localized: "回路") : String(localized: "单程×2")
        resultText = """
        \(String(format: String(localized: "材质: %@"), materialName))
        \(String(format: String(localized: "有效长度: %@ m (%@)"), String(format: "%.1f", effectiveLength), lengthModeText))
        \(String(format: String(localized: "线路电阻: %@ Ω"), String(format: "%.3f", drop.resistance)))
        \(String(format: String(localized: "电压降: %@ V (%@%%)"), String(format: "%.2f", drop.dropV), String(format: "%.2f", drop.dropPercent)))
        \(drop.dropPercent > 5 ? String(localized: "压降 > 5%，建议增大截面") : String(localized: "压降在允许范围内"))
        \(ampNote)
        \(recNote)
        """

        current = NumericInputSupport.normalizedStorageText(current, kind: .quantity, preservingInvalid: false)
        length = NumericInputSupport.normalizedStorageText(length, kind: .quantity, preservingInvalid: false)
        section = NumericInputSupport.normalizedStorageText(section, kind: .quantity, preservingInvalid: false)
        voltage = NumericInputSupport.normalizedStorageText(voltage, kind: .quantity, preservingInvalid: false)
    }

    private func calcAndSave() {
        calc()
        if !resultText.isEmpty {
            saveHistory(resultText.components(separatedBy: "\n").first ?? "")
        }
    }

    private func saveHistory(_ r: String) {
        store.appendCalculationHistory(
            tool: String(localized: "电缆压降"),
            input: "\(current)A, \(length)m, \(section)mm²",
            result: r
        )
    }

    private func formatSection(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private func presentError(_ message: String) {
        resultText = message
        resultModel = .error(message)
    }
}

enum WireMaterial: String, Hashable {
    case copper, aluminum
}
