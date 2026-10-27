import Foundation

enum EngineeringCalculations {
    struct VoltageDropMetrics: Equatable {
        let resistance: Double
        let dropV: Double
        let dropPercent: Double
    }

    private enum Limits {
        static let genericValueMax = 1_000_000_000.0
        static let powerKWMax = 5_000_000.0
        static let voltageMax = 100_000.0
        static let currentMax = 100_000.0
        static let lengthMax = 1_000_000.0
        static let sectionMax = 20_000.0
        static let resistivityMax = 10.0
        static let diameterMax = 10_000.0
        static let cableAreaMax = 500_000_000.0
        static let countMax = 100_000
    }

    static let standardWireSections: [Double] = [1.5, 2.5, 4, 6, 10, 16, 25, 35, 50, 70, 95, 120, 150, 185, 240]
    static let standardBreakerSizes: [Int] = [6, 10, 16, 20, 25, 32, 40, 50, 63, 80, 100, 125, 160, 200, 250]
    static let copperAmpacity: [Double: Double] = [
        1.5: 18, 2.5: 25, 4: 33, 6: 42, 10: 58, 16: 77,
        25: 101, 35: 125, 50: 153, 70: 196, 95: 238, 120: 276,
        150: 319, 185: 364, 240: 430
    ]
    static let commonConduitInnerDiameters: [Double] = [16, 20, 25, 32, 40, 50, 63]
    static let commonTraySizes: [(width: Double, height: Double)] = [
        (100, 50), (150, 75), (200, 100), (300, 100), (300, 150),
        (400, 150), (500, 150), (600, 200), (800, 200)
    ]

    static func unitConvertValidated(value: Double, fromFactor: Double, toFactor: Double) -> Result<Double, CalculationError> {
        CalculationValidator.nonNegative(value, field: "换算数值", max: Limits.genericValueMax)
            .flatMap { normalizedValue in
                CalculationValidator.positive(fromFactor, field: "原单位系数", max: Limits.genericValueMax)
                    .flatMap { normalizedFrom in
                        CalculationValidator.positive(toFactor, field: "目标单位系数", max: Limits.genericValueMax)
                            .map { normalizedTo in
                                normalizedValue * normalizedFrom / normalizedTo
                            }
                    }
            }
    }

    static func unitConvert(value: Double, fromFactor: Double, toFactor: Double) -> Double {
        switch unitConvertValidated(value: value, fromFactor: fromFactor, toFactor: toFactor) {
        case .success(let converted):
            return converted
        case .failure:
            return 0
        }
    }

    static func circuitCurrentValidated(powerKW: Double, voltage: Double, powerFactor: Double, isThreePhase: Bool) -> Result<Double, CalculationError> {
        CalculationValidator.positive(powerKW, field: "功率", max: Limits.powerKWMax)
            .flatMap { normalizedPowerKW in
                CalculationValidator.positive(voltage, field: "电压", max: Limits.voltageMax)
                    .flatMap { normalizedVoltage in
                        CalculationValidator.within(powerFactor, field: "功率因数", min: 0, max: 1, includeMin: false)
                            .flatMap { normalizedPowerFactor in
                                let powerW = normalizedPowerKW * 1000
                                let divisor = isThreePhase
                                    ? sqrt(3) * normalizedVoltage * normalizedPowerFactor
                                    : normalizedVoltage * normalizedPowerFactor
                                guard divisor.isFinite, divisor > 0 else {
                                    return .failure(.notFinite(field: "计算过程"))
                                }
                                let result = powerW / divisor
                                return result.isFinite
                                    ? .success(result)
                                    : .failure(.notFinite(field: "计算结果"))
                            }
                    }
            }
    }

    static func circuitCurrent(powerKW: Double, voltage: Double, powerFactor: Double, isThreePhase: Bool) -> Double {
        switch circuitCurrentValidated(powerKW: powerKW, voltage: voltage, powerFactor: powerFactor, isThreePhase: isThreePhase) {
        case .success(let current):
            return current
        case .failure:
            return 0
        }
    }

    static func recommendedBreaker(current: Double, safetyFactor: Double = 1.25) -> Int? {
        guard current.isFinite, current > 0,
              safetyFactor.isFinite, safetyFactor > 0 else { return nil }
        let rated = current * safetyFactor
        guard rated.isFinite else { return nil }
        return standardBreakerSizes.first { Double($0) >= rated }
    }

    static func recommendedWireSectionByAmpacity(current: Double, isCopper: Bool, safetyFactor: Double = 1.15) -> Double? {
        guard current.isFinite, current > 0,
              safetyFactor.isFinite, safetyFactor > 0 else { return nil }
        let target = current * safetyFactor
        guard target.isFinite else { return nil }
        return standardWireSections.first { section in
            ampacity(for: section, isCopper: isCopper) >= target
        }
    }
}

