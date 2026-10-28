import Foundation

enum SiteLengthUnit: String, CaseIterable, Identifiable {
    case meters = "m"
    case centimeters = "cm"
    case millimeters = "mm"

    var id: String { rawValue }
    var metersPerUnit: Double {
        switch self {
        case .meters: 1
        case .centimeters: 0.01
        case .millimeters: 0.001
        }
    }
}

enum SiteSlopeUnit: String, CaseIterable, Identifiable {
    case percent = "%"
    case perMille = "‰"
    case ratio = "1:n"

    var id: String { rawValue }
}

struct SlopeHeightMetrics: Equatable {
    let distanceMeters: Double
    let heightMeters: Double
    let gradient: Double
}

/// Magnitude-only geometry. The caller owns rise/fall direction, input text,
/// display formatting, and the narrower ranges presented by its form.
enum SlopeHeightCalculation {
    static func fromSlope(
        horizontalDistance: Double,
        distanceUnit: SiteLengthUnit,
        slope: Double,
        slopeUnit: SiteSlopeUnit
    ) -> Result<SlopeHeightMetrics, CalculationError> {
        distanceInMeters(horizontalDistance, unit: distanceUnit).flatMap { distanceMeters in
            let validatedSlope = slopeUnit == .ratio
                ? CalculationValidator.positive(slope, field: "坡比")
                : CalculationValidator.nonNegative(slope, field: "坡度")
            return validatedSlope.flatMap { value in
                let gradient: Double
                switch slopeUnit {
                case .percent: gradient = value / 100
                case .perMille: gradient = value / 1000
                case .ratio: gradient = 1 / value
                }
                return result(
                    distanceMeters: distanceMeters,
                    heightMeters: distanceMeters * gradient,
                    gradient: gradient
                )
            }
        }
    }

    static func fromHeight(
        horizontalDistance: Double,
        distanceUnit: SiteLengthUnit,
        height: Double,
        heightUnit: SiteLengthUnit
    ) -> Result<SlopeHeightMetrics, CalculationError> {
        distanceInMeters(horizontalDistance, unit: distanceUnit).flatMap { distanceMeters in
            CalculationValidator.nonNegative(height, field: "高差").flatMap { value in
                let heightMeters = value * heightUnit.metersPerUnit
                return result(
                    distanceMeters: distanceMeters,
                    heightMeters: heightMeters,
                    gradient: heightMeters / distanceMeters
                )
            }
        }
    }

    private static func distanceInMeters(
        _ value: Double,
        unit: SiteLengthUnit
    ) -> Result<Double, CalculationError> {
        CalculationValidator.positive(value, field: "水平距离").flatMap {
            // A positive subnormal input can become zero during unit conversion.
            CalculationValidator.positive($0 * unit.metersPerUnit, field: "水平距离")
        }
    }

    private static func result(
        distanceMeters: Double,
        heightMeters: Double,
        gradient: Double
    ) -> Result<SlopeHeightMetrics, CalculationError> {
        guard gradient.isFinite, heightMeters.isFinite else {
            return .failure(.notFinite(field: "计算结果"))
        }
        return .success(SlopeHeightMetrics(
            distanceMeters: distanceMeters, heightMeters: heightMeters, gradient: gradient
        ))
    }
}
