import CoreGraphics
import Foundation

public struct LibreDWGCanvasTransformSnapshot: Equatable {
    public let bounds: CGRect
    public let size: CGSize
    public let zoomScale: CGFloat
    public let panOffset: CGSize

    public init(bounds: CGRect, size: CGSize, zoomScale: CGFloat, panOffset: CGSize) {
        self.bounds = bounds
        self.size = size
        self.zoomScale = zoomScale
        self.panOffset = panOffset
    }
}

public struct LibreDWGCanvasViewStateSnapshot: Equatable {
    public let zoomScale: CGFloat
    public let panOffset: CGSize
    public let viewportCenter: CGPoint?
    public let usesSavedVisibleLayers: Bool
    public let visibleLayerNames: [String]

    public init(
        zoomScale: CGFloat,
        panOffset: CGSize,
        viewportCenter: CGPoint?,
        usesSavedVisibleLayers: Bool,
        visibleLayerNames: [String]
    ) {
        self.zoomScale = zoomScale
        self.panOffset = panOffset
        self.viewportCenter = viewportCenter
        self.usesSavedVisibleLayers = usesSavedVisibleLayers
        self.visibleLayerNames = visibleLayerNames
    }
}

public struct LibreDWGFontMapping: Hashable, Sendable {
    public let sourceKind: String
    public let pattern: String
    public let bigFont: Int32

    public init(
        sourceKind: String,
        pattern: String,
        bigFont: Int32
    ) {
        self.sourceKind = sourceKind
        self.pattern = pattern
        self.bigFont = bigFont
    }
}

public struct LibreDWGSnapPointPayload: Equatable {
    public let point: CGPoint
    public let snapKind: String
    public let layer: String
    public let primitiveKind: String
    public let styleRGB: UInt32
    public let styleWidth: CGFloat
    public let styleName: String?

    public init(
        point: CGPoint,
        snapKind: String,
        layer: String,
        primitiveKind: String,
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
}

public struct LibreDWGTextAutoDetectionSnapshot: Equatable {
    public let codePage: Int32?
    public let bigFont: Int32?
    public let styleName: String?
    public let fontFile: String?
    public let bigFontFile: String?
    public let autoDetectScore: Int
    public let styleSummary: String?
    public let matchedFontSummary: String?
    public let unresolvedFontSummary: String?
    public let fontResolutionSummary: String?
    public let rawTextBytesHexSample: String?
    public let detectionSummary: String?
    public let summary: String

    public init(
        codePage: Int32?,
        bigFont: Int32?,
        styleName: String?,
        fontFile: String?,
        bigFontFile: String?,
        autoDetectScore: Int,
        styleSummary: String?,
        matchedFontSummary: String?,
        unresolvedFontSummary: String?,
        fontResolutionSummary: String?,
        rawTextBytesHexSample: String?,
        detectionSummary: String?,
        summary: String
    ) {
        self.codePage = codePage
        self.bigFont = bigFont
        self.styleName = styleName
        self.fontFile = fontFile
        self.bigFontFile = bigFontFile
        self.autoDetectScore = autoDetectScore
        self.styleSummary = styleSummary
        self.matchedFontSummary = matchedFontSummary
        self.unresolvedFontSummary = unresolvedFontSummary
        self.fontResolutionSummary = fontResolutionSummary
        self.rawTextBytesHexSample = rawTextBytesHexSample
        self.detectionSummary = detectionSummary
        self.summary = summary
    }
}

extension Notification.Name {
    static let libreDWGFocusSourcePoint = Notification.Name("LibreDWGBridgeFocusSourcePoint")
}

struct DWGLightweightDiagnostic {
    let dwgVersion: String
    let totalObjectCount: Int
    let drawableObjectCount: Int
    let unsupportedObjectTypes: String
    let blockReferenceSummary: String
    let xrefReferences: [DWGXrefReference]
    let textEncoding: String
    let styleFonts: String
    let bigFonts: String
    let parseDurationMilliseconds: Int
    let estimatedMemoryMB: Double
    let failureReason: String?