// MARK: - Voltage drop and conductor sizing
extension EngineeringCalculations {
    static func voltageDropValidated(
        current: Double,
        length: Double,
        section: Double,
        voltage: Double,
        isLoopLength: Bool,
        resistivity: Double
    ) -> Result<VoltageDropMetrics, CalculationError> {
        CalculationValidator.positive(current, field: "电流", max: Limits.currentMax)
            .flatMap { normalizedCurrent in
                CalculationValidator.positive(length, field: "长度", max: Limits.lengthMax)
                    .flatMap { normalizedLength in
                        CalculationValidator.positive(section, field: "截面积", max: Limits.sectionMax)
                            .flatMap { normalizedSection in
                                CalculationValidator.positive(voltage, field: "电压", max: Limits.voltageMax)
                                    .flatMap { normalizedVoltage in
                                        CalculationValidator.positive(resistivity, field: "电阻率", max: Limits.resistivityMax)
                                            .flatMap { normalizedResistivity in
                                                let effectiveLength = isLoopLength ? normalizedLength : normalizedLength * 2
                                                let resistance = normalizedResistivity * effectiveLength / normalizedSection
                                                let dropV = normalizedCurrent * resistance
                                                let dropPercent = dropV / normalizedVoltage * 100
                                                guard resistance.isFinite, dropV.isFinite, dropPercent.isFinite else {
                                                    return .failure(.notFinite(field: "计算结果"))
                                                }
                                                return .success(
                                                    VoltageDropMetrics(
                                                        resistance: resistance,
                                                        dropV: dropV,
                                                        dropPercent: dropPercent
                                                    )
                                                )
                                            }
                                    }
                            }
                    }
            }
    }

    static func voltageDrop(current: Double, length: Double, section: Double, voltage: Double, isLoopLength: Bool, resistivity: Double) -> (resistance: Double, dropV: Double, dropPercent: Double) {
        switch voltageDropValidated(
            current: current,
            length: length,
            section: section,
            voltage: voltage,
            isLoopLength: isLoopLength,
            resistivity: resistivity
        ) {
        case .success(let metrics):
            return (metrics.resistance, metrics.dropV, metrics.dropPercent)
        case .failure:
            return (0, 0, 0)
        }
    }

    static func recommendedWireSection(current: Double, length: Double, voltage: Double, isLoopLength: Bool, isCopper: Bool, maxDropPercent: Double = 5) -> Double? {
        guard current.isFinite, current > 0,
              length.isFinite, length > 0,
              voltage.isFinite, voltage > 0,
              maxDropPercent.isFinite, maxDropPercent > 0, maxDropPercent <= 100 else {
            return nil
        }
        let resistivity = isCopper ? 0.0175 : 0.0283
        return standardWireSections.first { section in
            guard case .success(let drop) = voltageDropValidated(
                current: current,
                length: length,
                section: section,
                voltage: voltage,
                isLoopLength: isLoopLength,
                resistivity: resistivity
            ) else { return false }
            let ampacity = ampacity(for: section, isCopper: isCopper)
            return drop.dropPercent <= maxDropPercent && current <= ampacity
        }
    }

    static func ampacity(for section: Double, isCopper: Bool) -> Double {
        guard let base = copperAmpacity[section] else { return 0 }
        return isCopper ? base : base * 0.78
    }
}

// MARK: - Conduit and tray fill
extension EngineeringCalculations {
    static func circleArea(diameter: Double) -> Double {
        .pi * diameter * diameter / 4
    }

    static func conduitFillRateValidated(conduitInnerDiameter: Double, wireDiameter: Double, wireCount: Int) -> Result<Double, CalculationError> {
        CalculationValidator.positive(conduitInnerDiameter, field: "线管内径", max: Limits.diameterMax)
            .flatMap { normalizedConduitDiameter in
                CalculationValidator.positive(wireDiameter, field: "导线外径", max: Limits.diameterMax)
                    .flatMap { normalizedWireDiameter in
                        CalculationValidator.positiveCount(wireCount, field: "导线根数", max: Limits.countMax)
                            .flatMap { normalizedWireCount in
                                let conduitArea = circleArea(diameter: normalizedConduitDiameter)
                                let wireArea = circleArea(diameter: normalizedWireDiameter) * Double(normalizedWireCount)
                                let fillRate = wireArea / conduitArea
                                guard fillRate.isFinite else {
                                    return .failure(.notFinite(field: "穿线率"))
                                }
                                return .success(fillRate)
                            }
                    }
            }
    }

