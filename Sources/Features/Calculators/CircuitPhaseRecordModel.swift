import Foundation

enum CircuitPhaseRecordPhase: Int, CaseIterable, Identifiable, Sendable {
    case a, b, c

    var id: Int { rawValue }

    var symbol: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .c: "C"
        }
    }
}

struct CircuitPhaseRecordInput: Identifiable, Equatable {
    let id = UUID()
    var name = ""
    var currentText = ""
    var phase = CircuitPhaseRecordPhase.a
}

struct CircuitPhaseRecordEntry {
    let name: String
    let current: Decimal
    let phase: CircuitPhaseRecordPhase
}

struct CircuitPhaseRecordSummary {
    let circuits: [CircuitPhaseRecordEntry]
    let phaseTotals: [Decimal]

    var maximumPhases: [CircuitPhaseRecordPhase] {
        guard let maximum = phaseTotals.max() else { return [] }
        return CircuitPhaseRecordPhase.allCases.filter { phaseTotals[$0.rawValue] == maximum }
    }

    var minimumPhases: [CircuitPhaseRecordPhase] {
        guard let minimum = phaseTotals.min() else { return [] }
        return CircuitPhaseRecordPhase.allCases.filter { phaseTotals[$0.rawValue] == minimum }
    }
}

enum CircuitPhaseRecordError: Error {
    case noCircuits
    case tooManyCircuits
    case missingName(row: Int)
    case invalidCurrent(row: Int)
    case totalOutOfRange
}

enum CircuitPhaseRecordModel {
    static let maximumCircuitCount = 50

    static func summarize(_ inputs: [CircuitPhaseRecordInput]) throws -> CircuitPhaseRecordSummary {
        guard !inputs.isEmpty else { throw CircuitPhaseRecordError.noCircuits }
        guard inputs.count <= maximumCircuitCount else { throw CircuitPhaseRecordError.tooManyCircuits }

        var entries: [CircuitPhaseRecordEntry] = []
        var totals = [Decimal.zero, .zero, .zero]
        var currents: [Double] = []
        var assignments: [Int] = []

        for (index, input) in inputs.enumerated() {
            let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw CircuitPhaseRecordError.missingName(row: index + 1) }
            guard let current = DataValueParser.decimalValueIfPresent(
                from: input.currentText, requiresEntireString: true
            ), !current.isNaN, current >= .zero else {
                throw CircuitPhaseRecordError.invalidCurrent(row: index + 1)
            }
            let doubleCurrent = NSDecimalNumber(decimal: current).doubleValue
            guard doubleCurrent.isFinite, doubleCurrent >= 0 else {
                throw CircuitPhaseRecordError.invalidCurrent(row: index + 1)
            }

            let phaseIndex = input.phase.rawValue
            let nextTotal = DecimalMath.add(totals[phaseIndex], current)
            guard !nextTotal.isNaN else { throw CircuitPhaseRecordError.totalOutOfRange }
            totals[phaseIndex] = nextTotal
            entries.append(CircuitPhaseRecordEntry(name: name, current: current, phase: input.phase))
            currents.append(doubleCurrent)
            assignments.append(phaseIndex)
        }

        // Only validated nonnegative values reach the shared Double helper.
        // Exact Decimal totals remain authoritative for display and saved records.
        let checkedTotals = EngineeringCalculations.phaseTotals(currents: currents, assignments: assignments)
        guard checkedTotals.count == totals.count else { throw CircuitPhaseRecordError.totalOutOfRange }
        for index in totals.indices {
            let expected = NSDecimalNumber(decimal: totals[index]).doubleValue
            let actual = checkedTotals[index]
            let tolerance = max(1e-10, abs(expected) * 1e-12)
            guard expected.isFinite, actual.isFinite, actual >= 0,
                  abs(actual - expected) <= tolerance else {
                throw CircuitPhaseRecordError.totalOutOfRange
            }
        }

        return CircuitPhaseRecordSummary(circuits: entries, phaseTotals: totals)
    }
}
