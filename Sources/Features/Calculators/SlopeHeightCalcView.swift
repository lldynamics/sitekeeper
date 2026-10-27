import SwiftUI

private enum SiteLengthUnit: String, CaseIterable, Identifiable {
    case meters = "m"
    case centimeters = "cm"
    case millimeters = "mm"

    var id: String { rawValue }
    var metersPerUnit: Double {
        switch self {
        case .meters: 1
        case .centimeters: 0.01
        case .millimeters: 0.001
        }
    }
}

private enum SiteSlopeUnit: String, CaseIterable, Identifiable {
    case percent = "%"
    case perMille = "‰"
    case ratio = "1:n"

    var id: String { rawValue }
}

struct SlopeHeightCalcView: View {
    @State private var calculatesHeight = true
    @State private var distance = ""
    @State private var height = ""
    @State private var slope = ""
    @State private var distanceUnit = SiteLengthUnit.meters
    @State private var heightUnit = SiteLengthUnit.millimeters
    @State private var slopeUnit = SiteSlopeUnit.percent
    @State private var rises = false
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var distanceRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity, requirement: .requiredPositive, min: 0.0001, max: 1_000_000,
            rangeMessage: calculatorLoc("请输入 0.0001–1000000")
        )
    }

    private var heightRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity, requirement: .requiredNonNegative, max: 1_000_000,
            rangeMessage: calculatorLoc("请输入 0–1000000")
        )
    }

    private var slopeRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: slopeUnit == .ratio ? .requiredPositive : .requiredNonNegative,
            min: slopeUnit == .ratio ? 0.0001 : 0,
            max: 1_000_000,
            rangeMessage: slopeUnit == .ratio
                ? calculatorLoc("请输入 0.0001–1000000") : calculatorLoc("请输入 0–1000000")
        )
    }

    private var inputSnapshot: [String] {
        [String(calculatesHeight), distance, height, slope, distanceUnit.rawValue,
            heightUnit.rawValue, slopeUnit.rawValue, String(rises)]
    }

    var body: some View {
        CalculatorForm(title: calculatorLoc("坡度与高差"), focus: $isInputFocused) {
            Section(calculatorLoc("已知条件")) {
                Picker(calculatorLoc("换算方式"), selection: $calculatesHeight) {
                    Text(calculatorLoc("坡度求高差")).tag(true)
                    Text(calculatorLoc("高差求坡度")).tag(false)
                }
                .pickerStyle(.segmented)
                Picker(calculatorLoc("水平距离单位"), selection: $distanceUnit) {
                    ForEach(SiteLengthUnit.allCases) { unit in Text(unit.rawValue).tag(unit) }
                }
                CalculatorInputField(
                    title: calculatorLoc("水平距离"), placeholder: "0", unit: distanceUnit.rawValue,
                    text: $distance, rule: distanceRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused
                )
                if calculatesHeight {
                    Picker(calculatorLoc("坡度单位"), selection: $slopeUnit) {
                        ForEach(SiteSlopeUnit.allCases) { unit in Text(unit.rawValue).tag(unit) }
                    }
                    CalculatorInputField(
                        title: slopeUnit == .ratio ? calculatorLoc("坡比 1:n 中的 n") : calculatorLoc("坡度"),
                        placeholder: "0", unit: slopeUnit == .ratio ? nil : slopeUnit.rawValue,
                        text: $slope, rule: slopeRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused
                    )
                } else {
                    Picker(calculatorLoc("高差单位"), selection: $heightUnit) {
                        ForEach(SiteLengthUnit.allCases) { unit in Text(unit.rawValue).tag(unit) }
                    }
                    CalculatorInputField(
                        title: calculatorLoc("高差"), placeholder: "0", unit: heightUnit.rawValue,
                        text: $height, rule: heightRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused
                    )
                }
                Picker(calculatorLoc("沿测量方向"), selection: $rises) {
                    Text(calculatorLoc("下降")).tag(false)
                    Text(calculatorLoc("上升")).tag(true)
                }
                CalculatorInlineNotice(message: calculatorLoc("距离使用水平投影长度；高差按绝对值输入，升降方向单独选择。坡比 1:n 表示竖向 1、水平 n。"))
            }
            Section {
                CalculatorPrimaryActionButton(title: calculatorLoc("换算")) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calculate()
                }
            }
            if let resultModel {
                CalculatorResultPanel(cardTitle: calculatorLoc("坡度与高差"), result: resultModel)
            }
        }
        .onChange(of: inputSnapshot) { _, _ in resultModel = nil }
    }

    private func calculate() {
        resultModel = nil
        let distanceInput = distanceRule.validate(distance)
        guard distanceInput.errorMessage == nil, let rawDistance = distanceInput.doubleValue else { return }
        let distanceMeters = rawDistance * distanceUnit.metersPerUnit
        let gradient: Double
        let heightMeters: Double
        if calculatesHeight {
            let slopeInput = slopeRule.validate(slope)
            guard slopeInput.errorMessage == nil, let value = slopeInput.doubleValue else { return }
            switch slopeUnit {
            case .percent: gradient = value / 100
            case .perMille: gradient = value / 1000
            case .ratio: gradient = 1 / value
            }
            heightMeters = distanceMeters * gradient
        } else {
            let heightInput = heightRule.validate(height)
            guard heightInput.errorMessage == nil, let value = heightInput.doubleValue else { return }
            heightMeters = value * heightUnit.metersPerUnit
            gradient = heightMeters / distanceMeters
        }
        guard gradient.isFinite, heightMeters.isFinite else {
            resultModel = .error(calculatorLoc("计算结果超出可表示范围，请减小输入。"))
            return
        }
        let direction = gradient == 0 ? calculatorLoc("水平") : calculatorLoc(rises ? "上升" : "下降")
        let ratio = gradient == 0
            ? calculatorLoc("水平（无高差）")
            : "1:\(formatted(1 / gradient))"
        var result = CalculationResult.singleSection(
            headline: calculatorLocFormat("高差 %@ mm · %@", formatted(heightMeters * 1000), direction),
            formula: calculatorLoc("坡度 = 高差 ÷ 水平距离；百分比 = 坡度 × 100；千分比 = 坡度 × 1000。"),
            items: [
                CalculationResult.item(calculatorLoc("水平距离"), "\(formatted(distanceMeters)) m"),
                CalculationResult.item(calculatorLoc("高差"), "\(formatted(heightMeters)) m / \(formatted(heightMeters * 100)) cm / \(formatted(heightMeters * 1000)) mm"),
                CalculationResult.item(calculatorLoc("坡度百分比"), "\(formatted(gradient * 100))%"),
                CalculationResult.item(calculatorLoc("坡度千分比"), "\(formatted(gradient * 1000))‰"),
                CalculationResult.item(calculatorLoc("坡比（竖向:水平）"), ratio),
                CalculationResult.item(calculatorLoc("方向"), direction),
            ]
        )
        let knownInput = calculatesHeight
            ? calculatorLocFormat("坡度 %@ %@", slope, slopeUnit.rawValue)
            : calculatorLocFormat("高差 %@ %@", height, heightUnit.rawValue)
        result.historyDraft = .init(
            tool: calculatorLoc("坡度与高差"),
            input: calculatorLocFormat("水平距离 %@ %@；%@；%@", distance, distanceUnit.rawValue, knownInput, direction),
            result: result.plainText(title: calculatorLoc("坡度与高差"))
        )
        resultModel = result
    }

    private func formatted(_ value: Double) -> String {
        if value != 0, abs(value) < 0.000001 {
            return String(format: "%.6g", locale: Locale.current, value)
        }
        return CalculatorFormatting.decimal(value, maxFractionDigits: 6)
    }
}
