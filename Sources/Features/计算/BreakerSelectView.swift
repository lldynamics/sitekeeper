import SwiftUI

struct BreakerSelectView: View {
    @Environment(DataStore.self) private var store
    @AppStorage(UserPreferenceKeys.Calculator.breakerCurrent) private var calcCurrent = ""
    @AppStorage(UserPreferenceKeys.Calculator.breakerLoadType) private var loadTypeRawValue: String = LoadType.socket.rawValue
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @FocusState private var isInputFocused: Bool

    private var currentRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.1,
            max: 100_000,
            rangeMessage: CalculatorCopy.breakerCurrentRange
        )
    }

    private var currentValidation: NumericInputFieldValidation {
        currentRule.validate(calcCurrent)
    }

    private var loadType: LoadType {
        StringEnumFallback.value(loadTypeRawValue, default: LoadType.socket)
    }

    var body: some View {
        CalculatorForm(title: CalculatorCopy.breakerTool, focus: $isInputFocused) {
            Section(CalculatorCopy.breakerLoadSection) {
                CalculatorInputField(
                    title: CalculatorCopy.breakerCurrent,
                    placeholder: CalculatorCopy.breakerCurrentPlaceholder,
                    unit: "A",
                    text: $calcCurrent,
                    rule: currentRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(
                    title: CalculatorCopy.breakerCommonCurrent,
                    options: ["16", "20", "25", "32", "40", "63"],
                    selection: $calcCurrent
                )
                Picker(CalculatorCopy.breakerLoadType, selection: $loadTypeRawValue) {
                    ForEach(LoadType.allCases, id: \.self) { Text($0.displayName).tag($0.rawValue) }
                }
            }
            Section(CalculatorCopy.breakerReferenceSection) {
                CalculatorInlineNotice(
                    message: CalculatorResultCopy.breakerReference(
                        loadType: loadType.displayName,
                        factor: loadType.factor
                    )
                )
            }
            Section {
                CalculatorPrimaryActionButton(title: CalculatorCopy.actionSelect) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    select()
                }
            }
            if let resultModel {
                CalculatorResultPanel(
                    sectionTitle: CalculatorCopy.breakerResultSection,
                    cardTitle: CalculatorCopy.breakerResultTitle,
                    result: resultModel
                )
            }
        }
    }

    private func select() {
        guard let i = currentValidation.doubleValue else {
            presentError(CalculatorCopy.breakerCurrentRequired)
            return
        }
        let rated = i * loadType.factor
        let standardBreakers = EngineeringCalculations.standardBreakerSizes
        let breaker = standardBreakers.first { Double($0) >= rated } ?? 250
        let rcdRecommended = loadType == .socket
        let warning = rated > 100
        resultModel = .singleSection(
            headline: CalculatorResultCopy.breakerHeadline(breaker: breaker, poles: loadType.poles),
            formula: CalculatorResultCopy.breakerFormula(),
            items: [
                CalculationResult.item(
                    CalculatorResultLabel.current,
                    CalculatorFormatting.amperes(i, digits: 1)
                ),
                CalculationResult.item(
                    CalculatorResultLabel.currentRating,
                    CalculatorFormatting.amperes(rated, digits: 1),
                    status: warning ? .warning : .pass
                ),
                CalculationResult.item(
                    CalculatorResultLabel.rcdAdvice,
                    CalculatorResultCopy.breakerRcdAdvice(recommended: rcdRecommended),
                    status: rcdRecommended ? .pass : .normal
                ),
            ]
        )
        CalculatorHistorySupport.record(
            store: store,
            tool: CalculatorCopy.breakerTool,
            input: CalculatorHistoryCopy.breakerInput(
                current: i,
                loadType: loadType.displayName
            ),
            result: CalculatorHistoryCopy.breakerResult(breaker)
        )
    }

    private func presentError(_ message: String) {
        resultModel = .error(message)
    }
}

enum LoadType: String, CaseIterable {
    case socket
    case power

    var displayName: String {
        switch self {
        case .socket: CalculatorCopy.breakerSocketLoad
        case .power: CalculatorCopy.breakerPowerLoad
        }
    }
    var factor: Double { switch self { case .socket: 1.25; case .power: 1.5 } }
    var poles: String { switch self { case .socket: "1P+N"; case .power: "3P" } }
}
