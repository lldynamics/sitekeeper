import SwiftUI

struct MaterialUsageCalcView: View {
    @State private var materialName = ""
    @State private var area = ""
    @State private var consumption = ""
    @State private var coats = "1"
    @State private var waste = "0"
    @State private var packageSize = ""
    @State private var unit = "kg"
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var positiveRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity, requirement: .requiredPositive, min: 0.0001, max: 1_000_000,
            rangeMessage: calculatorLoc("请输入 0.0001–1000000")
        )
    }

    private var coatsRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity, requirement: .requiredPositive, max: 100,
            rangeMessage: calculatorLoc("请输入 1–100"),
            wholeNumberOnly: true
        )
    }

    private var wasteRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity, requirement: .requiredNonNegative, max: 100,
            rangeMessage: calculatorLoc("请输入 0–100")
        )
    }

    private var packageRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity, requirement: .optionalNonNegative, min: 0.0001, max: 1_000_000,
            rangeMessage: calculatorLoc("请输入 0.0001–1000000")
        )
    }

    private var inputSnapshot: [String] {
        [materialName, area, consumption, coats, waste, packageSize, unit]
    }

    var body: some View {
        CalculatorForm(title: calculatorLoc("材料用量与损耗"), focus: $isInputFocused) {
            Section(calculatorLoc("用量参数")) {
                TextField(calculatorLoc("材料名称（如防水涂料）"), text: $materialName)
                    .focused($isInputFocused)
                if didAttemptSubmit, materialName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(calculatorLoc("请填写材料名称"))
                        .font(.caption)
                        .foregroundStyle(.appRisk)
                }
                Picker(calculatorLoc("计量单位"), selection: $unit) {
                    Text("kg").tag("kg")
                    Text("L").tag("L")
                }
                CalculatorInputField(
                    title: calculatorLoc("施工面积"), placeholder: "0", unit: "m²",
                    text: $area, rule: positiveRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused
                )
                CalculatorInputField(
                    title: calculatorLoc("单遍每平方米用量"), placeholder: "0", unit: "\(unit)/m²",
                    text: $consumption, rule: positiveRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused
                )
                CalculatorInputField(
                    title: calculatorLoc("施工遍数"), placeholder: "1",
                    text: $coats, rule: coatsRule, keyboardType: .numberPad,
                    showWhenEmpty: didAttemptSubmit, focus: $isInputFocused
                )
                CalculatorInputField(
                    title: calculatorLoc("损耗"), placeholder: "0", unit: "%",
                    text: $waste, rule: wasteRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused
                )
                CalculatorInlineNotice(message: calculatorLoc("单耗按产品说明或现场实测填写，指单遍用量；kg 与 L 不自动互换。"))
            }
            Section(calculatorLoc("包装与采购")) {
                CalculatorInputField(
                    title: calculatorLoc("每包净含量（选填）"), placeholder: calculatorLoc("选填"), unit: unit,
                    text: $packageSize, rule: packageRule, focus: $isInputFocused
                )
                Text(calculatorLoc("未填包装量时，采购量向上保留 4 位小数；填写后按未舍入用量计算整包数。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                CalculatorPrimaryActionButton(title: calculatorLoc("计算用量")) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calculate()
                }
            }
            if let resultModel {
                CalculatorResultPanel(cardTitle: calculatorLoc("材料用量与损耗"), result: resultModel)
            }
        }
        .onChange(of: inputSnapshot) { _, _ in resultModel = nil }
    }

    private func calculate() {
        resultModel = nil
        let name = materialName.trimmingCharacters(in: .whitespacesAndNewlines)
        let areaInput = positiveRule.validate(area)
        let consumptionInput = positiveRule.validate(consumption)
        let coatsInput = coatsRule.validate(coats)
        let wasteInput = wasteRule.validate(waste)
        let packageInput = packageRule.validate(packageSize)
        guard !name.isEmpty,
              [areaInput, consumptionInput, coatsInput, wasteInput, packageInput].allSatisfy({ $0.errorMessage == nil }),
              let areaValue = areaInput.decimalValue,
              let consumptionValue = consumptionInput.decimalValue,
              let coatsValue = coatsInput.decimalValue,
              let wasteValue = wasteInput.decimalValue else { return }

        let net = DecimalMath.multiply(DecimalMath.multiply(areaValue, consumptionValue), coatsValue)
        let wasteFactor = DecimalMath.add(1, DecimalMath.divide(wasteValue, by: 100))
        var unroundedTotal = DecimalMath.multiply(net, wasteFactor)
        guard !net.isNaN, !unroundedTotal.isNaN else {
            resultModel = .error(calculatorLoc("计算结果超出可表示范围，请减小输入。"))
            return
        }
        var total = Decimal.zero
        NSDecimalRound(&total, &unroundedTotal, 4, .up)
        var purchase = total
        var items = [
            CalculationResult.item(calculatorLoc("材料名称"), name),
            CalculationResult.item(calculatorLoc("理论净用量"), quantityText(net)),
            CalculationResult.item(calculatorLoc("含损耗用量"), quantityText(unroundedTotal)),
        ]
        if let packageValue = packageInput.decimalValue {
            var rawPackageCount = unroundedTotal / packageValue
            var packageCount = Decimal.zero
            NSDecimalRound(&packageCount, &rawPackageCount, 0, .up)
            purchase = DecimalMath.multiply(packageCount, packageValue)
            guard !purchase.isNaN, !packageCount.isNaN else {
                resultModel = .error(calculatorLoc("计算结果超出可表示范围，请减小输入。"))
                return
            }
            items.append(CalculationResult.item(calculatorLoc("每包净含量"), quantityText(packageValue)))
            items.append(CalculationResult.item(calculatorLoc("整包数量"), NSDecimalNumber(decimal: packageCount).stringValue))
            items.append(CalculationResult.item(calculatorLoc("采购余量"), quantityText(DecimalMath.subtract(purchase, unroundedTotal))))
        }
        items.append(CalculationResult.item(calculatorLoc("建议采购量"), quantityText(purchase)))
        items.append(CalculationResult.item(
            calculatorLoc("采购口径"),
            calculatorLoc("未填包装量时，采购量向上保留 4 位小数；填写后按未舍入用量计算整包数。")
        ))
        items.append(CalculationResult.item(
            calculatorLoc("计算参数"),
            calculatorLocFormat("面积 %@ m²；单遍用量 %@ %@/m²；%@ 遍；损耗 %@%%",
                area, consumption, unit, coats, waste)
        ))
        items.append(CalculationResult.item(
            calculatorLoc("材料单带入规则"),
            calculatorLoc("带入建议采购量与当前计量单位，单价留空待核对。")
        ))
        var result = CalculationResult.singleSection(
            headline: calculatorLocFormat("建议采购 %@", quantityText(purchase)),
            formula: calculatorLoc("净用量 = 面积 × 单遍用量 × 遍数；含损耗用量 = 净用量 × (1 + 损耗%)。"),
            items: items
        )
        result.materialDraft = CalculatorMaterialDraft(name: name, quantity: QuantityValue(purchase), unit: unit)
        result.historyDraft = .init(
            tool: calculatorLoc("材料用量与损耗"),
            input: calculatorLocFormat("%@；面积 %@ m²；单遍用量 %@ %@/m²；%@ 遍；损耗 %@%%；每包 %@ %@",
                name, area, consumption, unit, coats, waste,
                packageSize.isEmpty ? calculatorLoc("未填写") : packageSize, unit),
            result: result.plainText(title: calculatorLoc("材料用量与损耗"))
        )
        resultModel = result
    }

    private func quantityText(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .current
        formatter.maximumFractionDigits = 38
        return "\(formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue) \(unit)"
    }
}
