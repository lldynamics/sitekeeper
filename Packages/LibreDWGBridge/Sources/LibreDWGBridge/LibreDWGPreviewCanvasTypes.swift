import CoreGraphics
import Foundation

extension Notification.Name {
    static let libreDWGCanvasTransformDidChange = Notification.Name("LibreDWGBridgeCanvasTransformDidChange")
}

struct DXFPreviewModel {
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
    }

    struct Polyline {
        enum RenderKind {
            case regular
            case dimension
            case hatch
        }

        let points: [CGPoint]
        let style: StrokeStyle
        let layer: String
        var renderKind: RenderKind = .regular
    }

    struct Circle {
        let center: CGPoint
        let radius: CGFloat
        let style: StrokeStyle
        let layer: String
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
