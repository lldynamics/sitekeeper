import SwiftUI
#if os(iOS)
import UIKit
#endif

struct CADPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

enum CADOverlayCoordinateSpace: String, Codable, Equatable {
    case canvas
    case drawing
}

struct CADNativeCanvasTransform: Equatable {
    var bounds: CGRect
    var size: CGSize
    var zoomScale: CGFloat
    var panOffset: CGSize

    init(bounds: CGRect, size: CGSize, zoomScale: CGFloat, panOffset: CGSize) {
        self.bounds = bounds
        self.size = size
        self.zoomScale = zoomScale
        self.panOffset = panOffset
    }

    init(_ transform: CADRendererCanvasTransform) {
        self.init(
            bounds: transform.bounds,
            size: transform.size,
            zoomScale: transform.zoomScale,
            panOffset: transform.panOffset
        )
    }

    var contentInset: CGFloat {
        min(max(min(size.width, size.height) * 0.018, 6), 14)
    }

    var baseScale: CGFloat {
        let availableWidth = max(size.width - contentInset * 2, 1)
        let availableHeight = max(size.height - contentInset * 2, 1)
        let sx = availableWidth / max(bounds.width, 1)
        let sy = availableHeight / max(bounds.height, 1)
        return min(sx, sy)
    }

    var horizontalPad: CGFloat {
        (size.width - bounds.width * baseScale) / 2
    }

    var verticalPad: CGFloat {
        (size.height - bounds.height * baseScale) / 2
    }

    func canvasPoint(fromDrawing source: CGPoint) -> CGPoint {
        let x = (source.x - bounds.minX) * baseScale
        let y = (source.y - bounds.minY) * baseScale
        let base = CGPoint(
            x: horizontalPad + x,
            y: size.height - (verticalPad + y)
        )
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(
            x: center.x + (base.x - center.x) * zoomScale + panOffset.width,
            y: center.y + (base.y - center.y) * zoomScale + panOffset.height
        )
    }

    func drawingPoint(fromCanvas rendered: CGPoint) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let unscaledX = ((rendered.x - panOffset.width) - center.x) / max(zoomScale, 0.0001) + center.x
        let unscaledY = ((rendered.y - panOffset.height) - center.y) / max(zoomScale, 0.0001) + center.y
        let sourceX = bounds.minX + (unscaledX - horizontalPad) / max(baseScale, 0.0001)
        let sourceY = bounds.minY + ((size.height - unscaledY) - verticalPad) / max(baseScale, 0.0001)
        return CGPoint(x: sourceX, y: sourceY)
    }
}

enum CADNativeSnapPointKind: String {
    case endpoint
    case midpoint
    case center
    case intersection
}

enum CADNativePrimitiveKind: String {
    case line
    case polyline
    case arc
    case circle
    case ellipse
    case text
    case mtext
    case dimension
    case hatch
    case leader
    case image
    case wipeout
    case blockRef
    case unknownProxy

    var supportsMeasurementSnap: Bool {
        switch self {
        case .text, .mtext, .unknownProxy:
            return false
        default:
            return true
        }
    }
}

struct CADNativeSnapSourcePoint {
    let point: CGPoint
    let snapKind: CADNativeSnapPointKind
    let layer: String
    let primitiveKind: CADNativePrimitiveKind
    let styleRGB: UInt32
    let styleWidth: CGFloat
    let styleName: String?

    init(
        point: CGPoint,
        snapKind: CADNativeSnapPointKind,
        layer: String,
        primitiveKind: CADNativePrimitiveKind,
        styleRGB: UInt32,
        styleWidth: CGFloat,
        styleName: String?
    ) {
        self.point = point
        self.snapKind = snapKind
        self.layer = layer
        self.primitiveKind = primitiveKind
        self.styleRGB = styleRGB
        self.styleWidth = styleWidth
        self.styleName = styleName
    }

