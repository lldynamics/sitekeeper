import SwiftUI

struct UnitConverterView: View {
    @AppStorage(UserPreferenceKeys.Calculator.unitCategory) private var categoryRawValue: String = ConvCategory.length.rawValue
    @AppStorage(UserPreferenceKeys.Calculator.unitInputValue) private var inputValue: String = "1"
    @AppStorage(UserPreferenceKeys.Calculator.unitFromUnit) private var fromUnit: String = "米"
    @AppStorage(UserPreferenceKeys.Calculator.unitToUnit) private var toUnit: String = "英尺"

    @State private var resultText: String = ""
    @State private var resultModel: CalculationResult?
    @FocusState private var isInputFocused: Bool
    private var category: ConvCategory {
        StringEnumFallback.value(categoryRawValue, default: ConvCategory.length)
    }

    // factor: 1 unit = factor 个基准单位（基准为米/平方米/千克）
    private let units: [ConvCategory: [(name: String, factor: Double)]] = [
        .length: [
            ("米", 1),
            ("千米", 1000),
            ("厘米", 0.01),
            ("毫米", 0.001),
            ("英尺", 0.3048),
            ("英寸", 0.0254),
            ("码", 0.9144),
        ],
        .area: [
            ("平方米", 1),
            ("平方千米", 1_000_000),
            ("公顷", 10000),
            ("亩", 666.667),
            ("平方英尺", 0.092903),
        ],
        .weight: [
            ("千克", 1),
            ("吨", 1000),
            ("克", 0.001),
            ("磅", 0.453592),
            ("盎司", 0.0283495),
        ],
    ]

    var body: some View {
        Form {
            Section("换算") {
                Picker("类别", selection: $categoryRawValue) {
                    ForEach(ConvCategory.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c.rawValue)
                    }
                }
                .onChange(of: categoryRawValue) { _, _ in
                    let opts = unitOptions()
                    fromUnit = opts.first ?? ""
                    toUnit = opts.last ?? ""
                }

                LabeledContent("数值") {
                    TextField("1", text: $inputValue)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                }
                CalculatorValidationHint(message: rangeMessage(inputValue, min: 0, max: 1_000_000_000, hint: "请输入 0–1000000000"))
                CalculatorPresetChips(title: "快捷值", options: ["0.5", "1", "5", "10", "100"], selection: $inputValue)

                Picker("从", selection: $fromUnit) {
                    ForEach(unitOptions(), id: \.self) { Text($0).tag($0) }
                }
                Picker("到", selection: $toUnit) {
                    ForEach(unitOptions(), id: \.self) { Text($0).tag($0) }
                }
            }

            Section {
                Button("换算") {
                    isInputFocused = false
                    convert()
                }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }

            if !resultText.isEmpty, let resultModel {
                Section("结果") {
                    CalculatorResultCard(
                        title: "单位换算",
                        result: resultModel,
                        copyText: resultText
                    )
                }
            }
        }
        .navigationTitle("单位换算")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
            }
        }
        .onAppear(perform: normalizeUnits)
    }

    private func unitOptions() -> [String] {
        units[category]?.map(\.name) ?? []
    }

    private func convert() {
        guard let value = CalculatorInputParser.double(inputValue) else {
            presentError("请输入有效数值")
            return
        }
        guard let list = units[category] else {
            presentError("换算配置缺失")
            return
        }
        guard let from = list.first(where: { $0.name == fromUnit }),
              let to = list.first(where: { $0.name == toUnit }) else {
            presentError("请选择单位")
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
            headline: "\(trim(converted)) \(toUnit)",
            formula: "输出值 = 输入值×源单位系数÷目标单位系数",
            items: [
                CalculationResult.item("输入", "\(trim(value)) \(fromUnit)"),
                CalculationResult.item("类别", category.displayName),
                CalculationResult.item("输出", "\(trim(converted)) \(toUnit)", status: .pass),
            ]
        )
        resultText = "\(trim(value)) \(fromUnit) = \(trim(converted)) \(toUnit)"
    }

    private func trim(_ v: Double) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 6
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private func normalizeUnits() {
        let options = unitOptions()
        if !options.contains(fromUnit) {
            fromUnit = options.first ?? ""
        }
        if !options.contains(toUnit) {
            toUnit = options.dropFirst().first ?? options.first ?? ""
        }
    }

    private func rangeMessage(_ text: String, min: Double, max: Double, hint: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = CalculatorInputParser.double(trimmed) else { return "请输入数值" }
        return (value >= min && value <= max) ? nil : hint
    }

    private func presentError(_ message: String) {
        resultText = message
        resultModel = .error(message)
    }
}

enum ConvCategory: String, CaseIterable {
    case length
    case area
    case weight

    var displayName: String {
        switch self {
        case .length: "长度"
        case .area: "面积"
        case .weight: "重量"
        }
    }
}
