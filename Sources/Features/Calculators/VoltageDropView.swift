import SwiftUI

struct VoltageDropView: View {
    @State private var current: String = ""
    @State private var length: String = ""
    @State private var materialRawValue: String = WireMaterial.copper.rawValue
    @State private var section: String = "2.5"
    @State private var voltage: String = "220"
    @State private var isLoopLength: Bool = false // true = loop length(round trip included), false = one-way length

    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private let resistivityCopper: Double = 0.0175
    private let resistivityAluminum: Double = 0.0283

    let commonSections = EngineeringCalculations.standardWireSections.map(CalculatorFormatting.section)
    private var material: WireMaterial {
        StringEnumFallback.value(materialRawValue, default: WireMaterial.copper)
    }

    private var currentRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.1,
            max: 100_000,
            rangeMessage: CalculatorCopy.voltageDropCurrentRange
        )
    }

    private var lengthRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 1,
            max: 1_000_000,
            rangeMessage: CalculatorCopy.voltageDropLengthRange
        )
    }

    private var sectionRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 1,
            max: 20_000,
            rangeMessage: CalculatorCopy.voltageDropSectionRange
        )
    }

    private var voltageRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 12,
            max: 100_000,
            rangeMessage: CalculatorCopy.voltageDropVoltageRange
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
        CalculatorForm(title: CalculatorCopy.voltageDropTool, focus: $isInputFocused) {
            Section(CalculatorCopy.voltageDropLineSection) {
                CalculatorInputField(
                    title: CalculatorCopy.voltageDropCurrent,
                    placeholder: CalculatorCopy.voltageDropCurrentPlaceholder,
                    unit: "A",
                    text: $current,
                    rule: currentRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.voltageDropCommonCurrent, options: ["10", "16", "20", "32", "50", "63"], selection: $current)
                CalculatorInputField(
                    title: CalculatorCopy.voltageDropLength,
                    placeholder: CalculatorCopy.voltageDropLengthPlaceholder,
                    unit: "m",
                    text: $length,
                    rule: lengthRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.voltageDropCommonLength, options: ["20", "50", "80", "100", "150", "200"], selection: $length)
                Toggle(CalculatorCopy.voltageDropLoopLength, isOn: $isLoopLength)
                Picker(CalculatorCopy.voltageDropMaterial, selection: $materialRawValue) {
                    Text(CalculatorCopy.voltageDropCopper).tag(WireMaterial.copper.rawValue)
                    Text(CalculatorCopy.voltageDropAluminum).tag(WireMaterial.aluminum.rawValue)
                }
                CalculatorInputField(
                    title: CalculatorCopy.voltageDropSectionArea,
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
                CalculatorInputField(
                    title: CalculatorCopy.voltageDropRatedVoltage,
                    placeholder: "220",
                    unit: "V",
                    text: $voltage,
                    rule: voltageRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.voltageDropVoltagePreset, options: ["220", "380"], selection: $voltage)
            }

            Section(CalculatorCopy.voltageDropAmpacitySection) {
                CalculatorInlineNotice(
                    message: CalculatorCopy.voltageDropAmpacityNotice
                )
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(EngineeringCalculations.standardWireSections, id: \.self) { item in
                            VStack(spacing: 2) {
                                Text(CalculatorFormatting.section(item)).font(.caption2)
                                Text(CalculatorFormatting.amperes(EngineeringCalculations.ampacity(for: item, isCopper: material == .copper), digits: 0))
                                    .font(.caption.weight(.medium)).foregroundStyle(Color.appDoc)
                            }
                            .padding(6)
                            .background(CalculatorFormatting.section(item) == section ? Color.appDocSurfaceSubtle : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }

            Section {
                CalculatorPrimaryActionButton(title: CalculatorCopy.actionCalculate) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calcAndPrepareHistory()
                }
            }

            if let resultModel {
                CalculatorResultPanel(
                    sectionTitle: CalculatorCopy.resultSection,
                    cardTitle: CalculatorCopy.voltageDropResultTitle,
                    result: resultModel
                )
            }
        }
    }
}

