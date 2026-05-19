import SwiftUI

struct UnitConverterView: View {
    @AppStorage(UserPreferenceKeys.Calculator.unitCategory) private var categoryRawValue: String = ConvCategory.length.rawValue
    @AppStorage(UserPreferenceKeys.Calculator.unitInputValue) private var inputValue: String = "1"
    @AppStorage(UserPreferenceKeys.Calculator.unitFromUnit) private var fromUnitID: String = UnitOptionID.lengthMeter.rawValue
    @AppStorage(UserPreferenceKeys.Calculator.unitToUnit) private var toUnitID: String = UnitOptionID.lengthFoot.rawValue

    @State private var resultText: String = ""
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var category: ConvCategory {
        StringEnumFallback.value(categoryRawValue, default: ConvCategory.length)
    }

    private var inputRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredNonNegative,
            min: 0,
            max: 1_000_000_000,
            rangeMessage: calculatorLoc(String(localized: "请输入 0–1000000000"))
        )
    }

    private var inputValidation: NumericInputFieldValidation {
        inputRule.validate(inputValue)
    }

    // factor: 1 unit = factor base units (base unit: meter / square meter / kilogram)
    private let units: [ConvCategory: [UnitOption]] = [
        .length: [
            UnitOption(id: .lengthMeter, factor: 1, displayName: String(localized: "米")),
            UnitOption(id: .lengthKilometer, factor: 1000, displayName: String(localized: "千米")),
            UnitOption(id: .lengthCentimeter, factor: 0.01, displayName: String(localized: "厘米")),
            UnitOption(id: .lengthMillimeter, factor: 0.001, displayName: String(localized: "毫米")),
            UnitOption(id: .lengthFoot, factor: 0.3048, displayName: String(localized: "英尺")),
            UnitOption(id: .lengthInch, factor: 0.0254, displayName: String(localized: "英寸")),
            UnitOption(id: .lengthYard, factor: 0.9144, displayName: String(localized: "码")),
        ],
        .area: [
            UnitOption(id: .areaSquareMeter, factor: 1, displayName: String(localized: "平方米")),
            UnitOption(id: .areaSquareKilometer, factor: 1_000_000, displayName: String(localized: "平方千米")),
            UnitOption(id: .areaHectare, factor: 10_000, displayName: String(localized: "公顷")),
            UnitOption(id: .areaMu, factor: 666.667, displayName: String(localized: "亩")),
            UnitOption(id: .areaSquareFoot, factor: 0.092903, displayName: String(localized: "平方英尺")),
        ],
        .weight: [
            UnitOption(id: .weightKilogram, factor: 1, displayName: String(localized: "千克")),
            UnitOption(id: .weightTon, factor: 1000, displayName: String(localized: "吨")),
            UnitOption(id: .weightGram, factor: 0.001, displayName: String(localized: "克")),
            UnitOption(id: .weightPound, factor: 0.453592, displayName: String(localized: "磅")),
            UnitOption(id: .weightOunce, factor: 0.0283495, displayName: String(localized: "盎司")),
        ],
    ]

    var body: some View {
        Form {
            Section(String(localized: "换算")) {
                Picker(String(localized: "类别"), selection: $categoryRawValue) {
                    ForEach(ConvCategory.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c.rawValue)
                    }
                }
                .onChange(of: categoryRawValue) { _, _ in
                    let options = unitOptions()
                    fromUnitID = options.first?.id.rawValue ?? ""
                    toUnitID = options.dropFirst().first?.id.rawValue ?? options.first?.id.rawValue ?? ""
                }

                CalculatorValidatedNumericField(
                    title: String(localized: "数值"),
                    placeholder: "1",
                    text: $inputValue,
                    rule: inputRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: String(localized: "快捷值"), options: ["0.5", "1", "5", "10", "100"], selection: $inputValue)

                Picker(String(localized: "从"), selection: $fromUnitID) {
                    ForEach(unitOptions()) { option in
                        Text(option.displayName).tag(option.id.rawValue)
                    }
                }
                Picker(String(localized: "到"), selection: $toUnitID) {
                    ForEach(unitOptions()) { option in
                        Text(option.displayName).tag(option.id.rawValue)
                    }
                }
            }

            Section {
                Button(String(localized: "换算")) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    convert()
                }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
            }

            if let resultModel {
                Section(String(localized: "结果")) {
                    CalculatorResultCard(
                        title: String(localized: "单位换算"),
                        result: resultModel
                    )
                }
            }
        }
        .navigationTitle(String(localized: "单位换算"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
            }
        }
        .onAppear(perform: normalizeUnits)
    }

    private func unitOptions() -> [UnitOption] {
        units[category] ?? []
    }

    private func convert() {
        guard let value = inputValidation.doubleValue else {
            resultText = ""
            resultModel = nil
            return
        }
        guard let from = unitOptions().first(where: { $0.id.rawValue == fromUnitID }),
              let to = unitOptions().first(where: { $0.id.rawValue == toUnitID }) else {
            presentError(String(localized: "请选择单位"))
            return
        }

        let converted: Double
        switch EngineeringCalculations.unitConvertValidated(value: value, fromFactor: from.factor, toFactor: to.factor) {
        case .success(let output):
            converted = output
        case .failure(let error):
            presentError(error.userMessage)
            return
        }

        resultModel = .singleSection(
            headline: String(format: String(localized: "%@ %@"), trim(converted), to.displayName),
            formula: String(localized: "输出值 = 输入值×源单位系数÷目标单位系数"),
            items: [
                CalculationResult.item(
                    String(localized: "输入"),
                    String(format: String(localized: "%@ %@"), trim(value), from.displayName)
                ),
                CalculationResult.item(String(localized: "类别"), category.displayName),
                CalculationResult.item(
                    String(localized: "输出"),
                    String(format: String(localized: "%@ %@"), trim(converted), to.displayName),
                    status: .pass
                ),
            ]
        )
        resultText = String(format: String(localized: "%@ %@ = %@ %@"), trim(value), from.displayName, trim(converted), to.displayName)
        inputValue = NumericInputSupport.normalizedStorageText(inputValue, kind: .quantity, preservingInvalid: false)
    }

    private func trim(_ v: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: v)) ?? String(v)
    }

    private func normalizeUnits() {
        let options = unitOptions()
        guard !options.isEmpty else {
            fromUnitID = ""
            toUnitID = ""
            return
        }
        if !options.contains(where: { $0.id.rawValue == fromUnitID }) {
            fromUnitID = options.first?.id.rawValue ?? ""
        }
        if !options.contains(where: { $0.id.rawValue == toUnitID }) {
            toUnitID = options.dropFirst().first?.id.rawValue ?? options.first?.id.rawValue ?? ""
        }
    }

    private func presentError(_ message: String) {
        resultText = message
        resultModel = .error(message)
    }
}

private struct UnitOption: Identifiable {
    let id: UnitOptionID
    let factor: Double
    let displayName: String
}

private enum UnitOptionID: String {
    case lengthMeter = "length_m"
    case lengthKilometer = "length_km"
    case lengthCentimeter = "length_cm"
    case lengthMillimeter = "length_mm"
    case lengthFoot = "length_ft"
    case lengthInch = "length_in"
    case lengthYard = "length_yd"

    case areaSquareMeter = "area_m2"
    case areaSquareKilometer = "area_km2"
    case areaHectare = "area_hectare"
    case areaMu = "area_mu"
    case areaSquareFoot = "area_ft2"

    case weightKilogram = "weight_kg"
    case weightTon = "weight_ton"
    case weightGram = "weight_g"
    case weightPound = "weight_lb"
    case weightOunce = "weight_oz"
}

enum ConvCategory: String, CaseIterable {
    case length
    case area
    case weight

    var displayName: String {
        switch self {
        case .length: String(localized: "长度")
        case .area: String(localized: "面积")
        case .weight: String(localized: "重量")
        }
    }
}
