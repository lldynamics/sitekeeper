import SwiftUI

struct ConduitFillView: View {
    @State private var conduitInnerDia = "16"
    @State private var wireDia = "2.5"
    @State private var wireCount = "3"
    @State private var resultModel: CalculationResult?
    @State private var didAttemptSubmit = false
    @State private var calculatedInnerDia: Double? = 16
    @State private var calculatedWireDia: Double? = 2.5
    @State private var calculatedWireCount: Int? = 3
    @State private var currentRate: Double? = 7.32
    @State private var currentPass: Bool = true
    @FocusState private var isInputFocused: Bool

    private var conduitInnerDiaRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 6,
            max: 10_000,
            rangeMessage: CalculatorCopy.conduitInnerDiameterRange
        )
    }

    private var wireDiaRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 0.5,
            max: 100,
            rangeMessage: CalculatorCopy.conduitWireDiameterRange
        )
    }

    private var wireCountRule: CalculatorNumericFieldRule {
        CalculatorNumericFieldRule(
            kind: .quantity,
            requirement: .requiredPositive,
            min: 1,
            max: 500,
            rangeMessage: CalculatorCopy.conduitWireCountRange,
            wholeNumberOnly: true,
            wholeNumberMessage: CalculatorCopy.integerRequired
        )
    }

    private var conduitInnerDiaValidation: NumericInputFieldValidation {
        conduitInnerDiaRule.validate(conduitInnerDia)
    }

    private var wireDiaValidation: NumericInputFieldValidation {
        wireDiaRule.validate(wireDia)
    }

    private var wireCountValidation: NumericInputFieldValidation {
        wireCountRule.validate(wireCount)
    }

    var body: some View {
        CalculatorForm(title: CalculatorCopy.conduitTool, focus: $isInputFocused) {
            Section(CalculatorCopy.conduitParameterSection) {
                CalculatorInputField(
                    title: CalculatorCopy.conduitInnerDiameter,
                    placeholder: "16",
                    unit: "mm",
                    text: $conduitInnerDia,
                    rule: conduitInnerDiaRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.conduitCommonDiameter, options: ["16", "20", "25", "32", "40", "50"], selection: $conduitInnerDia)
                CalculatorInputField(
                    title: CalculatorCopy.conduitWireDiameter,
                    placeholder: "2.5",
                    unit: "mm",
                    text: $wireDia,
                    rule: wireDiaRule,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.conduitCommonWireDiameter, options: ["2.5", "4", "6", "10", "16"], selection: $wireDia)
                CalculatorInputField(
                    title: CalculatorCopy.conduitWireCount,
                    placeholder: "3",
                    unit: CalculatorCopy.unitRoots,
                    text: $wireCount,
                    rule: wireCountRule,
                    keyboardType: .numberPad,
                    showWhenEmpty: didAttemptSubmit,
                    focus: $isInputFocused
                )
                CalculatorPresetChips(title: CalculatorCopy.conduitCommonWireCount, options: ["2", "3", "4", "6", "8", "12"], selection: $wireCount)
            }
            Section(CalculatorCopy.conduitReferenceSection) {
                CalculatorInlineNotice(message: CalculatorCopy.conduitFillNotice)
            }
            Section {
                CalculatorPrimaryActionButton(title: CalculatorCopy.actionCalculate) {
                    isInputFocused = false
                    didAttemptSubmit = true
                    AppHaptics.impact(.medium)
                    calc()
                }
            }
            if let resultModel, let calculatedInnerDia, let calculatedWireDia, let calculatedWireCount, let currentRate {
                ConduitCrossSectionVisualizer(
                    conduitDiameter: calculatedInnerDia,
                    wireDiameter: calculatedWireDia,
                    wireCount: calculatedWireCount,
                    fillRate: currentRate,
                    isPass: currentPass
                )
                CalculatorResultPanel(cardTitle: CalculatorCopy.conduitResultTitle, result: resultModel)
            }
        }
        .onAppear {
            calcSilently()
        }
        .onChange(of: conduitInnerDia) { _, _ in calcSilently() }
        .onChange(of: wireDia) { _, _ in calcSilently() }
        .onChange(of: wireCount) { _, _ in calcSilently() }
    }

    private func calcSilently() {
        guard let cd = conduitInnerDiaValidation.doubleValue,
              let wd = wireDiaValidation.doubleValue,
              let wcValue = wireCountValidation.doubleValue,
              cd >= 6, wd >= 0.5, wcValue >= 1 else {
            return
        }
        let wc = Int(wcValue.rounded(.towardZero))
        if case .success(let fillRate) = EngineeringCalculations.conduitFillRateValidated(conduitInnerDiameter: cd, wireDiameter: wd, wireCount: wc) {
            let rate = fillRate * 100
            let pass = rate <= 40
            calculatedInnerDia = cd
            calculatedWireDia = wd
            calculatedWireCount = wc
            currentRate = rate
            currentPass = pass
            if resultModel != nil {
                calc()
            }
        }
    }

    private func calc() {
        guard let cd = conduitInnerDiaValidation.doubleValue,
              let wd = wireDiaValidation.doubleValue,
              let wcValue = wireCountValidation.doubleValue else {
            resultModel = nil
            return
        }
        let wc = Int(wcValue.rounded(.towardZero))
        let fillRate: Double
        switch EngineeringCalculations.conduitFillRateValidated(conduitInnerDiameter: cd, wireDiameter: wd, wireCount: wc) {
        case .success(let value):
            fillRate = value
        case .failure(let error):
            presentError(error.userMessage)
            return
        }
        let conduitArea = EngineeringCalculations.circleArea(diameter: cd)
        let wireArea = EngineeringCalculations.circleArea(diameter: wd) * Double(wc)
        let rate = fillRate * 100
        let recommended = EngineeringCalculations.recommendedConduitDiameter(wireDiameter: wd, wireCount: wc)
        let pass = rate <= 40
        calculatedInnerDia = cd
        calculatedWireDia = wd
        calculatedWireCount = wc
        currentRate = rate
        currentPass = pass
        resultModel = .singleSection(
            headline: CalculatorResultCopy.conduitFillHeadline(rate: rate),
            formula: CalculatorResultCopy.conduitFillFormula(),
            items: [
                CalculationResult.item(
                    CalculatorResultLabel.conduitArea,
                    CalculatorFormatting.squareMillimeters(
                        conduitArea,
                        minFractionDigits: 1,
                        maxFractionDigits: 2
                    )
                ),
                CalculationResult.item(
                    CalculatorResultLabel.wireArea,
                    CalculatorFormatting.squareMillimeters(
                        wireArea,
                        minFractionDigits: 1,
                        maxFractionDigits: 2
                    )
                ),
                CalculationResult.item(
                    CalculatorResultLabel.complianceCheck,
                    CalculatorResultCopy.conduitComplianceText(pass: pass),
                    status: pass ? .pass : .warning
                ),
                CalculationResult.item(
                    CalculatorResultLabel.recommendedConduit,
                    recommended.map {
                        CalculatorFormatting.diameterMillimeters($0, digits: 2)
                    } ?? CalculatorCopy.conduitUnsupportedSize,
                    status: pass ? .normal : .warning
                ),
            ]
        )
        resultModel?.historyDraft = .init(
            tool: CalculatorCopy.conduitTool,
            input: CalculatorFormatting.conduitSpec(
                conduitInnerDiameter: conduitInnerDia,
                wireDiameter: wireDia,
                wireCount: wireCount
            ),
            result: CalculatorFormatting.percent(rate)
        )
        conduitInnerDia = NumericInputSupport.normalizedStorageText(conduitInnerDia, kind: .quantity, preservingInvalid: false)
        wireDia = NumericInputSupport.normalizedStorageText(wireDia, kind: .quantity, preservingInvalid: false)
        wireCount = NumericInputSupport.normalizedStorageText(wireCount, kind: .quantity, preservingInvalid: false)
    }

    private func presentError(_ message: String) {
        resultModel = .error(message)
    }
}

