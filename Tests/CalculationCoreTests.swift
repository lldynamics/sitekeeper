import Testing
import Foundation
@testable import sitekeeper

@MainActor
struct CalculationCoreTests {

    @Test func calculatorProjectWorkflowRequiresAnExplicitExistingProject() {
        let first = UUID()
        let chosen = UUID()
        let availableIDs = [first, chosen]

        #expect(CalculatorProjectSelection.resolve(id: nil, availableIDs: availableIDs) == nil)
        #expect(CalculatorProjectSelection.resolve(id: nil, availableIDs: [first]) == nil)
        #expect(CalculatorProjectSelection.resolve(id: chosen, availableIDs: availableIDs) == chosen)
        #expect(CalculatorProjectSelection.resolve(id: chosen, availableIDs: [chosen, first]) == chosen)
        #expect(CalculatorProjectSelection.resolve(id: chosen, availableIDs: [first]) == nil)
        #expect(CalculatorProjectSelection.resolve(id: chosen, availableIDs: []) == nil)
    }

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

    @Test func unitConvertValidatedRejectsInvalidFactor() {
        let result = EngineeringCalculations.unitConvertValidated(value: 100, fromFactor: 10, toFactor: 0)
        switch result {
        case .failure(.mustBeGreaterThanZero(field: "目标单位系数")):
            break
        default:
            Issue.record("预期目标单位系数应返回 mustBeGreaterThanZero 错误")
        }
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

    @Test func circuitCurrentValidatedRejectsOutOfRangePowerFactor() {
        let result = EngineeringCalculations.circuitCurrentValidated(powerKW: 10, voltage: 220, powerFactor: 1.2, isThreePhase: false)
        switch result {
        case .failure(.outOfRange(field: "功率因数", min: 0, max: 1)):
            break
        default:
            Issue.record("预期功率因数应返回 outOfRange 错误")
        }
    }

    // MARK: - recommendedBreaker

    @Test func breakerAt15A() {
        #expect(EngineeringCalculations.recommendedBreaker(current: 15) == 20)
    }

    @Test func breakerAtSmallCurrent() {
        #expect(EngineeringCalculations.recommendedBreaker(current: 1) == 6)
    }

    @Test func breakerAtLargeCurrent() {
        #expect(EngineeringCalculations.recommendedBreaker(current: 250) == nil)
    }

    @Test func breakerAtZero() {
        #expect(EngineeringCalculations.recommendedBreaker(current: 0) == nil)
    }

    @Test func recommendationRulesRejectInvalidInputsInsteadOfReturningSmallestSize() {
        for current in [Double.nan, -Double.infinity, -1, 0] {
            #expect(EngineeringCalculations.recommendedBreaker(current: current) == nil)
            #expect(EngineeringCalculations.recommendedWireSectionByAmpacity(current: current, isCopper: true) == nil)
            #expect(
                EngineeringCalculations.recommendedWireSection(
                    current: current,
                    length: 10,
                    voltage: 220,
                    isLoopLength: false,
                    isCopper: true
                ) == nil
            )
        }
        #expect(EngineeringCalculations.recommendedConduitDiameter(wireDiameter: 3.5, wireCount: 0) == nil)
        #expect(EngineeringCalculations.recommendedConduitDiameter(wireDiameter: .nan, wireCount: 5) == nil)
        #expect(EngineeringCalculations.recommendedTraySize(cableArea: 0) == nil)
        #expect(EngineeringCalculations.recommendedTraySize(cableArea: -Double.infinity) == nil)
        #expect(EngineeringCalculations.recommendedTraySize(cableArea: 100, maxFill: 0) == nil)
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
        #expect(EngineeringCalculations.ampacity(for: 999, isCopper: true) == 0)
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

    @Test func voltageDropValidatedRejectsNaN() {
        let result = EngineeringCalculations.voltageDropValidated(
            current: .nan,
            length: 50,
            section: 4,
            voltage: 220,
            isLoopLength: false,
            resistivity: 0.0175
        )
        switch result {
        case .failure(.notFinite(field: "电流")):
            break
        default:
            Issue.record("预期电流应返回 notFinite 错误")
        }
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

    @Test func conduitFillRateValidatedRejectsBadCount() {
        let result = EngineeringCalculations.conduitFillRateValidated(conduitInnerDiameter: 25, wireDiameter: 3.5, wireCount: 0)
        switch result {
        case .failure(.countOutOfRange(field: "导线根数", min: 1, max: 100_000)):
            break
        default:
            Issue.record("预期导线根数应返回 countOutOfRange 错误")
        }
    }

    @Test func recommendedConduit() throws {
        let d = try #require(EngineeringCalculations.recommendedConduitDiameter(wireDiameter: 3.5, wireCount: 5))
        #expect(d == 16)
    }

    @Test func recommendedConduitUsesLargestCommonDiameterWhenNeeded() {
        let d = EngineeringCalculations.recommendedConduitDiameter(wireDiameter: 10, wireCount: 10)
        #expect(d == 50)
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

    @Test func threePhaseIgnoresInvalidCurrents() {
        let totals = EngineeringCalculations.phaseTotals(
            currents: [.nan, .infinity, 30],
            assignments: [0, 1, 2]
        )
        #expect(totals[0] == 0)
        #expect(totals[1] == 0)
        #expect(totals[2] == 30)
    }

    // MARK: - cableArea

    @Test func cableAreaCalculation() {
        let area = EngineeringCalculations.cableArea(diameter: 10, count: 1)
        let expected = Double.pi * 25
        #expect(abs(area - expected) < 0.01)
    }
}

@MainActor
struct CalculatorDraftCommitTests {
    private func newStore() async throws -> DataStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("calculator-draft-commit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DataStore(storageDirectory: directory)
        await store.awaitInitialLoad()
        try #require(store.canEditBusinessData)
        return store
    }

    @Test(arguments: [CalculatorProjectDraftRequest.Kind.materialSheet, .quoteItem])
    func cancellationDoesNotWrite(kind: CalculatorProjectDraftRequest.Kind) async throws {
        let store = try await newStore()
        let target = Project(name: "Target", location: "")
        store.replaceProjects([target])
        let request = CalculatorProjectDraftRequest(kind: kind, projectId: target.id)
        var pending: CalculatorProjectDraftRequest? = nil // The review's Cancel action clears this value.
        _ = CalculatorProjectDraftCommitter.commit(request, pending: &pending, title: "Result", copyText: "Note", store: store)
        #expect(store.materialSheetDrafts.isEmpty)
        #expect(store.quoteItems.isEmpty)
    }

    @Test(arguments: [CalculatorProjectDraftRequest.Kind.materialSheet, .quoteItem])
    func confirmationWritesExactlyOnceToExplicitProject(kind: CalculatorProjectDraftRequest.Kind) async throws {
        let store = try await newStore()
        let other = Project(name: "A Other", location: "")
        let target = Project(name: "Z Target", location: "")
        store.replaceProjects([other, target])
        let request = CalculatorProjectDraftRequest(kind: kind, projectId: target.id)
        var pending: CalculatorProjectDraftRequest? = request
        _ = CalculatorProjectDraftCommitter.commit(request, pending: &pending, title: "Result", copyText: "Full\nresult", store: store)
        #expect(pending == nil)
        let draftIDs = Set(store.materialSheetDrafts.map(\.id))
        let quoteIDs = Set(store.quoteItems.map(\.id))
        _ = CalculatorProjectDraftCommitter.commit(request, pending: &pending, title: "Result", copyText: "Full\nresult", store: store)
        #expect(Set(store.materialSheetDrafts.map(\.id)) == draftIDs)
        #expect(Set(store.quoteItems.map(\.id)) == quoteIDs)
        if kind == .materialSheet {
            #expect(store.materialSheetDrafts.count == 1 && store.quoteItems.isEmpty)
            let draft = try #require(store.materialSheetDrafts.first)
            #expect(draft.projectId == target.id && draft.exportProjectName == target.name)
            #expect(draft.items.count == 1)
            let item = try #require(draft.items.first)
            #expect(item.name == "Result" && item.note == "Full\nresult")
            #expect(item.quantity.optionalDecimal == 1 && item.unit == calculatorLoc("项"))
            #expect(item.unitPrice.optionalDecimal == nil)
        } else {
            #expect(store.quoteItems.count == 1 && store.materialSheetDrafts.isEmpty)
            let item = try #require(store.quoteItems.first)
            #expect(item.projectId == target.id && item.name == "Result")
            #expect(item.notes == "Full\nresult" && item.quantity.optionalDecimal == 1)
            #expect(item.unit == calculatorLoc("项") && item.unitPrice.optionalDecimal == nil)
        }
    }

    @Test(arguments: [CalculatorProjectDraftRequest.Kind.materialSheet, .quoteItem])
    func deletedProjectDoesNotFallbackOrWrite(kind: CalculatorProjectDraftRequest.Kind) async throws {
        let store = try await newStore()
        let other = Project(name: "A Other", location: "")
        let target = Project(name: "Z Deleted", location: "")
        store.replaceProjects([other, target])
        let request = CalculatorProjectDraftRequest(kind: kind, projectId: target.id)
        var pending: CalculatorProjectDraftRequest? = request
        store.deleteProject(target.id)
        let outcome = CalculatorProjectDraftCommitter.commit(request, pending: &pending, title: "Result", copyText: "Note", store: store)
        guard case .missingProject = outcome else {
            Issue.record("Deleted target must reject confirmation")
            return
        }
        #expect(pending == nil)
        #expect(store.projects.map(\.id) == [other.id])
        #expect(store.materialSheetDrafts.isEmpty && store.quoteItems.isEmpty)
    }
}
