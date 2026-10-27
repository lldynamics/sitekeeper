import SwiftUI

struct UnitConverterView: View {
    @State private var categoryRawValue: String = ConvCategory.length.rawValue
    @State private var inputValue: String = "1"
    @State private var fromUnitID: String = UnitOptionID.lengthMeter.rawValue
    @State private var toUnitID: String = UnitOptionID.lengthFoot.rawValue

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
            rangeMessage: CalculatorCopy.unitInputRange
        )
    }

    private var inputValidation: NumericInputFieldValidation {
        inputRule.validate(inputValue)
    }

    // factor: 1 unit = factor base units (base unit: meter / square meter / kilogram)
    private let units: [ConvCategory: [UnitOption]] = [
        .length: [
            UnitOption(id: .lengthMeter, factor: 1, displayName: CalculatorCopy.unitMeter),
            UnitOption(id: .lengthKilometer, factor: 1000, displayName: CalculatorCopy.unitKilometer),
            UnitOption(id: .lengthCentimeter, factor: 0.01, displayName: CalculatorCopy.unitCentimeter),
            UnitOption(id: .lengthMillimeter, factor: 0.001, displayName: CalculatorCopy.unitMillimeter),
            UnitOption(id: .lengthFoot, factor: 0.3048, displayName: CalculatorCopy.unitFoot),
            UnitOption(id: .lengthInch, factor: 0.0254, displayName: CalculatorCopy.unitInch),
            UnitOption(id: .lengthYard, factor: 0.9144, displayName: CalculatorCopy.unitYard),
        ],
        .area: [
            UnitOption(id: .areaSquareMeter, factor: 1, displayName: CalculatorCopy.unitSquareMeter),
            UnitOption(id: .areaSquareKilometer, factor: 1_000_000, displayName: CalculatorCopy.unitSquareKilometer),
            UnitOption(id: .areaHectare, factor: 10_000, displayName: CalculatorCopy.unitHectare),
            UnitOption(id: .areaMu, factor: 666.667, displayName: CalculatorCopy.unitMu),
            UnitOption(id: .areaSquareFoot, factor: 0.092903, displayName: CalculatorCopy.unitSquareFoot),
        ],
        .weight: [
            UnitOption(id: .weightKilogram, factor: 1, displayName: CalculatorCopy.unitKilogram),
            UnitOption(id: .weightTon, factor: 1000, displayName: CalculatorCopy.unitTon),
            UnitOption(id: .weightGram, factor: 0.001, displayName: CalculatorCopy.unitGram),
            UnitOption(id: .weightPound, factor: 0.453592, displayName: CalculatorCopy.unitPound),
            UnitOption(id: .weightOunce, factor: 0.0283495, displayName: CalculatorCopy.unitOunce),
        ],
    ]

    var body: some View {
        CalculatorForm(title: CalculatorCopy.unitConverterTool, focus: $isInputFocused) {
            Section(CalculatorCopy.unitConverterSection) {
                Picker(CalculatorCopy.unitCategory, selection: $categoryRawValue) {
                    ForEach(ConvCategory.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c.rawValue)
                    }
                }
                .onChange(of: categoryRawValue) { _, _ in
                    let options = unitOptions()
                    fromUnitID = options.first?.id.rawValue ?? ""
                    toUnitID = options.dropFirst().first?.id.rawValue ?? options.first?.id.rawValue ?? ""
                }

                CalculatorInputField(
                    title: CalculatorCopy.unitValue,
                    placeholder: "1",
                    text: $inputValue,
                    rule: inputRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.unitQuickValue, options: ["0.5", "1", "5", "10", "100"], selection: $inputValue)

                Picker(CalculatorCopy.unitFrom, selection: $fromUnitID) {
                    ForEach(unitOptions()) { option in
                        Text(option.displayName).tag(option.id.rawValue)
                    }
                }
                Picker(CalculatorCopy.unitTo, selection: $toUnitID) {
                    ForEach(unitOptions()) { option in
                        Text(option.displayName).tag(option.id.rawValue)
                    }
                }
                CalculatorInlineNotice(message: CalculatorCopy.unitNotice)
            }

            Section {
                CalculatorPrimaryActionButton(title: CalculatorCopy.actionConvert) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    convert()
                }
            }

            if let resultModel {
                CalculatorResultPanel(cardTitle: CalculatorCopy.unitConverterResultTitle, result: resultModel)
            }
        }
        .onAppear(perform: normalizeUnits)
    }

    private func unitOptions() -> [UnitOption] {
        units[category] ?? []
    }

    private func convert() {
        guard let value = inputValidation.doubleValue else {
            resultModel = nil
            return
        }
        guard let from = unitOptions().first(where: { $0.id.rawValue == fromUnitID }),
              let to = unitOptions().first(where: { $0.id.rawValue == toUnitID }) else {
            presentError(CalculatorCopy.unitSelectUnit)
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
            headline: CalculatorFormatting.valueWithUnit(converted, unit: to.displayName),
            formula: CalculatorResultCopy.unitConvertFormula(),
            items: [
                CalculationResult.item(
                    CalculatorResultLabel.input,
                    CalculatorFormatting.valueWithUnit(value, unit: from.displayName)
                ),
                CalculationResult.item(CalculatorResultLabel.category, category.displayName),
                CalculationResult.item(
                    CalculatorResultLabel.output,
                    CalculatorFormatting.valueWithUnit(converted, unit: to.displayName),
                    status: .pass
                ),
            ]
        )
        inputValue = NumericInputSupport.normalizedStorageText(inputValue, kind: .quantity, preservingInvalid: false)
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
        case .length: CalculatorCopy.unitLengthCategory
        case .area: CalculatorCopy.unitAreaCategory
        case .weight: CalculatorCopy.unitWeightCategory
        }
    }
}
