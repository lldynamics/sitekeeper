import Foundation

enum MeasurementCheckUnit: String, CaseIterable, Identifiable {
    case millimeters = "mm"
    case centimeters = "cm"
    case meters = "m"

    var id: String { rawValue }
}

struct MeasurementCheckPointInput: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var reading: String
}

struct MeasurementCheckPointResult: Identifiable {
    let id: UUID
    let name: String
    let reading: Decimal
    let difference: Decimal
    let isWithinTolerance: Bool
}

struct MeasurementCheckSummary {
    let location: String
    let target: Decimal
    let tolerance: Decimal
    let unit: MeasurementCheckUnit
    let points: [MeasurementCheckPointResult]

    var withinCount: Int { points.filter(\.isWithinTolerance).count }
    var outsideCount: Int { points.count - withinCount }
}

enum MeasurementCheckModel {
    static let maximumPointCount = 50

    enum ValidationError: Error {
        case missingLocation
        case invalidTarget
        case invalidTolerance
        case invalidPointCount
        case missingPointName(Int)
        case invalidReading(Int)
        case unrepresentableDifference(Int)
    }

    // Signed measurements stay local to this tool; financial quantity validation remains unchanged.
    static func signedDecimal(_ text: String) -> Decimal? {
        let normalized = NumericInputSupport.normalizeSeparators(in: text).filter { !$0.isWhitespace }
        return DataValueParser.decimalValueIfPresent(from: normalized, requiresEntireString: true)
    }

    static func evaluate(
        location: String,
        targetText: String,
        toleranceText: String,
        unit: MeasurementCheckUnit,
        points: [MeasurementCheckPointInput]
    ) throws -> MeasurementCheckSummary {
        let cleanLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanLocation.isEmpty else { throw ValidationError.missingLocation }
        guard let target = signedDecimal(targetText) else { throw ValidationError.invalidTarget }
        guard let tolerance = signedDecimal(toleranceText), tolerance >= .zero else {
            throw ValidationError.invalidTolerance
        }
        guard (1...maximumPointCount).contains(points.count) else {
            throw ValidationError.invalidPointCount
        }

        let results = try points.enumerated().map { index, point in
            let name = point.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { throw ValidationError.missingPointName(index + 1) }
            guard let reading = signedDecimal(point.reading) else {
                throw ValidationError.invalidReading(index + 1)
            }
            let difference = DecimalMath.subtract(reading, target)
            guard !difference.isNaN else {
                throw ValidationError.unrepresentableDifference(index + 1)
            }
            return MeasurementCheckPointResult(
                id: point.id, name: name, reading: reading, difference: difference,
                isWithinTolerance: difference.magnitude <= tolerance
            )
        }

        return MeasurementCheckSummary(
            location: cleanLocation, target: target, tolerance: tolerance, unit: unit, points: results
        )
    }
}
