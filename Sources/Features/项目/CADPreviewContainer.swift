import SwiftUI
#if os(iOS)
import UIKit
#endif

enum CADTechnicalDiagnosticsVisibility {
    static let internalSwitchKey = "cad.internal.showTechnicalDiagnostics"

    static var isEnabled: Bool {
        #if DEBUG
        true
        #else
        UserDefaults.standard.bool(forKey: internalSwitchKey)
        #endif
    }

    static func isEnabled(isDebugBuild: Bool, internalSwitchOn: Bool) -> Bool {
        isDebugBuild || internalSwitchOn
    }
}

struct ProjectCADPreviewRequest: Identifiable {
    let id = UUID()
    let projectId: UUID
    let drawingID: UUID
    let fileURL: URL
    let displayName: String
    let fileType: String
    let importedAt: String
    let fileSizeBytes: Int
    let textEncoding: CADDrawingTextEncoding
    let textBigFont: CADDrawingTextBigFont
    let textSchemeSnapshot: CADDrawingTextSchemeSnapshot
    let cadViewState: CADDrawingViewState
    let projectFontMappings: [CADProjectFontMapping]
    let overlaySnapshotData: String
    let onOverlaySnapshotChange: (UUID, String) -> Void
    let onViewStateChange: (UUID, CADDrawingViewState) -> Void
    let onTextEncodingChange: (UUID, CADDrawingTextEncoding) -> Void
    let onTextBigFontChange: (UUID, CADDrawingTextBigFont) -> Void
    let onTextSchemeSnapshotChange: (UUID, CADDrawingTextSchemeSnapshot) -> Void
    let onProjectFontMappingsChange: (UUID, [CADProjectFontMapping]) -> Void

    var preferredTextCodePage: Int32? {
        textEncoding.codePageOverride
    }

    var preferredTextBigFontCode: Int32? {
        textBigFont.bridgeCode
    }

    var cadFile: CADFile {
        CADFile(
            id: id,
            projectId: projectId,
            drawingId: drawingID,
            fileURL: fileURL,
            displayName: displayName,
            fileType: fileType,
            importedAt: importedAt,
            fileSizeBytes: fileSizeBytes
        )
    }

    var rendererFontMappings: [CADRendererFontMapping] {
        projectFontMappings.compactMap { mapping in
            guard !mapping.normalizedPattern.isEmpty,
                  mapping.bigFont != .auto,
                  let bridgeCode = mapping.bigFont.bridgeCode else { return nil }
            return CADRendererFontMapping(
                sourceKind: mapping.source.rawValue,
                pattern: mapping.normalizedPattern,
                bigFont: bridgeCode
            )
        }
    }
}

struct CADDiagnosticMachineTrace: Codable {
    struct FileInfo: Codable {
        let displayName: String
        let path: String
        let fileType: String
        let fileByteCount: Int
        let headerHex: String
        let importedAt: String
    }

    struct Environment: Codable {
        let appVersion: String
        let buildNumber: String
        let cadEngineInstalled: Bool
        let rendererBound: Bool
        let viewerMode: String
        let fallbackViewerActive: Bool
        let performanceFallbackActive: Bool
        let performanceFallbackReason: String?
    }

    struct Pipeline: Codable {
        let failureLayer: String
        let failureStage: String
        let openState: String
        let importSource: String?
        let conclusion: String
        let traceSource: String
    }

    struct Counts: Codable {
        let rawEntityCount: Int
        let adapterEntityCount: Int
        let databaseEntityCount: Int
        let drawableEntityCount: Int
        let renderCommandCount: Int
        let visibleLayerCount: Int
    }

    struct Bounds: Codable {
        let minX: Double
        let minY: Double
        let maxX: Double
        let maxY: Double
    }

    struct TextState: Codable {
        let selectedEncoding: String
        let selectedBigFont: String
        let codePageOverride: Int32?
        let bigFontCode: Int32?
        let detectedCodePage: String?
        let detectedStyleName: String?
        let detectedFontFile: String?
        let detectedBigFontFile: String?
        let autoDetectScore: Int?
        let unresolvedFontSummary: String?
        let fontResolutionSummary: String?
        let rawTextBytesHexSample: String?
    }

    struct Performance: Codable {
        let entityCountInViewport: Int
        let drawCallCount: Int
        let frameTimeMilliseconds: Double
        let skippedEntityCount: Int
        let visibleLayerCount: Int
        let simplifiedMode: Bool
        let renderCommandCount: Int
        let textCommandCount: Int
        let textOverlayCount: Int
        let renderMilliseconds: Double
        let firstFrameMilliseconds: Double
    }

    struct OpenQuality: Codable {
        let level: String
        let title: String
        let summary: String
        let allowsMarkup: Bool
        let supportsSearch: Bool
        let detailLines: [String]
    }

    struct KernelTrace: Codable {
        let fileName: String
        let fileByteCount: Int
        let dwgVersion: String?
        let libreDwgAvailable: Bool
        let dwgreadJsonExitCode: Int?
        let dwgreadDxfExitCode: Int?
        let dwg2dxfExitCode: Int?
        let jsonRawEntityCount: Int
        let dxfRawEntityCount: Int
        let adapterEntityCount: Int
        let databaseEntityCount: Int
        let drawableEntityCount: Int
        let renderCommandCount: Int
        let extents: Bounds?
        let currentLayout: String?
        let visibleLayerCount: Int
        let openState: String
        let failureStage: String
    }

    struct NativeTrace: Codable {
        struct RawEntityCounts: Codable {
            let line: Int
            let polyline: Int
            let circle: Int
            let arc: Int
            let insert: Int
            let ellipse: Int
            let spline: Int
            let filledShape: Int
            let dimension: Int
            let hatch: Int
            let text: Int
            let total: Int
        }

        let fileName: String
        let importSource: String
        let rawEntityCounts: RawEntityCounts
        let expandedInsertEntityCount: Int
        let entityCount: Int
        let drawableEntityCount: Int
        let renderCommandCount: Int
        let bounds: Bounds?
        let openedForRender: Bool
    }

    let schemaVersion: Int
    let traceKind: String
    let generatedAt: String
    let humanReportFile: String
    let machineTraceFile: String
    let file: FileInfo
    let environment: Environment
    let pipeline: Pipeline
    let counts: Counts
    let text: TextState
    let performance: Performance?
    let openQuality: OpenQuality?
    let kernelTrace: KernelTrace?
    let nativeTrace: NativeTrace?
    let diagnostics: [String]
    let notes: [String]
}

private extension CADDiagnosticMachineTrace.Bounds {
    init?(_ bounds: SiteKeeperCADKernel.CADBounds?) {
        guard let bounds, !bounds.isEmpty else { return nil }
        self.init(minX: bounds.minX, minY: bounds.minY, maxX: bounds.maxX, maxY: bounds.maxY)
    }
}

private extension CADDiagnosticMachineTrace.KernelTrace {
    init(_ trace: SiteKeeperCADKernel.DWGOpenPipelineTrace) {
        self.init(
            fileName: trace.fileName,
            fileByteCount: trace.fileSize,
            dwgVersion: trace.dwgVersion,
            libreDwgAvailable: trace.libreDwgAvailable,
            dwgreadJsonExitCode: trace.dwgreadJsonExitCode,
            dwgreadDxfExitCode: trace.dwgreadDxfExitCode,
            dwg2dxfExitCode: trace.dwg2dxfExitCode,
            jsonRawEntityCount: trace.jsonRawEntityCount,
            dxfRawEntityCount: trace.dxfRawEntityCount,
            adapterEntityCount: trace.adapterEntityCount,
            databaseEntityCount: trace.databaseEntityCount,
            drawableEntityCount: trace.drawableEntityCount,
            renderCommandCount: trace.renderCommandCount,
            extents: CADDiagnosticMachineTrace.Bounds(trace.extents),
            currentLayout: trace.currentLayout,
            visibleLayerCount: trace.visibleLayerCount,
            openState: trace.openState.rawValue,
            failureStage: trace.failureStage
        )
    }
}

private extension CADDiagnosticMachineTrace.NativeTrace {
    init(_ trace: CADPoC.CADOpenTrace) {
        let rawCounts = RawEntityCounts(
            line: trace.rawLineCount,
            polyline: trace.rawPolylineCount,
            circle: trace.rawCircleCount,
            arc: trace.rawArcCount,
            insert: trace.rawInsertCount,
            ellipse: trace.rawEllipseCount,
            spline: trace.rawSplineCount,
            filledShape: trace.rawFilledShapeCount,
            dimension: trace.rawDimensionCount,
            hatch: trace.rawHatchCount,
            text: trace.rawTextCount,
            total: trace.rawLineCount
                + trace.rawPolylineCount
                + trace.rawCircleCount
                + trace.rawArcCount
                + trace.rawInsertCount
                + trace.rawEllipseCount
                + trace.rawSplineCount
                + trace.rawFilledShapeCount
                + trace.rawDimensionCount
                + trace.rawHatchCount
                + trace.rawTextCount
        )
        self.init(
            fileName: trace.fileName,
            importSource: trace.importSource,
            rawEntityCounts: rawCounts,
            expandedInsertEntityCount: trace.expandedInsertEntityCount,
            entityCount: trace.entityCount,
            drawableEntityCount: trace.drawableEntityCount,
            renderCommandCount: trace.renderCommandCount,
            bounds: CADDiagnosticMachineTrace.Bounds(trace.bounds),
            openedForRender: trace.openedForRender
        )
    }
}

struct CADKernelUnavailableView: View {
    let fileURL: URL
    let message: String
    let technicalDetails: CADOpenTechnicalDetails?
    let onReportIssue: () -> Void

