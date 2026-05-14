import CoreGraphics
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum DXFCanvasRenderer {
    static func color(from rgb: UInt32, layer: String) -> Color {
        if rgb == 0 {
            return layerFallbackColor(layer)
        }
        let red = Double((rgb >> 16) & 0xFF) / 255
        let green = Double((rgb >> 8) & 0xFF) / 255
        let blue = Double(rgb & 0xFF) / 255
        return Color(red: red, green: green, blue: blue)
    }

    static func drawAxes(
        in context: inout GraphicsContext,
        transform: CADCanvasTransform,
        bounds: CGRect
    ) {
        guard bounds.contains(CGPoint.zero) else { return }
        var xAxis = Path()
        xAxis.move(to: transform.point(CGPoint(x: bounds.minX, y: 0)))
        xAxis.addLine(to: transform.point(CGPoint(x: bounds.maxX, y: 0)))
        context.stroke(xAxis, with: .color(.green.opacity(0.75)), lineWidth: 1)

        var yAxis = Path()
        yAxis.move(to: transform.point(CGPoint(x: 0, y: bounds.minY)))
        yAxis.addLine(to: transform.point(CGPoint(x: 0, y: bounds.maxY)))
        context.stroke(yAxis, with: .color(.blue.opacity(0.75)), lineWidth: 1)
    }

    static func searchHighlightPulse(
        hasSelection: Bool,
        hasSearchText: Bool,
        at date: Date
    ) -> CGFloat {
        guard hasSelection, hasSearchText else { return 0 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.95) / 0.95
        return 0.5 + 0.5 * CGFloat(sin(phase * .pi * 2))
    }

    static func textFontSize(
        for text: DXFPreviewModel.TextEntity,
        transform: CADCanvasTransform,
        isSelected: Bool
    ) -> CGFloat {
        let base = activeTextHeight(text, transform: transform)
        switch text.renderKind {
        case .dimension:
            return min(max(base * 1.08, 9), isSelected ? 34 : 28)
        case .hatch:
            return min(max(base * 0.92, 8), isSelected ? 30 : 22)
        case .leader, .attribute:
            return min(max(base, 8), isSelected ? 32 : 25)
        case .regular:
            return min(max(base, 7), isSelected ? 30 : 26)
        }
    }

    static func textWeight(for text: DXFPreviewModel.TextEntity) -> Font.Weight {
        switch text.renderKind {
        case .dimension:
            return .semibold
        case .hatch:
            return .medium
        case .leader, .attribute:
            return .regular
        case .regular:
            return .regular
        }
    }

    static func textColor(
        for text: DXFPreviewModel.TextEntity,
        isMatch: Bool,
        isSelected: Bool,
        pulse: CGFloat
    ) -> Color {
        if isSelected {
            return Color.red.opacity(0.78 + 0.22 * Double(pulse))
        }
        if isMatch {
            return .orange
        }
        switch text.renderKind {
        case .dimension:
            return .cyan
        case .hatch:
            return .orange
        case .leader:
            return .purple
        case .attribute:
            return .teal
        case .regular:
            return color(from: text.style.rgb, layer: text.layer)
        }
    }

    static func drawTextBackdrop(
        for text: DXFPreviewModel.TextEntity,
        fontSize: CGFloat,
        isSelected: Bool,
        pulse: CGFloat,
        in context: inout GraphicsContext
    ) {
        let textWidth = max(CGFloat(text.value.count) * fontSize * 0.58, fontSize * 1.5)
        let textHeight = fontSize * 1.35
        let paddingX = max(fontSize * 0.36, 4)
        let paddingY = max(fontSize * 0.18, 2)
        let rect = CGRect(
            x: -paddingX,
            y: -textHeight / 2 - paddingY,
            width: textWidth + paddingX * 2,
            height: textHeight + paddingY * 2
        )
        let path = Path(roundedRect: rect, cornerRadius: min(8, textHeight / 2))

        if isSelected {
            let halo = rect.insetBy(dx: -5 - pulse * 5, dy: -4 - pulse * 4)
            context.fill(
                Path(roundedRect: halo, cornerRadius: min(12, halo.height / 2)),
                with: .color(Color.red.opacity(0.12 + 0.24 * Double(pulse)))
            )
            context.stroke(
                Path(roundedRect: halo, cornerRadius: min(12, halo.height / 2)),
                with: .color(Color.red.opacity(0.55 + 0.35 * Double(pulse))),
                lineWidth: 1.1 + pulse * 1.2
            )
        }

        switch text.renderKind {
        case .dimension:
            context.fill(path, with: .color(Color.cyan.opacity(0.12)))
            context.stroke(path, with: .color(Color.cyan.opacity(0.72)), lineWidth: 0.8)
        case .hatch:
            context.fill(path, with: .color(Color.orange.opacity(0.12)))
            context.stroke(path, with: .color(Color.orange.opacity(0.58)), lineWidth: 0.7)
        case .regular, .leader, .attribute:
            if isSelected {
                context.fill(path, with: .color(Color(uiColor: .systemBackground).opacity(0.82)))
            }
        }
    }

    static func drawDimensionTicks(
        for polyline: DXFPreviewModel.Polyline,
        in context: inout GraphicsContext,
        transform: CADCanvasTransform
    ) {
        guard polyline.points.count >= 2 else { return }
        let start = transform.point(polyline.points[0])
        let end = transform.point(polyline.points[polyline.points.count - 1])
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux
        let tickLength = min(max(length * 0.035, 7), 14)

        func addTick(at point: CGPoint, direction: CGFloat) {
            var path = Path()
            path.move(to: CGPoint(
                x: point.x - px * tickLength * 0.5 - ux * tickLength * direction * 0.35,
                y: point.y - py * tickLength * 0.5 - uy * tickLength * direction * 0.35
            ))
            path.addLine(to: CGPoint(
                x: point.x + px * tickLength * 0.5 + ux * tickLength * direction * 0.35,
                y: point.y + py * tickLength * 0.5 + uy * tickLength * direction * 0.35
            ))
            context.stroke(path, with: .color(Color.cyan.opacity(0.95)), lineWidth: 1.2)

            var arrow = Path()
            let arrowLength = tickLength * 0.72
            let directionSign = direction >= 0 ? CGFloat(1) : CGFloat(-1)
            arrow.move(to: point)
            arrow.addLine(to: CGPoint(
                x: point.x - ux * arrowLength * directionSign + px * arrowLength * 0.35,
                y: point.y - uy * arrowLength * directionSign + py * arrowLength * 0.35
            ))
            arrow.move(to: point)
            arrow.addLine(to: CGPoint(
                x: point.x - ux * arrowLength * directionSign - px * arrowLength * 0.35,
                y: point.y - uy * arrowLength * directionSign - py * arrowLength * 0.35
            ))
            context.stroke(arrow, with: .color(Color.cyan.opacity(0.86)), lineWidth: 1)
        }

        addTick(at: start, direction: 1)
        addTick(at: end, direction: -1)
    }

    static func drawPolyline(
        _ polyline: DXFPreviewModel.Polyline,
        path: Path,
        in context: inout GraphicsContext,
        allowsHatchPattern: Bool = true
    ) {
        switch polyline.renderKind {
        case .hatch:
            drawHatch(polyline, path: path, in: &context, allowsPattern: allowsHatchPattern)
        case .dimension:
            context.stroke(
                path,
                with: .color(Color.cyan.opacity(0.95)),
                style: StrokeStyle(lineWidth: max(polyline.style.width, 0.75), lineCap: .round, lineJoin: .round)
            )
        case .leader:
            context.stroke(
                path,
                with: .color(Color.purple.opacity(0.86)),
                style: StrokeStyle(lineWidth: max(polyline.style.width, 0.7), lineCap: .round, lineJoin: .round, dash: [5, 2])
            )
        case .image:
            context.stroke(
                path,
                with: .color(Color.blue.opacity(0.82)),
                style: StrokeStyle(lineWidth: max(polyline.style.width, 0.65), lineCap: .round, lineJoin: .round, dash: [3, 2])
            )
        case .wipeout:
            context.fill(path, with: .color(Color(uiColor: .systemBackground).opacity(0.62)))
            context.stroke(
                path,
                with: .color(Color.gray.opacity(0.75)),
                style: StrokeStyle(lineWidth: max(polyline.style.width, 0.6), lineCap: .round, lineJoin: .round, dash: [2, 3])
            )
        case .regular:
            switch polyline.kind {
            case .blockRef:
                context.stroke(
                    path,
                    with: .color(Color.teal.opacity(0.9)),
                    style: StrokeStyle(
                        lineWidth: max(polyline.style.width, 0.7),
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [4, 2]
                    )
                )
            case .unknownProxy:
                context.stroke(
                    path,
                    with: .color(Color.orange.opacity(0.88)),
                    style: StrokeStyle(
                        lineWidth: max(polyline.style.width, 0.75),
                        lineCap: .round,
                        lineJoin: .round,
                        dash: [3, 2]
                    )
                )
            default:
                context.stroke(
                    path,
                    with: .color(color(from: polyline.style.rgb, layer: polyline.layer)),
                    style: StrokeStyle(lineWidth: max(polyline.style.width, 0.45), lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    private static func drawHatch(
        _ polyline: DXFPreviewModel.Polyline,
        path: Path,
        in context: inout GraphicsContext,
        allowsPattern: Bool
    ) {
        let baseColor = color(from: polyline.style.rgb, layer: polyline.layer)
        let isClosed = polyline.points.count >= 3 &&
            distance(polyline.points.first!, polyline.points.last!) <= max(0.001, hatchClosureTolerance(for: polyline.points))

        if isClosed {
            context.fill(path, with: .color(baseColor.opacity(0.07)))
            if allowsPattern {
                drawHatchPattern(in: path.boundingRect, clippedTo: path, color: baseColor, in: &context)
            }
        }
        context.stroke(
            path,
            with: .color(baseColor.opacity(isClosed ? 0.72 : 0.58)),
            style: StrokeStyle(
                lineWidth: max(polyline.style.width, 0.45),
                lineCap: .round,
                lineJoin: .round,
                dash: isClosed ? [7, 3] : [3, 3]
            )
        )
    }

    private static func drawHatchPattern(
        in rect: CGRect,
        clippedTo path: Path,
        color: Color,
        in context: inout GraphicsContext
    ) {
        guard rect.width.isFinite, rect.height.isFinite, rect.width > 1, rect.height > 1 else { return }
        var clipped = context
        clipped.clip(to: path)
        let step = min(max(min(rect.width, rect.height) * 0.055, 8), 22)
        let span = rect.width + rect.height
        var offset = -rect.height
        while offset <= rect.width {
            var line = Path()
            line.move(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
            line.addLine(to: CGPoint(x: rect.minX + offset + span, y: rect.minY))
            clipped.stroke(line, with: .color(color.opacity(0.16)), lineWidth: 0.8)
            offset += step
        }
    }

    private static func hatchClosureTolerance(for points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0.001 }
        var total: CGFloat = 0
        for index in 1..<points.count {
            total += distance(points[index - 1], points[index])
        }
        return max(total * 0.015, 0.001)
    }

    private static func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }

    static func drawText(
        _ value: String,
        entity text: DXFPreviewModel.TextEntity,
        fontSize: CGFloat,
        color: Color,
        in context: inout GraphicsContext
    ) {
        guard !value.isEmpty else { return }
        if shouldUseSHXFallback(for: text) {
            drawTextWithSHXFallback(value, fontSize: fontSize, color: color, in: &context)
        } else {
            context.draw(
                Text(value)
                    .font(cadTextFont(size: fontSize, weight: textWeight(for: text)))
                    .foregroundStyle(color),
                at: .zero,
                anchor: .leading
            )
        }
    }

    static func formatCoordinate(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }

    static func codePageDisplayName(_ codePage: Int) -> String {
        switch codePage {
        case 936:
            return "GBK 936"
        case 54936:
            return "GB18030 54936"
        case 950:
            return "Big5 950"
        case 932:
            return "Shift-JIS 932"
        case 949:
            return "Korean 949"
        case 65001:
            return "UTF-8"
        default:
            return "CP\(codePage)"
        }
    }

    private static func activeTextHeight(_ text: DXFPreviewModel.TextEntity, transform: CADCanvasTransform) -> CGFloat {
        transform.radius(max(text.height, 1))
    }

    private static func shouldUseSHXFallback(for text: DXFPreviewModel.TextEntity) -> Bool {
        let styleSuggestsSHX = SHXGlyphPathLibrary.shouldUseFallback(
            styleName: text.styleName,
            fontFile: text.fontFile,
            bigFontFile: text.bigFontFile
        )
        let hasMissingLikeScalars = text.value.unicodeScalars.contains { scalar in
            scalar.value == 0xFFFD || (0xE000...0xF8FF).contains(scalar.value)
        }
        let raw = text.rawValue ?? ""
        let hasSHXEscapes = raw.contains("%%") || raw.contains("\\M+") || raw.contains("\\U+")
        guard styleSuggestsSHX || hasMissingLikeScalars || hasSHXEscapes else { return false }
        return text.value.contains { SHXGlyphPathLibrary.glyph(for: $0) != nil }
    }

    private static func cadTextFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let fontName = preferredCJKFontName {
            return .custom(fontName, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .default)
    }

    private static let preferredCJKFontName: String? = {
        let candidates = [
            "PingFangSC-Regular",
            "HiraginoSansGB-W3",
            "STHeitiSC-Medium",
            "SongtiSC-Regular"
        ]
#if canImport(UIKit)
        let availableNames = Set(UIFont.familyNames.flatMap { UIFont.fontNames(forFamilyName: $0) })
        return candidates.first { availableNames.contains($0) }
#elseif canImport(AppKit)
        let availableNames = Set(NSFontManager.shared.availableFonts)
        return candidates.first { availableNames.contains($0) }
#else
        return nil
#endif
    }()

    private static func drawTextWithSHXFallback(
        _ value: String,
        fontSize: CGFloat,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let charGap = max(fontSize * 0.08, 1.2)
        var cursorX: CGFloat = 0
        var lineIndex: Int = 0

        for character in value {
            if character == "\n" {
                lineIndex += 1
                cursorX = 0
                continue
            }

            let baselineY = CGFloat(lineIndex) * fontSize * 1.25
            if let glyph = SHXGlyphPathLibrary.glyph(for: character) {
                glyph.draw(
                    at: CGPoint(x: cursorX, y: baselineY),
                    fontSize: fontSize,
                    color: color,
                    in: &context
                )
                cursorX += max(fontSize * glyph.advance, fontSize * 0.52) + charGap
            } else {
                let textContext = context
                textContext.draw(
                    Text(String(character))
                        .font(cadTextFont(size: fontSize))
                        .foregroundStyle(color),
                    at: CGPoint(x: cursorX, y: baselineY),
                    anchor: .leading
                )
                cursorX += max(fontSize * 0.6, 6) + charGap
            }
        }
    }

    private static func layerFallbackColor(_ layer: String) -> Color {
        let palette: [Color] = [
            .blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint, .cyan, .brown,
        ]
        let hash = abs(layer.lowercased().hashValue)
        return palette[hash % palette.count]
    }
}
