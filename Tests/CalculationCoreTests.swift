import Testing
@testable import sitekeeper

@MainActor
struct CalculationCoreTests {

    // MARK: - unitConvert

    @Test func unitConvertBasic() {
        #expect(EngineeringCalculations.unitConvert(value: 1, fromFactor: 1000, toFactor: 1) == 1000)
        #expect(EngineeringCalculations.unitConvert(value: 1000, fromFactor: 1, toFactor: 1000) == 1)
    }

    @Test func unitConvertZero() {
        #expect(EngineeringCalculations.unitConvert(value: 0, fromFactor: 100, toFactor: 10) == 0)
    }

    @Test func unitConvertInvalidFactor() {
        #expect(EngineeringCalculations.unitConvert(value: 100, fromFactor: 10, toFactor: 0) == 0)
    }

    // MARK: - circuitCurrent

    @Test func circuitCurrentSinglePhase() {
        let c = EngineeringCalculations.circuitCurrent(powerKW: 4.5, voltage: 220, powerFactor: 0.9, isThreePhase: false)
        #expect(abs(c - 22.73) < 0.1)
    }

    @Test func circuitCurrentThreePhase() {
        let c = EngineeringCalculations.circuitCurrent(powerKW: 30, voltage: 380, powerFactor: 0.85, isThreePhase: true)
        #expect(abs(c - 53.6) < 1)
    }

    @Test func circuitCurrentInvalidInputs() {
        #expect(EngineeringCalculations.circuitCurrent(powerKW: 0, voltage: 220, powerFactor: 0.9, isThreePhase: false) == 0)
        #expect(EngineeringCalculations.circuitCurrent(powerKW: 10, voltage: 0, powerFactor: 0.9, isThreePhase: false) == 0)
        #expect(EngineeringCalculations.circuitCurrent(powerKW: 10, voltage: 220, powerFactor: 0, isThreePhase: false) == 0)
    }

    // MARK: - recommendedBreaker

    @Test func breakerAt15A() {
        #expect(EngineeringCalculations.recommendedBreaker(current: 15) == 20)
    }

    @Test func breakerAtSmallCurrent() {
        #expect(EngineeringCalculations.recommendedBreaker(current: 1) == 6)
    }

    @Test func breakerAtLargeCurrent() {
        #expect(EngineeringCalculations.recommendedBreaker(current: 250) == 250)
    }

    @Test func breakerAtZero() {
        #expect(EngineeringCalculations.recommendedBreaker(current: 0) >= 6)
    }

    // MARK: - ampacity

    @Test func ampacityCopper() {
        #expect(abs(EngineeringCalculations.ampacity(for: 2.5, isCopper: true) - 25) < 0.1)
        #expect(abs(EngineeringCalculations.ampacity(for: 10, isCopper: true) - 58) < 0.1)
    }

    @Test func ampacityAluminum() {
        let al = EngineeringCalculations.ampacity(for: 2.5, isCopper: false)
        #expect(al < 25 && al > 0)
    }

    @Test func ampacityUnknownSection() {
        #expect(EngineeringCalculations.ampacity(for: 999, isCopper: true) == .greatestFiniteMagnitude)
    }

    // MARK: - voltageDrop

    @Test func voltageDropBasic() {
        let drop = EngineeringCalculations.voltageDrop(current: 20, length: 50, section: 4, voltage: 220, isLoopLength: false, resistivity: 0.0175)
        #expect(drop.resistance > 0)
        #expect(drop.dropV > 0)
        #expect(drop.dropPercent > 0)
        #expect(abs(drop.dropV - drop.resistance * 20) < 0.01)
    }

    @Test func voltageDropLoopLength() {
        let d1 = EngineeringCalculations.voltageDrop(current: 20, length: 50, section: 4, voltage: 220, isLoopLength: false, resistivity: 0.0175)
        let d2 = EngineeringCalculations.voltageDrop(current: 20, length: 50, section: 4, voltage: 220, isLoopLength: true, resistivity: 0.0175)
        #expect(d2.resistance < d1.resistance)
    }

