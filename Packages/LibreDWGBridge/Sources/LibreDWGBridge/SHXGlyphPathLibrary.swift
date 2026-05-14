import CoreGraphics
import Foundation
import SwiftUI

struct SHXVectorGlyph {
    let advance: CGFloat
    let strokes: [[CGPoint]]

    func draw(
        at origin: CGPoint,
        fontSize: CGFloat,
        color: Color,
        in context: inout GraphicsContext
    ) {
        let width = max(fontSize * advance, fontSize * 0.52)
        let height = max(fontSize * 1.05, 1)
        let rect = CGRect(x: origin.x, y: origin.y - height * 0.78, width: width, height: height)
        var path = Path()
        for stroke in strokes where stroke.count > 1 {
            let first = map(stroke[0], rect: rect)
            path.move(to: first)
            for point in stroke.dropFirst() {
                path.addLine(to: map(point, rect: rect))
            }
        }
        context.stroke(path, with: .color(color), lineWidth: max(0.9, fontSize * 0.075))
    }

    private func map(_ point: CGPoint, rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + point.x * rect.width,
            y: rect.maxY - point.y * rect.height
        )
    }
}

enum SHXGlyphPathLibrary {
    static func shouldUseFallback(styleName: String?, fontFile: String?, bigFontFile: String?) -> Bool {
        let profile = CADTextBigFontProfile.inferred(styleName: styleName, fontFile: fontFile, bigFontFile: bigFontFile)
        if profile != .auto, profile != .disabled {
            return true
        }
        let tokens = [styleName, fontFile, bigFontFile]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return tokens.contains(".shx") ||
            tokens.contains("hztxt") ||
            tokens.contains("gbcbig") ||
            tokens.contains("hzfs") ||
            tokens.contains("tssd")
    }

    static func glyph(for character: Character) -> SHXVectorGlyph? {
        if let glyph = knownGlyphs[character] {
            return glyph
        }
        guard let scalar = character.unicodeScalars.first,
              character.unicodeScalars.count == 1 else {
            return nil
        }
        let value = scalar.value
        if (0x3400...0x9FFF).contains(value) || (0xF900...0xFAFF).contains(value) {
            return pseudoCJKGlyph(for: Int(value))
        }
        return nil
    }

    private static let knownGlyphs: [Character: SHXVectorGlyph] = {
        var map: [Character: SHXVectorGlyph] = [:]

        func put(_ char: Character, _ strokes: [[CGPoint]], advance: CGFloat = 1.0) {
            map[char] = SHXVectorGlyph(advance: advance, strokes: strokes)
        }

        // Symbols
        put("°", circleStrokes(segments: 10, inset: 0.25), advance: 0.72)
        put("Φ", circleStrokes(segments: 12, inset: 0.12) + [[CGPoint(x: 0.5, y: 0.1), CGPoint(x: 0.5, y: 0.9)]])
        put("Ø", circleStrokes(segments: 12, inset: 0.12) + [[CGPoint(x: 0.2, y: 0.16), CGPoint(x: 0.82, y: 0.84)]])
        put("±", [
            [CGPoint(x: 0.2, y: 0.62), CGPoint(x: 0.8, y: 0.62)],
            [CGPoint(x: 0.5, y: 0.4), CGPoint(x: 0.5, y: 0.82)],
            [CGPoint(x: 0.2, y: 0.24), CGPoint(x: 0.8, y: 0.24)],
        ])
        put("×", [
            [CGPoint(x: 0.18, y: 0.2), CGPoint(x: 0.82, y: 0.82)],
            [CGPoint(x: 0.18, y: 0.82), CGPoint(x: 0.82, y: 0.2)],
        ])
        put("△", [
            [CGPoint(x: 0.16, y: 0.18), CGPoint(x: 0.5, y: 0.86), CGPoint(x: 0.84, y: 0.18), CGPoint(x: 0.16, y: 0.18)],
        ])
        put("□", [
            [CGPoint(x: 0.15, y: 0.15), CGPoint(x: 0.85, y: 0.15), CGPoint(x: 0.85, y: 0.85), CGPoint(x: 0.15, y: 0.85), CGPoint(x: 0.15, y: 0.15)],
        ])
        put("○", circleStrokes(segments: 12, inset: 0.12))
        put("●", circleStrokes(segments: 12, inset: 0.18), advance: 0.94)
        put("→", [
            [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.84, y: 0.5)],
            [CGPoint(x: 0.64, y: 0.68), CGPoint(x: 0.84, y: 0.5), CGPoint(x: 0.64, y: 0.32)],
        ], advance: 1.1)
        put("←", [
            [CGPoint(x: 0.9, y: 0.5), CGPoint(x: 0.16, y: 0.5)],
            [CGPoint(x: 0.36, y: 0.68), CGPoint(x: 0.16, y: 0.5), CGPoint(x: 0.36, y: 0.32)],
        ], advance: 1.1)
        put("↑", [
            [CGPoint(x: 0.5, y: 0.12), CGPoint(x: 0.5, y: 0.86)],
            [CGPoint(x: 0.32, y: 0.66), CGPoint(x: 0.5, y: 0.86), CGPoint(x: 0.68, y: 0.66)],
        ], advance: 0.86)
        put("↓", [
            [CGPoint(x: 0.5, y: 0.88), CGPoint(x: 0.5, y: 0.14)],
            [CGPoint(x: 0.32, y: 0.34), CGPoint(x: 0.5, y: 0.14), CGPoint(x: 0.68, y: 0.34)],
        ], advance: 0.86)

