import Testing
@testable import sitekeeper

@MainActor
struct EngineeringRecommendationTests {
    @Test func threePhaseAssignmentBalance() {
        let currents = [10.0, 8.0, 6.0, 4.0]
        let assignments = EngineeringCalculations.assignThreePhases(currents: currents)
        let totals = EngineeringCalculations.phaseTotals(currents: currents, assignments: assignments)
        let imbalance = EngineeringCalculations.threePhaseImbalancePercent(phaseTotals: totals)
        #expect(assignments.count == currents.count)
        #expect(imbalance <= 25)
    }
}