    private var shouldShowTechnicalDetails: Bool {
        CADTechnicalDiagnosticsVisibility.isEnabled && technicalDetails != nil
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(Color.appWarning)

            VStack(spacing: 6) {
                Text("当前图纸暂不支持在线预览")
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ShareLink(item: fileURL) {
                Label("下载原图", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appProminent(tint: .appDoc))
            .controlSize(.large)

            Button {
                onReportIssue()
            } label: {
                Label("反馈问题", systemImage: "exclamationmark.bubble")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if shouldShowTechnicalDetails, let details = technicalDetails {
                DisclosureGroup("技术信息") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("DWG version") { Text(details.dwgVersion ?? "-") }
                        LabeledContent("file size") { Text("\(details.fileSizeBytes ?? 0) bytes") }
                        LabeledContent("import engine") { Text(details.importEngine ?? "-") }
                        LabeledContent("geometryParsed") { Text(details.geometryParsed ? "true" : "false") }
                        LabeledContent("drawableEntityCount") { Text("\(details.drawableEntityCount)") }
                        if let trace = details.pipelineTrace {
                            LabeledContent("failureStage") { Text(trace.failureStage) }
                            LabeledContent("databaseEntityCount") { Text("\(trace.databaseEntityCount)") }
                            LabeledContent("adapterEntityCount") { Text("\(trace.adapterEntityCount)") }
                            LabeledContent("renderCommandCount") { Text("\(trace.renderCommandCount)") }
                            LabeledContent("currentLayout") { Text(trace.currentLayout ?? "-") }
                            LabeledContent("visibleLayerCount") { Text("\(trace.visibleLayerCount)") }
                            LabeledContent("extents") { Text(formatBounds(trace.extents)) }
                        }
                        if !details.diagnostics.isEmpty {
                            Text("diagnostics")
                                .font(.caption.weight(.semibold))
                            ForEach(Array(details.diagnostics.prefix(8).enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func formatBounds(_ bounds: SiteKeeperCADKernel.CADBounds?) -> String {
        guard let bounds, !bounds.isEmpty else { return "-" }
        return "\(bounds.minX), \(bounds.minY) - \(bounds.maxX), \(bounds.maxY)"
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

private struct CADNativeSnapPointBuckets {
    let sourcePoints: [CADNativeSnapSourcePoint]
    let allPoints: [CGPoint]
    let endpointPoints: [CGPoint]
    let midpointPoints: [CGPoint]
    let centerPoints: [CGPoint]
    let measurementAllPoints: [CGPoint]
    let measurementEndpointPoints: [CGPoint]
    let measurementMidpointPoints: [CGPoint]
    let measurementCenterPoints: [CGPoint]

    var isEmpty: Bool {
        sourcePoints.isEmpty
    }

    init(sourcePoints: [CADNativeSnapSourcePoint] = []) {
        self.sourcePoints = sourcePoints
        var allPoints: [CGPoint] = []
        var endpointPoints: [CGPoint] = []
        var midpointPoints: [CGPoint] = []
        var centerPoints: [CGPoint] = []
        var measurementAllPoints: [CGPoint] = []
        var measurementEndpointPoints: [CGPoint] = []
        var measurementMidpointPoints: [CGPoint] = []
        var measurementCenterPoints: [CGPoint] = []
        allPoints.reserveCapacity(sourcePoints.count)
        endpointPoints.reserveCapacity(sourcePoints.count / 2)
        midpointPoints.reserveCapacity(sourcePoints.count / 3)
        centerPoints.reserveCapacity(sourcePoints.count / 4)
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
            }
        }

        self.allPoints = allPoints
        self.endpointPoints = endpointPoints
        self.midpointPoints = midpointPoints
        self.centerPoints = centerPoints
        self.measurementAllPoints = measurementAllPoints
        self.measurementEndpointPoints = measurementEndpointPoints
        self.measurementMidpointPoints = measurementMidpointPoints
        self.measurementCenterPoints = measurementCenterPoints
    }

    func points(enabledModes: Set<CADSnapMode>, measurementOnly: Bool) -> [CGPoint] {
        let allCandidates = measurementOnly ? measurementAllPoints : allPoints
        let endpointCandidates = measurementOnly ? measurementEndpointPoints : endpointPoints
        let midpointCandidates = measurementOnly ? measurementMidpointPoints : midpointPoints
        let centerCandidates = measurementOnly ? measurementCenterPoints : centerPoints

        var points: [CGPoint] = []
        points.reserveCapacity(endpointCandidates.count + midpointCandidates.count + centerCandidates.count)
        if enabledModes.contains(.endpoint) {
            points.append(contentsOf: endpointCandidates)
        }
        if enabledModes.contains(.midpoint) {
            points.append(contentsOf: midpointCandidates)
        }
        if enabledModes.contains(.center) {
            points.append(contentsOf: centerCandidates)
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

struct CADPreviewContainer: View {
    let request: ProjectCADPreviewRequest
    @Environment(\.dismiss) var dismiss
    @Environment(DataStore.self) var store

    @State var activeRequest: ProjectCADPreviewRequest
    @State var tool: CADOverlayTool = .browse
    @State var snapshot = CADOverlaySnapshot()
    @State var activeStrokePoints: [CGPoint] = []
    @State var pendingLengthPoints: [CGPoint] = []
    @State var pendingAreaPoints: [CGPoint] = []
    @State var activeDragLengthPoints: [CGPoint] = []
    @State var activeDragArrowPoints: [CGPoint] = []
    @State var showQuantitySheet = false
    @State var showResetConfirm = false
    @State var showScaleSheet = false
    @State var showOverlayLayerSheet = false
    @State var showAnnotationExportFormatDialog = false
    @State var showTextEncodingDialog = false
    @State var showCADDiagnosticSheet = false
    @State var scaleDraft = ""
    @State var calibrationActualMetersDraft = ""
    @State var selectedCalibrationMeasurementID: UUID?
    @State var newOverlayLayerName = ""
    @State var customOverlayColor = Color(red: 0.89, green: 0.29, blue: 0.48)
    @State var pendingNotePoint: CGPoint?
    @State var noteDraft = ""
    @State var showNoteSheet = false
    @State var pendingIssueMarkerPoint: CGPoint?
    @State var showIssuePhotoCamera = false
    @State var selectedCountCategory = String(localized: "点位")
    @State var lastPersistedSnapshotData = ""
    @State var isImmersivePreview = false
    @State var selectedTextEncoding: CADDrawingTextEncoding
    @State var selectedTextBigFont: CADDrawingTextBigFont
    @State var textSchemeSnapshot: CADDrawingTextSchemeSnapshot
    @State var cadOpenQuality: CADOpenQualitySnapshot?
    @State var projectFontMappingBigFont: CADDrawingTextBigFont = .gbcbig
    @State var currentCADViewState: CADDrawingViewState
    @State var lastPersistedCADViewState: CADDrawingViewState
    @State var isApplyingTextPreset = false
    @State var selectedStrokeLayer = String(localized: "现场批注")
    @State var selectedAnnotationColorHex = "2F80ED"
    @State var selectedMeasurementColorHex = "2F80ED"
    @State var selectedNoteColorHex = "F2994A"
    @State var hiddenOverlayGroups: Set<CADOverlayVisibilityGroup> = []
    @State var hiddenStrokeLayers: Set<String> = []
    @State var hiddenOverlayColorHexes: Set<String> = []
    @State var isSelectingStroke = false
    @State var isDeletingOverlayItem = false
    @State var selectedStrokeID: UUID?
    @State var overlayUndoStack: [CADOverlaySnapshot] = []
    @State var overlayRedoStack: [CADOverlaySnapshot] = []
    @State var isAutoDetectingText = false
    @State var isExportingDiagnosticLog = false
    @State var diagnosticExportPayload: ExportPayload?
    @State var annotationExportPayload: ExportPayload?
    @State var fallbackScreenshotPayload: ExportPayload?
    @State var quantityHighlightTarget: CADQuantityHighlightTarget?
    @State var nativeCanvasTransform: CADNativeCanvasTransform?
    @State var nativeSnapPoints: [CGPoint] = []
    @State var nativeEndpointSnapPoints: [CGPoint] = []
    @State var nativeMidpointSnapPoints: [CGPoint] = []
    @State var nativeCenterSnapPoints: [CGPoint] = []
    @State var nativeSnapSourcePoints: [CADNativeSnapSourcePoint] = []
    @State private var nativeSnapPointBuckets = CADNativeSnapPointBuckets()
    @State var nativeCADLayers: [CADPoC.CADLayer] = []
    @State var nativeCADVisibleLayerIDs: Set<String>?
    @State var enabledSnapModes: Set<CADSnapMode> = Set(CADSnapMode.allCases)
    @State var cadPreviewReloadToken = UUID()
    @State var lastRendererPerformance: CADRendererPerformanceSnapshot?
    @State var lastCADOpenTrace: CADPoC.CADOpenTrace?
    @State var forceFallbackForPerformance = false
    @State var forceFallbackReason: String?
    @State var alertMessage = ""
    @State var showAlert = false
    @State var showShareSheet = false
    @State var cadOpenRoute: CADOpenRoute = .unsupported(
        CADOpenResult(
            drawingId: UUID(),
            openState: .unsupported,
            message: CADViewerMessages.onlinePreviewUnavailableMessage,
            technicalDetails: nil
        )
    )
    @AppStorage("cadViewerMode") private var cadViewerModeRaw = CADViewerMode.auto.rawValue
    let overlaySnapTolerance: CGFloat = 14
    let activeStrokeSamplingCanvasDistance: CGFloat = 3
    let activeStrokePointLimit = 4096
    let overlayUndoLimit = 40

    init(request: ProjectCADPreviewRequest) {
        self.request = request
        _activeRequest = State(initialValue: request)
        _selectedTextEncoding = State(initialValue: request.textEncoding)
        _selectedTextBigFont = State(initialValue: request.textBigFont)
        _textSchemeSnapshot = State(initialValue: request.textSchemeSnapshot)
        _currentCADViewState = State(initialValue: request.cadViewState)
        _lastPersistedCADViewState = State(initialValue: request.cadViewState)
    }

    var isCADFile: Bool {
        CADDrawingCapability.isCADFile(extension: activeRequest.fileType)
    }

    var isDWGFile: Bool {
        let declaredType = activeRequest.fileType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pathExtension = activeRequest.fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return declaredType == "dwg" || pathExtension == "dwg"
    }

    var selectedCADViewerMode: CADViewerMode {
        CADViewerMode(rawValue: cadViewerModeRaw) ?? .auto
    }

    var shouldUseFallbackViewer: Bool {
        false
    }

    var shouldShowCADKernelUnavailable: Bool {
        isCADFile && !CADRendererProvider.isRendererBound
    }

    var shouldShowCADKernelUnbound: Bool {
        isCADFile && !CADRendererProvider.isRendererBound
    }

    var shouldUseCADKernelRenderer: Bool {
        guard !isDWGFile else { return false }
        return Self.shouldEnterInteractiveCADCanvas(
            isCADFile: isCADFile,
            rendererBound: CADRendererProvider.isRendererBound,
            route: cadOpenRoute
        )
    }

    var allowsOverlayEditing: Bool {
        if isDWGFile {
            return true
        }
        guard isCADFile else { return true }
        if case .online = cadOpenRoute {
            return true
        }
        return false
    }

    var shouldUseCADOverlayHost: Bool {
        isCADFile && (isDWGFile || shouldUseCADKernelRenderer)
    }

    var unsupportedKernelMessage: String {
        switch cadOpenRoute {
        case .unsupported(let result):
            return result.message
        case .online(let result):
            return result.message.isEmpty ? CADViewerMessages.onlinePreviewUnavailableMessage : result.message
        }
    }

    static func shouldEnterInteractiveCADCanvas(
        isCADFile: Bool,
        rendererBound: Bool,
        route: CADOpenRoute
    ) -> Bool {
        guard isCADFile, rendererBound else { return false }
        if case .online = route {
            return true
        }
        return false
    }

    var engineStatusHint: String? {
        return nil
    }

    @MainActor
    func refreshCADOpenRoute() async {
        guard isCADFile else { return }
        cadOpenQuality = nil
        lastRendererPerformance = nil
        forceFallbackForPerformance = false
        forceFallbackReason = nil
        cadOpenRoute = .unsupported(
            CADOpenResult(
                drawingId: activeRequest.drawingID,
                openState: .unsupported,
                message: CADViewerMessages.onlinePreviewUnavailableMessage,
                technicalDetails: nil
            )
        )
        cadOpenRoute = await CADOpenRouter.route(for: activeRequest.cadFile)
        cadPreviewReloadToken = UUID()
    }

    var cadOpenTechnicalDetails: CADOpenTechnicalDetails? {
        switch cadOpenRoute {
        case .online(let result), .unsupported(let result):
            return result.technicalDetails
        }
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
        if shouldUseFallbackViewer {
            return String(localized: "兼容预览使用归一化图纸坐标保存批注和问题点，不写回 CAD 原文件。")
        }
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

    var fallbackScreenshotExporterPresented: Binding<Bool> {
        Binding(
            get: { fallbackScreenshotPayload != nil },
            set: { isPresented in
                if !isPresented {
                    fallbackScreenshotPayload = nil
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
            String(localized: "复核标记"),
            String(localized: "整改记录")
        ]
    }

    var overlayVisibilityGroups: [CADOverlayVisibilityGroup] {
        [.annotation, .measurement, .notes, .counts, .issues]
    }

    var overlayStrokeLayerOptions: [String] {
        var result: [String] = []
        func append(_ value: String?) {
            let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !result.contains(text) else { return }
            result.append(text)
        }
        overlayStrokeLayerDefaults.forEach(append)
        snapshot.customStrokeLayerNames.forEach(append)
        snapshot.strokes.forEach { append(strokeLayerName($0)) }
        snapshot.arrowAnnotations.forEach { append(strokeLayerName($0)) }
        append(selectedStrokeLayer)
        return result
    }

    var defaultOverlayColorOptions: [CADOverlayColorOption] {
        [
            .init(name: String(localized: "桃红"), hex: "E24A7A"),
            .init(name: String(localized: "柳绿"), hex: "67A866"),
            .init(name: String(localized: "蓝色"), hex: "2F80ED"),
            .init(name: String(localized: "橙色"), hex: "F2994A"),
            .init(name: String(localized: "紫色"), hex: "8E6AD8"),
            .init(name: String(localized: "黑色"), hex: "333333")
        ]
    }

    var overlayColorOptions: [CADOverlayColorOption] {
        var result: [CADOverlayColorOption] = []
        func append(_ option: CADOverlayColorOption) {
            let normalized = normalizedColorHex(option.hex)
            guard !result.contains(where: { normalizedColorHex($0.hex) == normalized }) else { return }
            result.append(CADOverlayColorOption(name: option.name, hex: normalized))
        }
        func appendHex(_ hex: String?) {
            let normalized = normalizedColorHex(hex)
            guard !result.contains(where: { normalizedColorHex($0.hex) == normalized }) else { return }
            result.append(CADOverlayColorOption(name: "#\(normalized)", hex: normalized))
        }

        defaultOverlayColorOptions.forEach(append)
        snapshot.customOverlayColors.forEach(append)
        appendHex(selectedAnnotationColorHex)
        appendHex(selectedMeasurementColorHex)
        appendHex(selectedNoteColorHex)
        snapshot.strokes.forEach { appendHex(strokeColorHex($0)) }
        snapshot.arrowAnnotations.forEach { appendHex(arrowColorHex($0)) }
        snapshot.lengthMeasurements.forEach { appendHex(lengthMeasurementColorHex($0)) }
        snapshot.areaMeasurements.forEach { appendHex(areaMeasurementColorHex($0)) }
        snapshot.notes.forEach { appendHex(noteColorHex($0)) }
        snapshot.issueMarkers.forEach { appendHex(issueMarkerColorHex($0)) }
        return result
    }

    var overlayColorVisibilityOptions: [CADOverlayColorOption] {
        var result: [CADOverlayColorOption] = []
        func append(name: String, hex: String) {
            let normalized = normalizedColorHex(hex)
            guard overlayColorItemCount(for: normalized) > 0,
                  !result.contains(where: { normalizedColorHex($0.hex) == normalized }) else { return }
            result.append(CADOverlayColorOption(name: name, hex: normalized))
        }

        overlayColorOptions.forEach { append(name: $0.name, hex: $0.hex) }
        snapshot.strokes.forEach { append(name: colorDisplayName(for: strokeColorHex($0)), hex: strokeColorHex($0)) }
        snapshot.arrowAnnotations.forEach { append(name: colorDisplayName(for: arrowColorHex($0)), hex: arrowColorHex($0)) }
        snapshot.lengthMeasurements.forEach { append(name: colorDisplayName(for: lengthMeasurementColorHex($0)), hex: lengthMeasurementColorHex($0)) }
        snapshot.areaMeasurements.forEach { append(name: colorDisplayName(for: areaMeasurementColorHex($0)), hex: areaMeasurementColorHex($0)) }
        snapshot.notes.forEach { append(name: colorDisplayName(for: noteColorHex($0)), hex: noteColorHex($0)) }
        snapshot.issueMarkers.forEach { append(name: colorDisplayName(for: issueMarkerColorHex($0)), hex: issueMarkerColorHex($0)) }
        return result
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

    var initialRendererViewState: CADRendererViewState? {
        guard activeRequest.cadViewState.hasSavedViewport else { return nil }
        let state = activeRequest.cadViewState
        let viewportCenter: CGPoint?
        if let x = state.viewportCenterX, let y = state.viewportCenterY {
            viewportCenter = CGPoint(x: CGFloat(x), y: CGFloat(y))
        } else {
            viewportCenter = nil
        }
        return CADRendererViewState(
            zoomScale: CGFloat(state.zoomScale),
            panOffset: CGSize(width: CGFloat(state.panOffsetX), height: CGFloat(state.panOffsetY)),
            viewportCenter: viewportCenter,
            usesSavedVisibleLayers: state.usesSavedVisibleLayers,
            visibleLayerNames: state.visibleLayerNames
        )
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
            isOverlayGroupVisible(.annotation) &&
            isStrokeLayerVisible(strokeLayerName(stroke)) &&
            isOverlayColorVisible(strokeColorHex(stroke))
        }
    }

    var visibleArrows: [CADArrowAnnotation] {
        snapshot.arrowAnnotations.filter { arrow in
            isOverlayGroupVisible(.annotation) &&
            isStrokeLayerVisible(strokeLayerName(arrow)) &&
            isOverlayColorVisible(arrowColorHex(arrow))
        }
    }

    var visibleLengthMeasurements: [CADLengthMeasurement] {
        guard isOverlayGroupVisible(.measurement) else { return [] }
        return snapshot.lengthMeasurements.filter {
            isOverlayColorVisible(lengthMeasurementColorHex($0))
        }
    }

    var visibleAreaMeasurements: [CADAreaMeasurement] {
        guard isOverlayGroupVisible(.measurement) else { return [] }
        return snapshot.areaMeasurements.filter {
            isOverlayColorVisible(areaMeasurementColorHex($0))
        }
    }

    var visibleNotes: [CADTextNote] {
        guard isOverlayGroupVisible(.notes) else { return [] }
        return snapshot.notes.filter {
            isOverlayColorVisible(noteColorHex($0))
        }
    }

    var visibleIssueMarkers: [CADFallbackIssueMarker] {
        guard isOverlayGroupVisible(.issues) else { return [] }
        return snapshot.issueMarkers.filter {
            isOverlayColorVisible(issueMarkerColorHex($0))
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

    var rendererCallbacks: CADRendererCallbacks {
        let expectedFilePath = activeRequest.fileURL.path
        return CADRendererCallbacks(
            onCanvasTransformChange: { transform in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererCanvasTransform(transform)
                }
            },
            onViewStateChange: { viewState in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererViewState(viewState)
                }
            },
            onTextRepairPresetRequest: { codePage, bigFont in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererTextRepairPresetRequest(codePage: codePage, bigFont: bigFont)
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
            },
            onOpenQualityChange: { quality in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    cadOpenQuality = quality
                }
            },
            onOpenTraceChange: { trace in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    lastCADOpenTrace = trace
                }
            },
            onPerformanceSample: { sample in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererPerformanceSample(sample)
                }
            },
            onFallbackRecommendation: { reason in
                Task { @MainActor in
                    guard expectedFilePath == activeRequest.fileURL.path else { return }
                    handleRendererFallbackRecommendation(reason)
                }
            }
        )
    }

    var previewContent: AnyView {
        if isCADFile {
            if isDWGFile {
                return AnyView(
                    CADViewerRoute(
                        request: activeRequest,
                        showsToolbar: false,
                        initialViewState: initialRendererViewState,
                        callbacks: rendererCallbacks,
                        visibleLayerIDs: nativeCADVisibleLayerIDs,
                        onLayersChanged: { layers in
                            nativeCADLayers = layers
                        },
                        onVisibleLayerIDsChanged: { layerIDs in
                            nativeCADVisibleLayerIDs = layerIDs
                        },
                        onClose: {
                            dismiss()
                        },
                        onReportIssue: {
                            Task { @MainActor in
                                await exportDiagnosticLog()
                            }
                        }
                    )
                )
            }
            if shouldUseCADKernelRenderer,
               let renderer = CADRendererProvider.renderer(
                for: activeRequest.fileURL,
                preferredTextCodePage: activeRequest.preferredTextCodePage,
                preferredTextBigFont: activeRequest.preferredTextBigFontCode,
                initialViewState: cadKernelInitialViewState,
                fontMappings: activeRequest.rendererFontMappings,
                callbacks: rendererCallbacks
               ) {
                return renderer
            }
            return AnyView(
                CADKernelUnavailableView(
                    fileURL: activeRequest.fileURL,
                    message: unsupportedKernelMessage,
                    technicalDetails: cadOpenTechnicalDetails,
                    onReportIssue: {
                        Task { @MainActor in
                            await exportDiagnosticLog()
                        }
                    }
                )
            )
        }
        return AnyView(AppQuickLookPreviewController(url: activeRequest.fileURL))
    }

    var cadKernelInitialViewState: CADRendererViewState {
        CADRendererViewState(
            zoomScale: CGFloat(currentCADViewState.zoomScale),
            panOffset: CGSize(
                width: currentCADViewState.panOffsetX,
                height: currentCADViewState.panOffsetY
            ),
            viewportCenter: cadKernelViewportCenter,
            usesSavedVisibleLayers: currentCADViewState.usesSavedVisibleLayers,
            visibleLayerNames: currentCADViewState.visibleLayerNames
        )
    }

    var cadKernelViewportCenter: CGPoint? {
        guard let x = currentCADViewState.viewportCenterX,
              let y = currentCADViewState.viewportCenterY else {
            return nil
        }
        return CGPoint(x: x, y: y)
    }

    var body: some View {
        Group {
            if !shouldUseCADOverlayHost {
                previewContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CADCanvasHost(
                    isImmersivePreview: isImmersivePreview,
                    allowsOverlayEditing: allowsOverlayEditing,
                    overlayHitTestingEnabled: overlayHitTestingEnabled,
                    immersiveTopSafePadding: immersiveTopSafePadding,
                    immersiveBottomSafePadding: immersiveBottomSafePadding
                ) {
                    previewContent
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
            }
        }
            .onAppear {
                snapshot = restoredSnapshot(for: activeRequest)
                snapshot.normalizeMeasurementScale()
                applyOverlayDisplayPreferences(from: snapshot)
                if !countCategoryOptions.contains(selectedCountCategory) {
                    selectedCountCategory = countCategoryOptions.first ?? String(localized: "点位")
                }
                lastPersistedSnapshotData = encodedSnapshotData(snapshot)
                overlayUndoStack.removeAll()
                overlayRedoStack.removeAll()
                isDeletingOverlayItem = false
                selectedTextEncoding = activeRequest.textEncoding
                selectedTextBigFont = activeRequest.textBigFont
                textSchemeSnapshot = activeRequest.textSchemeSnapshot
                currentCADViewState = activeRequest.cadViewState
                lastPersistedCADViewState = activeRequest.cadViewState
                nativeCADLayers = []
                let savedCADLayerIDs = Set(activeRequest.cadViewState.visibleLayerNames)
                nativeCADVisibleLayerIDs = activeRequest.cadViewState.usesSavedVisibleLayers && !savedCADLayerIDs.isEmpty
                    ? savedCADLayerIDs
                    : nil
                lastRendererPerformance = nil
                lastCADOpenTrace = nil
                forceFallbackForPerformance = false
                forceFallbackReason = nil
                if isCADFile, !isDWGFile, CADRendererProvider.isRendererBound {
                    cadOpenRoute = .unsupported(
                        CADOpenResult(
                            drawingId: activeRequest.drawingID,
                            openState: .unsupported,
                            message: CADViewerMessages.onlinePreviewUnavailableMessage,
                            technicalDetails: nil
                        )
                    )
                }
                Task { @MainActor in
                    if isDWGFile {
                        cadOpenRoute = .unsupported(
                            CADOpenResult(
                                drawingId: activeRequest.drawingID,
                                openState: .unsupported,
                                message: CADViewerMessages.onlinePreviewUnavailableMessage,
                                technicalDetails: nil
                            )
                        )
                    } else if isCADFile {
                        await refreshCADOpenRoute()
                    } else {
                        cadOpenRoute = .unsupported(
                            CADOpenResult(
                                drawingId: activeRequest.drawingID,
                                openState: .unsupported,
                                message: CADOpenRouter.unsupportedOnlineOpenMessage,
                                technicalDetails: nil
                            )
                        )
                    }
                }
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
            .onChange(of: selectedMeasurementColorHex) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: selectedNoteColorHex) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: hiddenOverlayGroups) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: hiddenStrokeLayers) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: hiddenOverlayColorHexes) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onChange(of: enabledSnapModes) { _, _ in
                updateOverlayDisplayPreferences()
            }
            .onDisappear {
                saveCurrentViewState()
                persistSnapshotIfNeeded(snapshot)
            }
            .confirmationDialog(String(localized: "清空批注和测量？"), isPresented: $showResetConfirm, titleVisibility: .visible) {
                Button(String(localized: "清空全部"), role: .destructive) {
                    recordUndoSnapshot()
                    var cleared = CADOverlaySnapshot()
                    cleared.metersPerDrawingUnit = snapshot.metersPerDrawingUnit
                    copyOverlayDisplayPreferences(from: snapshot, to: &cleared)
                    snapshot = cleared
                    quantityHighlightTarget = nil
                    clearInProgress()
                }
                Button(String(localized: "取消"), role: .cancel) {}
            } message: {
                Text(String(localized: "将删除本图纸的批注、测量和算量数据。"))
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
            .sheet(isPresented: $showCADDiagnosticSheet) {
                CADDiagnosticPanel {
                    cadDiagnosticSheet
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
            .sheet(isPresented: $showIssuePhotoCamera) {
                ImagePickerView(sourceType: .camera) { image in
                    appendIssueMarker(photo: image)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ActivityShareSheet(activityItems: [activeRequest.fileURL])
            }
            .fileExporter(
                isPresented: diagnosticExporterPresented,
                document: ExportDocument(
                    data: diagnosticExportPayload?.data ?? Data(),
                    sourceFileURL: diagnosticExportPayload?.sourceFileURL
                ),
                contentType: diagnosticExportPayload?.contentType ?? .zipArchive,
                defaultFilename: diagnosticExportPayload?.defaultFilename ?? "CAD诊断包.zip"
            ) { result in
                switch result {
                case .success:
                    alertMessage = String(localized: "CAD 诊断包已导出。")
                    showAlert = true
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled {
                        alertMessage = "\(String(localized: "CAD 诊断包导出失败"))：\(error.localizedDescription)"
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
            .fileExporter(
                isPresented: fallbackScreenshotExporterPresented,
                document: ExportDocument(data: fallbackScreenshotPayload?.data ?? Data()),
                contentType: fallbackScreenshotPayload?.contentType ?? .png,
                defaultFilename: fallbackScreenshotPayload?.defaultFilename ?? "CAD兼容预览反馈.png"
            ) { result in
                switch result {
                case .success:
                    alertMessage = String(localized: "CAD 兼容预览截图已导出。")
                    showAlert = true
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled {
                        alertMessage = "\(String(localized: "CAD 兼容预览截图导出失败"))：\(error.localizedDescription)"
                        showAlert = true
                    }
                }
                fallbackScreenshotPayload = nil
            }
    }

    var standardTopBar: some View {
        VStack(spacing: 8) {
            cadCommandHeader(chrome: .standard)

            if isCADFile, let hint = engineStatusHint {
                Label(
                    hint,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.appWarning)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if shouldUseCADKernelRenderer {
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

            if allowsOverlayEditing {
                cadPrimaryCommandBar(chrome: .standard)
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
                alertMessage = String(localized: "当前图纸坐标尚未就绪，已阻止写入批注、测量和数数数据。请等待图纸加载完成后重试。")
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

    func appendActiveStrokePoint(fromCanvas canvasPoint: CGPoint, force: Bool = false) {
        guard let point = storedDrawingPoint(fromCanvas: canvasPoint) else { return }
        appendActiveStrokePoint(point, force: force)
    }

    func appendActiveStrokePoint(_ point: CGPoint, force: Bool = false) {
        guard let last = activeStrokePoints.last else {
            activeStrokePoints.append(point)
            return
        }

        let distance = hypot(point.x - last.x, point.y - last.y)
        let minimumDistance = activeStrokeMinimumDrawingDistance()
        if force {
            guard distance > max(minimumDistance * 0.15, 0.000001) else { return }
            appendOrReplaceActiveStrokePoint(point)
            return
        }

        guard distance >= minimumDistance else { return }
        appendOrReplaceActiveStrokePoint(point)
    }

    func appendOrReplaceActiveStrokePoint(_ point: CGPoint) {
        guard activeStrokePoints.count < activeStrokePointLimit else {
            activeStrokePoints[activeStrokePoints.count - 1] = point
            return
        }
        activeStrokePoints.append(point)
    }

    func activeStrokeMinimumDrawingDistance() -> CGFloat {
        guard let nativeCanvasTransform else { return 0.5 }
        let baseCanvasPoint = CGPoint(
            x: nativeCanvasTransform.size.width * 0.5,
            y: nativeCanvasTransform.size.height * 0.5
        )
        let rightCanvasPoint = CGPoint(
            x: baseCanvasPoint.x + activeStrokeSamplingCanvasDistance,
            y: baseCanvasPoint.y
        )
        let p0 = nativeCanvasTransform.drawingPoint(fromCanvas: baseCanvasPoint)
        let p1 = nativeCanvasTransform.drawingPoint(fromCanvas: rightCanvasPoint)
        return max(hypot(p1.x - p0.x, p1.y - p0.y), 0.0001)
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
    func handleRendererViewState(_ rendererViewState: CADRendererViewState) {
        let layerNames = Array(Set(rendererViewState.visibleLayerNames))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let next = CADDrawingViewState(
            zoomScale: Double(rendererViewState.zoomScale),
            panOffsetX: Double(rendererViewState.panOffset.width),
            panOffsetY: Double(rendererViewState.panOffset.height),
            viewportCenterX: rendererViewState.viewportCenter.map { Double($0.x) },
            viewportCenterY: rendererViewState.viewportCenter.map { Double($0.y) },
            usesSavedVisibleLayers: rendererViewState.usesSavedVisibleLayers,
            visibleLayerNames: layerNames
        )
        currentCADViewState = next
        persistCADViewStateIfNeeded(next)
    }

    func saveCurrentViewState(showConfirmation: Bool = false) {
        persistCADViewStateIfNeeded(currentCADViewState, force: true)
        activeRequest.onTextEncodingChange(activeRequest.drawingID, selectedTextEncoding)
        activeRequest.onTextBigFontChange(activeRequest.drawingID, selectedTextBigFont)
        activeRequest.onTextSchemeSnapshotChange(activeRequest.drawingID, textSchemeSnapshot)
        if showConfirmation {
            alertMessage = String(localized: "已保存当前缩放、位置、图层显示和文字编码。")
            showAlert = true
        }
    }

    func setCADViewerMode(_ mode: CADViewerMode) {
        guard selectedCADViewerMode != mode || forceFallbackForPerformance else { return }
        cadViewerModeRaw = mode.rawValue
        forceFallbackForPerformance = false
        forceFallbackReason = nil
        lastRendererPerformance = nil
        cadOpenQuality = nil
        nativeCanvasTransform = nil
        nativeSnapPoints.removeAll()
        nativeEndpointSnapPoints.removeAll()
        nativeMidpointSnapPoints.removeAll()
        nativeCenterSnapPoints.removeAll()
        nativeSnapSourcePoints.removeAll()
        nativeSnapPointBuckets = CADNativeSnapPointBuckets()
        clearInProgress()
        cadPreviewReloadToken = UUID()
        AppHaptics.impact(.light, intensity: 0.55)
    }

    func persistCADViewStateIfNeeded(_ viewState: CADDrawingViewState, force: Bool = false) {
        guard force || viewState != lastPersistedCADViewState else { return }
        lastPersistedCADViewState = viewState
        activeRequest.onViewStateChange(activeRequest.drawingID, viewState)
        activeRequest = updatingActiveRequest(cadViewState: viewState)
    }

    @MainActor
    func handleRendererTextRepairPresetRequest(codePage: Int32?, bigFont: Int32?) {
        let encoding = textEncoding(forCodePage: codePage) ?? .gbk936
        let profile = textBigFont(forBridgeCode: bigFont) ?? .gbcbig
        applyTextPreset(
            encoding: encoding,
            bigFont: profile,
            resetAutoDetectScore: true
        )
        alertMessage = String(localized: "已切换为 \(encoding.displayName) / \(profile.displayName)。")
        showAlert = true
    }

    @MainActor
    func handleRendererSnapPoints(_ payloads: [CADRendererSnapPointPayload]) {
        let buckets = CADNativeSnapPointBuckets(sourcePoints: payloads.compactMap(CADNativeSnapSourcePoint.init))
        if buckets.sourcePoints.isEmpty {
            nativeSnapPoints.removeAll()
            nativeSnapSourcePoints.removeAll()
            nativeEndpointSnapPoints.removeAll()
            nativeMidpointSnapPoints.removeAll()
            nativeCenterSnapPoints.removeAll()
            nativeSnapPointBuckets = CADNativeSnapPointBuckets()
            return
        }

        applyNativeSnapPointBuckets(buckets)
    }

    @MainActor
    func handleRendererPerformanceSample(_ sample: CADRendererPerformanceSnapshot) {
        lastRendererPerformance = sample
    }

    @MainActor
    func handleRendererFallbackRecommendation(_ reason: String) {
        guard !forceFallbackForPerformance else { return }
        forceFallbackForPerformance = true
        forceFallbackReason = reason
        cadPreviewReloadToken = UUID()
        alertMessage = reason
        showAlert = true
    }

    @MainActor
    private func applyNativeSnapPointBuckets(_ buckets: CADNativeSnapPointBuckets) {
        nativeSnapSourcePoints = buckets.sourcePoints
        nativeSnapPoints = buckets.allPoints
        nativeEndpointSnapPoints = buckets.endpointPoints
        nativeMidpointSnapPoints = buckets.midpointPoints
        nativeCenterSnapPoints = buckets.centerPoints
        nativeSnapPointBuckets = buckets
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
            matchedFontSummary: result.matchedFontSummary,
            unresolvedFontSummary: result.unresolvedFontSummary,
            fontResolutionSummary: result.fontResolutionSummary,
            rawTextBytesHexSample: result.rawTextBytesHexSample,
            detectionSummary: result.detectionSummary ?? result.summary
        )
        applyPreviewAutoDetectedTextOptions(snapshot: snapshot)
    }

    func appendIssueMarker(photo image: UIImage?) {
        guard ensureDrawingCoordinateCaptureAvailable(showAlertIfMissing: false),
              let point = pendingIssueMarkerPoint else {
            pendingIssueMarkerPoint = nil
            showIssuePhotoCamera = false
            return
        }

        let photoFileName = image
            .flatMap { $0.jpegData(compressionQuality: 0.82) }
            .flatMap { PhotoStorage.save(original: $0, fileName: "cad-issue-\(UUID().uuidString).jpg") }
        recordUndoSnapshot()
        let marker = CADFallbackIssueMarker(
            point: CADPoint(point),
            normalizedPoint: CADPoint(normalizedFallbackPoint(fromStored: point)),
            drawingId: activeRequest.drawingID,
            layoutId: SiteKeeperCADKernel.CADLayout.modelSpace.id,
            worldPoint: CADPoint(point),
            viewportTransform: currentFallbackViewportTransform(),
            title: String(localized: "问题点 \(snapshot.issueMarkers.count + 1)"),
            note: "",
            photoFileName: photoFileName,
            layerName: nearestDrawingLayerName(toStoredPoint: point),
            measurementSummary: nearestMeasurementSummary(toStoredPoint: point),
            colorHex: "E24A7A",
            createdAt: Formatters.now()
        )
        hiddenOverlayGroups.remove(.issues)
        hiddenOverlayColorHexes.remove(issueMarkerColorHex(marker))
        snapshot.issueMarkers.append(marker)
        pendingIssueMarkerPoint = nil
        showIssuePhotoCamera = false
        AppHaptics.success()
    }

    func normalizedFallbackPoint(fromStored point: CGPoint) -> CGPoint {
        guard shouldUseFallbackViewer,
              let bounds = nativeCanvasTransform?.bounds,
              bounds.width > 0,
              bounds.height > 0 else {
            return point
        }
        return CGPoint(
            x: min(max((point.x - bounds.minX) / bounds.width, 0), 1),
            y: min(max((point.y - bounds.minY) / bounds.height, 0), 1)
        )
    }

    func currentFallbackViewportTransform() -> CADFallbackViewportTransform? {
        guard shouldUseFallbackViewer,
              let nativeCanvasTransform else { return nil }
        return CADFallbackViewportTransform(
            transform: nativeCanvasTransform,
            viewState: currentCADViewState
        )
    }

    func restoredSnapshot(for request: ProjectCADPreviewRequest) -> CADOverlaySnapshot {
        if var decoded = decodedSnapshotData(request.overlaySnapshotData, displayName: request.displayName) {
            if decoded.coordinateSpace == .canvas, !decoded.hasOverlayContent {
                decoded.coordinateSpace = .drawing
            }
            return decoded
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
        hiddenOverlayColorHexes = Set(snapshot.hiddenOverlayColorHexes.map { normalizedColorHex($0) })

        let layer = (snapshot.selectedStrokeLayerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        selectedStrokeLayer = layer.isEmpty ? String(localized: "现场批注") : layer

        selectedAnnotationColorHex = normalizedColorHex(snapshot.selectedAnnotationColorHex, fallback: "2F80ED")

        selectedMeasurementColorHex = normalizedColorHex(snapshot.selectedMeasurementColorHex, fallback: "2F80ED")
        selectedNoteColorHex = normalizedColorHex(snapshot.selectedNoteColorHex, fallback: "F2994A")

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
        snapshot.hiddenOverlayColorHexes = hiddenOverlayColorHexes.map { normalizedColorHex($0) }.sorted()
        snapshot.selectedStrokeLayerName = selectedStrokeLayer
        snapshot.selectedAnnotationColorHex = normalizedColorHex(selectedAnnotationColorHex, fallback: "2F80ED")
        snapshot.selectedMeasurementColorHex = normalizedColorHex(selectedMeasurementColorHex, fallback: "2F80ED")
        snapshot.selectedNoteColorHex = normalizedColorHex(selectedNoteColorHex, fallback: "F2994A")
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
        destination.hiddenOverlayColorHexes = source.hiddenOverlayColorHexes
        destination.customStrokeLayerNames = source.customStrokeLayerNames
        destination.customOverlayColors = source.customOverlayColors
        destination.selectedStrokeLayerName = source.selectedStrokeLayerName
        destination.selectedAnnotationColorHex = source.selectedAnnotationColorHex
        destination.selectedRedlineColorHex = source.selectedRedlineColorHex
        destination.selectedMeasurementColorHex = source.selectedMeasurementColorHex
        destination.selectedNoteColorHex = source.selectedNoteColorHex
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
        activeDragArrowPoints.removeAll()
        pendingIssueMarkerPoint = nil
        isDeletingOverlayItem = false
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
        case .annotation, .cloud:
            hiddenOverlayGroups.remove(.annotation)
            if selectedStrokeLayer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectedStrokeLayer = String(localized: "现场批注")
            }
        case .length, .continuousLength, .area:
            hiddenOverlayGroups.remove(.measurement)
        case .arrow:
            hiddenOverlayGroups.remove(.annotation)
        case .note:
            hiddenOverlayGroups.remove(.notes)
        case .issueMarker:
            hiddenOverlayGroups.remove(.issues)
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
        recordUndoSnapshot()
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

        var rendererReport: String?
        var reporterErrorMessage: String?
        do {
            rendererReport = try await CADRendererProvider.makeDiagnosticReport(
                for: activeRequest.fileURL,
                preferredTextCodePage: selectedTextEncoding.codePageOverride,
                preferredTextBigFont: selectedTextBigFont.bridgeCode
            )
        } catch {
            reporterErrorMessage = "\(String(localized: "CAD 内核诊断生成失败"))：\(error.localizedDescription)"
            StorageIssueLog.record("CAD 诊断日志生成失败：\(activeRequest.displayName)，\(error.localizedDescription)")
        }

        do {
            let report = fallbackDiagnosticLog(
                extraMessage: reporterErrorMessage,
                rendererReport: rendererReport
            )
            diagnosticExportPayload = try diagnosticPackagePayload(humanReport: report)
        } catch {
            let report = fallbackDiagnosticLog(
                extraMessage: "\(String(localized: "CAD 诊断包生成失败"))：\(error.localizedDescription)",
                rendererReport: rendererReport
            )
            StorageIssueLog.record("CAD 诊断包生成失败：\(activeRequest.displayName)，\(error.localizedDescription)")
            diagnosticExportPayload = ExportPayload(
                data: Data(report.utf8),
                contentType: .plainText,
                defaultFilename: diagnosticLogFileName()
            )
        }
    }

    func diagnosticBaseName() -> String {
        let baseName = activeRequest.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        return baseName.isEmpty ? activeRequest.fileURL.deletingPathExtension().lastPathComponent : baseName
    }

    func diagnosticPackageFileName() -> String {
        "\(diagnosticBaseName())_CAD诊断包.zip"
    }

    func diagnosticLogFileName() -> String {
        "\(diagnosticBaseName())_CAD诊断日志.txt"
    }

    func diagnosticReportFileName() -> String {
        "diagnostic_report.txt"
    }

    func diagnosticMachineTraceFileName() -> String {
        "pipeline_trace.json"
    }

    func diagnosticPackagePayload(humanReport: String) throws -> ExportPayload {
        var zip = SimpleZipArchiveBuilder()
        zip.addFile(path: diagnosticReportFileName(), data: Data(humanReport.utf8))
        zip.addFile(path: diagnosticMachineTraceFileName(), data: try diagnosticMachineTraceData())
        return ExportPayload(
            data: zip.build(),
            contentType: .zipArchive,
            defaultFilename: diagnosticPackageFileName()
        )
    }

    func fallbackScreenshotFileName() -> String {
        let baseName = activeRequest.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
        let name = baseName.isEmpty ? activeRequest.fileURL.deletingPathExtension().lastPathComponent : baseName
        return "\(name)_兼容预览反馈.png"
    }

    func fallbackDiagnosticLog(extraMessage: String? = nil, rendererReport: String? = nil) -> String {
        var lines: [String] = []
        lines.append(String(localized: "CAD 技术排查报告"))
        lines.append("\(String(localized: "生成时间"))：\(Formatters.dateTime.string(from: Date()))")
        lines.append("")
        lines.append("## \(String(localized: "文件"))")
        lines.append("\(String(localized: "文件名"))：\(activeRequest.fileURL.lastPathComponent)")
        lines.append("\(String(localized: "路径"))：\(activeRequest.fileURL.path)")
        lines.append("\(String(localized: "类型"))：\(activeRequest.fileType.uppercased())")
        lines.append("\(String(localized: "大小"))：\(fallbackFileSizeText())")
        lines.append("\(String(localized: "文件头 Hex"))：\(fallbackHeaderHex())")
        lines.append("\(String(localized: "源文件写入"))：\(String(localized: "否（批注、测量、文字编码和字体设置只保存在应用项目数据中）"))")
        lines.append("\(String(localized: "机器 trace"))：\(diagnosticMachineTraceFileName())")
        lines.append("")
        lines.append("## \(String(localized: "预览环境"))")
        lines.append("\(String(localized: "CAD 看图内核可用"))：\(CADDrawingCapability.isCADEngineInstalled() ? String(localized: "是") : String(localized: "否"))")
        lines.append("\(String(localized: "Renderer 已绑定"))：\(CADRendererProvider.isRendererBound ? String(localized: "是") : String(localized: "否"))")
        lines.append("\(String(localized: "看图模式"))：\(selectedCADViewerMode.title)")
        let pipeline = diagnosticPipeline()
        lines.append("\(String(localized: "结论"))：\(pipeline.conclusion)")
        lines.append("failureLayer：\(pipeline.failureLayer)")
        lines.append("failureStage：\(pipeline.failureStage)")
        if forceFallbackForPerformance {
            lines.append("\(String(localized: "性能降级"))：\(String(localized: "是"))")
            lines.append("\(String(localized: "降级原因"))：\(forceFallbackReason ?? "-")")
        }
        if let performance = lastRendererPerformance {
            lines.append("\(String(localized: "性能采样"))：visible=\(performance.visibleEntityCount), commands=\(performance.renderCommandCount), textCommands=\(performance.textCommandCount), textOverlays=\(performance.textOverlayCount), renderMs=\(Int(performance.renderMs))ms, firstFrameMs=\(Int(performance.firstFrameMs))ms, skipped=\(performance.skippedEntityCount), layers=\(performance.visibleLayerCount)")
            if performance.textCommandCount > 0 && performance.textOverlayCount == 0 {
                lines.append("\(String(localized: "文字渲染诊断"))：CAD 已生成文字命令，但当前帧没有可见文字贴图；优先检查 viewport、文字坐标、图层和字体栅格化。")
            }
        }
        if shouldUseFallbackViewer {
            let outputs = CADFallbackOutputResolver.resolve(fileURL: activeRequest.fileURL)
            lines.append("\(String(localized: "兼容预览输出"))：\(outputs.summary)")
        }
        lines.append("\(String(localized: "当前文字编码"))：\(selectedTextEncoding.displayName)")
        lines.append("\(String(localized: "当前 SHX/大字体"))：\(selectedTextBigFont.displayName)")
        if !activeRequest.projectFontMappings.isEmpty {
            lines.append("\(String(localized: "本项目字体映射"))：")
            for mapping in projectFontMappingRows.prefix(12) {
                lines.append("- \(mapping.source.displayName)：\(mapping.pattern) -> \(mapping.bigFont.displayName)")
            }
        }
        if let codePage = textSchemeSnapshot.codePage {
            lines.append("\(String(localized: "当前命中编码"))：\(codePageDisplayName(codePage))")
        }
        if let styleName = textSchemeSnapshot.styleName {
            lines.append("\(String(localized: "当前样式"))：\(styleName)")
        }
        if let fontFile = textSchemeSnapshot.fontFile {
            lines.append("\(String(localized: "当前字体"))：\(fontFile)")
        }
        if let bigFontFile = textSchemeSnapshot.bigFontFile {
            lines.append("\(String(localized: "当前大字体文件"))：\(bigFontFile)")
        }
        if let score = textSchemeSnapshot.autoDetectScore {
            lines.append("\(String(localized: "自动识别评分"))：\(score)")
        }
        if let styleSummary = textSchemeSnapshot.styleSummary, !styleSummary.isEmpty {
            lines.append("\(String(localized: "STYLE 表"))：\(styleSummary)")
        }
        if let matchedFontSummary = textSchemeSnapshot.matchedFontSummary, !matchedFontSummary.isEmpty {
            lines.append("\(String(localized: "已匹配字体"))：\(matchedFontSummary)")
        }
        if let unresolvedFontSummary = textSchemeSnapshot.unresolvedFontSummary, !unresolvedFontSummary.isEmpty {
            lines.append("\(String(localized: "未匹配字体"))：\(unresolvedFontSummary)")
        }
        if let fontResolutionSummary = textSchemeSnapshot.fontResolutionSummary, !fontResolutionSummary.isEmpty {
            lines.append("\(String(localized: "字体解析"))：\(fontResolutionSummary)")
        }
        if let rawSample = textSchemeSnapshot.rawTextBytesHexSample, !rawSample.isEmpty {
            lines.append("raw text bytes：\(rawSample)")
        }
        if let summary = textSchemeSnapshot.detectionSummary, !summary.isEmpty {
            lines.append("\(String(localized: "识别摘要"))：\(summary)")
        }
        if let engineStatusHint {
            lines.append("\(String(localized: "提示"))：\(engineStatusHint)")
        }
        if let rendererReport, !rendererReport.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("## \(String(localized: "内核报告"))")
            lines.append(rendererReport)
        }
        if let extraMessage {
            lines.append("")
            lines.append("## \(String(localized: "诊断生成错误"))")
            lines.append(extraMessage)
        }
        return lines.joined(separator: "\n")
    }

    func diagnosticMachineTraceData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(diagnosticMachineTrace())
    }

    func diagnosticMachineTrace() -> CADDiagnosticMachineTrace {
        let kernelTrace = cadOpenTechnicalDetails?.pipelineTrace
        let nativeTrace = lastCADOpenTrace
        let pipeline = diagnosticPipeline(kernelTrace: kernelTrace, nativeTrace: nativeTrace)
        let counts = diagnosticCounts(kernelTrace: kernelTrace, nativeTrace: nativeTrace)
        let diagnostics = cadOpenTechnicalDetails?.diagnostics ?? []
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

        return CADDiagnosticMachineTrace(
            schemaVersion: 1,
            traceKind: "sitekeeper.cad.open",
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            humanReportFile: diagnosticReportFileName(),
            machineTraceFile: diagnosticMachineTraceFileName(),
            file: CADDiagnosticMachineTrace.FileInfo(
                displayName: activeRequest.displayName,
                path: activeRequest.fileURL.path,
                fileType: activeRequest.fileType.uppercased(),
                fileByteCount: diagnosticFileByteCount(),
                headerHex: fallbackHeaderHex(),
                importedAt: activeRequest.importedAt
            ),
            environment: CADDiagnosticMachineTrace.Environment(
                appVersion: appVersion,
                buildNumber: buildNumber,
                cadEngineInstalled: CADDrawingCapability.isCADEngineInstalled(),
                rendererBound: CADRendererProvider.isRendererBound,
                viewerMode: selectedCADViewerMode.rawValue,
                fallbackViewerActive: shouldUseFallbackViewer,
                performanceFallbackActive: forceFallbackForPerformance,
                performanceFallbackReason: forceFallbackReason
            ),
            pipeline: pipeline,
            counts: counts,
            text: CADDiagnosticMachineTrace.TextState(
                selectedEncoding: selectedTextEncoding.rawValue,
                selectedBigFont: selectedTextBigFont.rawValue,
                codePageOverride: selectedTextEncoding.codePageOverride,
                bigFontCode: selectedTextBigFont.bridgeCode,
                detectedCodePage: textSchemeSnapshot.codePage.map(codePageDisplayName),
                detectedStyleName: textSchemeSnapshot.styleName,
                detectedFontFile: textSchemeSnapshot.fontFile,
                detectedBigFontFile: textSchemeSnapshot.bigFontFile,
                autoDetectScore: textSchemeSnapshot.autoDetectScore,
                unresolvedFontSummary: textSchemeSnapshot.unresolvedFontSummary,
                fontResolutionSummary: textSchemeSnapshot.fontResolutionSummary,
                rawTextBytesHexSample: textSchemeSnapshot.rawTextBytesHexSample
            ),
            performance: lastRendererPerformance.map { performance in
                CADDiagnosticMachineTrace.Performance(
                    entityCountInViewport: performance.entityCountInViewport,
                    drawCallCount: performance.drawCallCount,
                    frameTimeMilliseconds: performance.frameTimeMilliseconds,
                    skippedEntityCount: performance.skippedEntityCount,
                    visibleLayerCount: performance.visibleLayerCount,
                    simplifiedMode: performance.simplifiedMode,
                    renderCommandCount: performance.renderCommandCount,
                    textCommandCount: performance.textCommandCount,
                    textOverlayCount: performance.textOverlayCount,
                    renderMilliseconds: performance.renderMs,
                    firstFrameMilliseconds: performance.firstFrameMs
                )
            },
            openQuality: cadOpenQuality.map { quality in
                CADDiagnosticMachineTrace.OpenQuality(
                    level: quality.level,
                    title: quality.title,
                    summary: quality.summary,
                    allowsMarkup: quality.allowsMarkup,
                    supportsSearch: quality.supportsSearch,
                    detailLines: quality.detailLines
                )
            },
            kernelTrace: kernelTrace.map(CADDiagnosticMachineTrace.KernelTrace.init),
            nativeTrace: nativeTrace.map(CADDiagnosticMachineTrace.NativeTrace.init),
            diagnostics: diagnostics,
            notes: diagnosticNotes(pipeline: pipeline, diagnostics: diagnostics)
        )
    }

    func diagnosticPipeline(
        kernelTrace: SiteKeeperCADKernel.DWGOpenPipelineTrace? = nil,
        nativeTrace: CADPoC.CADOpenTrace? = nil
    ) -> CADDiagnosticMachineTrace.Pipeline {
        if let kernelTrace {
            let failureLayer = diagnosticFailureLayer(kernelTrace)
            return CADDiagnosticMachineTrace.Pipeline(
                failureLayer: failureLayer,
                failureStage: kernelTrace.failureStage,
                openState: kernelTrace.openState.rawValue,
                importSource: cadOpenTechnicalDetails?.importEngine,
                conclusion: diagnosticConclusion(for: failureLayer),
                traceSource: "kernel_pipeline_trace"
            )
        }

        if let nativeTrace {
            let failureLayer = diagnosticFailureLayer(nativeTrace)
            return CADDiagnosticMachineTrace.Pipeline(
                failureLayer: failureLayer,
                failureStage: nativeTrace.openedForRender ? "rendered" : failureLayer,
                openState: nativeTrace.openedForRender ? "rendered" : "unsupported",
                importSource: nativeTrace.importSource,
                conclusion: diagnosticConclusion(for: failureLayer),
                traceSource: "native_canvas_trace"
            )
        }

        let failureLayer = CADRendererProvider.isRendererBound ? "unknown" : "render"
        return CADDiagnosticMachineTrace.Pipeline(
            failureLayer: failureLayer,
            failureStage: CADRendererProvider.isRendererBound ? "missing_trace" : "renderer_unbound",
            openState: currentOpenStateRawValue(),
            importSource: cadOpenTechnicalDetails?.importEngine,
            conclusion: diagnosticConclusion(for: failureLayer),
            traceSource: "fallback_context"
        )
    }

    func diagnosticCounts(
        kernelTrace: SiteKeeperCADKernel.DWGOpenPipelineTrace?,
        nativeTrace: CADPoC.CADOpenTrace?
    ) -> CADDiagnosticMachineTrace.Counts {
        if let kernelTrace {
            return CADDiagnosticMachineTrace.Counts(
                rawEntityCount: max(kernelTrace.jsonRawEntityCount, kernelTrace.dxfRawEntityCount),
                adapterEntityCount: kernelTrace.adapterEntityCount,
                databaseEntityCount: kernelTrace.databaseEntityCount,
                drawableEntityCount: kernelTrace.drawableEntityCount,
                renderCommandCount: kernelTrace.renderCommandCount,
                visibleLayerCount: kernelTrace.visibleLayerCount
            )
        }

        if let nativeTrace {
            let rawCount = CADDiagnosticMachineTrace.NativeTrace(nativeTrace).rawEntityCounts.total
            return CADDiagnosticMachineTrace.Counts(
                rawEntityCount: rawCount,
                adapterEntityCount: nativeTrace.entityCount,
                databaseEntityCount: nativeTrace.entityCount,
                drawableEntityCount: nativeTrace.drawableEntityCount,
                renderCommandCount: nativeTrace.renderCommandCount,
                visibleLayerCount: nativeCADVisibleLayerIDs?.count ?? nativeCADLayers.filter(\.isVisible).count
            )
        }

        return CADDiagnosticMachineTrace.Counts(
            rawEntityCount: 0,
            adapterEntityCount: 0,
            databaseEntityCount: cadOpenTechnicalDetails?.pipelineTrace?.databaseEntityCount ?? 0,
            drawableEntityCount: cadOpenTechnicalDetails?.drawableEntityCount ?? 0,
            renderCommandCount: lastRendererPerformance?.renderCommandCount ?? 0,
            visibleLayerCount: lastRendererPerformance?.visibleLayerCount ?? nativeCADVisibleLayerIDs?.count ?? nativeCADLayers.count
        )
    }

    func diagnosticFailureLayer(_ trace: SiteKeeperCADKernel.DWGOpenPipelineTrace) -> String {
        if trace.openState == .rendered || trace.failureStage == "rendered" {
            return "none"
        }
        if trace.jsonRawEntityCount == 0,
           trace.dxfRawEntityCount == 0,
           trace.adapterEntityCount == 0,
           trace.databaseEntityCount == 0 {
            return "libredwg"
        }
        if trace.adapterEntityCount == 0 { return "adapter" }
        if trace.drawableEntityCount == 0 { return "database" }
        if trace.renderCommandCount == 0 { return "render" }

        let stage = trace.failureStage.lowercased()
        if stage.contains("libredwg") || stage.contains("geometry_source") || stage.contains("import") {
            return "libredwg"
        }
        if stage.contains("adapter") { return "adapter" }
        if stage.contains("database") || stage.contains("drawable") { return "database" }
        if stage.contains("render") { return "render" }
        return "unknown"
    }

    func diagnosticFailureLayer(_ trace: CADPoC.CADOpenTrace) -> String {
        if trace.openedForRender {
            return "none"
        }
        let rawCount = CADDiagnosticMachineTrace.NativeTrace(trace).rawEntityCounts.total
        if rawCount == 0 { return "libredwg" }
        if trace.entityCount == 0 { return "adapter" }
        if trace.drawableEntityCount == 0 { return "database" }
        if trace.renderCommandCount == 0 { return "render" }
        return "unknown"
    }

    func diagnosticConclusion(for failureLayer: String) -> String {
        switch failureLayer {
        case "none":
            return "CAD pipeline reached renderable output."
        case "libredwg":
            return "LibreDWG did not provide drawable geometry."
        case "adapter":
            return "Raw geometry exists but adapter produced no database entities."
        case "database":
            return "Database entities exist but no drawable entities are available."
        case "render":
            return "Drawable entities exist but render commands are unavailable."
        default:
            return "CAD pipeline failure layer is unknown."
        }
    }

    func currentOpenStateRawValue() -> String {
        switch cadOpenRoute {
        case .online(let result), .unsupported(let result):
            switch result.openState {
            case .rendered:
                return "rendered"
            case .unsupported:
                return "unsupported"
            case .failed:
                return "failed"
            }
        }
    }

    func diagnosticNotes(pipeline: CADDiagnosticMachineTrace.Pipeline, diagnostics: [String]) -> [String] {
        var notes: [String] = []
        if pipeline.failureLayer == "libredwg" {
            notes.append("Stop at LibreDWG until raw drawable geometry is available.")
        }
        if diagnostics.isEmpty {
            notes.append("No kernel diagnostics were attached to this export.")
        }
        return notes
    }

    func fallbackFileSizeText() -> String {
        let bytes = diagnosticFileByteCount()
        guard bytes > 0 else { return "-" }
        return QuickNoteAttachmentStorage.formattedFileSize(bytes)
    }

    func diagnosticFileByteCount() -> Int {
        do {
            let values = try activeRequest.fileURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            return values.fileSize ?? values.totalFileAllocatedSize ?? activeRequest.fileSizeBytes
        } catch {
            return activeRequest.fileSizeBytes
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
        colorFromHex(strokeColorHex(stroke), fallback: strokeColor(stroke.kind))
    }

    func strokeColor(_ kind: CADStroke.StrokeKind) -> Color {
        .appPrimaryAction
    }

    func selectedStrokeColorHex(for kind: CADStroke.StrokeKind) -> String {
        normalizedColorHex(selectedAnnotationColorHex, fallback: defaultStrokeColorHex(for: kind))
    }

    func defaultStrokeColorHex(for kind: CADStroke.StrokeKind) -> String {
        "2F80ED"
    }

    func strokeColorHex(_ stroke: CADStroke) -> String {
        normalizedColorHex(stroke.colorHex, fallback: defaultStrokeColorHex(for: stroke.kind))
    }

    func lengthMeasurementColorHex(_ measurement: CADLengthMeasurement) -> String {
        normalizedColorHex(measurement.colorHex, fallback: "2F80ED")
    }

    func areaMeasurementColorHex(_ measurement: CADAreaMeasurement) -> String {
        normalizedColorHex(measurement.colorHex, fallback: "67A866")
    }

    func noteColorHex(_ note: CADTextNote) -> String {
        normalizedColorHex(note.colorHex, fallback: "F2994A")
    }

    func arrowColorHex(_ arrow: CADArrowAnnotation) -> String {
        normalizedColorHex(arrow.colorHex, fallback: "2F80ED")
    }

    func issueMarkerColorHex(_ marker: CADFallbackIssueMarker) -> String {
        normalizedColorHex(marker.colorHex, fallback: "E24A7A")
    }

    func selectedMeasurementOverlayColorHex() -> String {
        normalizedColorHex(selectedMeasurementColorHex, fallback: "2F80ED")
    }

    func selectedNoteOverlayColorHex() -> String {
        normalizedColorHex(selectedNoteColorHex, fallback: "F2994A")
    }

    func strokeLayerName(_ stroke: CADStroke) -> String {
        let text = (stroke.layerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(localized: "现场批注") : text
    }

    func strokeLayerName(_ arrow: CADArrowAnnotation) -> String {
        let text = (arrow.layerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(localized: "现场批注") : text
    }

    func isOverlayGroupVisible(_ group: CADOverlayVisibilityGroup) -> Bool {
        !hiddenOverlayGroups.contains(group)
    }

    func isStrokeLayerVisible(_ layer: String) -> Bool {
        !hiddenStrokeLayers.contains(layer)
    }

    func isOverlayColorVisible(_ hex: String) -> Bool {
        !hiddenOverlayColorHexes.contains(normalizedColorHex(hex))
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

    func overlayColorVisibleBinding(_ hex: String) -> Binding<Bool> {
        let normalized = normalizedColorHex(hex)
        return Binding(
            get: { isOverlayColorVisible(normalized) },
            set: { isVisible in
                if isVisible {
                    hiddenOverlayColorHexes.remove(normalized)
                } else {
                    hiddenOverlayColorHexes.insert(normalized)
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
        case .measurement:
            return snapshot.lengthMeasurements.count + snapshot.areaMeasurements.count
        case .notes:
            return snapshot.notes.count
        case .counts:
            return snapshot.countMarkers.count
        case .issues:
            return snapshot.issueMarkers.count
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

    func normalizedColorHex(_ hex: String?, fallback: String = "2F80ED") -> String {
        let cleaned = (hex ?? "").trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        if cleaned.count == 6, UInt64(cleaned, radix: 16) != nil {
            return cleaned
        }
        let fallbackCleaned = fallback.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
        return fallbackCleaned.count == 6 ? fallbackCleaned : "2F80ED"
    }

    func hexString(from color: Color) -> String? {
#if os(iOS)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        return String(
            format: "%02X%02X%02X",
            Int(round(red * 255)),
            Int(round(green * 255)),
            Int(round(blue * 255))
        )
#else
        return nil
#endif
    }

    func addCustomStrokeLayer() {
        let layer = newOverlayLayerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !layer.isEmpty else { return }
        if !snapshot.customStrokeLayerNames.contains(layer) {
            snapshot.customStrokeLayerNames.append(layer)
        }
        selectedStrokeLayer = layer
        hiddenStrokeLayers.remove(layer)
        newOverlayLayerName = ""
        updateOverlayDisplayPreferences()
        AppHaptics.impact(.light, intensity: 0.55)
    }

    @discardableResult
    func addCustomOverlayColor(_ color: Color) -> String? {
        guard let hex = hexString(from: color) else { return nil }
        let normalized = normalizedColorHex(hex)
        if !snapshot.customOverlayColors.contains(where: { normalizedColorHex($0.hex) == normalized }) {
            snapshot.customOverlayColors.append(
                CADOverlayColorOption(name: "#\(normalized)", hex: normalized)
            )
        }
        hiddenOverlayColorHexes.remove(normalized)
        AppHaptics.impact(.light, intensity: 0.55)
        return normalized
    }

    func colorDisplayName(for hex: String) -> String {
        let normalized = normalizedColorHex(hex)
        if let option = overlayColorOptions.first(where: { normalizedColorHex($0.hex) == normalized }) {
            return option.name
        }
        return "#\(normalized)"
    }

    func overlayColorItemCount(for hex: String) -> Int {
        let normalized = normalizedColorHex(hex)
        let strokeCount = snapshot.strokes.filter { strokeColorHex($0) == normalized }.count
        let arrowCount = snapshot.arrowAnnotations.filter { arrowColorHex($0) == normalized }.count
        let lengthCount = snapshot.lengthMeasurements.filter { lengthMeasurementColorHex($0) == normalized }.count
        let areaCount = snapshot.areaMeasurements.filter { areaMeasurementColorHex($0) == normalized }.count
        let noteCount = snapshot.notes.filter { noteColorHex($0) == normalized }.count
        let issueCount = snapshot.issueMarkers.filter { issueMarkerColorHex($0) == normalized }.count
        return strokeCount + arrowCount + lengthCount + areaCount + noteCount + issueCount
    }

    func overlayStrokeWidth(for tool: CADOverlayTool) -> Double {
        switch tool {
        case .annotation:
            return 4
        case .cloud:
            return 3.4
        case .arrow:
            return 2.4
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

    func closedPath(points: [CGPoint]) -> Path {
        var path = pathView(points: points)
        if points.count >= 3 {
            path.closeSubpath()
        }
        return path
    }

    func measurementPolyline(_ points: [CGPoint]) -> Path {
        pathView(points: points)
    }

    func arrowShape(start: CGPoint, end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 14
        let wing: CGFloat = .pi * 0.78
        let p1 = CGPoint(x: end.x + cos(angle + wing) * length, y: end.y + sin(angle + wing) * length)
        let p2 = CGPoint(x: end.x + cos(angle - wing) * length, y: end.y + sin(angle - wing) * length)
        path.move(to: p1)
        path.addLine(to: end)
        path.addLine(to: p2)
        return path
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

    func issueMarkerBadge(_ marker: CADFallbackIssueMarker) -> some View {
        HStack(spacing: 6) {
            Image(systemName: marker.photoFileName == nil ? "mappin.circle.fill" : "camera.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(5)
                .background(colorFromHex(issueMarkerColorHex(marker), fallback: Color.appRisk), in: Circle())
            Text(marker.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        .overlay(
            Capsule().stroke(colorFromHex(issueMarkerColorHex(marker), fallback: Color.appRisk), lineWidth: 1)
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
        recordUndoSnapshot()
        let measurement = CADLengthMeasurement(
            points: pendingLengthPoints.map(CADPoint.init),
            name: "\(String(localized: "连续长度")) \(snapshot.lengthMeasurements.count + 1)",
            colorHex: selectedMeasurementOverlayColorHex()
        )
        hiddenOverlayColorHexes.remove(lengthMeasurementColorHex(measurement))
        snapshot.lengthMeasurements.append(measurement)
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
            recordUndoSnapshot()
            let measurement = CADAreaMeasurement(
                points: points.map(CADPoint.init),
                name: "\(String(localized: "面积")) \(snapshot.areaMeasurements.count + 1)",
                colorHex: selectedMeasurementOverlayColorHex()
            )
            hiddenOverlayColorHexes.remove(areaMeasurementColorHex(measurement))
            snapshot.areaMeasurements.append(measurement)
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
        recordUndoSnapshot()
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
        recordUndoSnapshot()
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
        recordUndoSnapshot()
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

    func appendManualQuantityItem() {
        recordUndoSnapshot()
        snapshot.quantityItems.append(
            CADQuantityItem(
                name: String(localized: "新条目"),
                unit: String(localized: "项"),
                quantity: "1",
                unitPrice: "0",
                wasteRate: "0",
                source: String(localized: "手动"),
                sourceLinkKind: .manual
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
            name: .cadFocusSourcePoint,
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
        snapshot.strokes.count + snapshot.arrowAnnotations.count
    }

    func updateSelectedStrokeLayer(_ layer: String) {
        guard let index = selectedStrokeIndex else { return }
        guard snapshot.strokes[index].layerName != layer else { return }
        recordUndoSnapshot()
        snapshot.strokes[index].layerName = layer
        hiddenStrokeLayers.remove(layer)
    }

    func updateSelectedStrokeColor(_ hex: String) {
        guard let index = selectedStrokeIndex else { return }
        guard snapshot.strokes[index].colorHex != hex else { return }
        recordUndoSnapshot()
        snapshot.strokes[index].colorHex = hex
    }

    func deleteSelectedStroke() {
        guard let index = selectedStrokeIndex else { return }
        recordUndoSnapshot()
        snapshot.strokes.remove(at: index)
        selectedStrokeID = nil
    }

    var canUndoOverlayChange: Bool {
        !overlayUndoStack.isEmpty
    }

    var canRedoOverlayChange: Bool {
        !overlayRedoStack.isEmpty
    }

    var hasVisibleDeletableOverlayContent: Bool {
        !visibleStrokes.isEmpty ||
        !visibleArrows.isEmpty ||
        !visibleLengthMeasurements.isEmpty ||
        !visibleAreaMeasurements.isEmpty ||
        !visibleNotes.isEmpty ||
        !visibleIssueMarkers.isEmpty ||
        (isOverlayGroupVisible(.counts) && !snapshot.countMarkers.isEmpty)
    }

    var canDeleteCurrentOverlayItem: Bool {
        selectedStrokeIndex != nil || hasVisibleDeletableOverlayContent
    }

    func recordUndoSnapshot() {
        guard overlayUndoStack.last != snapshot else { return }
        overlayUndoStack.append(snapshot)
        if overlayUndoStack.count > overlayUndoLimit {
            overlayUndoStack.removeFirst(overlayUndoStack.count - overlayUndoLimit)
        }
        overlayRedoStack.removeAll()
    }

    func appendUndoSnapshotForHistory(_ value: CADOverlaySnapshot) {
        guard overlayUndoStack.last != value else { return }
        overlayUndoStack.append(value)
        if overlayUndoStack.count > overlayUndoLimit {
            overlayUndoStack.removeFirst(overlayUndoStack.count - overlayUndoLimit)
        }
    }

    func appendRedoSnapshotForHistory(_ value: CADOverlaySnapshot) {
        guard overlayRedoStack.last != value else { return }
        overlayRedoStack.append(value)
        if overlayRedoStack.count > overlayUndoLimit {
            overlayRedoStack.removeFirst(overlayRedoStack.count - overlayUndoLimit)
        }
    }

    func restoreOverlaySnapshotFromHistory(_ value: CADOverlaySnapshot) {
        snapshot = value
        applyOverlayDisplayPreferences(from: value)
        selectedStrokeID = nil
        quantityHighlightTarget = nil
        clearInProgress()
    }

    func undoLastOverlayChange() {
        guard let previous = overlayUndoStack.popLast() else { return }
        appendRedoSnapshotForHistory(snapshot)
        restoreOverlaySnapshotFromHistory(previous)
        AppHaptics.impact(.light, intensity: 0.55)
    }

    func redoOverlayChange() {
        guard let next = overlayRedoStack.popLast() else { return }
        appendUndoSnapshotForHistory(snapshot)
        restoreOverlaySnapshotFromHistory(next)
        AppHaptics.impact(.light, intensity: 0.55)
    }

    func deleteCurrentOverlayItem() {
        guard canDeleteCurrentOverlayItem || isDeletingOverlayItem else { return }
        let shouldEnterDeleteMode = !isDeletingOverlayItem
        clearInProgress()
        tool = .browse
        selectedStrokeID = nil
        quantityHighlightTarget = nil
        isSelectingStroke = false
        isDeletingOverlayItem = shouldEnterDeleteMode
        AppHaptics.impact(.light, intensity: shouldEnterDeleteMode ? 0.65 : 0.45)
    }

    func deleteOverlayItem(atCanvasPoint point: CGPoint) {
        guard let target = nearestOverlayDeleteTarget(toCanvasPoint: point) else {
            AppHaptics.warning()
            return
        }
        guard deleteOverlayTarget(target) else {
            AppHaptics.warning()
            return
        }
        selectedStrokeID = nil
        quantityHighlightTarget = nil
        isDeletingOverlayItem = false
        AppHaptics.success()
    }

    func deleteOverlayTarget(_ target: CADOverlayDeleteTarget) -> Bool {
        switch target {
        case .stroke(let id):
            guard let index = snapshot.strokes.firstIndex(where: { $0.id == id }) else { return false }
            recordUndoSnapshot()
            snapshot.strokes.remove(at: index)
        case .length(let id):
            guard let index = snapshot.lengthMeasurements.firstIndex(where: { $0.id == id }) else { return false }
            recordUndoSnapshot()
            snapshot.lengthMeasurements.remove(at: index)
        case .area(let id):
            guard let index = snapshot.areaMeasurements.firstIndex(where: { $0.id == id }) else { return false }
            recordUndoSnapshot()
            snapshot.areaMeasurements.remove(at: index)
        case .arrow(let id):
            guard let index = snapshot.arrowAnnotations.firstIndex(where: { $0.id == id }) else { return false }
            recordUndoSnapshot()
            snapshot.arrowAnnotations.remove(at: index)
        case .note(let id):
            guard let index = snapshot.notes.firstIndex(where: { $0.id == id }) else { return false }
            recordUndoSnapshot()
            snapshot.notes.remove(at: index)
        case .issue(let id):
            guard let index = snapshot.issueMarkers.firstIndex(where: { $0.id == id }) else { return false }
            recordUndoSnapshot()
            snapshot.issueMarkers.remove(at: index)
        case .count(let id):
            guard let index = snapshot.countMarkers.firstIndex(where: { $0.id == id }) else { return false }
            recordUndoSnapshot()
            snapshot.countMarkers.remove(at: index)
        }
        return true
    }

    var overlaySnapCandidates: [CGPoint] {
        var points: [CGPoint] = []
        if hasNativeDrawingCoordinateSpace {
            let buckets = nativeSnapPointBuckets.isEmpty ? fallbackNativeSnapPointBuckets() : nativeSnapPointBuckets
            points.append(contentsOf: buckets.points(
                enabledModes: enabledSnapModes,
                measurementOnly: tool.usesMeasurementSnapPrimitives
            ))
        }
        if isOverlayGroupVisible(.counts) {
            points.append(contentsOf: snapshot.countMarkers.map { $0.point.cgPoint })
        }
        for arrow in visibleArrows {
            points.append(arrow.start.cgPoint)
            points.append(arrow.end.cgPoint)
        }
        points.append(contentsOf: visibleNotes.map { $0.point.cgPoint })
        points.append(contentsOf: visibleIssueMarkers.map { $0.point.cgPoint })
        for measurement in visibleLengthMeasurements {
            points.append(contentsOf: measurement.points.map(\.cgPoint))
        }
        for measurement in visibleAreaMeasurements {
            points.append(contentsOf: measurement.points.map(\.cgPoint))
        }
        points.append(contentsOf: pendingLengthPoints)
        points.append(contentsOf: pendingAreaPoints)
        points.append(contentsOf: activeDragLengthPoints)
        points.append(contentsOf: activeDragArrowPoints)
        return points
    }

    private func fallbackNativeSnapPointBuckets() -> CADNativeSnapPointBuckets {
        var result: [CADNativeSnapSourcePoint] = []
        func append(_ point: CGPoint, kind: CADNativeSnapPointKind, primitiveKind: CADNativePrimitiveKind) {
            result.append(
                CADNativeSnapSourcePoint(
                    point: point,
                    snapKind: kind,
                    layer: "0",
                    primitiveKind: primitiveKind,
                    styleRGB: 0,
                    styleWidth: 1,
                    styleName: nil
                )
            )
        }
        nativeEndpointSnapPoints.forEach { append($0, kind: .endpoint, primitiveKind: .line) }
        nativeMidpointSnapPoints.forEach { append($0, kind: .midpoint, primitiveKind: .line) }
        nativeCenterSnapPoints.forEach { append($0, kind: .center, primitiveKind: .circle) }
        if result.isEmpty {
            nativeSnapPoints.forEach { append($0, kind: .endpoint, primitiveKind: .line) }
        }
        return CADNativeSnapPointBuckets(sourcePoints: result)
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
        guard isOverlayGroupVisible(.counts) else { return nil }
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
            guard isOverlayGroupVisible(.notes),
                  isOverlayColorVisible(noteColorHex(note)) else { continue }
            let target = canvasPoint(fromStored: note.point.cgPoint)
            let distance = hypot(target.x - point.x, target.y - point.y)
            if distance <= bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    func nearestOverlayDeleteTarget(toCanvasPoint point: CGPoint) -> CADOverlayDeleteTarget? {
        var bestTarget: CADOverlayDeleteTarget?
        var bestDistance = max(overlaySnapTolerance, 24)

        func consider(_ target: CADOverlayDeleteTarget, distance: CGFloat) {
            guard distance <= bestDistance else { return }
            bestDistance = distance
            bestTarget = target
        }

        for stroke in visibleStrokes {
            let renderedPoints = canvasPoints(fromStored: stroke.points.map(\.cgPoint))
            consider(.stroke(stroke.id), distance: distanceFrom(point, toPolyline: renderedPoints))
        }

        for arrow in visibleArrows {
            let renderedPoints = canvasPoints(fromStored: [arrow.start.cgPoint, arrow.end.cgPoint])
            consider(.arrow(arrow.id), distance: distanceFrom(point, toPolyline: renderedPoints))
        }

        for measurement in visibleLengthMeasurements {
            let renderedPoints = canvasPoints(fromStored: measurement.points.map(\.cgPoint))
            consider(.length(measurement.id), distance: distanceFrom(point, toPolyline: renderedPoints))
        }

        for area in visibleAreaMeasurements {
            let renderedPoints = canvasPoints(fromStored: area.points.map(\.cgPoint))
            guard renderedPoints.count >= 3 else { continue }
            let distance = isPoint(point, insidePolygon: renderedPoints)
                ? 0
                : distanceFrom(point, toPolyline: closedPolylinePoints(renderedPoints))
            consider(.area(area.id), distance: distance)
        }

        for note in visibleNotes {
            let target = canvasPoint(fromStored: note.point.cgPoint)
            let distance = hypot(target.x - point.x, target.y - point.y)
            consider(.note(note.id), distance: distance)
        }

        for marker in visibleIssueMarkers {
            let target = canvasPoint(fromStored: marker.point.cgPoint)
            let distance = hypot(target.x - point.x, target.y - point.y)
            consider(.issue(marker.id), distance: distance)
        }

        if isOverlayGroupVisible(.counts) {
            for marker in snapshot.countMarkers {
                let target = canvasPoint(fromStored: marker.point.cgPoint)
                let distance = hypot(target.x - point.x, target.y - point.y)
                consider(.count(marker.id), distance: distance)
            }
        }

        return bestTarget
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

    func closedPolylinePoints(_ points: [CGPoint]) -> [CGPoint] {
        guard let first = points.first, let last = points.last else { return points }
        guard hypot(first.x - last.x, first.y - last.y) > 0.5 else { return points }
        var result = points
        result.append(first)
        return result
    }

    func isPoint(_ point: CGPoint, insidePolygon polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var isInside = false
        var previousIndex = polygon.count - 1
        for index in polygon.indices {
            let current = polygon[index]
            let previous = polygon[previousIndex]
            let crossesY = (current.y > point.y) != (previous.y > point.y)
            if crossesY {
                let projectedX = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
                if point.x < projectedX {
                    isInside.toggle()
                }
            }
            previousIndex = index
        }
        return isInside
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
