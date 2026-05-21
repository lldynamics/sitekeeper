import SwiftUI

struct TrayFillView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.trayWidth) private var trayW = "200"
    @AppStorage(UserPreferenceKeys.Calculator.trayHeight) private var trayH = "100"
    @AppStorage(UserPreferenceKeys.Calculator.trayCables) private var cablesDraft = ""
    @State private var cables: [CableEntry] = [CableEntry(odia: 12, count: 5), CableEntry(odia: 18, count: 3)]
    @State private var showAdd = false; @State private var newDia = ""; @State private var newCount = ""
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var trayWidthRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 50,
            max: 10_000,
            rangeMessage: CalculatorCopy.trayWidthRange
        )
    }

    private var trayHeightRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 30,
            max: 2_000,
            rangeMessage: CalculatorCopy.trayHeightRange
        )
    }

    private var trayWidthValidation: NumericInputFieldValidation {
        trayWidthRule.validate(trayW)
    }

    private var trayHeightValidation: NumericInputFieldValidation {
        trayHeightRule.validate(trayH)
    }

    var body: some View {
        CalculatorForm(title: CalculatorCopy.trayTool, focus: $isInputFocused) {
            Section(CalculatorCopy.trayDimensionSection) {
                CalculatorInputField(
                    title: CalculatorCopy.trayWidth,
                    placeholder: "200",
                    unit: "mm",
                    text: $trayW,
                    rule: trayWidthRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.trayCommonWidth, options: ["100", "150", "200", "300", "400", "600"], selection: $trayW)
                CalculatorInputField(
                    title: CalculatorCopy.trayHeight,
                    placeholder: "100",
                    unit: "mm",
                    text: $trayH,
                    rule: trayHeightRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.trayCommonHeight, options: ["50", "75", "100", "150", "200"], selection: $trayH)
            }
            Section(CalculatorCopy.trayCableSection) {
                ForEach(cables.indices, id: \.self) { i in
                    HStack {
                        Text(CalculatorFormatting.cableSpec(diameter: cables[i].odia, count: cables[i].count))
                        Spacer()
                        Button {
                            cables.remove(at: i)
                            persistCableDraft()
                        } label: { Image(systemName: "trash").foregroundStyle(.appRisk) }
                        .accessibilityLabel(CalculatorCopy.trayDeleteCable)
                    }
                }
                Button { showAdd = true } label: { Label(CalculatorCopy.trayAddCable, systemImage: "plus") }
                CalculatorInlineNotice(message: CalculatorCopy.trayFillNotice)
            }
            Section {
                CalculatorPrimaryActionButton(title: CalculatorCopy.actionCalculate) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    calc()
                }
            }
            if let resultModel {
                CalculatorResultPanel(cardTitle: CalculatorCopy.trayResultTitle, result: resultModel)
            }
        }
        .alert(CalculatorCopy.trayAddCable, isPresented: $showAdd) {
            TextField(CalculatorCopy.trayCableOuterDiameter, text: $newDia.numericInput(.quantity)).keyboardType(.decimalPad).focused($isInputFocused)
            TextField(CalculatorCopy.trayCableCount, text: $newCount.numericInput(.quantity)).keyboardType(.numberPad).focused($isInputFocused)
            Button(CalculatorCopy.actionCancel, role: .cancel) { newDia = ""; newCount = "" }
            Button(CalculatorCopy.actionAdd) {
                if let d = CalculatorInputParser.double(newDia),
                   let c = CalculatorInputParser.int(newCount),
                   d > 0, c > 0 {
                    cables.append(CableEntry(odia: d, count: c))
                    persistCableDraft()
                }
                newDia = ""; newCount = ""
            }
        }
        .onAppear(perform: restoreCableDraftIfNeeded)
    }

    private func calc() {
        guard let w = trayWidthValidation.doubleValue,
              let h = trayHeightValidation.doubleValue else {
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
                    CalculatorResultCopy.trayCableItemError(index: index + 1, message: error.userMessage)
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
            headline: CalculatorResultCopy.trayFillHeadline(rate: rate),
            formula: CalculatorResultCopy.trayFillFormula(),
            items: [
                CalculationResult.item(
                    CalculatorResultLabel.trayArea,
                    CalculatorFormatting.squareMillimeters(
                        trayArea,
                        minFractionDigits: 1,
                        maxFractionDigits: 2
                    )
                ),
                CalculationResult.item(
                    CalculatorResultLabel.cableArea,
                    CalculatorFormatting.squareMillimeters(
                        cableArea,
                        minFractionDigits: 1,
                        maxFractionDigits: 2
                    )
                ),
                CalculationResult.item(
                    CalculatorResultLabel.complianceCheck,
                    CalculatorResultCopy.trayComplianceText(pass: pass),
                    status: pass ? .pass : .warning
                ),
                CalculationResult.item(
                    CalculatorResultLabel.recommendedTray,
                    recommended.map {
                        CalculatorFormatting.traySizeMillimeters(
                            width: $0.width,
                            height: $0.height,
                            digits: 2
                        )
                    } ?? CalculatorCopy.trayUnsupportedSize,
                    status: pass ? .normal : .warning
                ),
            ]
        )
        CalculatorHistorySupport.record(
            store: store,
            tool: CalculatorCopy.trayTool,
            input: CalculatorFormatting.traySpec(
                width: trayW,
                height: trayH,
                cableTypes: cables.count
            ),
            result: CalculatorFormatting.percent(rate)
        )

        trayW = NumericInputSupport.normalizedStorageText(trayW, kind: .quantity, preservingInvalid: false)
        trayH = NumericInputSupport.normalizedStorageText(trayH, kind: .quantity, preservingInvalid: false)
    }

    private func presentError(_ message: String) {
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
                CalculatorResultCopy.trayDraftDecodeFailed(error.localizedDescription)
            )
        }
    }

    private func persistCableDraft() {
        do {
            let data = try JSONEncoder().encode(cables)
            guard let encoded = String(data: data, encoding: .utf8) else {
                StorageIssueLog.record(CalculatorCopy.trayDraftUTF8EncodeFailed)
                return
            }
            cablesDraft = encoded
        } catch {
            StorageIssueLog.record(
                CalculatorResultCopy.trayDraftEncodeFailed(error.localizedDescription)
            )
        }
    }
}

struct CableEntry: Codable { var odia: Double; var count: Int }
