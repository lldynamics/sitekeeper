import SwiftUI

struct UnitConverterView: View {
    @State private var category: ConvCategory = .length
    @State private var inputValue: String = "1"
    @State private var fromUnit: String = "米"
    @State private var toUnit: String = "英尺"

    @State private var resultText: String = ""

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
                Picker("类别", selection: $category) {
                    ForEach(ConvCategory.allCases, id: \.self) { c in
                        Text(c.displayName).tag(c)
                    }
                }
                .onChange(of: category) { _, _ in
                    let opts = unitOptions()
                    fromUnit = opts.first ?? ""
                    toUnit = opts.last ?? ""
                }

                LabeledContent("数值") {
                    TextField("1", text: $inputValue)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }

                Picker("从", selection: $fromUnit) {
                    ForEach(unitOptions(), id: \.self) { Text($0).tag($0) }
                }
                Picker("到", selection: $toUnit) {
                    ForEach(unitOptions(), id: \.self) { Text($0).tag($0) }
                }
            }

            Section {
                Button("换算") { convert() }
                    .frame(maxWidth: .infinity)
                    .fontWeight(.semibold)
            }

            if !resultText.isEmpty {
                Section("结果") {
                    Text(resultText)
                        .font(.system(.title3, design: .monospaced).weight(.medium))
                }
            }
        }
        .navigationTitle("单位换算")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func unitOptions() -> [String] {
        units[category]?.map(\.name) ?? []
    }

    private func convert() {
        guard let value = Double(inputValue) else {
            resultText = "请输入有效数值"
            return
        }
        guard let list = units[category] else { return }
        guard let from = list.first(where: { $0.name == fromUnit }),
              let to = list.first(where: { $0.name == toUnit }) else {
            resultText = "请选择单位"
            return
        }
        // value × from.factor → 基准单位 → ÷ to.factor → 目标单位
        let converted = value * from.factor / to.factor
        resultText = "\(trim(value)) \(fromUnit) = \(trim(converted)) \(toUnit)"
    }

    private func trim(_ v: Double) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 6
        return f.string(from: NSNumber(value: v)) ?? String(v)
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