        // Minimal common Chinese set (construction drawings)
        put("平", [
            [CGPoint(x: 0.12, y: 0.84), CGPoint(x: 0.88, y: 0.84)],
            [CGPoint(x: 0.2, y: 0.56), CGPoint(x: 0.8, y: 0.56)],
            [CGPoint(x: 0.5, y: 0.8), CGPoint(x: 0.5, y: 0.14)],
            [CGPoint(x: 0.3, y: 0.18), CGPoint(x: 0.7, y: 0.18)],
        ])
        put("面", [
            [CGPoint(x: 0.14, y: 0.14), CGPoint(x: 0.86, y: 0.14), CGPoint(x: 0.86, y: 0.86), CGPoint(x: 0.14, y: 0.86), CGPoint(x: 0.14, y: 0.14)],
            [CGPoint(x: 0.24, y: 0.62), CGPoint(x: 0.76, y: 0.62)],
            [CGPoint(x: 0.24, y: 0.44), CGPoint(x: 0.76, y: 0.44)],
            [CGPoint(x: 0.34, y: 0.42), CGPoint(x: 0.34, y: 0.2)],
            [CGPoint(x: 0.5, y: 0.42), CGPoint(x: 0.5, y: 0.2)],
            [CGPoint(x: 0.66, y: 0.42), CGPoint(x: 0.66, y: 0.2)],
        ])
        put("图", [
            [CGPoint(x: 0.12, y: 0.12), CGPoint(x: 0.88, y: 0.12), CGPoint(x: 0.88, y: 0.88), CGPoint(x: 0.12, y: 0.88), CGPoint(x: 0.12, y: 0.12)],
            [CGPoint(x: 0.26, y: 0.72), CGPoint(x: 0.72, y: 0.72), CGPoint(x: 0.72, y: 0.28), CGPoint(x: 0.26, y: 0.28), CGPoint(x: 0.26, y: 0.72)],
            [CGPoint(x: 0.34, y: 0.34), CGPoint(x: 0.64, y: 0.62)],
            [CGPoint(x: 0.34, y: 0.58), CGPoint(x: 0.58, y: 0.34)],
        ])
        put("标", [
            [CGPoint(x: 0.18, y: 0.8), CGPoint(x: 0.46, y: 0.52)],
            [CGPoint(x: 0.22, y: 0.58), CGPoint(x: 0.48, y: 0.82)],
            [CGPoint(x: 0.33, y: 0.18), CGPoint(x: 0.33, y: 0.82)],
            [CGPoint(x: 0.56, y: 0.78), CGPoint(x: 0.84, y: 0.78)],
            [CGPoint(x: 0.56, y: 0.62), CGPoint(x: 0.84, y: 0.62)],
            [CGPoint(x: 0.56, y: 0.46), CGPoint(x: 0.84, y: 0.46)],
            [CGPoint(x: 0.7, y: 0.18), CGPoint(x: 0.7, y: 0.78)],
        ])
        put("高", [
            [CGPoint(x: 0.16, y: 0.82), CGPoint(x: 0.84, y: 0.82)],
            [CGPoint(x: 0.2, y: 0.66), CGPoint(x: 0.8, y: 0.66)],
            [CGPoint(x: 0.2, y: 0.66), CGPoint(x: 0.2, y: 0.16), CGPoint(x: 0.8, y: 0.16), CGPoint(x: 0.8, y: 0.66)],
            [CGPoint(x: 0.32, y: 0.52), CGPoint(x: 0.68, y: 0.52), CGPoint(x: 0.68, y: 0.32), CGPoint(x: 0.32, y: 0.32), CGPoint(x: 0.32, y: 0.52)],
        ])
        put("轴", [
            [CGPoint(x: 0.18, y: 0.72), CGPoint(x: 0.46, y: 0.72), CGPoint(x: 0.46, y: 0.26), CGPoint(x: 0.18, y: 0.26), CGPoint(x: 0.18, y: 0.72)],
            [CGPoint(x: 0.32, y: 0.82), CGPoint(x: 0.32, y: 0.18)],
            [CGPoint(x: 0.56, y: 0.5), CGPoint(x: 0.88, y: 0.5)],
            [CGPoint(x: 0.72, y: 0.82), CGPoint(x: 0.72, y: 0.18)],
        ])
        put("线", [
            [CGPoint(x: 0.16, y: 0.74), CGPoint(x: 0.4, y: 0.74)],
            [CGPoint(x: 0.2, y: 0.58), CGPoint(x: 0.36, y: 0.58)],
            [CGPoint(x: 0.18, y: 0.42), CGPoint(x: 0.38, y: 0.42)],
            [CGPoint(x: 0.5, y: 0.74), CGPoint(x: 0.86, y: 0.74)],
            [CGPoint(x: 0.5, y: 0.58), CGPoint(x: 0.86, y: 0.58)],
            [CGPoint(x: 0.52, y: 0.24), CGPoint(x: 0.84, y: 0.24)],
            [CGPoint(x: 0.68, y: 0.82), CGPoint(x: 0.68, y: 0.16)],
        ])
        put("尺", [
            [CGPoint(x: 0.2, y: 0.82), CGPoint(x: 0.82, y: 0.82)],
            [CGPoint(x: 0.2, y: 0.82), CGPoint(x: 0.2, y: 0.22), CGPoint(x: 0.54, y: 0.22), CGPoint(x: 0.54, y: 0.52), CGPoint(x: 0.2, y: 0.52)],
            [CGPoint(x: 0.54, y: 0.52), CGPoint(x: 0.82, y: 0.18)],
        ])
        put("寸", [
            [CGPoint(x: 0.2, y: 0.7), CGPoint(x: 0.82, y: 0.7)],
            [CGPoint(x: 0.52, y: 0.84), CGPoint(x: 0.52, y: 0.18)],
            [CGPoint(x: 0.52, y: 0.28), CGPoint(x: 0.68, y: 0.2)],
        ])
        put("配", [
            [CGPoint(x: 0.14, y: 0.76), CGPoint(x: 0.42, y: 0.76), CGPoint(x: 0.42, y: 0.24), CGPoint(x: 0.14, y: 0.24), CGPoint(x: 0.14, y: 0.76)],
            [CGPoint(x: 0.28, y: 0.84), CGPoint(x: 0.28, y: 0.16)],
            [CGPoint(x: 0.52, y: 0.76), CGPoint(x: 0.86, y: 0.76), CGPoint(x: 0.86, y: 0.52), CGPoint(x: 0.52, y: 0.52), CGPoint(x: 0.52, y: 0.76)],
            [CGPoint(x: 0.52, y: 0.46), CGPoint(x: 0.86, y: 0.46), CGPoint(x: 0.86, y: 0.2), CGPoint(x: 0.52, y: 0.2), CGPoint(x: 0.52, y: 0.46)],
        ])
        put("电", [
            [CGPoint(x: 0.14, y: 0.8), CGPoint(x: 0.86, y: 0.8), CGPoint(x: 0.86, y: 0.26), CGPoint(x: 0.14, y: 0.26), CGPoint(x: 0.14, y: 0.8)],
            [CGPoint(x: 0.5, y: 0.88), CGPoint(x: 0.5, y: 0.34)],
            [CGPoint(x: 0.5, y: 0.34), CGPoint(x: 0.72, y: 0.16)],
        ])
        put("回", [
            [CGPoint(x: 0.14, y: 0.14), CGPoint(x: 0.86, y: 0.14), CGPoint(x: 0.86, y: 0.86), CGPoint(x: 0.14, y: 0.86), CGPoint(x: 0.14, y: 0.14)],
            [CGPoint(x: 0.34, y: 0.34), CGPoint(x: 0.66, y: 0.34), CGPoint(x: 0.66, y: 0.66), CGPoint(x: 0.34, y: 0.66), CGPoint(x: 0.34, y: 0.34)],
        ])
        put("路", [
            [CGPoint(x: 0.16, y: 0.72), CGPoint(x: 0.42, y: 0.72), CGPoint(x: 0.42, y: 0.26), CGPoint(x: 0.16, y: 0.26), CGPoint(x: 0.16, y: 0.72)],
            [CGPoint(x: 0.56, y: 0.78), CGPoint(x: 0.86, y: 0.78)],
            [CGPoint(x: 0.56, y: 0.58), CGPoint(x: 0.86, y: 0.58)],
            [CGPoint(x: 0.56, y: 0.38), CGPoint(x: 0.86, y: 0.38)],
            [CGPoint(x: 0.7, y: 0.82), CGPoint(x: 0.7, y: 0.18)],
        ])
        put("照", [
            [CGPoint(x: 0.16, y: 0.8), CGPoint(x: 0.42, y: 0.8), CGPoint(x: 0.42, y: 0.48), CGPoint(x: 0.16, y: 0.48), CGPoint(x: 0.16, y: 0.8)],
            [CGPoint(x: 0.16, y: 0.42), CGPoint(x: 0.42, y: 0.42)],
            [CGPoint(x: 0.56, y: 0.8), CGPoint(x: 0.86, y: 0.8), CGPoint(x: 0.86, y: 0.48), CGPoint(x: 0.56, y: 0.48), CGPoint(x: 0.56, y: 0.8)],
            [CGPoint(x: 0.56, y: 0.32), CGPoint(x: 0.86, y: 0.32)],
            [CGPoint(x: 0.62, y: 0.2), CGPoint(x: 0.72, y: 0.12)],
            [CGPoint(x: 0.8, y: 0.2), CGPoint(x: 0.7, y: 0.12)],
        ])
        put("明", [
            [CGPoint(x: 0.16, y: 0.78), CGPoint(x: 0.42, y: 0.78), CGPoint(x: 0.42, y: 0.24), CGPoint(x: 0.16, y: 0.24), CGPoint(x: 0.16, y: 0.78)],
            [CGPoint(x: 0.56, y: 0.78), CGPoint(x: 0.86, y: 0.78), CGPoint(x: 0.86, y: 0.24), CGPoint(x: 0.56, y: 0.24), CGPoint(x: 0.56, y: 0.78)],
            [CGPoint(x: 0.56, y: 0.5), CGPoint(x: 0.86, y: 0.5)],
        ])
        put("插", [
            [CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0.44, y: 0.56)],
            [CGPoint(x: 0.24, y: 0.54), CGPoint(x: 0.44, y: 0.82)],
            [CGPoint(x: 0.32, y: 0.18), CGPoint(x: 0.32, y: 0.82)],
            [CGPoint(x: 0.54, y: 0.76), CGPoint(x: 0.84, y: 0.76)],
            [CGPoint(x: 0.54, y: 0.56), CGPoint(x: 0.84, y: 0.56)],
            [CGPoint(x: 0.54, y: 0.36), CGPoint(x: 0.84, y: 0.36)],
            [CGPoint(x: 0.7, y: 0.82), CGPoint(x: 0.7, y: 0.2)],
        ])
        put("座", [
            [CGPoint(x: 0.16, y: 0.82), CGPoint(x: 0.84, y: 0.82)],
            [CGPoint(x: 0.2, y: 0.68), CGPoint(x: 0.8, y: 0.68)],
            [CGPoint(x: 0.24, y: 0.54), CGPoint(x: 0.76, y: 0.54), CGPoint(x: 0.76, y: 0.22), CGPoint(x: 0.24, y: 0.22), CGPoint(x: 0.24, y: 0.54)],
            [CGPoint(x: 0.5, y: 0.82), CGPoint(x: 0.5, y: 0.22)],
        ])
        put("管", [
            [CGPoint(x: 0.2, y: 0.84), CGPoint(x: 0.8, y: 0.84)],
            [CGPoint(x: 0.24, y: 0.7), CGPoint(x: 0.76, y: 0.7)],
            [CGPoint(x: 0.24, y: 0.56), CGPoint(x: 0.76, y: 0.56)],
            [CGPoint(x: 0.26, y: 0.56), CGPoint(x: 0.26, y: 0.24), CGPoint(x: 0.74, y: 0.24), CGPoint(x: 0.74, y: 0.56)],
            [CGPoint(x: 0.5, y: 0.56), CGPoint(x: 0.5, y: 0.24)],
        ])

        return map
    }()

    private static func pseudoCJKGlyph(for scalar: Int) -> SHXVectorGlyph {
        let bits = UInt32(truncatingIfNeeded: scalar)
        let x1 = 0.22 + CGFloat((bits >> 2) & 0x3) * 0.06
        let x2 = 0.52 + CGFloat((bits >> 4) & 0x3) * 0.06
        let y1 = 0.3 + CGFloat((bits >> 6) & 0x3) * 0.08
        let y2 = 0.58 + CGFloat((bits >> 8) & 0x3) * 0.08
        return SHXVectorGlyph(
            advance: 1,
            strokes: [
                [CGPoint(x: 0.14, y: 0.14), CGPoint(x: 0.86, y: 0.14), CGPoint(x: 0.86, y: 0.86), CGPoint(x: 0.14, y: 0.86), CGPoint(x: 0.14, y: 0.14)],
                [CGPoint(x: x1, y: 0.2), CGPoint(x: x1, y: 0.78)],
                [CGPoint(x: x2, y: 0.2), CGPoint(x: x2, y: 0.78)],
                [CGPoint(x: 0.2, y: y1), CGPoint(x: 0.8, y: y1)],
                [CGPoint(x: 0.2, y: y2), CGPoint(x: 0.8, y: y2)],
            ]
        )
    }

    private static func circleStrokes(segments: Int, inset: CGFloat) -> [[CGPoint]] {
        let count = max(segments, 6)
        let radius = max(0.1, (1 - inset * 2) * 0.5)
        let center = CGPoint(x: 0.5, y: 0.5)
        var ring: [CGPoint] = []
        ring.reserveCapacity(count + 1)
        for idx in 0...count {
            let angle = (Double(idx) / Double(count)) * Double.pi * 2
            ring.append(
                CGPoint(
                    x: center.x + radius * CGFloat(cos(angle)),
                    y: center.y + radius * CGFloat(sin(angle))
                )
            )
        }
        return [ring]
    }
}