    init?(_ payload: [String: Any]) {
        let x = (payload["x"] as? NSNumber)?.doubleValue ?? (payload["x"] as? Double)
        let y = (payload["y"] as? NSNumber)?.doubleValue ?? (payload["y"] as? Double)
        guard let x, let y,
              let snapKindRaw = payload["snapKind"] as? String,
              let snapKind = CADNativeSnapPointKind(rawValue: snapKindRaw),
              let layer = payload["layer"] as? String,
              let primitiveRaw = payload["primitiveKind"] as? String,
              let primitiveKind = CADNativePrimitiveKind(rawValue: primitiveRaw) else {
            return nil
        }

        let rgbNumber = payload["styleRGB"] as? NSNumber
        let widthNumber = payload["styleWidth"] as? NSNumber
        self.point = CGPoint(x: x, y: y)
        self.snapKind = snapKind
        self.layer = layer
        self.primitiveKind = primitiveKind
        self.styleRGB = rgbNumber?.uint32Value ?? 0
        self.styleWidth = CGFloat(widthNumber?.doubleValue ?? 1)
        self.styleName = payload["styleName"] as? String
    }

    init?(_ payload: CADRendererSnapPointPayload) {
        guard let snapKind = CADNativeSnapPointKind(rawValue: payload.snapKind),
              let primitiveKind = CADNativePrimitiveKind(rawValue: payload.primitiveKind) else {
            return nil
        }
        self.point = payload.point
        self.snapKind = snapKind
        self.layer = payload.layer
        self.primitiveKind = primitiveKind
        self.styleRGB = payload.styleRGB
        self.styleWidth = payload.styleWidth
        self.styleName = payload.styleName
    }
}

struct CADNativeSnapPointBuckets {
    let sourcePoints: [CADNativeSnapSourcePoint]
    let allPoints: [CGPoint]
    let endpointPoints: [CGPoint]
    let midpointPoints: [CGPoint]
    let centerPoints: [CGPoint]
    let intersectionPoints: [CGPoint]
    let measurementAllPoints: [CGPoint]
    let measurementEndpointPoints: [CGPoint]
    let measurementMidpointPoints: [CGPoint]
    let measurementCenterPoints: [CGPoint]
    let measurementIntersectionPoints: [CGPoint]

    var isEmpty: Bool {
        sourcePoints.isEmpty
    }

    init(sourcePoints: [CADNativeSnapSourcePoint] = []) {
        self.sourcePoints = sourcePoints
        var allPoints: [CGPoint] = []
        var endpointPoints: [CGPoint] = []
        var midpointPoints: [CGPoint] = []
        var centerPoints: [CGPoint] = []
        var intersectionPoints: [CGPoint] = []
        var measurementAllPoints: [CGPoint] = []
        var measurementEndpointPoints: [CGPoint] = []
        var measurementMidpointPoints: [CGPoint] = []
        var measurementCenterPoints: [CGPoint] = []
        var measurementIntersectionPoints: [CGPoint] = []
        allPoints.reserveCapacity(sourcePoints.count)
        endpointPoints.reserveCapacity(sourcePoints.count / 2)
        midpointPoints.reserveCapacity(sourcePoints.count / 3)
        centerPoints.reserveCapacity(sourcePoints.count / 4)
        intersectionPoints.reserveCapacity(sourcePoints.count / 5)
        measurementAllPoints.reserveCapacity(sourcePoints.count)

        for sourcePoint in sourcePoints {
            allPoints.append(sourcePoint.point)
            if sourcePoint.primitiveKind.supportsMeasurementSnap {
                measurementAllPoints.append(sourcePoint.point)
            }
            switch sourcePoint.snapKind {
            case .endpoint:
                endpointPoints.append(sourcePoint.point)
                if sourcePoint.primitiveKind.supportsMeasurementSnap {
                    measurementEndpointPoints.append(sourcePoint.point)
                }
            case .midpoint:
                midpointPoints.append(sourcePoint.point)
                if sourcePoint.primitiveKind.supportsMeasurementSnap {
                    measurementMidpointPoints.append(sourcePoint.point)
                }
            case .center:
                centerPoints.append(sourcePoint.point)
                if sourcePoint.primitiveKind.supportsMeasurementSnap {
                    measurementCenterPoints.append(sourcePoint.point)
                }
            case .intersection:
                intersectionPoints.append(sourcePoint.point)
                if sourcePoint.primitiveKind.supportsMeasurementSnap {
                    measurementIntersectionPoints.append(sourcePoint.point)
                }
            }
        }

        self.allPoints = allPoints
        self.endpointPoints = endpointPoints
        self.midpointPoints = midpointPoints
        self.centerPoints = centerPoints
        self.intersectionPoints = intersectionPoints
        self.measurementAllPoints = measurementAllPoints
        self.measurementEndpointPoints = measurementEndpointPoints
        self.measurementMidpointPoints = measurementMidpointPoints
        self.measurementCenterPoints = measurementCenterPoints
        self.measurementIntersectionPoints = measurementIntersectionPoints
    }

