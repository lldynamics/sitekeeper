import SwiftUI

struct MeasurementCheckView: View {
    @State private var location = ""
    @State private var target = ""
    @State private var tolerance = ""
    @State private var unit = MeasurementCheckUnit.millimeters
    @State private var points = [MeasurementCheckPointInput(name: calculatorLocFormat("测点 %lld", Int64(1)), reading: "")]
    @State private var nextPointNumber = 2
    @State private var resultModel: CalculationResult?
    @State private var errorMessage: String?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var toleranceRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(kind: .quantity, requirement: .requiredNonNegative)
    }

    private var inputSnapshot: [String] {
        [location, target, tolerance, unit.rawValue]
            + points.flatMap { [$0.id.uuidString, $0.name, $0.reading] }
    }

    var body: some View {
        CalculatorForm(title: calculatorLoc("实测实量验收表"), focus: $isInputFocused) {
            Section(calculatorLoc("自设比较口径")) {
                TextField(calculatorLoc("部位（如二层客厅）"), text: $location)
                    .focused($isInputFocused)
                Picker(calculatorLoc("测量单位"), selection: $unit) {
                    ForEach(MeasurementCheckUnit.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                signedNumberField(title: calculatorLoc("用户目标值"), text: $target)
                CalculatorInputField(
                    title: calculatorLoc("用户允许偏差"), placeholder: "0", unit: unit.rawValue,
                    text: $tolerance, rule: toleranceRule,
                    showWhenEmpty: didAttemptSubmit, focus: $isInputFocused
                )
                CalculatorInlineNotice(message: calculatorLoc("仅按你填写的目标值和允许偏差比较，不代表规范或验收合规结论。"))
                Text(calculatorLoc("所有数值使用同一单位；切换单位只更改标记，不自动换算。目标值和读数可为负数，允许偏差可为 0。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(calculatorLocFormat("测点（%lld / 50）", Int64(points.count))) {
                ForEach($points) { $point in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(calculatorLoc("测点名称"), text: $point.name)
                            .focused($isInputFocused)
                        signedNumberField(title: calculatorLoc("实测读数"), text: $point.reading)
                        Button(role: .destructive) {
                            deletePoint(id: point.id)
                        } label: {
                            Label(calculatorLoc("删除测点"), systemImage: "minus.circle")
                        }
                        .disabled(points.count <= 1)
                    }
                    .padding(.vertical, 4)
                }
                Button {
                    guard points.count < MeasurementCheckModel.maximumPointCount else { return }
                    points.append(MeasurementCheckPointInput(
                        name: calculatorLocFormat("测点 %lld", Int64(nextPointNumber)), reading: ""
                    ))
                    nextPointNumber += 1
                } label: {
                    Label(calculatorLoc("新增测点"), systemImage: "plus.circle")
                }
                .disabled(points.count >= MeasurementCheckModel.maximumPointCount)
            }

            Section {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.appRisk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                CalculatorPrimaryActionButton(title: calculatorLoc("比较实测值")) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calculate()
                }
            }

            if let resultModel {
                CalculatorResultPanel(cardTitle: calculatorLoc("实测实量验收表"), result: resultModel)
                if let recordText = resultModel.historyDraft?.result {
                    ShareLink(item: recordText) {
                        Label(calculatorLoc("分享检查记录"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .onChange(of: inputSnapshot) { _, _ in
            resultModel = nil
            errorMessage = nil
        }
    }

    private func deletePoint(id: UUID) {
        guard points.count > 1 else { return }
        points.removeAll { $0.id == id }
    }

    private func signedNumberField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                HStack(spacing: 6) {
                    TextField("0", text: text)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                        .focused($isInputFocused)
                    Text(unit.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text(title)
            }
            if (didAttemptSubmit || !text.wrappedValue.isEmpty),
               MeasurementCheckModel.signedDecimal(text.wrappedValue) == nil {
                Text(calculatorLoc("请输入有效数值（可为负数）。"))
                    .font(.caption)
                    .foregroundStyle(.appRisk)
            }
        }
    }

    private func calculate() {
        resultModel = nil
        errorMessage = nil
        do {
            let summary = try MeasurementCheckModel.evaluate(
                location: location, targetText: target, toleranceText: tolerance, unit: unit, points: points
            )
            let percentage = CalculatorFormatting.decimal(
                Double(summary.withinCount) / Double(summary.points.count) * 100, maxFractionDigits: 2
            )
            let summaryItems = [
                CalculationResult.item(calculatorLoc("部位"), summary.location),
                CalculationResult.item(calculatorLoc("用户目标值"), valueText(summary.target)),
                CalculationResult.item(calculatorLoc("用户允许偏差"), "±\(valueText(summary.tolerance))"),
                CalculationResult.item(
                    calculatorLoc("范围内数量"),
                    calculatorLocFormat("%lld / %lld（%@%%）", Int64(summary.withinCount), Int64(summary.points.count), percentage)
                ),
                CalculationResult.item(
                    calculatorLoc("超出自设偏差数量"), String(summary.outsideCount),
                    status: summary.outsideCount > 0 ? .warning : .normal
                ),
                CalculationResult.item(
                    calculatorLoc("比较说明"),
                    calculatorLoc("仅按你填写的目标值和允许偏差比较，不代表规范或验收合规结论。")
                ),
            ]
            let pointItems = summary.points.enumerated().map { index, point in
                CalculationResult.item(
                    calculatorLocFormat("%lld. %@", Int64(index + 1), point.name),
                    calculatorLocFormat(
                        "读数 %@；差值 %@；%@",
                        valueText(point.reading), signedValueText(point.difference),
                        calculatorLoc(point.isWithinTolerance ? "在自设范围内" : "超出自设偏差")
                    ),
                    status: point.isWithinTolerance ? .normal : .warning
                )
            }
            var result = CalculationResult(
                headline: calculatorLocFormat(
                    "%lld 个测点，%lld 个在自设范围内，%lld 个超出",
                    Int64(summary.points.count), Int64(summary.withinCount), Int64(summary.outsideCount)
                ),
                formula: calculatorLoc("差值 = 实测读数 − 用户目标值；|差值| ≤ 用户允许偏差时在范围内，等于边界也计入。"),
                sections: [
                    .init(title: calculatorLoc("比较汇总"), items: summaryItems),
                    .init(title: calculatorLoc("逐点记录"), items: pointItems),
                ]
            )
            result.historyDraft = .init(
                tool: calculatorLoc("实测实量验收表"),
                input: calculatorLocFormat(
                    "%@；目标 %@；允许偏差 ±%@；%lld 个测点",
                    summary.location, valueText(summary.target), valueText(summary.tolerance), Int64(summary.points.count)
                ),
                result: result.plainText(title: calculatorLoc("实测实量验收表"))
            )
            resultModel = result
        } catch let error as MeasurementCheckModel.ValidationError {
            errorMessage = validationMessage(error)
        } catch {
            errorMessage = calculatorLoc("无法比较这些读数，请核对输入。")
        }
    }

    private func valueText(_ value: Decimal) -> String {
        "\(NSDecimalNumber(decimal: value).stringValue) \(unit.rawValue)"
    }

    private func signedValueText(_ value: Decimal) -> String {
        (value > .zero ? "+" : "") + valueText(value)
    }

    private func validationMessage(_ error: MeasurementCheckModel.ValidationError) -> String {
        switch error {
        case .missingLocation:
            calculatorLoc("请填写检查部位。")
        case .invalidTarget:
            calculatorLoc("请填写有效的目标值，可为负数。")
        case .invalidTolerance:
            calculatorLoc("请填写有效的非负允许偏差，可为 0。")
        case .invalidPointCount:
            calculatorLoc("请保留 1–50 个测点。")
        case .missingPointName(let index):
            calculatorLocFormat("请填写第 %lld 个测点的名称。", Int64(index))
        case .invalidReading(let index):
            calculatorLocFormat("请核对第 %lld 个测点的读数，可为负数。", Int64(index))
        case .unrepresentableDifference(let index):
            calculatorLocFormat("第 %lld 个测点的差值超出可精确表示范围，请减小输入。", Int64(index))
        }
    }
}
