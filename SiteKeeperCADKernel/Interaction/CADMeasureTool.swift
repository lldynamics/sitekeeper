import Foundation

extension SiteKeeperCADKernel {
    enum CADMeasureMode: String, Equatable, Codable {
        case distance
        case polyline
        case area
    }

    enum CADMeasureCoordinateSpace: String, Equatable, Codable {
        case world
        case screen
    }

    enum CADMeasurementUnit: String, Equatable, Codable, CaseIterable {
        case drawingUnit = "drawing-unit"
        case millimeter = "mm"
        case centimeter = "cm"
        case meter = "m"
        case kilometer = "km"
        case inch = "in"
        case foot = "ft"

        init(rawLabel: String) {
            switch rawLabel.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "drawing-unit", "drawingunit", "unit", "units", "du", "图纸单位":
                self = .drawingUnit
            case "millimeter", "millimeters", "毫米", "mm":
                self = .millimeter
            case "centimeter", "centimeters", "厘米", "cm":
                self = .centimeter
            case "meter", "meters", "metre", "metres", "米", "m":
                self = .meter
            case "kilometer", "kilometers", "km":
                self = .kilometer
            case "inch", "inches", "in":
                self = .inch
            case "foot", "feet", "ft":
                self = .foot
            default:
                self = .drawingUnit
            }
        }

        var label: String { rawValue }

        var areaLabel: String {
            switch self {
            case .drawingUnit:
                return "drawing-unit^2"
            case .millimeter:
                return "mm^2"
            case .centimeter:
                return "cm^2"
            case .meter:
                return "m^2"
            case .kilometer:
                return "km^2"
            case .inch:
                return "in^2"
            case .foot:
                return "ft^2"
            }
        }

