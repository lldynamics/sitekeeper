import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

struct ProjectCADPreviewRequest: Identifiable {
    let id = UUID()
    let projectId: UUID
    let drawingID: UUID
    let fileURL: URL
    let displayName: String
    let fileType: String
    let textEncoding: CADDrawingTextEncoding
    let textBigFont: CADDrawingTextBigFont
    let textSchemeSnapshot: CADDrawingTextSchemeSnapshot
    let overlaySnapshotData: String
    let onOverlaySnapshotChange: (UUID, String) -> Void
    let onTextEncodingChange: (UUID, CADDrawingTextEncoding) -> Void
    let onTextBigFontChange: (UUID, CADDrawingTextBigFont) -> Void
    let onTextSchemeSnapshotChange: (UUID, CADDrawingTextSchemeSnapshot) -> Void

    var preferredTextCodePage: Int32? {
        textEncoding.codePageOverride
    }

    var preferredTextBigFontCode: Int32? {
        textBigFont.bridgeCode
    }
}

struct CADLibreDWGUnavailableView: View {
    let fileURL: URL
    let displayName: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color.appWarning)

            VStack(spacing: 6) {
                Text("LibreDWG 引擎未集成")
                    .font(.title3.weight(.semibold))
                Text("已选择 LibreDWG 预览，但当前构建未包含 LibreDWGBridge。请先把桥接库接入工程，再重编译。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(displayName)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            ShareLink(item: fileURL) {
                Label("先用其他 CAD App 打开", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appProminent(tint: .appDoc))
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

struct CADLibreDWGUnboundView: View {
    let fileURL: URL
    let displayName: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color.appWarning)

            VStack(spacing: 6) {
                Text("LibreDWG 渲染器未注册")
                    .font(.title3.weight(.semibold))
                Text("检测到 LibreDWG 环境，但应用内还没有绑定渲染入口。请在启动时调用 CADRendererProvider.registerLibreDWGRenderer。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(displayName)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            ShareLink(item: fileURL) {
                Label("先用其他 CAD App 打开", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appProminent(tint: .appDoc))
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

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

extension Notification.Name {
    static let libreDWGCanvasTransformDidChange = Notification.Name("LibreDWGBridgeCanvasTransformDidChange")
    static let libreDWGSnapPointsDidChange = Notification.Name("LibreDWGBridgeSnapPointsDidChange")
    static let libreDWGFocusSourcePoint = Notification.Name("LibreDWGBridgeFocusSourcePoint")
    static let libreDWGTextAutoDetectionDidChange = Notification.Name("LibreDWGBridgeTextAutoDetectionDidChange")
}

struct CADStroke: Identifiable, Codable, Equatable {
    enum StrokeKind: String, Codable {
        case annotation
        case redline
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
    case redline
    case measurement
    case notes
    case counts

    var title: String {
        switch self {
        case .annotation: return String(localized: "批注线")
        case .redline: return String(localized: "红线")
        case .measurement: return String(localized: "测量")
        case .notes: return String(localized: "文字批注")
        case .counts: return String(localized: "数数")
        }
    }

    var icon: String {
        switch self {
        case .annotation: return "highlighter"
        case .redline: return "scribble"
        case .measurement: return "ruler"
        case .notes: return "text.bubble"
        case .counts: return "number.circle"
        }
    }
}

struct CADOverlayColorOption: Identifiable, Equatable {
    let name: String
    let hex: String

    var id: String { hex }
}

enum CADSnapMode: String, CaseIterable {
    case endpoint
    case midpoint
    case center

    var title: String {
        switch self {
        case .endpoint:
            return String(localized: "端点")
        case .midpoint:
            return String(localized: "中点")
        case .center:
            return String(localized: "圆心")
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
}

struct CADAreaMeasurement: Identifiable, Codable, Equatable {
    var id = UUID()
    var points: [CADPoint]
    var name: String
}

struct CADTextNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var point: CADPoint
    var createdAt: String
}

struct CADCountMarker: Identifiable, Codable, Equatable {
    var id = UUID()
    var point: CADPoint
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
    var notes: [CADTextNote] = []
    var countMarkers: [CADCountMarker] = []
    var quantityItems: [CADQuantityItem] = []
    var hiddenOverlayGroupIDs: [String] = []
    var hiddenStrokeLayerNames: [String] = []
    var selectedStrokeLayerName: String?
    var selectedAnnotationColorHex: String?
    var selectedRedlineColorHex: String?
    var enabledSnapModeIDs: [String] = CADSnapMode.allCases.map(\.rawValue)

    enum CodingKeys: String, CodingKey {
        case metersPerDrawingUnit
        case metersPerPoint
        case coordinateSpace
        case strokes
        case lengthMeasurements
        case areaMeasurements
        case notes
        case countMarkers
        case quantityItems
        case hiddenOverlayGroupIDs
        case hiddenStrokeLayerNames
        case selectedStrokeLayerName
        case selectedAnnotationColorHex
        case selectedRedlineColorHex
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
        notes = notes.map { note in
            var next = note
            next.point = CADPoint(transform.drawingPoint(fromCanvas: note.point.cgPoint))
            return next
        }
        countMarkers = countMarkers.map { marker in
            var next = marker
            next.point = CADPoint(transform.drawingPoint(fromCanvas: marker.point.cgPoint))
            return next
        }
        coordinateSpace = .drawing
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
        notes = try container.decodeIfPresent([CADTextNote].self, forKey: .notes) ?? []
        countMarkers = try container.decodeIfPresent([CADCountMarker].self, forKey: .countMarkers) ?? []
        quantityItems = try container.decodeIfPresent([CADQuantityItem].self, forKey: .quantityItems) ?? []
        hiddenOverlayGroupIDs = try container.decodeIfPresent([String].self, forKey: .hiddenOverlayGroupIDs) ?? []
        hiddenStrokeLayerNames = try container.decodeIfPresent([String].self, forKey: .hiddenStrokeLayerNames) ?? []
        selectedStrokeLayerName = try container.decodeIfPresent(String.self, forKey: .selectedStrokeLayerName)
        selectedAnnotationColorHex = try container.decodeIfPresent(String.self, forKey: .selectedAnnotationColorHex)
        selectedRedlineColorHex = try container.decodeIfPresent(String.self, forKey: .selectedRedlineColorHex)
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
        try container.encode(notes, forKey: .notes)
        try container.encode(countMarkers, forKey: .countMarkers)
        try container.encode(quantityItems, forKey: .quantityItems)
        try container.encode(hiddenOverlayGroupIDs, forKey: .hiddenOverlayGroupIDs)
        try container.encode(hiddenStrokeLayerNames, forKey: .hiddenStrokeLayerNames)
        try container.encodeIfPresent(selectedStrokeLayerName, forKey: .selectedStrokeLayerName)
        try container.encodeIfPresent(selectedAnnotationColorHex, forKey: .selectedAnnotationColorHex)
        try container.encodeIfPresent(selectedRedlineColorHex, forKey: .selectedRedlineColorHex)
        try container.encode(enabledSnapModeIDs, forKey: .enabledSnapModeIDs)
    }

    var hasOverlayContent: Bool {
        !strokes.isEmpty ||
        !lengthMeasurements.isEmpty ||
        !areaMeasurements.isEmpty ||
        !notes.isEmpty ||
        !countMarkers.isEmpty ||
        !quantityItems.isEmpty
    }
}

enum CADOverlayTool: String, CaseIterable {
    case browse
    case annotation
    case redline
    case length
    case continuousLength
    case area
    case note
    case count

    var title: String {
        switch self {
        case .browse: return String(localized: "浏览")
        case .annotation: return String(localized: "批注")
        case .redline: return String(localized: "红线")
        case .length: return String(localized: "线长")
        case .continuousLength: return String(localized: "连续长度")
        case .area: return String(localized: "面积")
        case .note: return String(localized: "文字批注")
        case .count: return String(localized: "数数")
        }
    }

    var icon: String {
        switch self {
        case .browse: return "hand.tap"
        case .annotation: return "highlighter"
        case .redline: return "scribble"
        case .length: return "ruler"
        case .continuousLength: return "point.topleft.down.curvedto.point.bottomright.up"
        case .area: return "square.dashed"
        case .note: return "text.bubble"
        case .count: return "number.circle"
        }
    }

    var guidance: String {
        switch self {
        case .browse:
            return String(localized: "双指缩放、拖动平移图纸")
        case .annotation:
            return String(localized: "按住并拖动，在图纸上画普通批注线")
        case .redline:
            return String(localized: "按住并拖动，在图纸上画红线标记")
        case .length:
            return String(localized: "拖动一次生成一条线长测量")
        case .continuousLength:
            return String(localized: "逐点点按，最后点完成连续测量")
        case .area:
            return String(localized: "逐点点按，最后闭合计算面积")
        case .note:
            return String(localized: "点空白新增文字批注，点现有批注删除")
        case .count:
            return String(localized: "点空白新增计数点，点编号删除")
        }
    }

    var requiresDrawingCoordinateCapture: Bool {
        switch self {
        case .browse:
            return false
        case .annotation, .redline, .length, .continuousLength, .area, .note, .count:
            return true
        }
    }
}

enum CADQuantityHighlightTarget: Equatable {
    case length(UUID)
    case area(UUID)
    case countCategory(String)
    case countMarkers([UUID])
}

struct CADDrawingTreeGroup: Identifiable {
    let id: String
    let title: String
    let drawings: [ProjectDrawing]
}

enum LegacyCADOverlayStorage {
    static func key(for fileURL: URL) -> String {
        let encoded = Data(fileURL.path.utf8).base64EncodedString()
        return "cad.overlay.snapshot.\(encoded)"
    }

    static func load(for fileURL: URL) -> CADOverlaySnapshot? {
        let key = key(for: fileURL)
        guard let raw = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(CADOverlaySnapshot.self, from: raw)
        } catch {
            StorageIssueLog.record("CAD 旧快照解析失败：\(fileURL.lastPathComponent)，\(error.localizedDescription)")
            return nil
        }
    }
}

struct CADPreviewContainer: View {
    let request: ProjectCADPreviewRequest
    @Environment(DataStore.self) var store
    @Environment(\.dismiss) var dismiss

    @State var activeRequest: ProjectCADPreviewRequest
    @State var tool: CADOverlayTool = .browse
    @State var snapshot = CADOverlaySnapshot()
    @State var activeStrokePoints: [CGPoint] = []
    @State var pendingLengthPoints: [CGPoint] = []
    @State var pendingAreaPoints: [CGPoint] = []
    @State var activeDragLengthPoints: [CGPoint] = []
    @State var showQuantitySheet = false
    @State var showResetConfirm = false
    @State var showScaleSheet = false
    @State var showOverlayLayerSheet = false
    @State var showAnnotationExportFormatDialog = false
    @State var showDrawingTreeSheet = false
    @State var drawingTreeSearchText = ""
    @State var showTextEncodingDialog = false
    @State var scaleDraft = ""
    @State var calibrationActualMetersDraft = ""
    @State var selectedCalibrationMeasurementID: UUID?
    @State var pendingNotePoint: CGPoint?
    @State var noteDraft = ""
    @State var showNoteSheet = false
    @State var recentDrawingTabIDs: [UUID] = []
    @State var selectedCountCategory = String(localized: "点位")
    @State var lastPersistedSnapshotData = ""
    @State var isImmersivePreview = false
    @State var selectedTextEncoding: CADDrawingTextEncoding
    @State var selectedTextBigFont: CADDrawingTextBigFont
    @State var textSchemeSnapshot: CADDrawingTextSchemeSnapshot
    @State var selectedStrokeLayer = String(localized: "现场批注")
    @State var selectedAnnotationColorHex = "2F80ED"
    @State var selectedRedlineColorHex = "D92D20"
    @State var hiddenOverlayGroups: Set<CADOverlayVisibilityGroup> = []
    @State var hiddenStrokeLayers: Set<String> = []
    @State var isSelectingStroke = false
    @State var selectedStrokeID: UUID?
    @State var isAutoDetectingText = false
    @State var isExportingDiagnosticLog = false
    @State var diagnosticExportPayload: ExportPayload?
    @State var annotationExportPayload: ExportPayload?
    @State var quantityHighlightTarget: CADQuantityHighlightTarget?
    @State var nativeCanvasTransform: CADNativeCanvasTransform?
    @State var nativeSnapPoints: [CGPoint] = []
    @State var nativeEndpointSnapPoints: [CGPoint] = []
    @State var nativeMidpointSnapPoints: [CGPoint] = []
    @State var nativeCenterSnapPoints: [CGPoint] = []
    @State var nativeSnapSourcePoints: [CADNativeSnapSourcePoint] = []
    @State var enabledSnapModes: Set<CADSnapMode> = Set(CADSnapMode.allCases)
    @State var cadPreviewReloadToken = UUID()
    @State var alertMessage = ""
    @State var showAlert = false
    @State var showShareSheet = false
    let overlaySnapTolerance: CGFloat = 14

    init(request: ProjectCADPreviewRequest) {
        self.request = request
        _activeRequest = State(initialValue: request)
        _selectedTextEncoding = State(initialValue: request.textEncoding)
        _selectedTextBigFont = State(initialValue: request.textBigFont)
        _textSchemeSnapshot = State(initialValue: request.textSchemeSnapshot)
    }

    var preferredEngine: CADPreviewEngine {
        CADPreviewEngineStore.selected
    }

    var resolvedEngine: CADPreviewEngine {
        CADPreviewCapability.resolvedEngine(preferredEngine)
    }

    var isCADFile: Bool {
        CADPreviewCapability.isCADFile(extension: activeRequest.fileType)
    }

    var shouldShowLibreDWGUnavailable: Bool {
        isCADFile && !CADPreviewCapability.isLibreDWGRendererAvailable()
    }

    var shouldShowLibreDWGUnbound: Bool {
        isCADFile &&
        resolvedEngine == .libreDWG &&
        !shouldShowLibreDWGUnavailable &&
        !CADRendererProvider.isLibreDWGRendererBound
    }

    var shouldUseLibreDWGRenderer: Bool {
        isCADFile &&
        resolvedEngine == .libreDWG &&
        CADRendererProvider.isLibreDWGRendererBound
    }

    var allowsOverlayEditing: Bool {
        isCADFile ? shouldUseLibreDWGRenderer : true
    }

    var engineStatusText: String {
        if !isCADFile {
            return String(localized: "文档预览")
        }
        if shouldShowLibreDWGUnavailable {
            return String(localized: "LibreDWG 未接入")
        }
        if shouldShowLibreDWGUnbound {
            return String(localized: "LibreDWG 未绑定")
        }
        return String(localized: "LibreDWG 预览")
    }

    var engineStatusIcon: String {
        if shouldShowLibreDWGUnavailable || shouldShowLibreDWGUnbound {
            return "exclamationmark.triangle.fill"
        }
        return isCADFile ? "checkmark.seal.fill" : "viewfinder"
    }

    var engineStatusTint: Color {
        if shouldShowLibreDWGUnavailable || shouldShowLibreDWGUnbound {
            return Color.appWarning
        }
        return isCADFile ? Color.appSuccess : Color.appDoc
    }

    var engineStatusHint: String? {
        if shouldShowLibreDWGUnavailable {
            return String(localized: "当前构建未包含 LibreDWGBridge，已显示接入提示。")
        }
        if shouldShowLibreDWGUnbound {
            return String(localized: "LibreDWG 已可用，但渲染入口未注册。")
        }
        return nil
    }

    var unitHint: String {
        "\(measurementScalePresetTitle)：\(String(localized: "1")) \(measurementUnitName) = \(measurementScaleText) m"
    }

    var measurementUnitName: String {
        String(localized: "图纸单位")
    }

    var measurementScalePresetTitle: String {
        let value = snapshot.metersPerDrawingUnit
        if let preset = CADDrawingUnitPreset.allCases.first(where: { $0.isMatching(value) }) {
            return preset.title
        }
        return String(localized: "自定义标定")
    }

    var measurementScaleText: String {
        Formatters.number(snapshot.metersPerDrawingUnit, minFraction: 0, maxFraction: 6)
    }

    var measurementScalePrompt: String {
        String(localized: "1 图纸单位对应多少米")
    }

    var measurementScaleDescription: String {
        if hasNativeDrawingCoordinateSpace {
            return String(localized: "测量按 DWG 图纸坐标计算，再通过“图纸单位 → 米”换算，缩放和平移不会改变线长/面积结果。")
        }
        return String(localized: "当前图纸坐标尚未就绪，测量/数数已禁用，避免把屏幕坐标写入算量数据。")
    }

    var calibrationCandidateMeasurements: [CADLengthMeasurement] {
        snapshot.lengthMeasurements.sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var selectedCalibrationMeasurement: CADLengthMeasurement? {
        guard let selectedCalibrationMeasurementID else { return calibrationCandidateMeasurements.first }
        return calibrationCandidateMeasurements.first(where: { $0.id == selectedCalibrationMeasurementID }) ?? calibrationCandidateMeasurements.first
    }

    var calibrationComputedScale: Double? {
        guard let measurement = selectedCalibrationMeasurement else { return nil }
        let actualMeters = ReportBuilder.number(calibrationActualMetersDraft)
        guard actualMeters > 0 else { return nil }
        let sourceLength = drawingUnitLength(for: measurement.points.map(\.cgPoint))
        guard sourceLength > 0 else { return nil }
        return actualMeters / sourceLength
    }

    var currentTextSchemeTitle: String {
        "\(selectedTextEncoding.displayName) / \(selectedTextBigFont.displayName)"
    }

    var textSchemeDiagnosticRows: [(String, String)] {
        var rows: [(String, String)] = []
        let codePage = textSchemeSnapshot.codePage.map(codePageDisplayName) ?? String(localized: "自动/未知")
        rows.append((String(localized: "命中编码"), codePage))
        let bigFontCode = textSchemeSnapshot.bigFont ?? selectedTextBigFont.bridgeCode ?? 0
        let bigFontProfile = textBigFont(forBridgeCode: bigFontCode) ?? .auto
        rows.append((String(localized: "大字体策略"), bigFontProfile.displayName))
        if let styleName = textSchemeSnapshot.styleName, !styleName.isEmpty {
            rows.append((String(localized: "样式"), styleName))
        }
        if let fontFile = textSchemeSnapshot.fontFile, !fontFile.isEmpty {
            rows.append((String(localized: "字体"), fontFile))
        }
        if let bigFontFile = textSchemeSnapshot.bigFontFile, !bigFontFile.isEmpty {
            rows.append((String(localized: "大字体文件"), bigFontFile))
        }
        if let autoDetectScore = textSchemeSnapshot.autoDetectScore {
            rows.append((String(localized: "自动识别评分"), "\(autoDetectScore)"))
        }
        if let styleSummary = textSchemeSnapshot.styleSummary, !styleSummary.isEmpty {
            rows.append((String(localized: "STYLE 表"), styleSummary))
        }
        if let rawSample = textSchemeSnapshot.rawTextBytesHexSample, !rawSample.isEmpty {
            rows.append((String(localized: "raw text bytes"), rawSample))
        }
        if let summary = textSchemeSnapshot.detectionSummary, !summary.isEmpty {
            rows.append((String(localized: "识别摘要"), summary))
        }
        return rows
    }

    var diagnosticExporterPresented: Binding<Bool> {
        Binding(
            get: { diagnosticExportPayload != nil },
            set: { isPresented in
                if !isPresented {
                    diagnosticExportPayload = nil
                }
            }
        )
    }

    var annotationExporterPresented: Binding<Bool> {
        Binding(
            get: { annotationExportPayload != nil },
            set: { isPresented in
                if !isPresented {
                    annotationExportPayload = nil
                }
            }
        )
    }

    var quantityTotal: Double {
        snapshot.quantityItems.reduce(0) { result, item in
            let quantity = ReportBuilder.number(item.quantity)
            let unitPrice = ReportBuilder.number(item.unitPrice)
            let waste = ReportBuilder.number(item.wasteRate) / 100
            return result + quantity * max(0, 1 + waste) * unitPrice
        }
    }

    var countCategoryOptions: [String] {
        [
            String(localized: "点位"),
            String(localized: "灯位"),
            String(localized: "插座"),
            String(localized: "开关"),
            String(localized: "桥架点"),
            String(localized: "管卡")
        ]
    }

    var countCategoryStats: [(category: String, count: Int)] {
        var grouped: [String: Int] = [:]
        for marker in snapshot.countMarkers {
            grouped[marker.category, default: 0] += 1
        }
        return grouped
            .map { ($0.key, $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.category.localizedStandardCompare($1.category) == .orderedAscending
                }
                return $0.count > $1.count
            }
    }

    var overlayStrokeLayerDefaults: [String] {
        [
            String(localized: "现场批注"),
            String(localized: "问题红线"),
            String(localized: "复核标记"),
            String(localized: "整改记录")
        ]
    }

    var overlayStrokeLayerOptions: [String] {
        var result: [String] = []
        func append(_ value: String?) {
            let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !result.contains(text) else { return }
            result.append(text)
        }
        overlayStrokeLayerDefaults.forEach(append)
        snapshot.strokes.forEach { append(strokeLayerName($0)) }
        append(selectedStrokeLayer)
        return result
    }

    var overlayColorOptions: [CADOverlayColorOption] {
        [
            .init(name: String(localized: "桃红"), hex: "E24A7A"),
            .init(name: String(localized: "柳绿"), hex: "67A866"),
            .init(name: String(localized: "蓝色"), hex: "2F80ED"),
            .init(name: String(localized: "橙色"), hex: "F2994A"),
            .init(name: String(localized: "紫色"), hex: "8E6AD8"),
            .init(name: String(localized: "黑色"), hex: "333333")
        ]
    }

    var selectedCategoryCount: Int {
        snapshot.countMarkers.reduce(0) { result, marker in
            result + (marker.category == selectedCountCategory ? 1 : 0)
        }
    }

    var snapModeSummaryText: String {
        let orderedModes = CADSnapMode.allCases.filter { enabledSnapModes.contains($0) }
        guard !orderedModes.isEmpty else { return String(localized: "已关闭吸附") }
        return orderedModes.map(\.title).joined(separator: " · ")
    }

    var highlightedLengthMeasurementID: UUID? {
        guard case let .length(id)? = quantityHighlightTarget else { return nil }
        return id
    }

    var highlightedAreaMeasurementID: UUID? {
        guard case let .area(id)? = quantityHighlightTarget else { return nil }
        return id
    }

    var highlightedCountCategory: String? {
        guard case let .countCategory(category)? = quantityHighlightTarget else { return nil }
        return category
    }

    var highlightedCountMarkerIDs: Set<UUID> {
        guard case let .countMarkers(ids)? = quantityHighlightTarget else { return [] }
        return Set(ids)
    }

    var quantityHighlightCanvasRect: CGRect? {
        guard let quantityHighlightTarget,
              let storedBounds = bounds(forStoredPoints: storedPoints(for: quantityHighlightTarget)) else {
            return nil
        }
        let minPoint = canvasPoint(fromStored: CGPoint(x: storedBounds.minX, y: storedBounds.minY))
        let maxPoint = canvasPoint(fromStored: CGPoint(x: storedBounds.maxX, y: storedBounds.maxY))
        let rect = CGRect(
            x: min(minPoint.x, maxPoint.x),
            y: min(minPoint.y, maxPoint.y),
            width: max(abs(maxPoint.x - minPoint.x), 34),
            height: max(abs(maxPoint.y - minPoint.y), 34)
        )
        return rect.insetBy(dx: -10, dy: -10)
    }

    var visibleStrokes: [CADStroke] {
        snapshot.strokes.filter { stroke in
            isOverlayGroupVisible(stroke.kind == .redline ? .redline : .annotation) &&
            isStrokeLayerVisible(strokeLayerName(stroke))
        }
    }

    var selectedStrokeIndex: Int? {
        guard let selectedStrokeID else { return nil }
        return snapshot.strokes.firstIndex { $0.id == selectedStrokeID }
    }

    var selectedStroke: CADStroke? {
        guard let selectedStrokeIndex else { return nil }
        return snapshot.strokes[selectedStrokeIndex]
    }

    var projectDrawingTabs: [ProjectDrawing] {
        store.projectDrawings
            .filter { drawing in
                drawing.projectId == activeRequest.projectId &&
                ProjectDrawing.allowedFileExtensions.contains(drawing.fileType.lowercased())
            }
            .sorted { lhs, rhs in
                if lhs.isCurrentVersion != rhs.isCurrentVersion {
                    return lhs.isCurrentVersion && !rhs.isCurrentVersion
                }
                let leftDate = Formatters.parseDateOrDateTime(lhs.importedAt) ?? .distantPast
                let rightDate = Formatters.parseDateOrDateTime(rhs.importedAt) ?? .distantPast
                if leftDate != rightDate {
                    return leftDate > rightDate
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    var recentDrawingTabsStorageKey: String {
        "cad.preview.recent.tabs.\(activeRequest.projectId.uuidString)"
    }

    var recentDrawingTabs: [ProjectDrawing] {
        let drawingByID = Dictionary(uniqueKeysWithValues: projectDrawingTabs.map { ($0.id, $0) })
        var ordered: [ProjectDrawing] = []
        for id in recentDrawingTabIDs {
            guard let drawing = drawingByID[id] else { continue }
            if ordered.contains(where: { $0.id == drawing.id }) {
                continue
            }
            ordered.append(drawing)
        }
        if let active = drawingByID[activeRequest.drawingID],
           !ordered.contains(where: { $0.id == active.id }) {
            ordered.insert(active, at: 0)
        }
        if ordered.isEmpty {
            ordered = Array(projectDrawingTabs.prefix(5))
        }
        return Array(ordered.prefix(5))
    }

    var drawingTreeGroups: [CADDrawingTreeGroup] {
        let grouped = Dictionary(grouping: projectDrawingTabs) { drawing in
            ProjectDetailDrawingHelper.zipFolderPath(for: drawing) ?? String(localized: "单张图纸")
        }
        return grouped
            .map { key, drawings in
                CADDrawingTreeGroup(
                    id: key,
                    title: key,
                    drawings: drawings.sorted(by: preferredDrawingTabSort)
                )
            }
            .sorted {
                if $0.title == String(localized: "单张图纸") { return false }
                if $1.title == String(localized: "单张图纸") { return true }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    var filteredDrawingTreeGroups: [CADDrawingTreeGroup] {
        let query = drawingTreeSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return drawingTreeGroups }
        let foldedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return drawingTreeGroups.compactMap { group in
            let matchedDrawings = group.drawings.filter { drawing in
                drawingTreeSearchFields(for: drawing, groupTitle: group.title).contains { value in
                    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(foldedQuery)
                }
            }
            guard !matchedDrawings.isEmpty else { return nil }
            return CADDrawingTreeGroup(id: group.id, title: group.title, drawings: matchedDrawings)
        }
    }

    var activeDrawingGroup: CADDrawingTreeGroup? {
        drawingTreeGroups.first { group in
            group.drawings.contains { $0.id == activeRequest.drawingID }
        }
    }

    var activeRecentDrawingIndex: Int? {
        recentDrawingTabs.firstIndex { $0.id == activeRequest.drawingID }
    }

    var activeProjectDrawingIndex: Int? {
        projectDrawingTabs.firstIndex { $0.id == activeRequest.drawingID }
    }

    var drawingPositionText: String {
        if let index = activeRecentDrawingIndex {
            return "\(String(localized: "最近图纸")) · \(index + 1)/\(recentDrawingTabs.count)"
        }
        if let activeDrawingGroup,
           let index = activeDrawingGroup.drawings.firstIndex(where: { $0.id == activeRequest.drawingID }) {
            return "\(activeDrawingGroup.title) · \(index + 1)/\(activeDrawingGroup.drawings.count)"
        }
        if let index = activeProjectDrawingIndex {
            return "\(String(localized: "全部图纸")) · \(index + 1)/\(projectDrawingTabs.count)"
        }
        return String(localized: "图纸包")
    }

    var hasMultipleProjectDrawings: Bool {
        projectDrawingTabs.count > 1
    }

    var rendererCallbacks: CADRendererCallbacks {
        let expectedFilePath = activeRequest.fileURL.path
        return CADRendererCallbacks(
            onCanvasTransformChange: { transform in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererCanvasTransform(transform)
                }
            },
            onSnapPointsChange: { points in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererSnapPoints(points)
                }
            },
            onTextAutoDetectionChange: { result in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererTextAutoDetection(result)
                }
            }
        )
    }

    var body: some View {
        CADCanvasHost(
            isImmersivePreview: isImmersivePreview,
            allowsOverlayEditing: allowsOverlayEditing,
            overlayHitTestingEnabled: overlayHitTestingEnabled,
            immersiveTopSafePadding: immersiveTopSafePadding,
            immersiveBottomSafePadding: immersiveBottomSafePadding
        ) {
            if shouldShowLibreDWGUnavailable {
                CADLibreDWGUnavailableView(
                    fileURL: activeRequest.fileURL,
                    displayName: activeRequest.displayName
                )
            } else if shouldShowLibreDWGUnbound {
                CADLibreDWGUnboundView(
                    fileURL: activeRequest.fileURL,
                    displayName: activeRequest.displayName
                )
            } else if shouldUseLibreDWGRenderer,
                      let renderer = CADRendererProvider.libreDWGRenderer(
                        for: activeRequest.fileURL,
                        preferredTextCodePage: selectedTextEncoding.codePageOverride,
                        preferredTextBigFont: selectedTextBigFont.bridgeCode,
                        callbacks: rendererCallbacks
                      ) {
                renderer.id(cadPreviewReloadToken)
            } else if isCADFile {
                CADLibreDWGUnboundView(
                    fileURL: activeRequest.fileURL,
                    displayName: activeRequest.displayName
                )
            } else {
                AppQuickLookPreviewController(url: activeRequest.fileURL)
            }
        } overlayLayer: { size in
            overlayLayer(size: size)
        } immersiveOverlayControls: {
            immersiveOverlayControls
        } immersiveTopControls: {
            immersiveTopControls
        }
        .ignoresSafeArea(.container, edges: isImmersivePreview ? .all : [])
        .statusBarHidden(isImmersivePreview)
        .safeAreaInset(edge: .top) {
            if !isImmersivePreview {
                standardTopBar
            }
        }
        .safeAreaInset(edge: .bottom) {
            if allowsOverlayEditing && !isImmersivePreview {
                bottomControlBar
            }
        }
            .onAppear {
                snapshot = restoredSnapshot(for: activeRequest)
                snapshot.normalizeMeasurementScale()
                applyOverlayDisplayPreferences(from: snapshot)
                if !countCategoryOptions.contains(selectedCountCategory) {
                    selectedCountCategory = countCategoryOptions.first ?? String(localized: "点位")
                }
                loadRecentDrawingTabs()
                touchRecentDrawingTab(activeRequest.drawingID)
                lastPersistedSnapshotData = encodedSnapshotData(snapshot)
                selectedTextEncoding = activeRequest.textEncoding
                selectedTextBigFont = activeRequest.textBigFont
                textSchemeSnapshot = activeRequest.textSchemeSnapshot
            }
            .task(id: snapshot) {
                await debouncePersistSnapshot(snapshot)
            }
            .onChange(of: selectedStrokeLayer) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: selectedAnnotationColorHex) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: selectedRedlineColorHex) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: hiddenOverlayGroups) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: hiddenStrokeLayers) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: enabledSnapModes) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: projectDrawingTabs.map(\.id)) { _, _ in
                pruneRecentDrawingTabs()
            }
            .onDisappear {
                persistSnapshotIfNeeded(snapshot)
            }
            .confirmationDialog(String(localized: "清空批注和测量？"), isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button(String(localized: "清空全部"), role: .destructive) {
                    var cleared = CADOverlaySnapshot()
                    cleared.metersPerDrawingUnit = snapshot.metersPerDrawingUnit
                    copyOverlayDisplayPreferences(from: snapshot, to: &cleared)
                    snapshot = cleared
                    quantityHighlightTarget = nil
                    clearInProgress()
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "将删除本图纸的批注、红线、测量和算量数据。"))
            }
            .confirmationDialog(String(localized: "导出批注测量"), isPresented: $showAnnotationExportFormatDialog, titleVisibility: .visible) {
                Button(CADAnnotationExportFormat.csv.title) {
                    exportAnnotationSummary(format: .csv)
                }
                Button(CADAnnotationExportFormat.pdf.title) {
                    exportAnnotationSummary(format: .pdf)
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "可导出为 CSV 表格或 PDF 报表。"))
            }
            .alert(String(localized: "CAD 提示"), isPresented: $showAlert) {
                Button(String(localized: "知道了"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showTextEncodingDialog) {
                CADTextOptionsPanel {
                    textOptionsSheet
                }
            }
            .sheet(isPresented: $showScaleSheet) {
                CADMeasurementPanel {
                    scaleEditor
                }
            }
            .sheet(isPresented: $showOverlayLayerSheet) {
                CADOverlayEditor {
                    overlayLayerEditor
                }
            }
            .sheet(isPresented: $showDrawingTreeSheet) {
                CADDrawingBrowser {
                    drawingTreeSheet
                }
            }
            .sheet(isPresented: $showQuantitySheet) {
                CADMeasurementPanel {
                    quantitySheet
                }
            }
            .sheet(isPresented: $showNoteSheet) {
                CADAnnotationPanel {
                    noteEditorSheet
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityShareSheet(activityItems: [activeRequest.fileURL])
            }
            .fileExporter(
                isPresented: diagnosticExporterPresented,
                document: ExportDocument(data: diagnosticExportPayload?.data ?? Data()),
                contentType: diagnosticExportPayload?.contentType ?? .plainText,
                defaultFilename: diagnosticExportPayload?.defaultFilename ?? "CAD诊断日志.txt"
            ) { result in
                switch result {
                case .success:
                    alertMessage = String(localized: "CAD 诊断日志已导出。")
                    showAlert = true
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled {
                        alertMessage = "\(String(localized: "CAD 诊断日志导出失败"))：\(error.localizedDescription)"
                        showAlert = true
                    }
                }
                diagnosticExportPayload = nil
            }
            .fileExporter(
                isPresented: annotationExporterPresented,
                document: ExportDocument(data: annotationExportPayload?.data ?? Data()),
                contentType: annotationExportPayload?.contentType ?? .commaSeparatedText,
                defaultFilename: annotationExportPayload?.defaultFilename ?? "CAD批注测量.csv"
            ) { result in
                switch result {
                case .success:
                    alertMessage = String(localized: "CAD 批注测量已导出。")
                    showAlert = true
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled {
                        alertMessage = "\(String(localized: "CAD 批注测量导出失败"))：\(error.localizedDescription)"
                        showAlert = true
                    }
                }
                annotationExportPayload = nil
            }
    }

    var standardTopBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    Label(String(localized: "完成"), systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.appPrimaryAction)
                .background(.regularMaterial, in: Circle())
                .accessibilityLabel(String(localized: "完成"))

                VStack(alignment: .leading, spacing: 3) {
                    Text(activeRequest.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    HStack(spacing: 6) {
                        Image(systemName: engineStatusIcon)
                            .font(.caption2)
                            .foregroundStyle(engineStatusTint)
                        Text(engineStatusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if allowsOverlayEditing {
                            Text(unitHint)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isImmersivePreview = true
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").visibleIconStyle()
                }
                .accessibilityLabel(String(localized: "全屏图纸"))

                ShareLink(item: activeRequest.fileURL) {
                    Image(systemName: "square.and.arrow.up").visibleIconStyle()
                }
                .accessibilityLabel(String(localized: "分享图纸"))

                Menu {
                    if hasMultipleProjectDrawings {
                        Button {
                            showDrawingTreeSheet = true
                        } label: {
                            Label(String(localized: "图纸包目录树"), systemImage: "list.bullet.indent")
                        }
                    }
                    if allowsOverlayEditing {
                        Button {
                            showOverlayLayerSheet = true
                        } label: {
                            Label(String(localized: "覆盖层设置"), systemImage: "square.3.layers.3d")
                        }
                        Button {
                            openScaleCalibrationSheet()
                        } label: {
                            Label(String(localized: "测量标定"), systemImage: "slider.horizontal.3")
                        }
                        if shouldUseLibreDWGRenderer {
                            Button {
                                showTextEncodingDialog = true
                            } label: {
                                Label(String(localized: "文字编码与字体"), systemImage: "character.textbox")
                            }
                        }
                        Button {
                            showQuantitySheet = true
                        } label: {
                            Label(String(localized: "半自动算量"), systemImage: "sum")
                        }
                        Button {
                            showAnnotationExportFormatDialog = true
                        } label: {
                            Label(String(localized: "导出批注测量"), systemImage: "doc.text")
                        }
                        .disabled(!snapshot.hasOverlayContent)
                    }
                    if isCADFile {
                        Button {
                            Task {
                                await exportDiagnosticLog()
                            }
                        } label: {
                            Label(String(localized: "导出 CAD 诊断日志"), systemImage: isExportingDiagnosticLog ? "hourglass" : "doc.text.magnifyingglass")
                        }
                        .disabled(isExportingDiagnosticLog)
                    }
                    if allowsOverlayEditing {
                        Divider()
                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            Label(String(localized: "清空覆盖层"), systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").visibleIconStyle()
                }
                .accessibilityLabel(String(localized: "更多图纸操作"))
            }

            if let engineStatusHint {
                Text(engineStatusHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if shouldUseLibreDWGRenderer {
                HStack(spacing: 6) {
                    Image(systemName: "character.textbox")
                        .foregroundStyle(.secondary)
                    Text("\(String(localized: "当前文字方案"))：\(currentTextSchemeTitle)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let autoDetectScore = textSchemeSnapshot.autoDetectScore {
                        Text("\(String(localized: "识别评分"))：\(autoDetectScore)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }

            if hasMultipleProjectDrawings {
                drawingTabStrip
            }

            if allowsOverlayEditing {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CADOverlayTool.allCases, id: \.self) { candidate in
                            topToolButton(for: candidate)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    var hasNativeDrawingCoordinateSpace: Bool {
        snapshot.coordinateSpace == .drawing && nativeCanvasTransform != nil
    }

    var canCaptureDrawingOverlay: Bool {
        allowsOverlayEditing && hasNativeDrawingCoordinateSpace
    }

    var overlayHitTestingEnabled: Bool {
        guard allowsOverlayEditing else { return false }
        if tool.requiresDrawingCoordinateCapture {
            return canCaptureDrawingOverlay
        }
        return isSelectingStroke && canCaptureDrawingOverlay
    }

    func isOverlayToolEnabled(_ candidate: CADOverlayTool) -> Bool {
        !candidate.requiresDrawingCoordinateCapture || canCaptureDrawingOverlay
    }

    func ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: Bool = true) -> Bool {
        guard hasNativeDrawingCoordinateSpace else {
            if showAlertIfMissing {
                alertMessage = String(localized: "当前图纸坐标尚未就绪，已阻止写入批注、红线、测量和数数数据。请等待图纸加载完成后重试。")
                showAlert = true
            }
            return false
        }
        return true
    }

    func canvasPoint(fromStored point: CGPoint) -> CGPoint {
        guard snapshot.coordinateSpace == .drawing,
              let nativeCanvasTransform else { return point }
        return nativeCanvasTransform.canvasPoint(fromDrawing: point)
    }

    func storedDrawingPoint(fromCanvas point: CGPoint) -> CGPoint? {
        guard snapshot.coordinateSpace == .drawing,
              let nativeCanvasTransform else { return nil }
        return nativeCanvasTransform.drawingPoint(fromCanvas: point)
    }

    func canvasPoints(fromStored points: [CGPoint]) -> [CGPoint] {
        points.map(canvasPoint(fromStored:))
    }

    @MainActor
    func handleRendererCanvasTransform(_ rendererTransform: CADRendererCanvasTransform) {
        let transform = CADNativeCanvasTransform(rendererTransform)
        nativeCanvasTransform = transform
        if snapshot.coordinateSpace == .canvas {
            snapshot.convertCanvasPointsToDrawingCoordinates(using: transform)
        }
    }

    @MainActor
    func handleRendererSnapPoints(_ payloads: [CADRendererSnapPointPayload]) {
        nativeSnapSourcePoints = payloads.compactMap(CADNativeSnapSourcePoint.init)
        if nativeSnapSourcePoints.isEmpty {
            nativeSnapPoints.removeAll()
            nativeEndpointSnapPoints.removeAll()
            nativeMidpointSnapPoints.removeAll()
            nativeCenterSnapPoints.removeAll()
            return
        }

        nativeSnapPoints = nativeSnapSourcePoints.map(\.point)
        nativeEndpointSnapPoints = nativeSnapSourcePoints
            .filter { $0.snapKind == .endpoint }
            .map(\.point)
        nativeMidpointSnapPoints = nativeSnapSourcePoints
            .filter { $0.snapKind == .midpoint }
            .map(\.point)
        nativeCenterSnapPoints = nativeSnapSourcePoints
            .filter { $0.snapKind == .center }
            .map(\.point)
    }

    @MainActor
    func handleRendererTextAutoDetection(_ result: CADTextAutoDetectionResult) {
        let snapshot = CADDrawingTextSchemeSnapshot(
            codePage: result.codePage,
            bigFont: result.bigFont,
            styleName: result.styleName,
            fontFile: result.fontFile,
            bigFontFile: result.bigFontFile,
            autoDetectScore: result.autoDetectScore,
            styleSummary: result.styleSummary,
            rawTextBytesHexSample: result.rawTextBytesHexSample,
            detectionSummary: result.detectionSummary ?? result.summary
        )
        applyPreviewAutoDetectedTextOptions(snapshot: snapshot)
    }

    @MainActor
    func observeNativeCanvasTransform() async {
        for await notification in NotificationCenter.default.notifications(named: .libreDWGCanvasTransformDidChange) {
            guard !Task.isCancelled,
                  let userInfo = notification.userInfo,
                  let filePath = userInfo["filePath"] as? String,
                  filePath == activeRequest.fileURL.path,
                  let boundsValue = userInfo["bounds"] as? NSValue,
                  let sizeValue = userInfo["size"] as? NSValue,
                  let zoomScaleNumber = userInfo["zoomScale"] as? NSNumber,
                  let panOffsetValue = userInfo["panOffset"] as? NSValue else { continue }

            let transform = CADNativeCanvasTransform(
                bounds: boundsValue.cgRectValue,
                size: sizeValue.cgSizeValue,
                zoomScale: CGFloat(zoomScaleNumber.doubleValue),
                panOffset: panOffsetValue.cgSizeValue
            )
            nativeCanvasTransform = transform
            if snapshot.coordinateSpace == .canvas {
                snapshot.convertCanvasPointsToDrawingCoordinates(using: transform)
            }
        }
    }

    @MainActor
    func observeNativeSnapPoints() async {
        for await notification in NotificationCenter.default.notifications(named: .libreDWGSnapPointsDidChange) {
            guard !Task.isCancelled,
                  let userInfo = notification.userInfo,
                  let filePath = userInfo["filePath"] as? String,
                  filePath == activeRequest.fileURL.path else { continue }

            if let payloads = userInfo["pointMetadata"] as? [[String: Any]] {
                nativeSnapSourcePoints = payloads.compactMap(CADNativeSnapSourcePoint.init)
            } else {
                nativeSnapSourcePoints.removeAll()
            }

            if let endpointValues = userInfo["endpointPoints"] as? [NSValue] {
                nativeEndpointSnapPoints = endpointValues.map(\.cgPointValue)
            } else {
                nativeEndpointSnapPoints.removeAll()
            }
            if let midpointValues = userInfo["midpointPoints"] as? [NSValue] {
                nativeMidpointSnapPoints = midpointValues.map(\.cgPointValue)
            } else {
                nativeMidpointSnapPoints.removeAll()
            }
            if let centerValues = userInfo["centerPoints"] as? [NSValue] {
                nativeCenterSnapPoints = centerValues.map(\.cgPointValue)
            } else {
                nativeCenterSnapPoints.removeAll()
            }

            if let pointValues = userInfo["points"] as? [NSValue] {
                nativeSnapPoints = pointValues.map(\.cgPointValue)
            } else {
                nativeSnapPoints.removeAll()
            }

            if !nativeSnapSourcePoints.isEmpty {
                nativeSnapPoints = nativeSnapSourcePoints.map(\.point)
                nativeEndpointSnapPoints = nativeSnapSourcePoints
                    .filter { $0.snapKind == .endpoint }
                    .map(\.point)
                nativeMidpointSnapPoints = nativeSnapSourcePoints
                    .filter { $0.snapKind == .midpoint }
                    .map(\.point)
                nativeCenterSnapPoints = nativeSnapSourcePoints
                    .filter { $0.snapKind == .center }
                    .map(\.point)
            }
        }
    }

    @MainActor
    func observeNativeTextAutoDetection() async {
        for await notification in NotificationCenter.default.notifications(named: .libreDWGTextAutoDetectionDidChange) {
            guard !Task.isCancelled,
                  let userInfo = notification.userInfo,
                  let filePath = userInfo["filePath"] as? String,
                  filePath == activeRequest.fileURL.path else { continue }

            let codePage = (userInfo["codePage"] as? NSNumber).map { Int32(truncating: $0) }
            let bigFont = (userInfo["bigFont"] as? NSNumber).map { Int32(truncating: $0) }
            let score = (userInfo["autoDetectScore"] as? NSNumber).map { Int(truncating: $0) }
            let snapshot = CADDrawingTextSchemeSnapshot(
                codePage: codePage,
                bigFont: bigFont,
                styleName: userInfo["styleName"] as? String,
                fontFile: userInfo["fontFile"] as? String,
                bigFontFile: userInfo["bigFontFile"] as? String,
                autoDetectScore: score
            )
            applyPreviewAutoDetectedTextOptions(snapshot: snapshot)
        }
    }

    func previewRequest(for drawing: ProjectDrawing, fileURL: URL) -> ProjectCADPreviewRequest {
        ProjectCADPreviewRequest(
            projectId: drawing.projectId,
            drawingID: drawing.id,
            fileURL: fileURL,
            displayName: drawing.name.isEmpty ? drawing.fileName : drawing.name,
            fileType: drawing.fileType,
            textEncoding: drawing.textEncoding,
            textBigFont: drawing.textBigFont,
            textSchemeSnapshot: drawing.textSchemeSnapshot,
            overlaySnapshotData: drawing.cadOverlaySnapshotData,
            onOverlaySnapshotChange: { drawingID, snapshotData in
                guard let index = store.projectDrawings.firstIndex(where: { $0.id == drawingID }) else { return }
                store.projectDrawings[index].cadOverlaySnapshotData = snapshotData
                store.scheduleSave()
            },
            onTextEncodingChange: { drawingID, encoding in
                guard let index = store.projectDrawings.firstIndex(where: { $0.id == drawingID }) else { return }
                store.projectDrawings[index].textEncoding = encoding
                store.scheduleSave()
            },
            onTextBigFontChange: { drawingID, profile in
                guard let index = store.projectDrawings.firstIndex(where: { $0.id == drawingID }) else { return }
                store.projectDrawings[index].textBigFont = profile
                store.scheduleSave()
            },
            onTextSchemeSnapshotChange: { drawingID, snapshot in
                guard let index = store.projectDrawings.firstIndex(where: { $0.id == drawingID }) else { return }
                store.projectDrawings[index].textSchemeSnapshot = snapshot
                store.scheduleSave()
            }
        )
    }

    func restoredSnapshot(for request: ProjectCADPreviewRequest) -> CADOverlaySnapshot {
        if var decoded = decodedSnapshotData(request.overlaySnapshotData, displayName: request.displayName) {
            if decoded.coordinateSpace == .canvas, !decoded.hasOverlayContent {
                decoded.coordinateSpace = .drawing
            }
            return decoded
        }
        if var legacy = LegacyCADOverlayStorage.load(for: request.fileURL) {
            if legacy.coordinateSpace == .canvas, !legacy.hasOverlayContent {
                legacy.coordinateSpace = .drawing
            }
            return legacy
        }
        return CADOverlaySnapshot()
    }

    func decodedSnapshotData(_ raw: String, displayName: String) -> CADOverlaySnapshot? {
        guard !raw.isEmpty,
              let data = Data(base64Encoded: raw) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(CADOverlaySnapshot.self, from: data)
        } catch {
            StorageIssueLog.record("CAD 快照解析失败：\(displayName)，\(error.localizedDescription)")
            return nil
        }
    }

    func applyOverlayDisplayPreferences(from snapshot: CADOverlaySnapshot) {
        let groups = snapshot.hiddenOverlayGroupIDs.compactMap(CADOverlayVisibilityGroup.init(rawValue:))
        hiddenOverlayGroups = Set(groups)
        hiddenStrokeLayers = Set(snapshot.hiddenStrokeLayerNames)

        let layer = (snapshot.selectedStrokeLayerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        selectedStrokeLayer = layer.isEmpty ? String(localized: "现场批注") : layer

        let annotationHex = (snapshot.selectedAnnotationColorHex ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        selectedAnnotationColorHex = annotationHex.isEmpty ? "2F80ED" : annotationHex

        let redlineHex = (snapshot.selectedRedlineColorHex ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        selectedRedlineColorHex = redlineHex.isEmpty ? "D92D20" : redlineHex

        let snapModes = snapshot.enabledSnapModeIDs.compactMap(CADSnapMode.init(rawValue:))
        if snapModes.isEmpty {
            enabledSnapModes = Set(CADSnapMode.allCases)
        } else {
            enabledSnapModes = Set(snapModes)
        }
    }

    func updateOverlayDisplayPreferences() {
        snapshot.hiddenOverlayGroupIDs = hiddenOverlayGroups.map(\.rawValue).sorted()
        snapshot.hiddenStrokeLayerNames = hiddenStrokeLayers.sorted()
        snapshot.selectedStrokeLayerName = selectedStrokeLayer
        snapshot.selectedAnnotationColorHex = selectedAnnotationColorHex
        snapshot.selectedRedlineColorHex = selectedRedlineColorHex
        snapshot.enabledSnapModeIDs = CADSnapMode.allCases
            .filter { enabledSnapModes.contains($0) }
            .map(\.rawValue)
    }

    func copyOverlayDisplayPreferences(
        from source: CADOverlaySnapshot,
        to destination: inout CADOverlaySnapshot
    ) {
        destination.hiddenOverlayGroupIDs = source.hiddenOverlayGroupIDs
        destination.hiddenStrokeLayerNames = source.hiddenStrokeLayerNames
        destination.selectedStrokeLayerName = source.selectedStrokeLayerName
        destination.selectedAnnotationColorHex = source.selectedAnnotationColorHex
        destination.selectedRedlineColorHex = source.selectedRedlineColorHex
        destination.enabledSnapModeIDs = source.enabledSnapModeIDs
    }

    func encodedSnapshotData(_ snapshot: CADOverlaySnapshot) -> String {
        do {
            let data = try JSONEncoder().encode(snapshot)
            return data.base64EncodedString()
        } catch {
            StorageIssueLog.record("CAD 快照编码失败：\(activeRequest.displayName)，\(error.localizedDescription)")
            return ""
        }
    }

    func clearInProgress() {
        activeStrokePoints.removeAll()
        pendingLengthPoints.removeAll()
        pendingAreaPoints.removeAll()
        activeDragLengthPoints.removeAll()
    }

    func selectOverlayTool(_ nextTool: CADOverlayTool) {
        guard isOverlayToolEnabled(nextTool) else {
            clearInProgress()
            tool = .browse
            _ = ensureDrawingCoordinateCaptureAvailable()
            return
        }
        if tool != nextTool {
            clearInProgress()
            AppHaptics.impact(.light, intensity: 0.55)
        }
        tool = nextTool
        selectedStrokeID = nil
        isSelectingStroke = false
        switch nextTool {
        case .annotation:
            hiddenOverlayGroups.remove(.annotation)
            if selectedStrokeLayer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedStrokeLayer = String(localized: "现场批注")
            }
        case .redline:
            hiddenOverlayGroups.remove(.redline)
            if selectedStrokeLayer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedStrokeLayer = String(localized: "问题红线")
            }
        case .length, .continuousLength, .area:
            hiddenOverlayGroups.remove(.measurement)
        case .note:
            hiddenOverlayGroups.remove(.notes)
        case .count:
            hiddenOverlayGroups.remove(.counts)
        case .browse:
            break
        }
    }

    func openScaleCalibrationSheet() {
        scaleDraft = measurementScaleText
        let measurements = calibrationCandidateMeasurements
        if let first = measurements.first {
            if selectedCalibrationMeasurementID == nil || !measurements.contains(where: { $0.id == selectedCalibrationMeasurementID }) {
                selectedCalibrationMeasurementID = first.id
            }
            if calibrationActualMetersDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let suggested = lengthInMeters(for: first.points.map(\.cgPoint))
                calibrationActualMetersDraft = Formatters.number(suggested, minFraction: 2, maxFraction: 3)
            }
        } else {
            selectedCalibrationMeasurementID = nil
            calibrationActualMetersDraft = ""
        }
        showScaleSheet = true
    }

    func applyTwoPointCalibration() {
        guard let computedScale = calibrationComputedScale else { return }
        snapshot.metersPerDrawingUnit = computedScale
        scaleDraft = Formatters.number(computedScale, minFraction: 0, maxFraction: 8)
        showScaleSheet = false
        alertMessage = String(localized: "已更新标定：1 图纸单位 = \(Formatters.number(computedScale, minFraction: 0, maxFraction: 8)) m")
        showAlert = true
    }

    @MainActor
    func debouncePersistSnapshot(_ value: CADOverlaySnapshot) async {
        guard await DebouncedTask.wait(for: .milliseconds(350)) else { return }
        persistSnapshotIfNeeded(value)
    }

    func persistSnapshotIfNeeded(_ value: CADOverlaySnapshot) {
        let encoded = encodedSnapshotData(value)
        guard encoded != lastPersistedSnapshotData else { return }
        lastPersistedSnapshotData = encoded
        activeRequest.onOverlaySnapshotChange(activeRequest.drawingID, encoded)
    }

    @MainActor
    func exportDiagnosticLog() async {
        guard !isExportingDiagnosticLog else { return }
        isExportingDiagnosticLog = true
        defer { isExportingDiagnosticLog = false }

        do {
            let report = try await CADRendererProvider.makeLibreDWGDiagnosticReport(
                for: activeRequest.fileURL,
                preferredTextCodePage: selectedTextEncoding.codePageOverride,
                preferredTextBigFont: selectedTextBigFont.bridgeCode
            ) ?? fallbackDiagnosticLog()
            diagnosticExportPayload = ExportPayload(
                data: Data(report.utf8),
                contentType: .plainText,
                defaultFilename: diagnosticLogFileName()
            )
        } catch {
            let report = fallbackDiagnosticLog(extraMessage: "\(String(localized: "LibreDWG 诊断生成失败"))：\(error.localizedDescription)")
            StorageIssueLog.record("CAD 诊断日志生成失败：\(activeRequest.displayName)，\(error.localizedDescription)")
            diagnosticExportPayload = ExportPayload(
                data: Data(report.utf8),
                contentType: .plainText,
                defaultFilename: diagnosticLogFileName()
            )
        }
    }

    func diagnosticLogFileName() -> String {
        let baseName = activeRequest.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let name = baseName.isEmpty ? activeRequest.fileURL.deletingPathExtension().lastPathComponent : baseName
        return "\(name)_CAD诊断日志.txt"
    }

    func fallbackDiagnosticLog(extraMessage: String? = nil) -> String {
        var lines: [String] = []
        lines.append("CAD 图纸诊断日志")
        lines.append("生成时间：\(Formatters.dateTime.string(from: Date()))")
        lines.append("")
        lines.append("## 文件")
        lines.append("文件名：\(activeRequest.fileURL.lastPathComponent)")
        lines.append("路径：\(activeRequest.fileURL.path)")
        lines.append("类型：\(activeRequest.fileType.uppercased())")
        lines.append("大小：\(fallbackFileSizeText())")
        lines.append("文件头 Hex：\(fallbackHeaderHex())")
        lines.append("")
        lines.append("## 预览环境")
        lines.append("首选引擎：\(preferredEngine.title)")
        lines.append("实际引擎：\(resolvedEngine.title)")
        lines.append("LibreDWG 可用：\(CADPreviewCapability.isLibreDWGRendererAvailable() ? "是" : "否")")
        lines.append("LibreDWG 已绑定：\(CADRendererProvider.isLibreDWGRendererBound ? "是" : "否")")
        lines.append("当前文字编码：\(selectedTextEncoding.displayName)")
        lines.append("当前 SHX/大字体：\(selectedTextBigFont.displayName)")
        if let codePage = textSchemeSnapshot.codePage {
            lines.append("当前命中编码：\(codePageDisplayName(codePage))")
        }
        if let styleName = textSchemeSnapshot.styleName {
            lines.append("当前样式：\(styleName)")
        }
        if let fontFile = textSchemeSnapshot.fontFile {
            lines.append("当前字体：\(fontFile)")
        }
        if let bigFontFile = textSchemeSnapshot.bigFontFile {
            lines.append("当前大字体文件：\(bigFontFile)")
        }
        if let score = textSchemeSnapshot.autoDetectScore {
            lines.append("自动识别评分：\(score)")
        }
        if let styleSummary = textSchemeSnapshot.styleSummary, !styleSummary.isEmpty {
            lines.append("STYLE 表：\(styleSummary)")
        }
        if let rawSample = textSchemeSnapshot.rawTextBytesHexSample, !rawSample.isEmpty {
            lines.append("raw text bytes：\(rawSample)")
        }
        if let summary = textSchemeSnapshot.detectionSummary, !summary.isEmpty {
            lines.append("识别摘要：\(summary)")
        }
        if let engineStatusHint {
            lines.append("提示：\(engineStatusHint)")
        }
        if let extraMessage {
            lines.append("")
            lines.append("## 诊断生成错误")
            lines.append(extraMessage)
        }
        return lines.joined(separator: "\n")
    }

    func fallbackFileSizeText() -> String {
        do {
            let values = try activeRequest.fileURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            let bytes = values.fileSize ?? values.totalFileAllocatedSize ?? 0
            return QuickNoteAttachmentStorage.formattedFileSize(bytes)
        } catch {
            return "-"
        }
    }

    func fallbackHeaderHex() -> String {
        guard let handle = try? FileHandle(forReadingFrom: activeRequest.fileURL) else {
            return "-"
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 32) else {
            return "-"
        }
        return data.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    func strokeColor(_ stroke: CADStroke) -> Color {
        colorFromHex(stroke.colorHex, fallback: strokeColor(stroke.kind))
    }

    func strokeColor(_ kind: CADStroke.StrokeKind) -> Color {
        switch kind {
        case .annotation:
            return .appPrimaryAction
        case .redline:
            return .appRisk
        }
    }

    func selectedStrokeColorHex(for kind: CADStroke.StrokeKind) -> String {
        kind == .redline ? selectedRedlineColorHex : selectedAnnotationColorHex
    }

    func strokeLayerName(_ stroke: CADStroke) -> String {
        let fallback = stroke.kind == .redline ? String(localized: "问题红线") : String(localized: "现场批注")
        let text = (stroke.layerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : text
    }

    func isOverlayGroupVisible(_ group: CADOverlayVisibilityGroup) -> Bool {
        !hiddenOverlayGroups.contains(group)
    }

    func isStrokeLayerVisible(_ layer: String) -> Bool {
        !hiddenStrokeLayers.contains(layer)
    }

    func overlayGroupVisibleBinding(_ group: CADOverlayVisibilityGroup) -> Binding<Bool> {
        Binding(
            get: { isOverlayGroupVisible(group) },
            set: { isVisible in
                if isVisible {
                    hiddenOverlayGroups.remove(group)
                } else {
                    hiddenOverlayGroups.insert(group)
                }
            }
        )
    }

    func strokeLayerVisibleBinding(_ layer: String) -> Binding<Bool> {
        Binding(
            get: { isStrokeLayerVisible(layer) },
            set: { isVisible in
                if isVisible {
                    hiddenStrokeLayers.remove(layer)
                } else {
                    hiddenStrokeLayers.insert(layer)
                }
            }
        )
    }

    func snapModeEnabledBinding(_ mode: CADSnapMode) -> Binding<Bool> {
        Binding(
            get: { enabledSnapModes.contains(mode) },
            set: { isEnabled in
                if isEnabled {
                    enabledSnapModes.insert(mode)
                } else {
                    enabledSnapModes.remove(mode)
                }
                if enabledSnapModes.isEmpty {
                    enabledSnapModes = Set(CADSnapMode.allCases)
                }
            }
        )
    }

    func overlayItemCount(for group: CADOverlayVisibilityGroup) -> Int {
        switch group {
        case .annotation:
            return annotationStrokeCount
        case .redline:
            return redlineStrokeCount
        case .measurement:
            return snapshot.lengthMeasurements.count + snapshot.areaMeasurements.count
        case .notes:
            return snapshot.notes.count
        case .counts:
            return snapshot.countMarkers.count
        }
    }

    func colorFromHex(_ hex: String?, fallback: Color) -> Color {
        guard let hex else { return fallback }
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return fallback
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        return Color(red: red, green: green, blue: blue)
    }

    func overlayStrokeWidth(for tool: CADOverlayTool) -> Double {
        switch tool {
        case .redline:
            return 5
        case .annotation:
            return 4
        default:
            return 3
        }
    }

    func pathView(points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    func measurementPolyline(_ points: [CGPoint]) -> Path {
        pathView(points: points)
    }

    func measurementBadge(text: String, isHighlighted: Bool = false) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                isHighlighted ? Color.appWarning.opacity(0.2) : Color(uiColor: .secondarySystemGroupedBackground),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(isHighlighted ? Color.appWarning : Color.appStrokeSecondary, lineWidth: isHighlighted ? 1.4 : 0.8)
            )
    }

    func countMarkerBadge(number: Int, category: String, isHighlighted: Bool = false) -> some View {
        HStack(spacing: 5) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isHighlighted ? Color.appWarning : Color.appPrimaryAction, in: Capsule())
            Text(category)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isHighlighted ? Color.appWarning : .primary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            isHighlighted ? Color.appWarning.opacity(0.17) : Color(uiColor: .secondarySystemGroupedBackground),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(isHighlighted ? Color.appWarning : Color.appStrokeSecondary, lineWidth: isHighlighted ? 1.4 : 0.8)
        )
    }

    func centerPoint(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { result, point in
            CGPoint(x: result.x + point.x, y: result.y + point.y)
        }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    func lengthInMeters(for points: [CGPoint]) -> Double {
        drawingUnitLength(for: points) * snapshot.metersPerDrawingUnit
    }

    func drawingUnitLength(for points: [CGPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        var sum: Double = 0
        for idx in 1..<points.count {
            let dx = points[idx].x - points[idx - 1].x
            let dy = points[idx].y - points[idx - 1].y
            sum += sqrt(dx * dx + dy * dy)
        }
        return sum
    }

    func areaInSquareMeters(for points: [CGPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        var shoelace: Double = 0
        for idx in points.indices {
            let next = (idx + 1) % points.count
            shoelace += (points[idx].x * points[next].y) - (points[next].x * points[idx].y)
        }
        let drawingUnitArea = abs(shoelace) / 2
        return drawingUnitArea * snapshot.metersPerDrawingUnit * snapshot.metersPerDrawingUnit
    }

    func lengthLabel(for points: [CGPoint]) -> String {
        "\(Formatters.number(lengthInMeters(for: points), minFraction: 2, maxFraction: 3)) m"
    }

    func areaLabel(for points: [CGPoint]) -> String {
        "\(Formatters.number(areaInSquareMeters(for: points), minFraction: 2, maxFraction: 3)) m²"
    }

    enum AreaClosureCheckResult {
        case valid(points: [CGPoint], autoClosed: Bool)
        case selfIntersecting
    }

    func validateAreaClosure(points: [CGPoint]) -> AreaClosureCheckResult? {
        guard points.count >= 3 else { return nil }
        var normalized = points
        let tolerance = areaClosureToleranceInDrawingUnits()

        let first = normalized[0]
        let last = normalized[normalized.count - 1]
        let isAlreadyClosed = hypot(first.x - last.x, first.y - last.y) <= tolerance
        if isAlreadyClosed {
            normalized.removeLast()
        }
        guard normalized.count >= 3 else { return nil }

        if polygonHasSelfIntersection(normalized) {
            return .selfIntersecting
        }
        return .valid(points: normalized, autoClosed: !isAlreadyClosed)
    }

    func areaClosureToleranceInDrawingUnits() -> CGFloat {
        guard let nativeCanvasTransform else { return 0.5 }
        let baseCanvasPoint = CGPoint(x: nativeCanvasTransform.size.width * 0.5, y: nativeCanvasTransform.size.height * 0.5)
        let rightCanvasPoint = CGPoint(x: baseCanvasPoint.x + overlaySnapTolerance, y: baseCanvasPoint.y)
        let p0 = nativeCanvasTransform.drawingPoint(fromCanvas: baseCanvasPoint)
        let p1 = nativeCanvasTransform.drawingPoint(fromCanvas: rightCanvasPoint)
        let tolerance = hypot(p1.x - p0.x, p1.y - p0.y)
        return max(tolerance, 0.0001)
    }

    func polygonHasSelfIntersection(_ points: [CGPoint]) -> Bool {
        guard points.count >= 4 else { return false }
        let count = points.count
        for i in 0..<count {
            let a1 = points[i]
            let a2 = points[(i + 1) % count]
            for j in (i + 1)..<count {
                if abs(i - j) <= 1 { continue }
                if i == 0 && j == count - 1 { continue }
                let b1 = points[j]
                let b2 = points[(j + 1) % count]
                if segmentsIntersect(a1, a2, b1, b2) {
                    return true
                }
            }
        }
        return false
    }

    func segmentsIntersect(_ p1: CGPoint, _ q1: CGPoint, _ p2: CGPoint, _ q2: CGPoint) -> Bool {
        let o1 = orientation(p1, q1, p2)
        let o2 = orientation(p1, q1, q2)
        let o3 = orientation(p2, q2, p1)
        let o4 = orientation(p2, q2, q1)

        if o1 != o2 && o3 != o4 { return true }

        if o1 == 0 && pointOnSegment(p2, p1, q1) { return true }
        if o2 == 0 && pointOnSegment(q2, p1, q1) { return true }
        if o3 == 0 && pointOnSegment(p1, p2, q2) { return true }
        if o4 == 0 && pointOnSegment(q1, p2, q2) { return true }
        return false
    }

    func orientation(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> Int {
        let value = (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y)
        if abs(value) <= 1e-7 { return 0 }
        return value > 0 ? 1 : 2
    }

    func pointOnSegment(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> Bool {
        p.x <= max(q.x, r.x) + 1e-7 &&
        p.x >= min(q.x, r.x) - 1e-7 &&
        p.y <= max(q.y, r.y) + 1e-7 &&
        p.y >= min(q.y, r.y) - 1e-7
    }

    func finalizeContinuousLength() {
        guard ensureDrawingCoordinateCaptureAvailable() else { return }
        guard pendingLengthPoints.count >= 2 else { return }
        snapshot.lengthMeasurements.append(
            CADLengthMeasurement(
                points: pendingLengthPoints.map(CADPoint.init),
                name: "\(String(localized: "连续长度")) \(snapshot.lengthMeasurements.count + 1)"
            )
        )
        pendingLengthPoints.removeAll()
        AppHaptics.impact(.light, intensity: 0.65)
    }

    func finalizeAreaMeasurement() {
        guard ensureDrawingCoordinateCaptureAvailable() else { return }
        guard pendingAreaPoints.count >= 3 else { return }
        guard let closure = validateAreaClosure(points: pendingAreaPoints) else { return }
        switch closure {
        case .selfIntersecting:
            alertMessage = String(localized: "面积边界存在自交，无法闭合计算。请调整点位后重试。")
            showAlert = true
            return
        case let .valid(points, autoClosed):
            snapshot.areaMeasurements.append(
                CADAreaMeasurement(
                    points: points.map(CADPoint.init),
                    name: "\(String(localized: "面积")) \(snapshot.areaMeasurements.count + 1)"
                )
            )
            pendingAreaPoints.removeAll()
            if autoClosed {
                alertMessage = String(localized: "已自动补齐闭合边，面积已加入测量。")
                showAlert = true
            }
            AppHaptics.impact(.light, intensity: 0.65)
        }
    }

    func appendQuantityFromLength(_ measurement: CADLengthMeasurement) {
        let length = lengthInMeters(for: measurement.points.map(\.cgPoint))
        snapshot.quantityItems.append(
            CADQuantityItem(
                name: measurement.name,
                unit: "m",
                quantity: Formatters.number(length, minFraction: 2, maxFraction: 3),
                unitPrice: "0",
                wasteRate: "0",
                source: String(localized: "测量-线长"),
                sourceLinkKind: .lengthMeasurement,
                sourceLinkID: measurement.id
            )
        )
    }

    func appendQuantityFromArea(_ measurement: CADAreaMeasurement) {
        let area = areaInSquareMeters(for: measurement.points.map(\.cgPoint))
        snapshot.quantityItems.append(
            CADQuantityItem(
                name: measurement.name,
                unit: "m²",
                quantity: Formatters.number(area, minFraction: 2, maxFraction: 3),
                unitPrice: "0",
                wasteRate: "0",
                source: String(localized: "测量-面积"),
                sourceLinkKind: .areaMeasurement,
                sourceLinkID: measurement.id
            )
        )
    }

    func appendQuantityFromCountCategory(_ category: String) {
        let sourceMarkers = snapshot.countMarkers.filter { $0.category == category }
        let sourceIDs = sourceMarkers.map(\.id)
        let count = sourceIDs.count
        guard count > 0 else { return }
        snapshot.quantityItems.append(
            CADQuantityItem(
                name: category,
                unit: String(localized: "个"),
                quantity: "\(count)",
                unitPrice: "0",
                wasteRate: "0",
                source: String(localized: "数数-\(category)"),
                sourceLinkKind: .countMarkers,
                sourceLinkCategory: category,
                sourceLinkMarkerIDs: sourceIDs
            )
        )
    }

    func quantityHighlightTarget(for item: CADQuantityItem) -> CADQuantityHighlightTarget? {
        switch item.sourceLinkKind {
        case .manual:
            // 兼容旧快照：历史条目只有 source 文本，没有 sourceLink 字段
            if item.source.contains(String(localized: "测量-线长")),
               let measurement = snapshot.lengthMeasurements.last(where: { $0.name == item.name }) {
                return .length(measurement.id)
            }
            if item.source.contains(String(localized: "测量-面积")),
               let measurement = snapshot.areaMeasurements.last(where: { $0.name == item.name }) {
                return .area(measurement.id)
            }
            if let range = item.source.range(of: String(localized: "数数-")) {
                let category = String(item.source[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !category.isEmpty else { return nil }
                let ids = snapshot.countMarkers
                    .filter { $0.category == category }
                    .map(\.id)
                guard !ids.isEmpty else { return nil }
                return .countMarkers(ids)
            }
            return nil
        case .lengthMeasurement:
            guard let id = item.sourceLinkID,
                  snapshot.lengthMeasurements.contains(where: { $0.id == id }) else { return nil }
            return .length(id)
        case .areaMeasurement:
            guard let id = item.sourceLinkID,
                  snapshot.areaMeasurements.contains(where: { $0.id == id }) else { return nil }
            return .area(id)
        case .countCategory:
            let category = (item.sourceLinkCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !category.isEmpty else { return nil }
            let ids = snapshot.countMarkers
                .filter { $0.category == category }
                .map(\.id)
            guard !ids.isEmpty else { return nil }
            return .countMarkers(ids)
        case .countMarkers:
            let ids = (item.sourceLinkMarkerIDs ?? [])
                .filter { markerID in
                    snapshot.countMarkers.contains(where: { $0.id == markerID })
                }
            if !ids.isEmpty {
                return .countMarkers(ids)
            }
            let category = (item.sourceLinkCategory ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !category.isEmpty,
                  snapshot.countMarkers.contains(where: { $0.category == category }) else { return nil }
            return .countCategory(category)
        }
    }

    func locateQuantitySource(_ item: CADQuantityItem) {
        guard let target = quantityHighlightTarget(for: item) else {
            alertMessage = String(localized: "该算量条目来源已不存在，无法定位。")
            showAlert = true
            return
        }
        quantityHighlightTarget = target
        tool = .browse
        clearInProgress()
        showQuantitySheet = false
        focusQuantityTarget(target)
    }

    func focusQuantityTarget(_ target: CADQuantityHighlightTarget) {
        let points = storedPoints(for: target)
        guard let center = centerPoint(of: points) else { return }
        var userInfo: [String: Any] = [
            "filePath": activeRequest.fileURL.path,
            "point": NSValue(cgPoint: center),
        ]
        if let bounds = bounds(forStoredPoints: points) {
            userInfo["bounds"] = NSValue(cgRect: bounds)
        }
        NotificationCenter.default.post(
            name: .libreDWGFocusSourcePoint,
            object: nil,
            userInfo: userInfo
        )
    }

    func bounds(forStoredPoints points: [CGPoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        let width = max(maxX - minX, 0.001)
        let height = max(maxY - minY, 0.001)
        let pad = max(max(width, height) * 0.18, 0.002)
        return CGRect(x: minX - pad, y: minY - pad, width: width + pad * 2, height: height + pad * 2)
    }

    func storedPoints(for target: CADQuantityHighlightTarget) -> [CGPoint] {
        switch target {
        case .length(let id):
            return snapshot.lengthMeasurements
                .first(where: { $0.id == id })?
                .points
                .map(\.cgPoint) ?? []
        case .area(let id):
            return snapshot.areaMeasurements
                .first(where: { $0.id == id })?
                .points
                .map(\.cgPoint) ?? []
        case .countCategory(let category):
            return snapshot.countMarkers
                .filter { $0.category == category }
                .map { $0.point.cgPoint }
        case .countMarkers(let markerIDs):
            let sourceIDSet = Set(markerIDs)
            return snapshot.countMarkers
                .filter { sourceIDSet.contains($0.id) }
                .map { $0.point.cgPoint }
        }
    }

    func quantitySubtotal(_ item: CADQuantityItem) -> Double {
        let quantity = ReportBuilder.number(item.quantity)
        let unitPrice = ReportBuilder.number(item.unitPrice)
        let waste = ReportBuilder.number(item.wasteRate) / 100
        return quantity * max(0, 1 + waste) * unitPrice
    }

    var annotationStrokeCount: Int {
        snapshot.strokes.reduce(0) { result, stroke in
            result + (stroke.kind == .annotation ? 1 : 0)
        }
    }

    var redlineStrokeCount: Int {
        snapshot.strokes.reduce(0) { result, stroke in
            result + (stroke.kind == .redline ? 1 : 0)
        }
    }

    func removeLastStroke(kind: CADStroke.StrokeKind) {
        guard let index = snapshot.strokes.lastIndex(where: { $0.kind == kind }) else { return }
        snapshot.strokes.remove(at: index)
    }

    func updateSelectedStrokeLayer(_ layer: String) {
        guard let index = selectedStrokeIndex else { return }
        snapshot.strokes[index].layerName = layer
        hiddenStrokeLayers.remove(layer)
    }

    func updateSelectedStrokeColor(_ hex: String) {
        guard let index = selectedStrokeIndex else { return }
        snapshot.strokes[index].colorHex = hex
    }

    func deleteSelectedStroke() {
        guard let index = selectedStrokeIndex else { return }
        snapshot.strokes.remove(at: index)
        selectedStrokeID = nil
    }

    func removeLastLengthMeasurement() {
        guard !snapshot.lengthMeasurements.isEmpty else { return }
        _ = snapshot.lengthMeasurements.removeLast()
    }

    func removeLastNote() {
        guard !snapshot.notes.isEmpty else { return }
        _ = snapshot.notes.removeLast()
    }

    var overlaySnapCandidates: [CGPoint] {
        var points: [CGPoint] = []
        if hasNativeDrawingCoordinateSpace {
            let semanticCandidates = nativeSnapCandidatesForCurrentTool()
            if enabledSnapModes.contains(.endpoint) {
                points.append(contentsOf: semanticCandidates.filter { $0.snapKind == .endpoint }.map(\.point))
            }
            if enabledSnapModes.contains(.midpoint) {
                points.append(contentsOf: semanticCandidates.filter { $0.snapKind == .midpoint }.map(\.point))
            }
            if enabledSnapModes.contains(.center) {
                points.append(contentsOf: semanticCandidates.filter { $0.snapKind == .center }.map(\.point))
            }
            if points.isEmpty {
                points.append(contentsOf: semanticCandidates.map(\.point))
            }
        }
        points.append(contentsOf: snapshot.countMarkers.map { $0.point.cgPoint })
        points.append(contentsOf: snapshot.notes.map { $0.point.cgPoint })
        for measurement in snapshot.lengthMeasurements {
            points.append(contentsOf: measurement.points.map(\.cgPoint))
        }
        for measurement in snapshot.areaMeasurements {
            points.append(contentsOf: measurement.points.map(\.cgPoint))
        }
        points.append(contentsOf: pendingLengthPoints)
        points.append(contentsOf: pendingAreaPoints)
        points.append(contentsOf: activeDragLengthPoints)
        return points
    }

    func nativeSnapCandidatesForCurrentTool() -> [CADNativeSnapSourcePoint] {
        let base = nativeSnapSourcePoints.isEmpty ? fallbackNativeSnapCandidates() : nativeSnapSourcePoints
        guard !base.isEmpty else { return [] }
        switch tool {
        case .length, .continuousLength, .area, .count:
            return base.filter { $0.primitiveKind.supportsMeasurementSnap }
        default:
            return base
        }
    }

    func fallbackNativeSnapCandidates() -> [CADNativeSnapSourcePoint] {
        var result: [CADNativeSnapSourcePoint] = []
        func append(_ point: CGPoint, kind: CADNativeSnapPointKind) {
            result.append(
                CADNativeSnapSourcePoint(
                    point: point,
                    snapKind: kind,
                    layer: "0",
                    primitiveKind: .unknownProxy,
                    styleRGB: 0,
                    styleWidth: 1,
                    styleName: nil
                )
            )
        }
        nativeEndpointSnapPoints.forEach { append($0, kind: .endpoint) }
        nativeMidpointSnapPoints.forEach { append($0, kind: .midpoint) }
        nativeCenterSnapPoints.forEach { append($0, kind: .center) }
        if result.isEmpty {
            nativeSnapPoints.forEach { append($0, kind: .endpoint) }
        }
        return result
    }

    func snappedOverlayPoint(_ rawPoint: CGPoint) -> CGPoint? {
        guard let storedRawPoint = storedDrawingPoint(fromCanvas: rawPoint) else {
            return nil
        }
        guard tool == .length || tool == .continuousLength || tool == .area || tool == .note || tool == .count else {
            return storedRawPoint
        }
        guard let nearest = nearestPoint(toCanvasPoint: rawPoint, inStoredPoints: overlaySnapCandidates, maxDistance: overlaySnapTolerance) else {
            return storedRawPoint
        }
        return nearest
    }

    func nearestCountMarkerIndex(toCanvasPoint point: CGPoint) -> Int? {
        var bestIndex: Int?
        var bestDistance = overlaySnapTolerance
        for (index, marker) in snapshot.countMarkers.enumerated() {
            let target = canvasPoint(fromStored: marker.point.cgPoint)
            let distance = hypot(target.x - point.x, target.y - point.y)
            if distance <= bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    func nearestStrokeID(toCanvasPoint point: CGPoint) -> UUID? {
        var bestID: UUID?
        var bestDistance = overlaySnapTolerance
        for stroke in visibleStrokes {
            let renderedPoints = canvasPoints(fromStored: stroke.points.map(\.cgPoint))
            let distance = distanceFrom(point, toPolyline: renderedPoints)
            if distance <= bestDistance {
                bestDistance = distance
                bestID = stroke.id
            }
        }
        return bestID
    }

    func nearestNoteIndex(toCanvasPoint point: CGPoint) -> Int? {
        var bestIndex: Int?
        var bestDistance = overlaySnapTolerance
        for (index, note) in snapshot.notes.enumerated() {
            let target = canvasPoint(fromStored: note.point.cgPoint)
            let distance = hypot(target.x - point.x, target.y - point.y)
            if distance <= bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    func nearestPoint(toCanvasPoint source: CGPoint, inStoredPoints points: [CGPoint], maxDistance: CGFloat) -> CGPoint? {
        var nearest: CGPoint?
        var nearestDistance = maxDistance
        for point in points {
            let canvasPoint = canvasPoint(fromStored: point)
            let distance = hypot(canvasPoint.x - source.x, canvasPoint.y - source.y)
            if distance <= nearestDistance {
                nearestDistance = distance
                nearest = point
            }
        }
        return nearest
    }

    func distanceFrom(_ point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard !points.isEmpty else { return .greatestFiniteMagnitude }
        guard points.count > 1 else {
            return hypot(points[0].x - point.x, points[0].y - point.y)
        }
        var best = CGFloat.greatestFiniteMagnitude
        for index in 0..<(points.count - 1) {
            best = min(best, distanceFrom(point, toSegmentStart: points[index], end: points[index + 1]))
        }
        return best
    }

    func distanceFrom(_ point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }
        let rawT = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
        let t = min(max(rawT, 0), 1)
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }
}