    func points(enabledModes: Set<CADSnapMode>, measurementOnly: Bool) -> [CGPoint] {
        let allCandidates = measurementOnly ? measurementAllPoints : allPoints
        let endpointCandidates = measurementOnly ? measurementEndpointPoints : endpointPoints
        let midpointCandidates = measurementOnly ? measurementMidpointPoints : midpointPoints
        let centerCandidates = measurementOnly ? measurementCenterPoints : centerPoints
        let intersectionCandidates = measurementOnly ? measurementIntersectionPoints : intersectionPoints

        var points: [CGPoint] = []
        points.reserveCapacity(
            endpointCandidates.count
                + midpointCandidates.count
                + centerCandidates.count
                + intersectionCandidates.count
        )
        if enabledModes.contains(.endpoint) {
            points.append(contentsOf: endpointCandidates)
        }
        if enabledModes.contains(.midpoint) {
            points.append(contentsOf: midpointCandidates)
        }
        if enabledModes.contains(.center) {
            points.append(contentsOf: centerCandidates)
        }
        if enabledModes.contains(.intersection) {
            points.append(contentsOf: intersectionCandidates)
        }
        return points.isEmpty ? allCandidates : points
    }
}

extension Notification.Name {
    static let cadFocusSourcePoint = Notification.Name("CADFocusSourcePoint")
    static let cadOpenDrawingLayerPanel = Notification.Name("CADOpenDrawingLayerPanel")
    static let cadOpenTextSearchPanel = Notification.Name("CADOpenTextSearchPanel")
}

struct CADStroke: Identifiable, Codable, Equatable {
    enum StrokeKind: String, Codable {
        case annotation
        case redline
        case cloud
    }

    var id = UUID()
    var kind: StrokeKind
    var points: [CADPoint]
    var lineWidth: Double
    var colorHex: String?
    var layerName: String?
}

enum CADOverlayVisibilityGroup: String, CaseIterable {
    case annotation
    case measurement
    case notes
    case counts
    case issues

    var title: String {
        switch self {
        case .annotation: return String(localized: "批注线")
        case .measurement: return String(localized: "测量")
        case .notes: return String(localized: "文字批注")
        case .counts: return String(localized: "数数")
        case .issues: return String(localized: "问题点")
        }
    }

    var icon: String {
        switch self {
        case .annotation: return "highlighter"
        case .measurement: return "ruler"
        case .notes: return "text.bubble"
        case .counts: return "number.circle"
        case .issues: return "mappin.and.ellipse"
        }
    }
}

struct CADOverlayColorOption: Identifiable, Codable, Equatable {
    let name: String
    let hex: String

    var id: String { hex }
}

enum CADSnapMode: String, CaseIterable {
    case endpoint
    case midpoint
    case center
    case intersection

    var title: String {
        switch self {
        case .endpoint:
            return String(localized: "端点")
        case .midpoint:
            return String(localized: "中点")
        case .center:
            return String(localized: "圆心")
        case .intersection:
            return String(localized: "交点")
        }
    }

    var icon: String {
        switch self {
        case .endpoint:
            return "point.topleft.down.curvedto.point.bottomright.up"
        case .midpoint:
            return "line.3.horizontal"
        case .center:
            return "circle"
        case .intersection:
            return "plus"
        }
    }
}

enum CADAnnotationExportFormat {
    case csv
    case pdf

    var title: String {
        switch self {
        case .csv:
            return String(localized: "CSV 表格")
        case .pdf:
            return String(localized: "PDF 文档")
        }
    }
}

struct CADLengthMeasurement: Identifiable, Codable, Equatable {
    var id = UUID()
    var points: [CADPoint]
    var name: String
    var colorHex: String?
}

struct CADAreaMeasurement: Identifiable, Codable, Equatable {
    var id = UUID()
    var points: [CADPoint]
    var name: String
    var colorHex: String?
}