        func metersPerUnit(metersPerDrawingUnit: Double?) -> Double? {
            switch self {
            case .drawingUnit:
                return metersPerDrawingUnit
            case .millimeter:
                return 0.001
            case .centimeter:
                return 0.01
            case .meter:
                return 1
            case .kilometer:
                return 1_000
            case .inch:
                return 0.0254
            case .foot:
                return 0.3048
            }
        }
    }

    struct CADMeasureSegment: Equatable, Codable {
        var start: CADPoint
        var end: CADPoint
        var length: Double

        init(start: CADPoint, end: CADPoint, length: Double) {
            self.start = start
            self.end = end
            self.length = length
        }
    }

    struct CADMeasureInput: Equatable, Codable {
        var mode: CADMeasureMode
        var points: [CADPoint]
        var unit: String
        var coordinateSpace: CADMeasureCoordinateSpace
        var metersPerDrawingUnit: Double?
        var coordinateMapper: CADMarkupCoordinateMapper?

        init(
            mode: CADMeasureMode = .distance,
            points: [CADPoint],
            unit: String = CADMeasurementUnit.drawingUnit.rawValue,
            coordinateSpace: CADMeasureCoordinateSpace = .world,
            metersPerDrawingUnit: Double? = nil,
            coordinateMapper: CADMarkupCoordinateMapper? = nil
        ) {
            self.mode = mode
            self.points = points
            self.unit = unit
            self.coordinateSpace = coordinateSpace
            self.metersPerDrawingUnit = metersPerDrawingUnit
            self.coordinateMapper = coordinateMapper
        }
    }

    struct CADMeasureResult: Equatable, Codable {
        var mode: CADMeasureMode
        var value: Double
        var perimeter: Double?
        var area: Double?
        var unit: String
        var areaUnit: String?
        var worldPoints: [CADPoint]
        var segments: [CADMeasureSegment]
        var rawDrawingValue: Double
        var warnings: [String]

        init(
            mode: CADMeasureMode = .distance,
            value: Double,
            perimeter: Double? = nil,
            area: Double? = nil,
            unit: String,
            areaUnit: String? = nil,
            worldPoints: [CADPoint] = [],
            segments: [CADMeasureSegment] = [],
            rawDrawingValue: Double? = nil,
            warnings: [String] = []
        ) {
            self.mode = mode
            self.value = value
            self.perimeter = perimeter
            self.area = area
            self.unit = unit
            self.areaUnit = areaUnit
            self.worldPoints = worldPoints
            self.segments = segments
            self.rawDrawingValue = rawDrawingValue ?? value
            self.warnings = warnings
        }
    }

    struct CADMeasureTool {
        var units: CADUnits

        init(units: CADUnits = .unitless) {
            self.units = units
        }

        init(metersPerDrawingUnit: Double?) {
            self.units = CADUnits(name: "custom", metersPerDrawingUnit: metersPerDrawingUnit)
        }

        func measure(_ input: CADMeasureInput) -> CADMeasureResult {
            let unit = CADMeasurementUnit(rawLabel: input.unit)
            let metersPerDrawingUnit = input.metersPerDrawingUnit ?? units.metersPerDrawingUnit
            let worldPoints = pointsInWorldCoordinates(input)
            let warnings = conversionWarnings(for: unit, metersPerDrawingUnit: metersPerDrawingUnit)

            switch input.mode {
            case .distance:
                guard worldPoints.count >= 2 else {
                    return CADMeasureResult(
                        mode: .distance,
                        value: 0,
                        unit: unit.label,
                        worldPoints: worldPoints,
                        warnings: warnings
                    )
                }
                let rawLength = distanceValue(from: worldPoints[0], to: worldPoints[1])
                let converted = convertLength(rawLength, to: unit, metersPerDrawingUnit: metersPerDrawingUnit)
                return CADMeasureResult(
                    mode: .distance,
                    value: converted,
                    unit: unit.label,
                    worldPoints: worldPoints,
                    segments: [
                        CADMeasureSegment(
                            start: worldPoints[0],
                            end: worldPoints[1],
                            length: converted
                        )
                    ],
                    rawDrawingValue: rawLength,
                    warnings: warnings
                )
            case .polyline:
                let rawSegments = zip(worldPoints, worldPoints.dropFirst()).map { pair in
                    CADMeasureSegment(
                        start: pair.0,
                        end: pair.1,
                        length: distanceValue(from: pair.0, to: pair.1)
                    )
                }
                let rawLength = rawSegments.reduce(0) { $0 + $1.length }
                let converted = convertLength(rawLength, to: unit, metersPerDrawingUnit: metersPerDrawingUnit)
                let convertedSegments = rawSegments.map {
                    CADMeasureSegment(
                        start: $0.start,
                        end: $0.end,
                        length: convertLength($0.length, to: unit, metersPerDrawingUnit: metersPerDrawingUnit)
                    )
                }
                return CADMeasureResult(
                    mode: .polyline,
                    value: converted,
                    perimeter: converted,
                    unit: unit.label,
                    worldPoints: worldPoints,
                    segments: convertedSegments,
                    rawDrawingValue: rawLength,
                    warnings: warnings
                )
            case .area:
                let rawArea = polygonArea(worldPoints)
                let rawPerimeter = closedPairs(worldPoints).reduce(0) { total, pair in
                    total + distanceValue(from: pair.0, to: pair.1)
                }
                let convertedArea = convertArea(rawArea, to: unit, metersPerDrawingUnit: metersPerDrawingUnit)
                let convertedPerimeter = convertLength(rawPerimeter, to: unit, metersPerDrawingUnit: metersPerDrawingUnit)
                return CADMeasureResult(
                    mode: .area,
                    value: convertedArea,
                    perimeter: convertedPerimeter,
                    area: convertedArea,
                    unit: unit.label,
                    areaUnit: unit.areaLabel,
                    worldPoints: worldPoints,
                    rawDrawingValue: rawArea,
                    warnings: warnings
                )
            }
        }

        func distance(from start: CADPoint, to end: CADPoint, unit: String = CADMeasurementUnit.drawingUnit.rawValue) -> CADMeasureResult {
            measure(CADMeasureInput(points: [start, end], unit: unit))
        }

        func worldPoint(fromScreenPoint point: CADPoint, mapper: CADMarkupCoordinateMapper) -> CADPoint {
            mapper.worldPoint(forScreenPoint: point)
        }

        func screenPoint(fromWorldPoint point: CADPoint, mapper: CADMarkupCoordinateMapper) -> CADPoint {
            mapper.screenPoint(forWorldPoint: point)
        }

        private func pointsInWorldCoordinates(_ input: CADMeasureInput) -> [CADPoint] {
            guard input.coordinateSpace == .screen else { return input.points }
            guard let mapper = input.coordinateMapper else { return input.points }
            return input.points.map { mapper.worldPoint(forScreenPoint: $0) }
        }

        private func convertLength(_ drawingLength: Double, to unit: CADMeasurementUnit, metersPerDrawingUnit: Double?) -> Double {
            guard unit != .drawingUnit,
                  let metersPerDrawingUnit,
                  let metersPerOutputUnit = unit.metersPerUnit(metersPerDrawingUnit: metersPerDrawingUnit),
                  metersPerOutputUnit > 0 else {
                return drawingLength
            }
            return drawingLength * metersPerDrawingUnit / metersPerOutputUnit
        }

        private func convertArea(_ drawingArea: Double, to unit: CADMeasurementUnit, metersPerDrawingUnit: Double?) -> Double {
            guard unit != .drawingUnit,
                  let metersPerDrawingUnit,
                  let metersPerOutputUnit = unit.metersPerUnit(metersPerDrawingUnit: metersPerDrawingUnit),
                  metersPerOutputUnit > 0 else {
                return drawingArea
            }
            return drawingArea * metersPerDrawingUnit * metersPerDrawingUnit / (metersPerOutputUnit * metersPerOutputUnit)
        }

        private func conversionWarnings(for unit: CADMeasurementUnit, metersPerDrawingUnit: Double?) -> [String] {
            guard unit != .drawingUnit, metersPerDrawingUnit == nil else { return [] }
            return ["CAD_MEASURE_UNIT_SCALE_MISSING"]
        }

        private func distanceValue(from start: CADPoint, to end: CADPoint) -> Double {
            let dx = end.x - start.x
            let dy = end.y - start.y
            return (dx * dx + dy * dy).squareRoot()
        }

        private func polygonArea(_ points: [CADPoint]) -> Double {
            guard points.count >= 3 else { return 0 }
            let sum = closedPairs(points).reduce(0) { total, pair in
                total + pair.0.x * pair.1.y - pair.1.x * pair.0.y
            }
            return abs(sum) / 2
        }

        private func closedPairs(_ points: [CADPoint]) -> [(CADPoint, CADPoint)] {
            guard let first = points.first else { return [] }
            return Array(zip(points, Array(points.dropFirst()) + [first]))
        }
    }
}
