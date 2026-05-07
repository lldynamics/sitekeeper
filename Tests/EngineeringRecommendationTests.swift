import Testing
@testable import sitekeeper

@MainActor
struct EngineeringRecommendationTests {
    @Test func circuitCurrentSinglePhase() {
        let current = EngineeringCalculations.circuitCurrent(powerKW: 4.5, voltage: 220, powerFactor: 0.9, isThreePhase: false)
        #expect(abs(current - 22.73) < 0.1)
    }

    @Test func breakerRecommendation() {
        let breaker = EngineeringCalculations.recommendedBreaker(current: 15, safetyFactor: 1.25)
        #expect(breaker == 20)
    }

    @Test func threePhaseAssignmentBalance() {
        let currents = [10.0, 8.0, 6.0, 4.0]
        let assignments = EngineeringCalculations.assignThreePhases(currents: currents)
        let totals = EngineeringCalculations.phaseTotals(currents: currents, assignments: assignments)
        let imbalance = EngineeringCalculations.threePhaseImbalancePercent(phaseTotals: totals)
        #expect(assignments.count == currents.count)
        #expect(imbalance <= 25)
    }

    @Test func recommendsLargerWireForLongRun() throws {
        let section = try #require(EngineeringCalculations.recommendedWireSection(current: 32, length: 80, voltage: 220, isLoopLength: false, isCopper: true))
        #expect(section >= 6)
    }

    @Test func recommendsConduitDiameter() throws {
        let diameter = try #require(EngineeringCalculations.recommendedConduitDiameter(wireDiameter: 3.5, wireCount: 5))
        #expect(diameter >= 16)
    }

    @Test func recommendsTraySize() throws {
        let area = EngineeringCalculations.cableArea(diameter: 18, count: 8)
        let tray = try #require(EngineeringCalculations.recommendedTraySize(cableArea: area))
        #expect(tray.width * tray.height * 0.4 >= area)
    }
}