struct ConduitCrossSectionVisualizer: View {
    let conduitDiameter: Double
    let wireDiameter: Double
    let wireCount: Int
    let fillRate: Double
    let isPass: Bool

    private let conductorPhaseColors: [Color] = [
        Color.appFinance,
        Color.appWarning,
        Color.appSuccess,
        Color.appRisk,
        Color.appDoc
    ]

    var body: some View {
        VStack(spacing: AppSpacing.tight) {
            HStack {
                Label(AppLocalization.string("穿线切面排样示意"), systemImage: "circle.grid.cross")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(isPass ? Color.appSuccess : Color.appRisk)
                        .frame(width: 8, height: 8)
                    Text(isPass ? AppLocalization.string("合规 ≤40%") : AppLocalization.string("超标 >40%"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isPass ? Color.appSuccess : Color.appRisk)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill((isPass ? Color.appSuccess : Color.appRisk).opacity(0.12))
                )
            }

            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let outerRadius = min(size.width, size.height) * 0.44
                    let pipeInnerRadius = outerRadius * 0.88

                    let pipeWallPath = Path(ellipseIn: CGRect(x: center.x - outerRadius, y: center.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2))
                    context.fill(pipeWallPath, with: .color(Color(uiColor: .tertiarySystemFill)))
                    context.stroke(pipeWallPath, with: .color(Color(uiColor: .separator).opacity(0.4)), lineWidth: 1)

                    let lumenPath = Path(ellipseIn: CGRect(x: center.x - pipeInnerRadius, y: center.y - pipeInnerRadius, width: pipeInnerRadius * 2, height: pipeInnerRadius * 2))
                    context.fill(lumenPath, with: .color(Color(uiColor: .secondarySystemGroupedBackground)))
                    let lumenStrokeColor = isPass ? Color.appSuccess.opacity(0.5) : Color.appRisk.opacity(0.7)
                    context.stroke(lumenPath, with: .color(lumenStrokeColor), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

                    var crosshair = Path()
                    crosshair.move(to: CGPoint(x: center.x - pipeInnerRadius * 0.9, y: center.y))
                    crosshair.addLine(to: CGPoint(x: center.x + pipeInnerRadius * 0.9, y: center.y))
                    crosshair.move(to: CGPoint(x: center.x, y: center.y - pipeInnerRadius * 0.9))
                    crosshair.addLine(to: CGPoint(x: center.x, y: center.y + pipeInnerRadius * 0.9))
                    context.stroke(crosshair, with: .color(Color(uiColor: .separator).opacity(0.15)), lineWidth: 0.5)

                    guard conduitDiameter > 0, wireDiameter > 0, wireCount > 0 else { return }
                    let scale = pipeInnerRadius / CGFloat(conduitDiameter / 2)
                    let wireRadiusOnScreen = CGFloat(wireDiameter / 2) * scale
                    let wirePositions = calculateWirePositions(count: wireCount, wireRadius: wireRadiusOnScreen, center: center)

                    for (index, pt) in wirePositions.enumerated() {
                        let phaseColor = conductorPhaseColors[index % conductorPhaseColors.count]
                        let wireRect = CGRect(x: pt.x - wireRadiusOnScreen, y: pt.y - wireRadiusOnScreen, width: wireRadiusOnScreen * 2, height: wireRadiusOnScreen * 2)

                        let wirePath = Path(ellipseIn: wireRect)
                        context.fill(wirePath, with: .color(phaseColor.opacity(0.25)))
                        context.stroke(wirePath, with: .color(phaseColor), lineWidth: 1.5)

                        let coreRadius = wireRadiusOnScreen * 0.45
                        let coreRect = CGRect(x: pt.x - coreRadius, y: pt.y - coreRadius, width: coreRadius * 2, height: coreRadius * 2)
                        let corePath = Path(ellipseIn: coreRect)
                        context.fill(corePath, with: .color(Color(red: 0.88, green: 0.54, blue: 0.28)))
                    }
                }
                .frame(height: 140)

                VStack {
                    Spacer()
                    HStack {
                        Text(String(format: AppLocalization.string("线管内径 Ø%.0fmm"), conduitDiameter))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: AppLocalization.string("填充率 %.1f%%"), fillRate))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isPass ? Color.appSuccess : Color.appRisk)
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding(AppSpacing.normal)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .shadow(color: AppSurfaceShadow.subtle.color,
                        radius: AppSurfaceShadow.subtle.radius,
                        y: AppSurfaceShadow.subtle.y)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isPass ? Color(uiColor: .separator).opacity(0.18) : Color.appRisk.opacity(0.3), lineWidth: 0.8)
        )
    }

    private func calculateWirePositions(count: Int, wireRadius: CGFloat, center: CGPoint) -> [CGPoint] {
        if count <= 0 { return [] }
        if count == 1 { return [center] }
        if count == 2 {
            return [
                CGPoint(x: center.x - wireRadius * 0.95, y: center.y),
                CGPoint(x: center.x + wireRadius * 0.95, y: center.y)
            ]
        }
        if count == 3 {
            let dist = wireRadius * 1.15
            return (0..<3).map { i in
                let angle = CGFloat(i) * (2 * .pi / 3) - .pi / 2
                return CGPoint(x: center.x + cos(angle) * dist, y: center.y + sin(angle) * dist)
            }
        }
        if count == 4 {
            let dist = wireRadius * 1.40
            return (0..<4).map { i in
                let angle = CGFloat(i) * (.pi / 2) + .pi / 4
                return CGPoint(x: center.x + cos(angle) * dist, y: center.y + sin(angle) * dist)
            }
        }
        var points: [CGPoint] = [center]
        var ring = 1
        while points.count < count {
            let ringRadius = CGFloat(ring) * wireRadius * 2.05
            let capacity = max(6, Int(floor(Double(ring) * 6.0)))
            let needed = min(capacity, count - points.count)
            for i in 0..<needed {
                let angle = CGFloat(i) * (2 * .pi / CGFloat(capacity))
                points.append(CGPoint(x: center.x + cos(angle) * ringRadius, y: center.y + sin(angle) * ringRadius))
            }
            ring += 1
        }
        return points
    }
}