    static func conduitFillRate(conduitInnerDiameter: Double, wireDiameter: Double, wireCount: Int) -> Double {
        switch conduitFillRateValidated(conduitInnerDiameter: conduitInnerDiameter, wireDiameter: wireDiameter, wireCount: wireCount) {
        case .success(let rate):
            return rate
        case .failure:
            return 0
        }
    }

    static func recommendedConduitDiameter(wireDiameter: Double, wireCount: Int, maxFill: Double = 0.4) -> Double? {
        guard wireDiameter.isFinite, wireDiameter > 0,
              wireCount > 0, wireCount <= Limits.countMax,
              maxFill.isFinite, maxFill > 0, maxFill <= 1 else {
            return nil
        }
        return commonConduitInnerDiameters.first {
            guard case .success(let fillRate) = conduitFillRateValidated(
                conduitInnerDiameter: $0,
                wireDiameter: wireDiameter,
                wireCount: wireCount
            ) else { return false }
            return fillRate <= maxFill
        }
    }

    static func cableAreaValidated(diameter: Double, count: Int) -> Result<Double, CalculationError> {
        CalculationValidator.positive(diameter, field: "电缆外径", max: Limits.diameterMax)
            .flatMap { normalizedDiameter in
                CalculationValidator.positiveCount(count, field: "电缆根数", max: Limits.countMax)
                    .flatMap { normalizedCount in
                        let area = circleArea(diameter: normalizedDiameter) * Double(normalizedCount)
                        guard area.isFinite, area <= Limits.cableAreaMax else {
                            return .failure(.outOfRange(field: "电缆面积", min: 0, max: Limits.cableAreaMax))
                        }
                        return .success(area)
                    }
            }
    }

    static func cableArea(diameter: Double, count: Int) -> Double {
        switch cableAreaValidated(diameter: diameter, count: count) {
        case .success(let area):
            return area
        case .failure:
            return 0
        }
    }

    static func trayFillRateValidated(width: Double, height: Double, cableArea: Double) -> Result<Double, CalculationError> {
        CalculationValidator.positive(width, field: "桥架宽度", max: Limits.lengthMax)
            .flatMap { normalizedWidth in
                CalculationValidator.positive(height, field: "桥架高度", max: Limits.lengthMax)
                    .flatMap { normalizedHeight in
                        CalculationValidator.nonNegative(cableArea, field: "电缆总面积", max: Limits.cableAreaMax)
                            .flatMap { normalizedCableArea in
                                let fillRate = normalizedCableArea / (normalizedWidth * normalizedHeight)
                                guard fillRate.isFinite else {
                                    return .failure(.notFinite(field: "填充率"))
                                }
                                return .success(fillRate)
                            }
                    }
            }
    }

    static func trayFillRate(width: Double, height: Double, cableArea: Double) -> Double {
        switch trayFillRateValidated(width: width, height: height, cableArea: cableArea) {
        case .success(let rate):
            return rate
        case .failure:
            return 0
        }
    }

    static func recommendedTraySize(cableArea: Double, maxFill: Double = 0.4) -> (width: Double, height: Double)? {
        guard cableArea.isFinite, cableArea > 0, cableArea <= Limits.cableAreaMax,
              maxFill.isFinite, maxFill > 0, maxFill <= 1 else {
            return nil
        }
        return commonTraySizes.first {
            guard case .success(let fillRate) = trayFillRateValidated(
                width: $0.width,
                height: $0.height,
                cableArea: cableArea
            ) else { return false }
            return fillRate <= maxFill
        }
    }
}

// MARK: - Three-phase balancing
extension EngineeringCalculations {
    /// Returns phase index (0=A, 1=B, 2=C) for each load using a greedy balancing strategy.
    static func assignThreePhases(currents: [Double]) -> [Int] {
        var totals = [0.0, 0.0, 0.0]
        var assignments: [Int] = []
        for current in currents {
            let targetPhase = totals.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            assignments.append(targetPhase)
            let normalizedCurrent = current.isFinite ? max(current, 0) : 0
            totals[targetPhase] += normalizedCurrent
        }
        return assignments
    }

    static func phaseTotals(currents: [Double], assignments: [Int]) -> [Double] {
        var totals = [0.0, 0.0, 0.0]
        for (index, current) in currents.enumerated() where index < assignments.count {
            let phase = assignments[index]
            guard phase >= 0, phase <= 2 else { continue }
            let normalizedCurrent = current.isFinite ? max(current, 0) : 0
            totals[phase] += normalizedCurrent
        }
        return totals
    }

    static func threePhaseImbalancePercent(phaseTotals: [Double]) -> Double {
        let sanitizedTotals = phaseTotals.map { $0.isFinite ? max($0, 0) : 0 }
        guard let maxValue = sanitizedTotals.max(), let minValue = sanitizedTotals.min(), maxValue > 0 else { return 0 }
        return (maxValue - minValue) / maxValue * 100
    }
}