struct CADTextNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var point: CADPoint
    var layoutId: String?
    var worldPoint: CADPoint?
    var createdAt: String
    var colorHex: String?
}

struct CADCountMarker: Identifiable, Codable, Equatable {
    var id = UUID()
    var point: CADPoint
    var layoutId: String?
    var worldPoint: CADPoint?
    var category: String
    var createdAt: String
}

struct CADQuantityItem: Identifiable, Codable, Equatable {
    enum SourceLinkKind: String, Codable, Equatable {
        case manual
        case lengthMeasurement
        case areaMeasurement
        case countCategory
        case countMarkers
    }

    var id = UUID()
    var name: String
    var unit: String
    var quantity: String
    var unitPrice: String
    var wasteRate: String
    var source: String
    var sourceLinkKind: SourceLinkKind = .manual
    var sourceLinkID: UUID?
    var sourceLinkCategory: String?
    var sourceLinkMarkerIDs: [UUID]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case unit
        case quantity
        case unitPrice
        case wasteRate
        case source
        case sourceLinkKind
        case sourceLinkID
        case sourceLinkCategory
        case sourceLinkMarkerIDs
    }

    init(
        id: UUID = UUID(),
        name: String,
        unit: String,
        quantity: String,
        unitPrice: String,
        wasteRate: String,
        source: String,
        sourceLinkKind: SourceLinkKind = .manual,
        sourceLinkID: UUID? = nil,
        sourceLinkCategory: String? = nil,
        sourceLinkMarkerIDs: [UUID]? = nil
    ) {
        self.id = id
        self.name = name
        self.unit = unit
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.wasteRate = wasteRate
        self.source = source
        self.sourceLinkKind = sourceLinkKind
        self.sourceLinkID = sourceLinkID
        self.sourceLinkCategory = sourceLinkCategory
        self.sourceLinkMarkerIDs = sourceLinkMarkerIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        unit = try container.decodeIfPresent(String.self, forKey: .unit) ?? ""
        quantity = try container.decodeIfPresent(String.self, forKey: .quantity) ?? ""
        unitPrice = try container.decodeIfPresent(String.self, forKey: .unitPrice) ?? "0"
        wasteRate = try container.decodeIfPresent(String.self, forKey: .wasteRate) ?? "0"
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? String(localized: "手动")
        sourceLinkKind = try container.decodeIfPresent(SourceLinkKind.self, forKey: .sourceLinkKind) ?? .manual
        sourceLinkID = try container.decodeIfPresent(UUID.self, forKey: .sourceLinkID)
        sourceLinkCategory = try container.decodeIfPresent(String.self, forKey: .sourceLinkCategory)
        sourceLinkMarkerIDs = try container.decodeIfPresent([UUID].self, forKey: .sourceLinkMarkerIDs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(unit, forKey: .unit)
        try container.encode(quantity, forKey: .quantity)
        try container.encode(unitPrice, forKey: .unitPrice)
        try container.encode(wasteRate, forKey: .wasteRate)
        try container.encode(source, forKey: .source)
        try container.encode(sourceLinkKind, forKey: .sourceLinkKind)
        try container.encodeIfPresent(sourceLinkID, forKey: .sourceLinkID)
        try container.encodeIfPresent(sourceLinkCategory, forKey: .sourceLinkCategory)
        try container.encodeIfPresent(sourceLinkMarkerIDs, forKey: .sourceLinkMarkerIDs)
    }
}

enum CADDrawingUnitPreset: String, CaseIterable, Identifiable {
    case millimeter
    case centimeter
    case meter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .millimeter:
            return String(localized: "毫米图纸")
        case .centimeter:
            return String(localized: "厘米图纸")
        case .meter:
            return String(localized: "米制图纸")
        }
    }

    var subtitle: String {
        switch self {
        case .millimeter:
            return String(localized: "常见施工图：1 图纸单位 = 1 mm")
        case .centimeter:
            return String(localized: "少量现场草图：1 图纸单位 = 1 cm")
        case .meter:
            return String(localized: "总平面/测绘类：1 图纸单位 = 1 m")
        }
    }

    var metersPerDrawingUnit: Double {
        switch self {
        case .millimeter:
            return 0.001
        case .centimeter:
            return 0.01
        case .meter:
            return 1
        }
    }

    func isMatching(_ value: Double) -> Bool {
        abs(value - metersPerDrawingUnit) < 0.000000001
    }
}

