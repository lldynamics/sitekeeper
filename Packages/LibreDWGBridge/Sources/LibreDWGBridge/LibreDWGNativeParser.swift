import CoreGraphics
import Foundation

enum LibreDWGNativeParser {
    static func parse(fileURL: URL, preferredCodePage: Int32?) throws -> DXFPreviewModel {
        var result = SKCADParseResult()
        let overrideCodePage = preferredCodePage ?? 0
        let success = fileURL.path.withCString { path in
            sk_libredwg_parse_file_with_codepage(path, Int32(overrideCodePage), &result)
        }
        defer {
            sk_libredwg_free_parse_result(&result)
        }

        guard success != 0 else {
            let message = errorMessage(from: &result)
            throw NSError(domain: "LibreDWGBridge", code: 2001, userInfo: [
                NSLocalizedDescriptionKey: message.isEmpty ? "LibreDWG 未能解析 DWG 几何。" : message,
            ])
        }
        guard let primitives = result.primitives, result.primitiveCount > 0 else {
            throw NSError(domain: "LibreDWGBridge", code: 2002, userInfo: [
                NSLocalizedDescriptionKey: "LibreDWG 没有返回可绘制实体。",
            ])
        }

        let buffer = UnsafeBufferPointer(start: primitives, count: Int(result.primitiveCount))
        var segments: [DXFPreviewModel.Segment] = []
        var polylines: [DXFPreviewModel.Polyline] = []
        var circles: [DXFPreviewModel.Circle] = []
        var texts: [DXFPreviewModel.TextEntity] = []
        var arcCount = 0

        for primitive in buffer {
            let style = strokeStyle(from: primitive)
            let layerName: String = {
                guard let raw = primitive.layerName else { return "0" }
                let trimmed = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "0" : trimmed
            }()
            switch primitive.kind {
            case SKCADPrimitiveLine:
                segments.append(.init(
                    from: CGPoint(x: primitive.start.x, y: primitive.start.y),
                    to: CGPoint(x: primitive.end.x, y: primitive.end.y),
                    style: style,
                    layer: layerName
                ))
            case SKCADPrimitiveArc:
                let points = sampleArcPoints(
                    center: CGPoint(x: primitive.center.x, y: primitive.center.y),
                    radius: primitive.radius,
                    startRadians: primitive.startAngle,
                    endRadians: primitive.endAngle
                )
                if points.count > 1 {
                    polylines.append(.init(points: points, style: style, layer: layerName))
                    arcCount += 1
                }
            case SKCADPrimitiveCircle:
                circles.append(.init(
                    center: CGPoint(x: primitive.center.x, y: primitive.center.y),
                    radius: primitive.radius,
                    style: style,
                    layer: layerName
                ))
            case SKCADPrimitiveText:
                let value: String
                if let text = primitive.text {
                    value = normalizeCADText(String(cString: text))
                } else {
                    value = ""
                }
                if !value.isEmpty {
                    texts.append(.init(
                        point: CGPoint(x: primitive.start.x, y: primitive.start.y),
                        value: value,
                        height: primitive.textHeight > 0 ? primitive.textHeight : 2,
                        rotation: primitive.textRotation,
                        style: style,
                        layer: layerName
                    ))
                }
            default:
                break
            }
        }

        guard let bounds = computeBounds(segments: segments, polylines: polylines, circles: circles, texts: texts) else {
            throw NSError(domain: "LibreDWGBridge", code: 2003, userInfo: [
                NSLocalizedDescriptionKey: "LibreDWG 已读取实体，但无法计算图纸范围。",
            ])
        }

        return DXFPreviewModel(
            segments: segments,
            polylines: polylines,
            circles: circles,
            texts: texts,
            arcCount: arcCount,
            polylineEntityCount: 0,
            sourceObjectCount: Int(result.totalObjectCount),
            unsupportedEntityCount: Int(result.unsupportedEntityCount),
            bounds: bounds
        )
    }

    private static func strokeStyle(from primitive: SKCADPrimitive) -> DXFPreviewModel.StrokeStyle {
        let rgb = UInt32(primitive.strokeRGB & 0x00FF_FFFF)
        let width = CGFloat(max(primitive.strokeWidth, 0.45))
        return .init(rgb: rgb, width: width)
    }

    private static func normalizeCADText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .replacingOccurrences(of: "\\P", with: "\n")
            .replacingOccurrences(of: "\\p", with: "\n")
            .replacingOccurrences(of: "\\~", with: " ")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
    }

    private static func sampleArcPoints(
        center: CGPoint,
        radius: CGFloat,
        startRadians: CGFloat,
        endRadians: CGFloat
    ) -> [CGPoint] {
        let twoPi = CGFloat.pi * 2
        var end = endRadians
        while end < startRadians {
            end += twoPi
        }
        let span = max(end - startRadians, 0)
        let segments = max(Int(ceil(span / (.pi / 18))), 8)
        return (0...segments).map { index in
            let t = CGFloat(index) / CGFloat(segments)
            let angle = startRadians + span * t
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private static func computeBounds(
        segments: [DXFPreviewModel.Segment],
        polylines: [DXFPreviewModel.Polyline],
        circles: [DXFPreviewModel.Circle],
        texts: [DXFPreviewModel.TextEntity]
    ) -> CGRect? {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        func include(_ point: CGPoint) {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        for segment in segments {
            include(segment.from)
            include(segment.to)
        }
        for polyline in polylines {
            for point in polyline.points {
                include(point)
            }
        }
        for circle in circles {
            include(CGPoint(x: circle.center.x - circle.radius, y: circle.center.y - circle.radius))
            include(CGPoint(x: circle.center.x + circle.radius, y: circle.center.y + circle.radius))
        }
        for text in texts {
            include(text.point)
        }

        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else {
            return nil
        }
        return CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 1),
            height: max(maxY - minY, 1)
        )
    }

    private static func errorMessage(from result: inout SKCADParseResult) -> String {
        withUnsafeBytes(of: &result.errorMessage) { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: CChar.self).baseAddress else {
                return ""
            }
            return String(cString: baseAddress)
        }
    }
}