private extension VoltageDropView {
    func calc() {
        guard let i = currentValidation.doubleValue,
              let l = lengthValidation.doubleValue,
              let s = sectionValidation.doubleValue,
              let v = voltageValidation.doubleValue else {
            resultModel = nil
            return
        }
        guard EngineeringCalculations.standardWireSections.contains(where: { abs($0 - s) < 0.000_1 }) else {
            presentError(calculatorLoc("请输入标准电缆截面，或从常用截面中选择。"))
            return
        }
        let isCopper = material == .copper
        let rho = isCopper ? resistivityCopper : resistivityAluminum
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
        resultModel = makeResult(current: i, length: l, section: s, voltage: v, drop: drop)

        current = NumericInputSupport.normalizedStorageText(current, kind: .quantity, preservingInvalid: false)
        length = NumericInputSupport.normalizedStorageText(length, kind: .quantity, preservingInvalid: false)
        section = NumericInputSupport.normalizedStorageText(section, kind: .quantity, preservingInvalid: false)
        voltage = NumericInputSupport.normalizedStorageText(voltage, kind: .quantity, preservingInvalid: false)
    }

    private func makeResult(
        current i: Double, length l: Double, section s: Double, voltage v: Double,
        drop: EngineeringCalculations.VoltageDropMetrics
    ) -> CalculationResult {
        let isCopper = material == .copper
        let effectiveLength = isLoopLength ? l : l * 2
        let recommended = EngineeringCalculations.recommendedWireSection(current: i, length: l, voltage: v, isLoopLength: isLoopLength, isCopper: isCopper)
        let ampacity = EngineeringCalculations.ampacity(for: s, isCopper: isCopper)
        let ampNote = CalculatorResultCopy.ampacityCheck(ampacity: ampacity, loadCurrent: i)
        let recNote = CalculatorResultCopy.recommendedSection(recommended)
        let dropPercent = drop.dropPercent
        let warning = dropPercent > 5
        let materialName = material == .copper ? CalculatorCopy.voltageDropCopper : CalculatorCopy.voltageDropAluminum
        return .singleSection(
            headline: CalculatorResultCopy.voltageDropHeadline(percent: dropPercent),
            formula: CalculatorResultCopy.voltageDropFormula(),
            items: [
                CalculationResult.item(CalculatorResultLabel.material, materialName),
                CalculationResult.item(
                    CalculatorResultLabel.effectiveLength,
                    CalculatorFormatting.meters(effectiveLength, digits: 1)
                ),
                CalculationResult.item(
                    CalculatorResultLabel.lineResistance,
                    CalculatorFormatting.ohms(drop.resistance, digits: 3)
                ),
                CalculationResult.item(
                    CalculatorResultLabel.voltageDrop,
                    CalculatorFormatting.volts(drop.dropV, digits: 2),
                    status: warning ? .warning : .pass
                ),
                CalculationResult.item(CalculatorResultLabel.ampacityCheck, ampNote, status: i <= ampacity ? .pass : .warning),
                CalculationResult.item(CalculatorResultLabel.recommendedSection, recNote, status: warning ? .warning : .normal),
            ]
        )
    }

    private func calcAndPrepareHistory() {
        calc()
        let resultHeadline = CalculatorPlainTextExport.headline(
            from: resultModel,
            title: CalculatorCopy.voltageDropResultTitle
        )
        if !resultHeadline.isEmpty {
            resultModel?.historyDraft = .init(
                tool: CalculatorCopy.voltageDropTool,
                input: CalculatorHistoryCopy.voltageDropInput(
                    current: current,
                    length: length,
                    section: section
                ),
                result: resultHeadline
            )
        }
    }

    private func presentError(_ message: String) {
        resultModel = .error(message)
    }
}

enum WireMaterial: String, Hashable {
    case copper, aluminum
}
