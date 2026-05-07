import Foundation

enum EngineeringCalculations {
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

    static func unitConvert(value: Double, fromFactor: Double, toFactor: Double) -> Double {
        guard toFactor > 0 else { return 0 }
        return value * fromFactor / toFactor
    }

    static func circuitCurrent(powerKW: Double, voltage: Double, powerFactor: Double, isThreePhase: Bool) -> Double {
        guard powerKW > 0, voltage > 0, powerFactor > 0 else { return 0 }
        let powerW = powerKW * 1000
        let divisor = isThreePhase ? sqrt(3) * voltage * powerFactor : voltage * powerFactor
        return powerW / divisor
    }

    static func recommendedBreaker(current: Double, safetyFactor: Double = 1.25) -> Int {
        let rated = max(current * safetyFactor, 0)
        return standardBreakerSizes.first { Double($0) >= rated } ?? (standardBreakerSizes.last ?? 250)
    }

    static func recommendedWireSectionByAmpacity(current: Double, isCopper: Bool, safetyFactor: Double = 1.15) -> Double? {
        let target = max(current * safetyFactor, 0)
        return standardWireSections.first { section in
            ampacity(for: section, isCopper: isCopper) >= target
        }
    }

    static func voltageDrop(current: Double, length: Double, section: Double, voltage: Double, isLoopLength: Bool, resistivity: Double) -> (resistance: Double, dropV: Double, dropPercent: Double) {
        let effectiveLength = isLoopLength ? length : length * 2
        let resistance = resistivity * effectiveLength / section
        let dropV = current * resistance
        return (resistance, dropV, dropV / voltage * 100)
    }

    static func recommendedWireSection(current: Double, length: Double, voltage: Double, isLoopLength: Bool, isCopper: Bool, maxDropPercent: Double = 5) -> Double? {
        let resistivity = isCopper ? 0.0175 : 0.0283
        return standardWireSections.first { section in
            let drop = voltageDrop(current: current, length: length, section: section, voltage: voltage, isLoopLength: isLoopLength, resistivity: resistivity)
            let ampacity = ampacity(for: section, isCopper: isCopper)
            return drop.dropPercent <= maxDropPercent && current <= ampacity
        }
    }

    static func ampacity(for section: Double, isCopper: Bool) -> Double {
        let base = copperAmpacity[section] ?? .greatestFiniteMagnitude
        return isCopper ? base : base * 0.78
    }

    static func circleArea(diameter: Double) -> Double {
        .pi * diameter * diameter / 4
    }

    static func conduitFillRate(conduitInnerDiameter: Double, wireDiameter: Double, wireCount: Int) -> Double {
        let conduitArea = circleArea(diameter: conduitInnerDiameter)
        let wireArea = circleArea(diameter: wireDiameter) * Double(wireCount)
        return wireArea / conduitArea
    }

    static func recommendedConduitDiameter(wireDiameter: Double, wireCount: Int, maxFill: Double = 0.4) -> Double? {
        commonConduitInnerDiameters.first {
            conduitFillRate(conduitInnerDiameter: $0, wireDiameter: wireDiameter, wireCount: wireCount) <= maxFill
        }
    }

    static func cableArea(diameter: Double, count: Int) -> Double {
        circleArea(diameter: diameter) * Double(count)
    }

    static func trayFillRate(width: Double, height: Double, cableArea: Double) -> Double {
        cableArea / (width * height)
    }

    static func recommendedTraySize(cableArea: Double, maxFill: Double = 0.4) -> (width: Double, height: Double)? {
        commonTraySizes.first {
            trayFillRate(width: $0.width, height: $0.height, cableArea: cableArea) <= maxFill
        }
    }

    /// Returns phase index (0=A, 1=B, 2=C) for each load using a greedy balancing strategy.
    static func assignThreePhases(currents: [Double]) -> [Int] {
        var totals = [0.0, 0.0, 0.0]
        var assignments: [Int] = []
        for current in currents {
            let targetPhase = totals.enumerated().min(by: { $0.element < $1.element })?.offset ?? 0
            assignments.append(targetPhase)
            totals[targetPhase] += max(current, 0)
        }
        return assignments
    }

    static func phaseTotals(currents: [Double], assignments: [Int]) -> [Double] {
        var totals = [0.0, 0.0, 0.0]
        for (index, current) in currents.enumerated() where index < assignments.count {
            let phase = assignments[index]
            guard phase >= 0, phase <= 2 else { continue }
            totals[phase] += max(current, 0)
        }
        return totals
    }

    static func threePhaseImbalancePercent(phaseTotals: [Double]) -> Double {
        guard let maxValue = phaseTotals.max(), let minValue = phaseTotals.min(), maxValue > 0 else { return 0 }
        return (maxValue - minValue) / maxValue * 100
    }
}
