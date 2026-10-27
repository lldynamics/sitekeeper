import SwiftUI
import UIKit

/// A single layout and drawing path for the live preview and the baked image.
/// All dimensions scale with the photo's short edge, independent of screen scale.
struct WatermarkCameraLayout {
    struct Line {
        let text: String
        let rect: CGRect
    }
    let canvasSize: CGSize
    let contentFrame: CGRect
    let fontSize: CGFloat
    let cornerRadius: CGFloat
    let lines: [Line]
    let coordinateScale: CGFloat
    let canonicalFontSize: CGFloat
    private let canonicalContentFrame: CGRect
    private let canonicalCornerRadius: CGFloat
    private let canonicalLines: [Line]

    static func make(context: CameraWatermarkContext, capturedAt: Date, canvasSize: CGSize) -> Self {
        guard canvasSize.width.isFinite, canvasSize.height.isFinite,
              canvasSize.width > 0, canvasSize.height > 0 else {
            return Self(canvasSize: .zero, contentFrame: .zero, fontSize: 0, cornerRadius: 0, lines: [],
                        coordinateScale: 1, canonicalFontSize: 0, canonicalContentFrame: .zero,
                        canonicalCornerRadius: 0, canonicalLines: [])
        }
        // UIFont applies optical sizing at different point sizes. Measure and draw
        // in one canonical space, then scale the entire graphics context, so preview
        // and exported photo retain exactly the same glyphs, breaks and geometry.
        let shortEdge: CGFloat = 1000
        let coordinateScale = min(canvasSize.width, canvasSize.height) / shortEdge
        let canonicalCanvas = CGSize(width: canvasSize.width / coordinateScale,
                                     height: canvasSize.height / coordinateScale)
        let margin = shortEdge * 0.028
        let paddingX = shortEdge * 0.024
        let paddingY = shortEdge * 0.020
        let maxWidth = min(canonicalCanvas.width - margin * 2, shortEdge * 0.94)
        let textWidth = maxWidth - paddingX * 2
        let strings = context.lines(capturedAt: capturedAt)
        var fontSize = shortEdge * (context.style.detail == .compact ? 0.032 : 0.027)
        // Fit even the fullest template into the frame in landscape orientation.
        let maximumHeight = canonicalCanvas.height * 0.61
        let naturalHeight = CGFloat(strings.count) * (fontSize * 1.45) + paddingY * 2
        if naturalHeight > maximumHeight {
            fontSize *= (maximumHeight - paddingY * 2) / (naturalHeight - paddingY * 2)
        }
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let lineHeight = font.lineHeight
        let gap = fontSize * 0.24
        let renderedStrings = strings.map { fittedText($0, width: textWidth, font: font) }
        let measuredWidth = renderedStrings.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let width = min(maxWidth, measuredWidth + paddingX * 2)
        let height = CGFloat(strings.count) * lineHeight + CGFloat(max(0, strings.count - 1)) * gap + paddingY * 2
        let x = context.style.position == .bottomLeft ? margin : canonicalCanvas.width - margin - width
        let frame = CGRect(x: x, y: canonicalCanvas.height - margin - height, width: width, height: height)
        let lines = renderedStrings.enumerated().map { index, text in
            Line(text: text, rect: CGRect(x: frame.minX + paddingX,
                                        y: frame.minY + paddingY + CGFloat(index) * (lineHeight + gap),
                                        width: width - paddingX * 2, height: lineHeight))
        }
        let transform = CGAffineTransform(scaleX: coordinateScale, y: coordinateScale)
        return Self(canvasSize: canvasSize, contentFrame: frame.applying(transform),
                    fontSize: fontSize * coordinateScale, cornerRadius: shortEdge * 0.015 * coordinateScale,
                    lines: lines.map { Line(text: $0.text, rect: $0.rect.applying(transform)) },
                    coordinateScale: coordinateScale, canonicalFontSize: fontSize,
                    canonicalContentFrame: frame, canonicalCornerRadius: shortEdge * 0.015,
                    canonicalLines: lines)
    }

    /// Truncate once before drawing, preserving grapheme clusters (including emoji).
    /// Both destinations draw the resulting exact strings; no SwiftUI line limits are involved.
    private static func fittedText(_ text: String, width: CGFloat, font: UIFont) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        if (text as NSString).size(withAttributes: attributes).width <= width { return text }
        let characters = Array(text.prefix(4096))
        var low = 0
        var high = characters.count
        while low < high {
            let middle = (low + high + 1) / 2
            let candidate = String(characters.prefix(middle)) + "…"
            if (candidate as NSString).size(withAttributes: attributes).width <= width {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return String(characters.prefix(low)) + "…"
    }

    func draw() {
        guard !canonicalLines.isEmpty, let graphics = UIGraphicsGetCurrentContext() else { return }
        graphics.saveGState()
        defer { graphics.restoreGState() }
        graphics.scaleBy(x: coordinateScale, y: coordinateScale)
        UIColor.black.withAlphaComponent(0.58).setFill()
        UIBezierPath(roundedRect: canonicalContentFrame, cornerRadius: canonicalCornerRadius).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: canonicalFontSize, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        for line in canonicalLines { (line.text as NSString).draw(in: line.rect, withAttributes: attributes) }
    }

    func overlayImage(scale: CGFloat) -> UIImage {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return UIImage() }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        format.scale = scale
        return UIGraphicsImageRenderer(size: canvasSize, format: format).image { _ in draw() }
    }
}

struct WatermarkCameraLiveOverlay: View {
    let context: CameraWatermarkContext
    let capturedAt: Date
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let layout = WatermarkCameraLayout.make(context: context, capturedAt: capturedAt, canvasSize: proxy.size)
            Image(uiImage: layout.overlayImage(scale: displayScale))
                .resizable()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .accessibilityLabel(layout.lines.map(\.text).joined(separator: "，"))
        }
        .allowsHitTesting(false)
    }
}
