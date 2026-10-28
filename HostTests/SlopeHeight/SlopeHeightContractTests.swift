import Foundation
import Testing
@testable import sitekeeper

struct SlopeHeightContractTests {
    @Test func percentPerMilleAndRatioDescribeTheSameSlope() throws {
        let inputs: [(SiteSlopeUnit, Double)] = [(.percent, 2), (.perMille, 20), (.ratio, 50)]
        for (unit, value) in inputs {
            let metrics = try SlopeHeightCalculation.fromSlope(
                horizontalDistance: 12, distanceUnit: .meters, slope: value, slopeUnit: unit
            ).get()
            #expect(metrics == SlopeHeightMetrics(distanceMeters: 12, heightMeters: 0.24, gradient: 0.02))
        }
    }

    @Test func allLengthUnitsProduceTheSamePhysicalResult() throws {
        let distances: [(SiteLengthUnit, Double)] = [(.meters, 12), (.centimeters, 1200), (.millimeters, 12000)]
        let heights: [(SiteLengthUnit, Double)] = [(.meters, 0.24), (.centimeters, 24), (.millimeters, 240)]
        for (distanceUnit, distance) in distances {
            let fromSlope = try SlopeHeightCalculation.fromSlope(
                horizontalDistance: distance, distanceUnit: distanceUnit, slope: 2, slopeUnit: .percent
            ).get()
            #expect(fromSlope == SlopeHeightMetrics(distanceMeters: 12, heightMeters: 0.24, gradient: 0.02))
            for (heightUnit, height) in heights {
                let fromHeight = try SlopeHeightCalculation.fromHeight(
                    horizontalDistance: distance, distanceUnit: distanceUnit, height: height, heightUnit: heightUnit
                ).get()
                #expect(fromHeight == fromSlope)
            }
        }
    }