struct CADOverlaySnapshot: Codable, Equatable {
    static let defaultMetersPerDrawingUnit: Double = CADDrawingUnitPreset.millimeter.metersPerDrawingUnit

    var metersPerDrawingUnitValue: Double = Self.defaultMetersPerDrawingUnit
    var coordinateSpace: CADOverlayCoordinateSpace = .drawing
    var strokes: [CADStroke] = []
    var lengthMeasurements: [CADLengthMeasurement] = []
    var areaMeasurements: [CADAreaMeasurement] = []
    var arrowAnnotations: [CADArrowAnnotation] = []
    var notes: [CADTextNote] = []
    var countMarkers: [CADCountMarker] = []
    var issueMarkers: [CADFallbackIssueMarker] = []
    var quantityItems: [CADQuantityItem] = []
    var hiddenOverlayGroupIDs: [String] = []
    var hiddenStrokeLayerNames: [String] = []
    var hiddenOverlayColorHexes: [String] = []
    var customStrokeLayerNames: [String] = []
    var customOverlayColors: [CADOverlayColorOption] = []
    var selectedStrokeLayerName: String?
    var selectedAnnotationColorHex: String?
    var selectedRedlineColorHex: String?
    var selectedMeasurementColorHex: String?
    var selectedNoteColorHex: String?
    var enabledSnapModeIDs: [String] = CADSnapMode.allCases.map(\.rawValue)

    enum CodingKeys: String, CodingKey {
        case metersPerDrawingUnit
        case metersPerPoint
        case coordinateSpace
        case strokes
        case lengthMeasurements
        case areaMeasurements
        case arrowAnnotations
        case notes
        case countMarkers
        case issueMarkers
        case quantityItems
        case hiddenOverlayGroupIDs
        case hiddenStrokeLayerNames
        case hiddenOverlayColorHexes
        case customStrokeLayerNames
        case customOverlayColors
        case selectedStrokeLayerName
        case selectedAnnotationColorHex
        case selectedRedlineColorHex
        case selectedMeasurementColorHex
        case selectedNoteColorHex
        case enabledSnapModeIDs
    }

    init() {}

    var metersPerDrawingUnit: Double {
        get { metersPerDrawingUnitValue }
        set { metersPerDrawingUnitValue = newValue }
    }

    mutating func normalizeMeasurementScale() {
        if metersPerDrawingUnit <= 0 {
            metersPerDrawingUnit = Self.defaultMetersPerDrawingUnit
        }
    }

    mutating func convertCanvasPointsToDrawingCoordinates(using transform: CADNativeCanvasTransform) {
        guard coordinateSpace == .canvas else { return }

        strokes = strokes.map { stroke in
            var next = stroke
            next.points = stroke.points.map { CADPoint(transform.drawingPoint(fromCanvas: $0.cgPoint)) }
            return next
        }
        lengthMeasurements = lengthMeasurements.map { measurement in
            var next = measurement
            next.points = measurement.points.map { CADPoint(transform.drawingPoint(fromCanvas: $0.cgPoint)) }
            return next
        }
        areaMeasurements = areaMeasurements.map { measurement in
            var next = measurement
            next.points = measurement.points.map { CADPoint(transform.drawingPoint(fromCanvas: $0.cgPoint)) }
            return next
        }
        arrowAnnotations = arrowAnnotations.map { arrow in
            var next = arrow
            next.start = CADPoint(transform.drawingPoint(fromCanvas: arrow.start.cgPoint))
            next.end = CADPoint(transform.drawingPoint(fromCanvas: arrow.end.cgPoint))
            return next
        }
        notes = notes.map { note in
            var next = note
            let point = CADPoint(transform.drawingPoint(fromCanvas: note.point.cgPoint))
            next.point = point
            next.worldPoint = point
            return next
        }
        countMarkers = countMarkers.map { marker in
            var next = marker
            let point = CADPoint(transform.drawingPoint(fromCanvas: marker.point.cgPoint))
            next.point = point
            next.worldPoint = point
            return next
        }
        issueMarkers = issueMarkers.map { marker in
            var next = marker
            let point = CADPoint(transform.drawingPoint(fromCanvas: marker.point.cgPoint))
            next.point = point
            next.worldPoint = point
            next.normalizedPoint = CADPoint(Self.normalizedPoint(point.cgPoint, in: transform.bounds))
            return next
        }
        coordinateSpace = .drawing
    }