    var hasMissingXrefs: Bool {
        xrefReferences.contains { $0.localStatus == .missing || $0.localStatus == .pathEmpty }
    }

    var xrefSummary: String {
        guard !xrefReferences.isEmpty else { return "无" }
        let found = xrefReferences.filter { $0.localStatus == .found }.count
        let missing = xrefReferences.filter { $0.localStatus == .missing || $0.localStatus == .pathEmpty }.count
        var parts = ["XREF:\(xrefReferences.count)"]
        if found > 0 {
            parts.append("本地已找到:\(found)")
        }
        if missing > 0 {
            parts.append("本地缺失:\(missing)")
        }
        return parts.joined(separator: ", ")
    }
}

struct DWGXrefReference: Identifiable, Equatable {
    enum LocalStatus: String {
        case found
        case missing
        case pathEmpty

        var displayText: String {
            switch self {
            case .found:
                return "本地已找到"
            case .missing:
                return "本地缺失"
            case .pathEmpty:
                return "未记录路径"
            }
        }
    }

    let id: String
    let name: String
    let savedPath: String
    let resolvedLocalPath: String?
    let localStatus: LocalStatus
    let isOverlay: Bool
    let isLoadedInDWG: Bool
    let isResolvedInDWG: Bool
    let referenceCount: Int

    var title: String {
        if !name.isEmpty {
            return name
        }
        if !savedPath.isEmpty {
            let normalizedPath = savedPath.replacingOccurrences(of: "\\", with: "/")
            return normalizedPath.split(separator: "/").last.map(String.init) ?? savedPath
        }
        return "未命名 XREF"
    }

    var sourceSummary: String {
        var parts: [String] = []
        if isOverlay {
            parts.append("overlay")
        }
        if isLoadedInDWG || isResolvedInDWG {
            parts.append("DWG 已加载")
        }
        if referenceCount > 0 {
            parts.append("引用 \(referenceCount)")
        }
        return parts.isEmpty ? "-" : parts.joined(separator: " / ")
    }
}

struct DXFTextIssueHint: Equatable {
    let textCount: Int
    let suspiciousTextCount: Int
    let mojibakeTextCount: Int
    let styleDiagnostics: [String]

    var shouldSuggestTextRepair: Bool {
        textCount > 0 && suspiciousTextCount > 0
    }

    var summary: String {
        var parts = ["疑似乱码 \(suspiciousTextCount)/\(max(textCount, 1))"]
        if mojibakeTextCount > 0, mojibakeTextCount != suspiciousTextCount {
            parts.append("典型乱码 \(mojibakeTextCount)")
        }
        if !styleDiagnostics.isEmpty {
            parts.append(styleDiagnostics.prefix(2).joined(separator: " / "))
        }
        return parts.joined(separator: "，")
    }
}

enum DXFSnapPointKind: String, Codable {
    case endpoint
    case midpoint
    case center
}

struct DXFSnapSourcePoint {
    let point: CGPoint
    let kind: DXFSnapPointKind
    let layer: String
    let primitiveKind: DXFPreviewModel.PrimitiveKind
    let styleRGB: UInt32
    let styleWidth: CGFloat
    let styleName: String?

    var metadataPayload: [String: Any] {
        var payload: [String: Any] = [
            "x": point.x,
            "y": point.y,
            "snapKind": kind.rawValue,
            "layer": layer,
            "primitiveKind": primitiveKind.rawValue,
            "styleRGB": NSNumber(value: styleRGB),
            "styleWidth": styleWidth,
        ]
        if let styleName, !styleName.isEmpty {
            payload["styleName"] = styleName
        }
        return payload
    }
}

struct DXFSnapPointSet {
    let points: [DXFSnapSourcePoint]

    var allPoints: [CGPoint] {
        points.map(\.point)
    }

    var endpointPoints: [CGPoint] {
        points
            .filter { $0.kind == .endpoint }
            .map(\.point)
    }

    var midpointPoints: [CGPoint] {
        points
            .filter { $0.kind == .midpoint }
            .map(\.point)
    }

