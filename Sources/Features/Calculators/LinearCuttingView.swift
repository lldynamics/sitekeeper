import SwiftUI

struct LinearCuttingView: View {
    @State private var materialName = ""
    @State private var stockLength = ""
    @State private var kerf = "0"
    @State private var unit = LinearCuttingUnit.millimeters
    @State private var demands = [LinearCuttingDemand()]
    @State private var resultModel: CalculationResult?
    @State private var lastPlan: LinearCuttingPlan?
    @State private var errorMessage: String?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var lengthRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(kind: .quantity, requirement: .requiredPositive)
    }

    private var kerfRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(kind: .quantity, requirement: .requiredNonNegative)
    }

    private var countRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity, requirement: .requiredPositive, min: 1, max: 500,
            rangeMessage: calculatorLoc("请输入 1–500"), wholeNumberOnly: true
        )
    }

    private var inputSnapshot: [String] {
        [materialName, stockLength, kerf, unit.rawValue]
            + demands.flatMap { [$0.id.uuidString, $0.lengthText, $0.quantityText] }
    }

    var body: some View {
        CalculatorForm(title: calculatorLoc("定尺下料"), focus: $isInputFocused) {
            Section(calculatorLoc("原材与切缝")) {
                TextField(calculatorLoc("材料名称"), text: $materialName)
                    .focused($isInputFocused)
                Picker(calculatorLoc("长度单位"), selection: $unit) {
                    ForEach(LinearCuttingUnit.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                CalculatorInputField(
                    title: calculatorLoc("原材长度"), placeholder: "0", unit: unit.rawValue,
                    text: $stockLength, rule: lengthRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused
                )
                CalculatorInputField(
                    title: calculatorLoc("每段切缝"), placeholder: "0", unit: unit.rawValue,
                    text: $kerf, rule: kerfRule, showWhenEmpty: didAttemptSubmit, focus: $isInputFocused
                )
                Text(calculatorLoc("所有长度使用同一单位；切换单位会换算有效数字，未完成输入需重新核对。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(calculatorLoc("长度上限为 1000 m（1000000 mm），精度为 0.001 mm；更细输入会被拒绝，不自动舍入。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach($demands) { $demand in
                Section(calculatorLocFormat("段长需求 %lld", Int64(demandPosition(demand.id)))) {
                    CalculatorInputField(
                        title: calculatorLoc("成品段长"), placeholder: "0", unit: unit.rawValue,
                        text: $demand.lengthText, rule: lengthRule,
                        showWhenEmpty: didAttemptSubmit, focus: $isInputFocused
                    )
                    CalculatorInputField(
                        title: calculatorLoc("需求段数"), placeholder: "1",
                        text: $demand.quantityText, rule: countRule, keyboardType: .numberPad,
                        showWhenEmpty: didAttemptSubmit, focus: $isInputFocused
                    )
                    Button(calculatorLoc("删除这项需求"), role: .destructive) {
                        let id = demand.id
                        demands.removeAll { $0.id == id }
                    }
                    .disabled(demands.count <= 1)
                }
            }
            Section {
                Button {
                    demands.append(LinearCuttingDemand())
                } label: {
                    Label(calculatorLoc("增加段长需求"), systemImage: "plus.circle")
                }
                .disabled(demands.count >= LinearCuttingPlanner.maximumDemandCount)
                Text(calculatorLoc("最多 20 种段长、合计 500 段；不同段长不会自动拼接。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                CalculatorInlineNotice(message: calculatorLoc("每段计一次切缝，包含每根原材的最后一段；按保守用量排料，未计夹持和端头修整余量。"))
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.appRisk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                CalculatorPrimaryActionButton(title: calculatorLoc("生成下料方案")) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calculate()
                }
            }
            if let resultModel {
                if let lastPlan, !lastPlan.bars.isEmpty {
                    Section(calculatorLoc("排料图形示意")) {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(lastPlan.bars) { bar in
                                LinearCuttingVisualizerBar(bar: bar, plan: lastPlan)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                CalculatorResultPanel(cardTitle: calculatorLoc("定尺下料"), result: resultModel)
                if resultModel.primaryStatus != .fail {
                    Section {
                        ShareLink(item: resultModel.plainText(title: calculatorLoc("定尺下料"))) {
                            Label(calculatorLoc("分享下料记录"), systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .onChange(of: unit) { oldUnit, newUnit in
            stockLength = oldUnit.converting(stockLength, to: newUnit) ?? stockLength
            kerf = oldUnit.converting(kerf, to: newUnit) ?? kerf
            for index in demands.indices {
                demands[index].lengthText = oldUnit.converting(demands[index].lengthText, to: newUnit)
                    ?? demands[index].lengthText
            }
        }
        .onChange(of: inputSnapshot) { _, _ in
            resultModel = nil
            lastPlan = nil
            errorMessage = nil
        }
    }

    private func demandPosition(_ id: UUID) -> Int {
        (demands.firstIndex { $0.id == id } ?? 0) + 1
    }

    private func calculate() {
        resultModel = nil
        lastPlan = nil
        errorMessage = nil
        do {
            let plan = try LinearCuttingPlanner.makePlan(
                materialName: materialName, stockLengthText: stockLength,
                kerfText: kerf, unit: unit, demands: demands
            )
            lastPlan = plan
            resultModel = makeResult(plan)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func makeResult(_ plan: LinearCuttingPlan) -> CalculationResult {
        let length = plan.unit.formatted
        let demandText = plan.demands.map { "\(length($0.length)) × \($0.quantity)" }.joined(separator: "; ")
        let heuristicNotice = calculatorLoc("采用最长段优先的最佳适配启发式排料，结果为建议方案，非全局最优。")
        let kerfNotice = calculatorLoc("每段计一次切缝，包含每根原材的最后一段；按保守用量排料，未计夹持和端头修整余量。")
        let summary = CalculationResult.ResultSection(
            title: calculatorLoc("下料汇总"),
            items: [
                CalculationResult.item(calculatorLoc("材料名称"), plan.materialName),
                CalculationResult.item(calculatorLoc("原材长度"), length(plan.stockLength)),
                CalculationResult.item(calculatorLoc("长度单位"), plan.unit.rawValue),
                CalculationResult.item(calculatorLoc("每段切缝"), length(plan.kerf)),
                CalculationResult.item(calculatorLoc("段长与需求数量"), demandText),
                CalculationResult.item(calculatorLoc("成品总段数"), "\(plan.pieceCount)"),
                CalculationResult.item(calculatorLoc("原材根数"), "\(plan.bars.count)"),
                CalculationResult.item(calculatorLoc("成品总长度"), length(plan.totalFinishedLength)),
                CalculationResult.item(calculatorLoc("切缝总损耗"), length(plan.totalKerfLength)),
                CalculationResult.item(calculatorLoc("余料总长度"), length(plan.totalRemainingLength)),
                CalculationResult.item(calculatorLoc("切缝口径"), kerfNotice),
                CalculationResult.item(calculatorLoc("算法说明"), heuristicNotice),
            ]
        )
        let barSections = plan.bars.map { bar in
            let grouped = Dictionary(grouping: bar.pieceLengths, by: { $0 })
            let combination = grouped.keys.sorted(by: >).map { pieceLength in
                "\(length(pieceLength)) × \(grouped[pieceLength]?.count ?? 0)"
            }.joined(separator: " + ")
            return CalculationResult.ResultSection(
                title: calculatorLocFormat("第 %lld 根原材", Int64(bar.id)),
                items: [
                    CalculationResult.item(calculatorLoc("切割组合"), combination),
                    CalculationResult.item(calculatorLoc("本根切缝损耗"), length(Int64(bar.pieceLengths.count) * plan.kerf)),
                    CalculationResult.item(calculatorLoc("本根余料"), length(bar.remaining)),
                ]
            )
        }
        var result = CalculationResult(
            headline: calculatorLocFormat("建议使用 %lld 根原材", Int64(plan.bars.count)),
            formula: calculatorLoc("每根成品段长合计 + 每段切缝 × 段数 + 余料 = 原材长度。"),
            sections: [summary] + barSections
        )
        result.historyDraft = .init(
            tool: calculatorLoc("定尺下料"),
            input: calculatorLocFormat("%@；原材 %@；每段切缝 %@；需求 %@",
                plan.materialName, length(plan.stockLength), length(plan.kerf), demandText),
            result: result.plainText(title: calculatorLoc("定尺下料"))
        )
        return result
    }
}

private struct LinearCuttingVisualizerBar: View {
    let bar: LinearCuttingBar
    let plan: LinearCuttingPlan

    private static let colorPalette: [Color] = [
        .blue, .green, .orange, .purple, .teal, .indigo, .mint
    ]

    private var utilizationPercentage: Double {
        guard plan.stockLength > 0 else { return 0 }
        let used = plan.stockLength - bar.remaining
        return min(100, max(0, Double(used) / Double(plan.stockLength) * 100))
    }

    private func colorFor(length: Int64) -> Color {
        let uniqueLengths = Array(Set(plan.demands.map(\.length))).sorted(by: >)
        guard let index = uniqueLengths.firstIndex(of: length) else { return .blue }
        return Self.colorPalette[index % Self.colorPalette.count]
    }

    private struct CuttingVisualPiece: Identifiable {
        let id: String
        let piece: Int64
    }

    private var visualPieces: [CuttingVisualPiece] {
        bar.pieceLengths.enumerated().map { index, piece in
            CuttingVisualPiece(id: "bar-\(bar.id)-piece-\(index)-\(piece)", piece: piece)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(calculatorLocFormat("第 %lld 根原材", Int64(bar.id)))
                    .font(.caption.weight(.bold))
                Spacer()
                Text(String(format: calculatorLoc("利用率 %.1f%%"), utilizationPercentage))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(utilizationPercentage >= 85 ? Color.appSuccess : .secondary)
            }

            // 比例条状排料示意
            GeometryReader { geometry in
                let totalWidth = geometry.size.width
                HStack(spacing: 1.5) {
                    ForEach(visualPieces) { item in
                        let piece = item.piece
                        let ratio = plan.stockLength > 0 ? CGFloat(piece) / CGFloat(plan.stockLength) : 0
                        let blockWidth = max(24, totalWidth * ratio - 2)
                        let pieceColor = colorFor(length: piece)

                        ZStack {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(pieceColor.opacity(0.85))
                            Text(plan.unit.formatted(piece))
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, 2)
                        }
                        .frame(width: blockWidth, height: 26)
                    }

                    // 余料部分
                    if bar.remaining > 0 {
                        let remainRatio = plan.stockLength > 0 ? CGFloat(bar.remaining) / CGFloat(plan.stockLength) : 0
                        let remainWidth = max(20, totalWidth * remainRatio)
                        ZStack {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                            Text(String(format: calculatorLoc("余%@"), plan.unit.formatted(bar.remaining)))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .padding(.horizontal, 2)
                        }
                        .frame(minWidth: remainWidth, maxHeight: 26)
                    }
                }
            }
            .frame(height: 26)

            // 下料切段文字辅助
            let grouped = Dictionary(grouping: bar.pieceLengths, by: { $0 })
            let combination = grouped.keys.sorted(by: >).map { len in
                "\(plan.unit.formatted(len)) × \(grouped[len]?.count ?? 0)"
            }.joined(separator: " + ")

            Text(combination)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
