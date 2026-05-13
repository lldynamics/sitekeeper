import CoreGraphics
import Foundation

enum LibreDWGNativeParser {
    static func parse(fileURL: URL, preferredCodePage: Int32?, preferredBigFont: Int32?) throws -> DXFPreviewModel {
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
        var textStyleDiagnostics: Set<String> = []
        var arcCount = 0

        for primitive in buffer {
            let style = strokeStyle(from: primitive)
            let layerName = decodedCString(primitive.layerName) ?? "0"
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
                let styleName = decodedCString(primitive.textStyleName)
                let fontFile = decodedCString(primitive.fontFile)
                let bigFontFile = decodedCString(primitive.bigFontFile)
                let rawValue = primitive.text.map { String(cString: $0) }
                let rawTextBytesHex = decodedCString(primitive.rawTextBytesHex)
                let chosenCodepage = primitive.chosenCodepage > 0 ? Int(primitive.chosenCodepage) : nil
                let value: String
                if let text = primitive.text {
                    value = normalizeCADText(
                        String(cString: text),
                        preferredBigFont: preferredBigFont,
                        styleBigFontFile: bigFontFile
                    )
                } else {
                    value = ""
                }
                if !value.isEmpty {
                    if let styleName {
                        textStyleDiagnostics.insert("样式 \(styleName)")
                    }
                    if let fontFile {
                        textStyleDiagnostics.insert("字体 \(fontFile)")
                    }
                    if let bigFontFile {
                        textStyleDiagnostics.insert("大字体 \(bigFontFile)")
                    }
                    texts.append(.init(
                        point: CGPoint(x: primitive.start.x, y: primitive.start.y),
                        value: value,
                        rawValue: rawValue,
                        rawTextBytesHex: rawTextBytesHex,
                        chosenCodepage: chosenCodepage,
                        height: primitive.textHeight > 0 ? primitive.textHeight : 2,
                        rotation: primitive.textRotation,
                        style: style,
                        layer: layerName,
                        styleName: styleName,
                        fontFile: fontFile,
                        bigFontFile: bigFontFile
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
            unsupportedEntitySummary: unsupportedSummary(from: &result),
            textDecodingHint: decodingHint(
                preferredCodePage: preferredCodePage,
                preferredBigFont: preferredBigFont,
                result: result,
                textStyleDiagnostics: textStyleDiagnostics
            ),
            bounds: bounds
        )
    }

    private static func strokeStyle(from primitive: SKCADPrimitive) -> DXFPreviewModel.StrokeStyle {
        let rgb = UInt32(primitive.strokeRGB & 0x00FF_FFFF)
        let width = CGFloat(max(primitive.strokeWidth, 0.45))
        return .init(rgb: rgb, width: width)
    }

    private static func normalizeCADText(
        _ raw: String,
        preferredBigFont: Int32?,
        styleBigFontFile: String?
    ) -> String {
        let selectedProfile = preferredBigFont
            .flatMap(CADTextBigFontProfile.init(rawValue:)) ?? .auto
        let profile = selectedProfile == .auto
            ? CADTextBigFontProfile.inferred(from: styleBigFontFile)
            : selectedProfile
        return CADTextNormalizer.normalize(raw, bigFontProfile: profile)
    }

    private static func decodedCString(_ raw: UnsafeMutablePointer<CChar>?) -> String? {
        guard let raw else { return nil }
        let trimmed = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func decodingHint(
        preferredCodePage: Int32?,
        preferredBigFont: Int32?,
        result: SKCADParseResult,
        textStyleDiagnostics: Set<String>
    ) -> String? {
        let codePageText = preferredCodePage.map(codePageName(for:)) ?? "自动正文编码"
        let bigFontText = preferredBigFont
            .flatMap(CADTextBigFontProfile.init(rawValue:))
            .map(bigFontName(for:)) ?? "自动 SHX"

        var parts = ["文字 \(codePageText) / \(bigFontText)"]
        let headerCodePage = Int(result.headerCodepage)
        let effectiveCodePage = Int(result.effectiveCodepage)
        if headerCodePage > 0 || effectiveCodePage > 0 {
            parts.append("DWG \(nativeCodePageName(for: headerCodePage)) -> \(nativeCodePageName(for: effectiveCodePage))")
        }

        let textCount = Int(result.textPrimitiveCount)
        let suspiciousCount = Int(result.suspiciousTextCount)
        if textCount > 0 {
            if suspiciousCount > 0 {
                parts.append("疑似乱码 \(suspiciousCount)/\(textCount)")
            } else {
                parts.append("文字 \(textCount) 条")
            }
        }
        if !textStyleDiagnostics.isEmpty {
            parts.append(textStyleDiagnostics.sorted().prefix(3).joined(separator: " / "))
        }
        if result.unsupportedEntityCount > 0 {
            parts.append("未渲染对象 \(Int(result.unsupportedEntityCount))")
        }
        return parts.joined(separator: "，")
    }

    private static func codePageName(for codePage: Int32) -> String {
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
            return "代码页 \(Int(codePage))"
        }
    }

    private static func nativeCodePageName(for codePage: Int) -> String {
        switch codePage {
        case 0:
            return "UTF-8"
        case 24:
            return "Big5"
        case 31:
            return "GB2312"
        case 38:
            return "ANSI 932"
        case 39:
            return "ANSI 936"
        case 40:
            return "ANSI 949"
        case 41:
            return "ANSI 950"
        case 43:
            return "UTF-16"
        case 0xFF:
            return "未定义"
        default:
            return "CP\(codePage)"
        }
    }

    private static func bigFontName(for profile: CADTextBigFontProfile) -> String {
        switch profile {
        case .auto:
            return "自动 SHX"
        case .gbcbig:
            return "GBCBIG"
        case .hztxt:
            return "HZTXT"
        case .hzfs:
            return "HZFS"
        case .big5:
            return "Big5 字体"
        case .disabled:
            return "关闭 SHX 映射"
        }
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

    private static func unsupportedSummary(from result: inout SKCADParseResult) -> String? {
        withUnsafeBytes(of: &result.unsupportedEntitySummary) { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: CChar.self).baseAddress else {
                return nil
            }
            let text = String(cString: baseAddress).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }
}