    @Test func levelGeometryAcceptsZeroHeightAndNonRatioSlope() throws {
        for unit in [SiteSlopeUnit.percent, .perMille] {
            let metrics = try SlopeHeightCalculation.fromSlope(
                horizontalDistance: 1, distanceUnit: .meters, slope: 0, slopeUnit: unit
            ).get()
            #expect(metrics.heightMeters == 0)
            #expect(metrics.gradient == 0)
        }
        let metrics = try SlopeHeightCalculation.fromHeight(
            horizontalDistance: 1, distanceUnit: .meters, height: 0, heightUnit: .millimeters
        ).get()
        #expect(metrics.heightMeters == 0)
        #expect(metrics.gradient == 0)
        #expect(SlopeHeightCalculation.fromSlope(
            horizontalDistance: 1, distanceUnit: .meters, slope: 0, slopeUnit: .ratio
        ) == .failure(.mustBeGreaterThanZero(field: "坡比")))
    }

    @Test func zeroNegativeAndNonFiniteSpansAreRejectedByBothOperations() {
        for value in [0, -1, Double.nan, .infinity, -.infinity] {
            let error: CalculationError = value.isFinite
                ? .mustBeGreaterThanZero(field: "水平距离") : .notFinite(field: "水平距离")
            #expect(SlopeHeightCalculation.fromSlope(
                horizontalDistance: value, distanceUnit: .meters, slope: 1, slopeUnit: .percent
            ) == .failure(error))
            #expect(SlopeHeightCalculation.fromHeight(
                horizontalDistance: value, distanceUnit: .meters, height: 1, heightUnit: .meters
            ) == .failure(error))
        }
    }

    @Test func negativeAndNonFiniteSlopesAreRejectedInEveryUnit() {
        for unit in SiteSlopeUnit.allCases {
            for value in [-1, Double.nan, .infinity, -.infinity] {
                let field = unit == .ratio ? "坡比" : "坡度"
                let error: CalculationError
                if !value.isFinite {
                    error = .notFinite(field: field)
                } else if unit == .ratio {
                    error = .mustBeGreaterThanZero(field: field)
                } else {
                    error = .mustBeNonNegative(field: field)
                }
                #expect(SlopeHeightCalculation.fromSlope(
                    horizontalDistance: 1, distanceUnit: .meters, slope: value, slopeUnit: unit
                ) == .failure(error))
            }
        }
    }

    @Test func negativeAndNonFiniteHeightsAreRejectedInEveryUnit() {
        for unit in SiteLengthUnit.allCases {
            for value in [-1, Double.nan, .infinity, -.infinity] {
                let error: CalculationError = value.isFinite
                    ? .mustBeNonNegative(field: "高差") : .notFinite(field: "高差")
                #expect(SlopeHeightCalculation.fromHeight(
                    horizontalDistance: 1, distanceUnit: .meters, height: value, heightUnit: unit
                ) == .failure(error))
            }
        }
    }

    @Test func overflowAndUnitConversionUnderflowDoNotProduceSuccess() {
        let overflow = CalculationError.notFinite(field: "计算结果")
        #expect(SlopeHeightCalculation.fromSlope(
            horizontalDistance: .greatestFiniteMagnitude, distanceUnit: .meters, slope: 1000, slopeUnit: .percent
        ) == .failure(overflow))
        #expect(SlopeHeightCalculation.fromSlope(
            horizontalDistance: 1, distanceUnit: .meters, slope: .leastNonzeroMagnitude, slopeUnit: .ratio
        ) == .failure(overflow))
        #expect(SlopeHeightCalculation.fromHeight(
            horizontalDistance: 1e-300, distanceUnit: .meters, height: 1e300, heightUnit: .meters
        ) == .failure(overflow))
        #expect(SlopeHeightCalculation.fromHeight(
            horizontalDistance: .leastNonzeroMagnitude, distanceUnit: .millimeters, height: 1, heightUnit: .meters
        ) == .failure(.mustBeGreaterThanZero(field: "水平距离")))
    }

    @Test func validFormBoundaryInputsPreserveTheOriginalViewExpressionsExactly() throws {
        // These are the original View expressions, evaluated over the form's
        // minimum/maximum and unit combinations; the app uses the complete core file.
        for distance in [0.0001, 1, 1_000_000] {
            for distanceUnit in SiteLengthUnit.allCases {
                let distanceMeters = distance * distanceUnit.metersPerUnit
                for slopeUnit in SiteSlopeUnit.allCases {
                    let values = slopeUnit == .ratio ? [0.0001, 0.5, 1, 1_000_000] : [0, 0.0001, 1, 1_000_000]
                    for value in values {
                        let originalGradient: Double
                        switch slopeUnit {
                        case .percent: originalGradient = value / 100
                        case .perMille: originalGradient = value / 1000
                        case .ratio: originalGradient = 1 / value
                        }
                        let metrics = try SlopeHeightCalculation.fromSlope(
                            horizontalDistance: distance, distanceUnit: distanceUnit, slope: value, slopeUnit: slopeUnit
                        ).get()
                        #expect(metrics == SlopeHeightMetrics(
                            distanceMeters: distanceMeters,
                            heightMeters: distanceMeters * originalGradient,
                            gradient: originalGradient
                        ))
                    }
                }
                for heightUnit in SiteLengthUnit.allCases {
                    for height in [0, 0.0001, 1, 1_000_000] {
                        let originalHeightMeters = height * heightUnit.metersPerUnit
                        let metrics = try SlopeHeightCalculation.fromHeight(
                            horizontalDistance: distance, distanceUnit: distanceUnit, height: height, heightUnit: heightUnit
                        ).get()
                        #expect(metrics == SlopeHeightMetrics(
                            distanceMeters: distanceMeters,
                            heightMeters: originalHeightMeters,
                            gradient: originalHeightMeters / distanceMeters
                        ))
                    }
                }
            }
        }
    }

    @Test func convertingHeightToSlopeAndBackPreservesMagnitude() throws {
        for distance in [0.0001, 12, 1_000_000] {
            for height in [0, 0.0001, 0.24, 1_000_000] {
                let fromHeight = try SlopeHeightCalculation.fromHeight(
                    horizontalDistance: distance, distanceUnit: .meters, height: height, heightUnit: .meters
                ).get()
                let fromSlope = try SlopeHeightCalculation.fromSlope(
                    horizontalDistance: distance, distanceUnit: .meters,
                    slope: fromHeight.gradient * 100, slopeUnit: .percent
                ).get()
                #expect(abs(fromSlope.heightMeters - height) <= max(1, height) * 1e-12)
            }
        }
    }
}