    // MARK: - recommendedWireSectionByAmpacity

    @Test func wireByAmpacityCopper() throws {
        let s = try #require(EngineeringCalculations.recommendedWireSectionByAmpacity(current: 30, isCopper: true))
        #expect(s >= 6)
    }

    @Test func wireByAmpacityAluminum() throws {
        let s = try #require(EngineeringCalculations.recommendedWireSectionByAmpacity(current: 30, isCopper: false))
        #expect(s >= 10)
    }

    // MARK: - recommendedWireSection (voltage drop)

    @Test func wireSectionWithVoltageDropCopper() throws {
        let s = try #require(EngineeringCalculations.recommendedWireSection(current: 32, length: 80, voltage: 220, isLoopLength: false, isCopper: true))
        #expect(s >= 6)
    }

    @Test func wireSectionWithVoltageDropAluminum() throws {
        let s = try #require(EngineeringCalculations.recommendedWireSection(current: 32, length: 80, voltage: 220, isLoopLength: false, isCopper: false))
        #expect(s >= 10)
    }

    @Test func wireSectionShortRun() throws {
        let s = try #require(EngineeringCalculations.recommendedWireSection(current: 10, length: 5, voltage: 220, isLoopLength: false, isCopper: true))
        #expect(s >= 1)
    }

    // MARK: - conduitFillRate

    @Test func conduitFillRateBasic() {
        let rate = EngineeringCalculations.conduitFillRate(conduitInnerDiameter: 25, wireDiameter: 3.5, wireCount: 5)
        #expect(rate > 0 && rate < 1)
    }

    @Test func recommendedConduit() throws {
        let d = try #require(EngineeringCalculations.recommendedConduitDiameter(wireDiameter: 3.5, wireCount: 5))
        #expect(d >= 20)
    }

    @Test func recommendedConduitMaxedOut() {
        let d = EngineeringCalculations.recommendedConduitDiameter(wireDiameter: 10, wireCount: 10)
        #expect(d == nil)
    }

    // MARK: - trayFillRate

    @Test func trayFillRateBasic() throws {
        let area = EngineeringCalculations.cableArea(diameter: 18, count: 8)
        let tray = try #require(EngineeringCalculations.recommendedTraySize(cableArea: area))
        #expect(tray.width * tray.height * 0.4 >= area)
    }

    @Test func trayFillRateTooLarge() {
        let area = EngineeringCalculations.cableArea(diameter: 100, count: 50)
        let tray = EngineeringCalculations.recommendedTraySize(cableArea: area)
        #expect(tray == nil)
    }

    // MARK: - threePhase assignment

    @Test func threePhaseBalancedAssignment() {
        let currents = [10.0, 10.0, 10.0, 10.0, 10.0, 10.0]
        let assignments = EngineeringCalculations.assignThreePhases(currents: currents)
        let totals = EngineeringCalculations.phaseTotals(currents: currents, assignments: assignments)
        let imbalance = EngineeringCalculations.threePhaseImbalancePercent(phaseTotals: totals)
        #expect(assignments.count == currents.count)
        #expect(imbalance < 10)
    }

    @Test func threePhaseSingleLoad() {
        let currents = [100.0]
        let assignments = EngineeringCalculations.assignThreePhases(currents: currents)
        let totals = EngineeringCalculations.phaseTotals(currents: currents, assignments: assignments)
        #expect(totals.max() == 100)
        #expect(totals.min() == 0)
    }

    @Test func threePhaseImbalanceEmpty() {
        #expect(EngineeringCalculations.threePhaseImbalancePercent(phaseTotals: [0, 0, 0]) == 0)
    }

    // MARK: - cableArea

    @Test func cableAreaCalculation() {
        let area = EngineeringCalculations.cableArea(diameter: 10, count: 1)
        let expected = .pi * 25
        #expect(abs(area - expected) < 0.01)
    }
}