    var centerPoints: [CGPoint] {
        points
            .filter { $0.kind == .center }
            .map(\.point)
    }

    var metadataPayloads: [[String: Any]] {
        points.map(\.metadataPayload)
    }
}

struct DXFPreviewModel {
    enum PrimitiveKind: String {
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
    }

    struct StrokeStyle {
        let rgb: UInt32
        let width: CGFloat

        static let `default` = StrokeStyle(rgb: 0x2A2A2A, width: 1)
    }

    struct Segment {
        let from: CGPoint
        let to: CGPoint
        let style: StrokeStyle
        let layer: String
        var kind: PrimitiveKind = .line
    }

    struct Polyline {
        enum RenderKind {
            case regular
            case dimension
            case hatch
            case leader
            case image
            case wipeout
        }

        let points: [CGPoint]
        let style: StrokeStyle
        let layer: String
        var renderKind: RenderKind = .regular
        var kind: PrimitiveKind = .polyline
    }

    struct Circle {
        let center: CGPoint
        let radius: CGFloat
        let style: StrokeStyle
        let layer: String
        var kind: PrimitiveKind = .circle
    }

    struct TextEntity: Identifiable {
        enum RenderKind {
            case regular
            case dimension
            case hatch
            case leader
            case attribute
        }

        let id = UUID()
        let point: CGPoint
        let value: String
        let rawValue: String?
        let rawTextBytesHex: String?
        let chosenCodepage: Int?
        let height: CGFloat
        let rotation: CGFloat
        let style: StrokeStyle
        let layer: String
        var styleName: String? = nil
        var fontFile: String? = nil
        var bigFontFile: String? = nil
        var renderKind: RenderKind = .regular
        var kind: PrimitiveKind = .text
    }

    var segments: [Segment]
    var polylines: [Polyline]
    var circles: [Circle]
    var texts: [TextEntity] = []
    var arcCount: Int
    var polylineEntityCount: Int
    var sourceObjectCount: Int = 0
    var unsupportedEntityCount: Int = 0
    var unsupportedEntitySummary: String? = nil
    var textDecodingHint: String? = nil
    var textIssueHint: DXFTextIssueHint? = nil
    var dwgDiagnostic: DWGLightweightDiagnostic? = nil
    var styleTableSummary: String? = nil
    var bounds: CGRect
}

struct CADCanvasTransform {
    let bounds: CGRect
    let size: CGSize
    let zoomScale: CGFloat
    let panOffset: CGSize

    private var contentInset: CGFloat {
        min(max(min(size.width, size.height) * 0.018, 6), 14)
    }

    private var baseScale: CGFloat {
        let availableWidth = max(size.width - contentInset * 2, 1)
        let availableHeight = max(size.height - contentInset * 2, 1)
        let sx = availableWidth / max(bounds.width, 1)
        let sy = availableHeight / max(bounds.height, 1)
        return min(sx, sy)
    }

    private var horizontalPad: CGFloat {
        (size.width - bounds.width * baseScale) / 2
    }

    private var verticalPad: CGFloat {
        (size.height - bounds.height * baseScale) / 2
    }

    func point(_ source: CGPoint) -> CGPoint {
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

    func sourcePoint(_ rendered: CGPoint) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let unscaledX = ((rendered.x - panOffset.width) - center.x) / max(zoomScale, 0.0001) + center.x
        let unscaledY = ((rendered.y - panOffset.height) - center.y) / max(zoomScale, 0.0001) + center.y
        let sourceX = bounds.minX + (unscaledX - horizontalPad) / max(baseScale, 0.0001)
        let sourceY = bounds.minY + ((size.height - unscaledY) - verticalPad) / max(baseScale, 0.0001)
        return CGPoint(x: sourceX, y: sourceY)
    }

    func viewportRectInSource() -> CGRect {
        let topLeft = sourcePoint(CGPoint(x: 0, y: 0))
        let bottomRight = sourcePoint(CGPoint(x: size.width, y: size.height))
        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }

    func radius(_ source: CGFloat) -> CGFloat {
        source * baseScale * zoomScale
    }
}
