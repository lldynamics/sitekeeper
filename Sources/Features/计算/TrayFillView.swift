import SwiftUI

struct TrayFillView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.trayWidth) private var trayW = "200"
    @AppStorage(UserPreferenceKeys.Calculator.trayHeight) private var trayH = "100"
    @AppStorage(UserPreferenceKeys.Calculator.trayCables) private var cablesDraft = ""
    @State private var cables: [CableEntry] = [CableEntry(odia: 12, count: 5), CableEntry(odia: 18, count: 3)]
    @State private var showAdd = false; @State private var newDia = ""; @State private var newCount = ""
    @State private var result = ""
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var trayWidthRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 50,
            max: 10_000,
            rangeMessage: calculatorLoc(String(localized: "请输入 50–10000"))
        )
    }

    private var trayHeightRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 30,
            max: 2_000,
            rangeMessage: calculatorLoc(String(localized: "请输入 30–2000"))
        )
    }

    private var trayWidthValidation: NumericInputFieldValidation {
        trayWidthRule.validate(trayW)
    }

    private var trayHeightValidation: NumericInputFieldValidation {
        trayHeightRule.validate(trayH)
    }

    var body: some View {
        Form {
            Section(String(localized: "桥架尺寸 (mm)")) {
                CalculatorValidatedNumericField(
                    title: String(localized: "宽度"),
                    placeholder: "200",
                    unit: "mm",
                    text: $trayW,
                    rule: trayWidthRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: String(localized: "常用宽度"), options: ["100", "150", "200", "300", "400", "600"], selection: $trayW)
                CalculatorValidatedNumericField(
                    title: String(localized: "高度"),
                    placeholder: "100",
                    unit: "mm",
                    text: $trayH,
                    rule: trayHeightRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: String(localized: "常用高度"), options: ["50", "75", "100", "150", "200"], selection: $trayH)
            }
            Section(String(localized: "电缆列表")) {
                ForEach(cables.indices, id: \.self) { i in
                    HStack {
                        Text(
                            String(
                                format: String(localized: "Φ%@mm × %lld 根"),
                                String(format: "%.0f", cables[i].odia),
                                Int64(cables[i].count)
                            )
                        )
                        Spacer()
                        Button {
                            cables.remove(at: i)
                            persistCableDraft()
                        } label: { Image(systemName: "trash").foregroundStyle(.appRisk) }
                        .accessibilityLabel(String(localized: "删除此电缆"))
                    }
                }
                Button { showAdd = true } label: { Label(String(localized: "添加电缆"), systemImage: "plus") }
            }
            Section {
                Button(String(localized: "计算")) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calc()
                }
                .frame(maxWidth: .infinity)
                .fontWeight(.semibold)
            }
            if let resultModel {
                Section(String(localized: "结果")) {
                    CalculatorResultCard(
                        title: String(localized: "桥架填充率"),
                        result: resultModel
                    )
                }
            }
        }
        .alert(String(localized: "添加电缆"), isPresented: $showAdd) {
            TextField(String(localized: "外径 (mm)"), text: $newDia.numericInput(.quantity)).keyboardType(.decimalPad).focused($isInputFocused)
            TextField(String(localized: "根数 (根)"), text: $newCount.numericInput(.quantity)).keyboardType(.numberPad).focused($isInputFocused)
            Button(String(localized: "取消"), role: .cancel) { newDia = ""; newCount = "" }
            Button(String(localized: "添加")) {
                if let d = CalculatorInputParser.double(newDia),
                   let c = CalculatorInputParser.int(newCount),
                   d > 0, c > 0 {
                    cables.append(CableEntry(odia: d, count: c))
                    persistCableDraft()
                }
                newDia = ""; newCount = ""
            }
        }
        .navigationTitle(String(localized: "桥架填充率")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            KeyboardDismissToolbar {
                isInputFocused = false
            }
        }
        .onAppear(perform: restoreCableDraftIfNeeded)
    }

    private func calc() {
        guard let w = trayWidthValidation.doubleValue,
              let h = trayHeightValidation.doubleValue else {
            result = ""
            resultModel = nil
            return
        }
        let trayArea = w * h
        var cableArea = 0.0
        for (index, cable) in cables.enumerated() {
            switch EngineeringCalculations.cableAreaValidated(diameter: cable.odia, count: cable.count) {
            case .success(let area):
                cableArea += area
            case .failure(let error):
                presentError(
                    String(
                        format: String(localized: "第 %lld 项电缆：%@"),
                        Int64(index + 1),
                        error.userMessage
                    )
                )
                return
            }
        }
        let fillRate: Double
        switch EngineeringCalculations.trayFillRateValidated(width: w, height: h, cableArea: cableArea) {
        case .success(let rate):
            fillRate = rate
        case .failure(let error):
            presentError(error.userMessage)
            return
        }
        let rate = fillRate * 100
        let recommended = EngineeringCalculations.recommendedTraySize(cableArea: cableArea)
        let pass = rate <= 40
        resultModel = .singleSection(
            headline: String(format: String(localized: "填充率 %@%%"), fmt(rate)),
            formula: String(localized: "填充率 = (电缆总截面积 ÷ 桥架截面积)×100%"),
            items: [
                CalculationResult.item(
                    String(localized: "桥架截面积"),
                    String(format: String(localized: "%@ mm²"), fmt(trayArea))
                ),
                CalculationResult.item(
                    String(localized: "电缆总截面积"),
                    String(format: String(localized: "%@ mm²"), fmt(cableArea))
                ),
                CalculationResult.item(
                    String(localized: "规范校核"),
                    pass ? String(localized: "符合规范（≤40%）") : String(localized: "超出规范（>40%）"),
                    status: pass ? .pass : .warning
                ),
                CalculationResult.item(
                    String(localized: "推荐桥架"),
                    recommended.map {
                        String(format: String(localized: "%@×%@ mm"), fmt($0.width), fmt($0.height))
                    } ?? String(localized: "超出常用规格"),
                    status: pass ? .normal : .warning
                ),
            ]
        )
        let recommendationText = recommended.map {
            String(format: String(localized: "%@×%@ mm"), fmt($0.width), fmt($0.height))
        } ?? String(localized: "超出常用规格")
        result = """
        \(String(format: String(localized: "桥架截面积: %@ mm²"), fmt(trayArea)))
        \(String(format: String(localized: "电缆总截面积: %@ mm²"), fmt(cableArea)))
        \(String(format: String(localized: "填充率: %@ %%"), fmt(rate)))
        \(rate <= 40 ? String(localized: "符合规范") : String(localized: "超过 40%，请增大桥架"))
        \(String(format: String(localized: "推荐桥架: %@"), recommendationText))
        """
        store.appendCalculationHistory(
            tool: String(localized: "桥架填充率"),
            input: String(
                format: String(localized: "%@×%@mm, %lld 种电缆"),
                trayW,
                trayH,
                Int64(cables.count)
            ),
            result: "\(fmt(rate))%"
        )

        trayW = NumericInputSupport.normalizedStorageText(trayW, kind: .quantity, preservingInvalid: false)
        trayH = NumericInputSupport.normalizedStorageText(trayH, kind: .quantity, preservingInvalid: false)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.minimumFractionDigits = 1; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? String(v)
    }

    private func presentError(_ message: String) {
        result = message
        resultModel = .error(message)
    }

    private func restoreCableDraftIfNeeded() {
        guard !cablesDraft.isEmpty,
              let data = cablesDraft.data(using: .utf8) else {
            return
        }
        do {
            let decoded = try JSONDecoder().decode([CableEntry].self, from: data)
            guard !decoded.isEmpty else { return }
            cables = decoded
        } catch {
            StorageIssueLog.record(
                String(format: String(localized: "桥架填充草稿解析失败：%@"), error.localizedDescription)
            )
        }
    }

    private func persistCableDraft() {
        do {
            let data = try JSONEncoder().encode(cables)
            guard let encoded = String(data: data, encoding: .utf8) else {
                StorageIssueLog.record(String(localized: "桥架填充草稿编码后 UTF8 转换失败"))
                return
            }
            cablesDraft = encoded
        } catch {
            StorageIssueLog.record(
                String(format: String(localized: "桥架填充草稿编码失败：%@"), error.localizedDescription)
            )
        }
    }
}

struct CableEntry: Codable { var odia: Double; var count: Int }