    private static func normalizedPoint(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return point }
        return CGPoint(
            x: min(max((point.x - bounds.minX) / bounds.width, 0), 1),
            y: min(max((point.y - bounds.minY) / bounds.height, 0), 1)
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metersPerDrawingUnitValue = try container.decodeIfPresent(Double.self, forKey: .metersPerDrawingUnit)
            ?? container.decodeIfPresent(Double.self, forKey: .metersPerPoint)
            ?? Self.defaultMetersPerDrawingUnit
        coordinateSpace = try container.decodeIfPresent(CADOverlayCoordinateSpace.self, forKey: .coordinateSpace) ?? .canvas
        strokes = try container.decodeIfPresent([CADStroke].self, forKey: .strokes) ?? []
        lengthMeasurements = try container.decodeIfPresent([CADLengthMeasurement].self, forKey: .lengthMeasurements) ?? []
        areaMeasurements = try container.decodeIfPresent([CADAreaMeasurement].self, forKey: .areaMeasurements) ?? []
        arrowAnnotations = try container.decodeIfPresent([CADArrowAnnotation].self, forKey: .arrowAnnotations) ?? []
        notes = try container.decodeIfPresent([CADTextNote].self, forKey: .notes) ?? []
        countMarkers = try container.decodeIfPresent([CADCountMarker].self, forKey: .countMarkers) ?? []
        issueMarkers = try container.decodeIfPresent([CADFallbackIssueMarker].self, forKey: .issueMarkers) ?? []
        quantityItems = try container.decodeIfPresent([CADQuantityItem].self, forKey: .quantityItems) ?? []
        hiddenOverlayGroupIDs = try container.decodeIfPresent([String].self, forKey: .hiddenOverlayGroupIDs) ?? []
        hiddenStrokeLayerNames = try container.decodeIfPresent([String].self, forKey: .hiddenStrokeLayerNames) ?? []
        hiddenOverlayColorHexes = try container.decodeIfPresent([String].self, forKey: .hiddenOverlayColorHexes) ?? []
        customStrokeLayerNames = try container.decodeIfPresent([String].self, forKey: .customStrokeLayerNames) ?? []
        customOverlayColors = try container.decodeIfPresent([CADOverlayColorOption].self, forKey: .customOverlayColors) ?? []
        selectedStrokeLayerName = try container.decodeIfPresent(String.self, forKey: .selectedStrokeLayerName)
        selectedAnnotationColorHex = try container.decodeIfPresent(String.self, forKey: .selectedAnnotationColorHex)
        selectedRedlineColorHex = try container.decodeIfPresent(String.self, forKey: .selectedRedlineColorHex)
        selectedMeasurementColorHex = try container.decodeIfPresent(String.self, forKey: .selectedMeasurementColorHex)
        selectedNoteColorHex = try container.decodeIfPresent(String.self, forKey: .selectedNoteColorHex)
        enabledSnapModeIDs = try container.decodeIfPresent([String].self, forKey: .enabledSnapModeIDs) ?? CADSnapMode.allCases.map(\.rawValue)
        normalizeMeasurementScale()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metersPerDrawingUnitValue, forKey: .metersPerDrawingUnit)
        // Keep the legacy key for one migration window so older saved overlays can still round-trip.
        try container.encode(metersPerDrawingUnitValue, forKey: .metersPerPoint)
        try container.encode(coordinateSpace, forKey: .coordinateSpace)
        try container.encode(strokes, forKey: .strokes)
        try container.encode(lengthMeasurements, forKey: .lengthMeasurements)
        try container.encode(areaMeasurements, forKey: .areaMeasurements)
        try container.encode(arrowAnnotations, forKey: .arrowAnnotations)
        try container.encode(notes, forKey: .notes)
        try container.encode(countMarkers, forKey: .countMarkers)
        try container.encode(issueMarkers, forKey: .issueMarkers)
        try container.encode(quantityItems, forKey: .quantityItems)
        try container.encode(hiddenOverlayGroupIDs, forKey: .hiddenOverlayGroupIDs)
        try container.encode(hiddenStrokeLayerNames, forKey: .hiddenStrokeLayerNames)
        try container.encode(hiddenOverlayColorHexes, forKey: .hiddenOverlayColorHexes)
        try container.encode(customStrokeLayerNames, forKey: .customStrokeLayerNames)
        try container.encode(customOverlayColors, forKey: .customOverlayColors)
        try container.encodeIfPresent(selectedStrokeLayerName, forKey: .selectedStrokeLayerName)
        try container.encodeIfPresent(selectedAnnotationColorHex, forKey: .selectedAnnotationColorHex)
        try container.encodeIfPresent(selectedRedlineColorHex, forKey: .selectedRedlineColorHex)
        try container.encodeIfPresent(selectedMeasurementColorHex, forKey: .selectedMeasurementColorHex)
        try container.encodeIfPresent(selectedNoteColorHex, forKey: .selectedNoteColorHex)
        try container.encode(enabledSnapModeIDs, forKey: .enabledSnapModeIDs)
    }

    var hasOverlayContent: Bool {
        !strokes.isEmpty ||
        !lengthMeasurements.isEmpty ||
        !areaMeasurements.isEmpty ||
        !arrowAnnotations.isEmpty ||
        !notes.isEmpty ||
        !countMarkers.isEmpty ||
        !issueMarkers.isEmpty ||
        !quantityItems.isEmpty
    }
}

