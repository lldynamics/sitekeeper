import SwiftUI

struct CircuitPhaseRecordView: View {
    @State private var circuits = [CircuitPhaseRecordInput()]
    @State private var resultModel: CalculationResult?
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    private var scopeNotice: String {
        calculatorLoc("仅汇总已填写的计算电流，未计同时系数；不作为配电设计、保护选型或安全结论。")
    }

    var body: some View {
        CalculatorForm(title: calculatorLoc("回路负荷分相记录"), focus: $isInputFocused) {
            Section {
                Text(calculatorLoc("逐条填写回路名称、计算电流和相别，最多 50 条；电流允许为 0，空值和负数不能汇总。"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                CalculatorInlineNotice(message: scopeNotice)
            }

            ForEach($circuits) { circuit in
                circuitSection(circuit)
            }

            Section {
                Button {
                    guard circuits.count < CircuitPhaseRecordModel.maximumCircuitCount else { return }
                    circuits.append(CircuitPhaseRecordInput())
                } label: {
                    Label(calculatorLoc("添加回路"), systemImage: "plus")
                }
                .disabled(circuits.count >= CircuitPhaseRecordModel.maximumCircuitCount)
                LabeledContent(
                    calculatorLoc("回路数量"),
                    value: calculatorLocFormat("%lld / 50 条", Int64(circuits.count))
                )
                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.appRisk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                CalculatorPrimaryActionButton(title: calculatorLoc("生成分相记录")) {
                    isInputFocused = false
                    summarize()
                }
            }

            if let resultModel {
                CalculatorResultPanel(cardTitle: calculatorLoc("回路负荷分相记录"), result: resultModel)
                Section {
                    ShareLink(item: resultModel.plainText(title: calculatorLoc("回路负荷分相记录"))) {
                        Label(calculatorLoc("分享分相记录"), systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .onChange(of: circuits) { _, _ in
            resultModel = nil
            errorMessage = nil
        }
    }

    private func circuitSection(_ circuit: Binding<CircuitPhaseRecordInput>) -> some View {
        let rowNumber = (circuits.firstIndex { $0.id == circuit.wrappedValue.id } ?? 0) + 1
        return Section {
            TextField(calculatorLoc("回路名称"), text: circuit.name)
                .focused($isInputFocused)
            LabeledContent(calculatorLoc("计算电流 A")) {
                TextField("0", text: circuit.currentText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($isInputFocused)
            }
            Picker(calculatorLoc("相别"), selection: circuit.phase) {
                ForEach(CircuitPhaseRecordPhase.allCases) { phase in
                    Text(phase.symbol).tag(phase)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            HStack {
                Text(calculatorLocFormat("回路 %lld", Int64(rowNumber)))
                Spacer()
                Button(role: .destructive) {
                    let id = circuit.wrappedValue.id
                    circuits.removeAll { $0.id == id }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(circuits.count <= 1)
                .accessibilityLabel(calculatorLocFormat("删除第 %lld 条回路", Int64(rowNumber)))
            }
        }
    }

    private func summarize() {
        resultModel = nil
        errorMessage = nil
        do {
            let summary = try CircuitPhaseRecordModel.summarize(circuits)
            let phaseItems = CircuitPhaseRecordPhase.allCases.map { phase in
                CalculationResult.item(
                    calculatorLocFormat("%@ 相合计", phase.symbol),
                    currentText(summary.phaseTotals[phase.rawValue])
                )
            }
            let extremaItems = [
                CalculationResult.item(calculatorLoc("最大相"), phaseSummary(summary.maximumPhases, summary: summary)),
                CalculationResult.item(calculatorLoc("最小相"), phaseSummary(summary.minimumPhases, summary: summary)),
            ]
            let circuitItems = summary.circuits.enumerated().map { index, circuit in
                CalculationResult.item(
                    calculatorLocFormat("第 %lld 条 · %@", Int64(index + 1), circuit.name),
                    calculatorLocFormat("%@ 相 · %@", circuit.phase.symbol, currentText(circuit.current))
                )
            }
            var result = CalculationResult(
                headline: calculatorLocFormat("已汇总 %lld 条回路", Int64(summary.circuits.count)),
                formula: calculatorLoc("各相合计 = 归属该相的已填回路电流相加。"),
                sections: [
                    .init(title: calculatorLoc("各相电流合计"), items: phaseItems + extremaItems),
                    .init(title: calculatorLoc("逐回路记录"), items: circuitItems),
                    .init(title: calculatorLoc("记录口径"), items: [CalculationResult.item(calculatorLoc("说明"), scopeNotice)]),
                ]
            )
            let inputText = circuitItems.map { "\($0.label): \($0.value)" }.joined(separator: "\n")
            result.historyDraft = .init(
                tool: calculatorLoc("回路负荷分相记录"),
                input: inputText,
                result: result.plainText(title: calculatorLoc("回路负荷分相记录"))
            )
            resultModel = result
        } catch let error as CircuitPhaseRecordError {
            errorMessage = validationMessage(error)
        } catch {
            errorMessage = calculatorLoc("无法汇总回路记录，请检查输入后重试。")
        }
    }

    private func phaseSummary(_ phases: [CircuitPhaseRecordPhase], summary: CircuitPhaseRecordSummary) -> String {
        guard let phase = phases.first else { return "" }
        return calculatorLocFormat(
            "%@ 相 · %@", phases.map(\.symbol).joined(separator: "/"), currentText(summary.phaseTotals[phase.rawValue])
        )
    }

    private func currentText(_ value: Decimal) -> String {
        calculatorLocFormat("%@ A", NSDecimalNumber(decimal: value).stringValue)
    }

    private func validationMessage(_ error: CircuitPhaseRecordError) -> String {
        switch error {
        case .noCircuits:
            calculatorLoc("请至少填写一条回路。")
        case .tooManyCircuits:
            calculatorLoc("最多支持 50 条回路，请减少记录。")
        case .missingName(let row):
            calculatorLocFormat("请填写第 %lld 条回路名称。", Int64(row))
        case .invalidCurrent(let row):
            calculatorLocFormat("第 %lld 条回路电流无效，请填写可表示的非负数，单位 A。", Int64(row))
        case .totalOutOfRange:
            calculatorLoc("相电流合计超出可表示范围或精度，请减小输入。")
        }
    }
}