enum CADOverlayTool: String, CaseIterable {
    case browse
    case annotation
    case length
    case continuousLength
    case area
    case cloud
    case arrow
    case note
    case issueMarker
    case count

    var title: String {
        switch self {
        case .browse: return String(localized: "浏览")
        case .annotation: return String(localized: "批注")
        case .length: return String(localized: "线长")
        case .continuousLength: return String(localized: "连续长度")
        case .area: return String(localized: "面积")
        case .cloud: return String(localized: "云线")
        case .arrow: return String(localized: "箭头")
        case .note: return String(localized: "文字批注")
        case .issueMarker: return String(localized: "拍照问题点")
        case .count: return String(localized: "数数")
        }
    }

    var icon: String {
        switch self {
        case .browse: return "hand.tap"
        case .annotation: return "highlighter"
        case .length: return "ruler"
        case .continuousLength: return "point.topleft.down.curvedto.point.bottomright.up"
        case .area: return "square.dashed"
        case .cloud: return "cloud"
        case .arrow: return "arrow.up.right"
        case .note: return "text.bubble"
        case .issueMarker: return "camera.viewfinder"
        case .count: return "number.circle"
        }
    }

    var guidance: String {
        switch self {
        case .browse:
            return String(localized: "双指缩放、拖动平移图纸")
        case .annotation:
            return String(localized: "按住并拖动，在图纸上画批注线")
        case .length:
            return String(localized: "拖动一次生成一条线长测量")
        case .continuousLength:
            return String(localized: "逐点点按，最后点完成连续测量")
        case .area:
            return String(localized: "逐点点按，最后闭合计算面积")
        case .cloud:
            return String(localized: "按住并拖动，用云线圈出问题范围")
        case .arrow:
            return String(localized: "拖动一次生成一条指向箭头")
        case .note:
            return String(localized: "点空白新增文字批注，删除请用删除模式")
        case .issueMarker:
            return String(localized: "点图纸位置拍照或记录问题点")
        case .count:
            return String(localized: "点空白新增计数点，删除请用删除模式")
        }
    }

    var requiresDrawingCoordinateCapture: Bool {
        switch self {
        case .browse:
            return false
        case .annotation, .length, .continuousLength, .area, .cloud, .arrow, .note, .issueMarker, .count:
            return true
        }
    }

    var usesMeasurementSnapPrimitives: Bool {
        switch self {
        case .length, .continuousLength, .area, .count:
            return true
        case .browse, .annotation, .cloud, .arrow, .note, .issueMarker:
            return false
        }
    }
}

enum CADQuantityHighlightTarget: Equatable {
    case length(UUID)
    case area(UUID)
    case countCategory(String)
    case countMarkers([UUID])
}

enum CADOverlayDeleteTarget: Equatable {
    case stroke(UUID)
    case length(UUID)
    case area(UUID)
    case arrow(UUID)
    case note(UUID)
    case issue(UUID)
    case count(UUID)
}

