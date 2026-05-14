import CoreGraphics
import Foundation

enum LibreDWGNativeParser {
    static func parse(fileURL: URL, preferredCodePage: Int32?, preferredBigFont: Int32?) throws -> DXFPreviewModel {
        if shouldAttemptAC1036Compatibility(for: fileURL) {
            do {
                let compatibilityURL = try makeAC1036CompatibilityCopy(for: fileURL)
                defer {
                    try? FileManager.default.removeItem(at: compatibilityURL)
                }
                return try parseNative(
                    fileURL: compatibilityURL,
                    preferredCodePage: preferredCodePage,
                    preferredBigFont: preferredBigFont
                )
            } catch {
                throw NSError(domain: "LibreDWGBridge", code: 2010, userInfo: [
                    NSLocalizedDescriptionKey: "AC1036 DWG 兼容读取失败：\(error.localizedDescription)",
                ])
            }
        }

        return try parseNative(
            fileURL: fileURL,
            preferredCodePage: preferredCodePage,
            preferredBigFont: preferredBigFont
        )
    }

    private static func parseNative(fileURL: URL, preferredCodePage: Int32?, preferredBigFont: Int32?) throws -> DXFPreviewModel {
        try Task.checkCancellation()
        nativeParseLock.lock()
        defer {
            nativeParseLock.unlock()
        }

        var result = SKCADParseResult()
        let overrideCodePage = preferredCodePage ?? 0
        let parseStart = CFAbsoluteTimeGetCurrent()
        let success = fileURL.path.withCString { path in
            sk_libredwg_parse_file_with_codepage(path, Int32(overrideCodePage), &result)
        }
        let parseDurationMilliseconds = max(1, Int((CFAbsoluteTimeGetCurrent() - parseStart) * 1000))
        defer {
            sk_libredwg_free_parse_result(&result)
        }
        try Task.checkCancellation()

        guard success != 0 else {
            let failure = buildFailureDiagnosticMessage(
                failureReason: errorMessage(from: &result),
                result: &result,
                preferredCodePage: preferredCodePage,
                parseDurationMilliseconds: parseDurationMilliseconds
            )
            throw NSError(domain: "LibreDWGBridge", code: 2001, userInfo: [
                NSLocalizedDescriptionKey: failure,
            ])
        }
        guard let primitives = result.primitives, result.primitiveCount > 0 else {
            let diagnostic = buildFailureDiagnosticMessage(
                failureReason: errorMessage(from: &result).isEmpty ? "LibreDWG 没有返回可绘制实体。" : errorMessage(from: &result),
                result: &result,
                preferredCodePage: preferredCodePage,
                parseDurationMilliseconds: parseDurationMilliseconds
            )
            throw NSError(domain: "LibreDWGBridge", code: 2002, userInfo: [
                NSLocalizedDescriptionKey: diagnostic,
            ])
        }
        guard result.primitiveCount <= 120_000 else {
            throw NSError(domain: "LibreDWGBridge", code: 2004, userInfo: [
                NSLocalizedDescriptionKey: "DWG 实体数量过大（\(Int(result.primitiveCount))/\(Int(result.primitiveLimit))），已停止预览以避免内存不足。",
            ])
        }

        let buffer = UnsafeBufferPointer(start: primitives, count: Int(result.primitiveCount))
        var segments: [DXFPreviewModel.Segment] = []
        var polylines: [DXFPreviewModel.Polyline] = []
        var circles: [DXFPreviewModel.Circle] = []
        var texts: [DXFPreviewModel.TextEntity] = []
        var textStyleDiagnostics: Set<String> = []
        var arcCount = 0
        var polylineEntityCount = 0
        var swiftTextPrimitiveCount = 0
        var swiftSuspiciousTextCount = 0
        var swiftMojibakeTextCount = 0

        func makeTextEntity(
            from primitive: SKCADPrimitive,
            layerName: String,
            style: DXFPreviewModel.StrokeStyle,
            kind: DXFPreviewModel.PrimitiveKind,
            renderKind: DXFPreviewModel.TextEntity.RenderKind
        ) -> DXFPreviewModel.TextEntity? {
            let styleName = decodedCString(primitive.textStyleName)
            let fontFile = decodedCString(primitive.fontFile)
            let bigFontFile = decodedCString(primitive.bigFontFile)
            let rawValue = lossyCString(primitive.text)
            let rawTextBytesHex = decodedCString(primitive.rawTextBytesHex)
            let chosenCodepage = primitive.chosenCodepage > 0 ? Int(primitive.chosenCodepage) : nil
            let value: String
            let resolvedCodepage: Int?
            if primitive.text != nil {
                let normalized = normalizeCADText(
                    rawValue ?? "",
                    rawTextBytesHex: rawTextBytesHex,
                    preferredCodePage: preferredCodePage,
                    preferredBigFont: preferredBigFont,
                    styleName: styleName,
                    fontFile: fontFile,
                    styleBigFontFile: bigFontFile
                )
                value = normalized.text
                resolvedCodepage = normalized.codePage.map(Int.init) ?? chosenCodepage
            } else {
                value = ""
                resolvedCodepage = chosenCodepage
            }
            guard !value.isEmpty else { return nil }
            swiftTextPrimitiveCount += 1
            if CADTextNormalizer.looksLikeMojibake(value) {
                swiftMojibakeTextCount += 1
            }
            if CADTextNormalizer.looksSuspicious(value) {
                swiftSuspiciousTextCount += 1
            }
            if let styleName {
                textStyleDiagnostics.insert("样式 \(styleName)")
            }
            if let fontFile {
                textStyleDiagnostics.insert("字体 \(fontFile)")
            }
            if let bigFontFile {
                textStyleDiagnostics.insert("大字体 \(bigFontFile)")
            }
            if let alias = CADSHXFontCatalog.diagnosticSummary(
                styleName: styleName,
                fontFile: fontFile,
                bigFontFile: bigFontFile
            ) {
                textStyleDiagnostics.insert("映射 \(alias)")
            }
            return .init(
                point: CGPoint(x: primitive.start.x, y: primitive.start.y),
                value: value,
                rawValue: rawValue,
                rawTextBytesHex: rawTextBytesHex,
                chosenCodepage: resolvedCodepage,
                height: primitive.textHeight > 0 ? primitive.textHeight : 2,
                rotation: primitive.textRotation,
                style: style,
                layer: layerName,
                styleName: styleName,
                fontFile: fontFile,
                bigFontFile: bigFontFile,
                renderKind: renderKind,
                kind: kind
            )
        }

        func primitivePoints(from primitive: SKCADPrimitive) -> [CGPoint] {
            let pointCount = Int(primitive.pointCount)
            if pointCount > 1, let rawPoints = primitive.points {
                let points = UnsafeBufferPointer(start: rawPoints, count: pointCount)
                let mapped = points.map { CGPoint(x: $0.x, y: $0.y) }
                if mapped.count > 1 {
                    return mapped
                }
            }
            let start = CGPoint(x: primitive.start.x, y: primitive.start.y)
            let end = CGPoint(x: primitive.end.x, y: primitive.end.y)
            guard hypot(start.x - end.x, start.y - end.y) > 0.000_001 else { return [] }
            return [start, end]
        }

        func markerPoints(from primitive: SKCADPrimitive) -> [CGPoint] {
            let center = CGPoint(x: primitive.start.x, y: primitive.start.y)
            let size = max(CGFloat(primitive.strokeWidth), 0.5)
            return [
                CGPoint(x: center.x, y: center.y - size),
                CGPoint(x: center.x + size, y: center.y),
                CGPoint(x: center.x, y: center.y + size),
                CGPoint(x: center.x - size, y: center.y),
                CGPoint(x: center.x, y: center.y - size),
            ]
        }

        func appendPolyline(
            from primitive: SKCADPrimitive,
            layerName: String,
            style: DXFPreviewModel.StrokeStyle,
            renderKind: DXFPreviewModel.Polyline.RenderKind,
            kind: DXFPreviewModel.PrimitiveKind
        ) {
            let points = primitivePoints(from: primitive)
            guard points.count > 1 else { return }
            polylines.append(.init(
                points: points,
                style: style,
                layer: layerName,
                renderKind: renderKind,
                kind: kind
            ))
            polylineEntityCount += 1
        }

        for primitive in buffer {
            let style = strokeStyle(from: primitive)
            let layerName = decodedCString(primitive.layerName) ?? "0"
            switch primitive.kind {
            case SKCADPrimitiveLine:
                segments.append(.init(
                    from: CGPoint(x: primitive.start.x, y: primitive.start.y),
                    to: CGPoint(x: primitive.end.x, y: primitive.end.y),
                    style: style,
                    layer: layerName,
                    kind: .line
                ))
            case SKCADPrimitivePolyline:
                appendPolyline(
                    from: primitive,
                    layerName: layerName,
                    style: style,
                    renderKind: .regular,
                    kind: .polyline
                )
            case SKCADPrimitiveArc:
                let points = sampleArcPoints(
                    center: CGPoint(x: primitive.center.x, y: primitive.center.y),
                    radius: primitive.radius,
                    startRadians: primitive.startAngle,
                    endRadians: primitive.endAngle
                )
                if points.count > 1 {
                    polylines.append(.init(
                        points: points,
                        style: style,
                        layer: layerName,
                        renderKind: .regular,
                        kind: .arc
                    ))
                    arcCount += 1
                }
            case SKCADPrimitiveCircle:
                circles.append(.init(
                    center: CGPoint(x: primitive.center.x, y: primitive.center.y),
                    radius: primitive.radius,
                    style: style,
                    layer: layerName,
                    kind: .circle
                ))
            case SKCADPrimitiveEllipse:
                appendPolyline(
                    from: primitive,
                    layerName: layerName,
                    style: style,
                    renderKind: .regular,
                    kind: .ellipse
                )
            case SKCADPrimitiveText:
                if let entity = makeTextEntity(
                    from: primitive,
                    layerName: layerName,
                    style: style,
                    kind: .text,
                    renderKind: .regular
                ) {
                    texts.append(entity)
                }
            case SKCADPrimitiveMText:
                if let entity = makeTextEntity(
                    from: primitive,
                    layerName: layerName,
                    style: style,
                    kind: .mtext,
                    renderKind: .regular
                ) {
                    texts.append(entity)
                }
            case SKCADPrimitiveDimension:
                if primitive.text != nil {
                    if let entity = makeTextEntity(
                        from: primitive,
                        layerName: layerName,
                        style: style,
                        kind: .dimension,
                        renderKind: .dimension
                    ) {
                        texts.append(entity)
                    }
                } else {
                    appendPolyline(
                        from: primitive,
                        layerName: layerName,
                        style: style,
                        renderKind: .dimension,
                        kind: .dimension
                    )
                }
            case SKCADPrimitiveHatch:
                if primitive.radius > 0 {
                    let points = sampleArcPoints(
                        center: CGPoint(x: primitive.center.x, y: primitive.center.y),
                        radius: primitive.radius,
                        startRadians: primitive.startAngle,
                        endRadians: primitive.endAngle
                    )
                    if points.count > 1 {
                        polylines.append(.init(
                            points: points,
                            style: style,
                            layer: layerName,
                            renderKind: .hatch,
                            kind: .hatch
                        ))
                    }
                } else {
                    appendPolyline(
                        from: primitive,
                        layerName: layerName,
                        style: style,
                        renderKind: .hatch,
                        kind: .hatch
                    )
                }
            case SKCADPrimitiveLeader:
                if primitive.text != nil {
                    if let entity = makeTextEntity(
                        from: primitive,
                        layerName: layerName,
                        style: style,
                        kind: .leader,
                        renderKind: .leader
                    ) {
                        texts.append(entity)
                    }
                } else {
                    appendPolyline(
                        from: primitive,
                        layerName: layerName,
                        style: style,
                        renderKind: .leader,
                        kind: .leader
                    )
                }
            case SKCADPrimitiveImage:
                appendPolyline(
                    from: primitive,
                    layerName: layerName,
                    style: style,
                    renderKind: .image,
                    kind: .image
                )
            case SKCADPrimitiveWipeout:
                appendPolyline(
                    from: primitive,
                    layerName: layerName,
                    style: style,
                    renderKind: .wipeout,
                    kind: .wipeout
                )
            case SKCADPrimitiveBlockRef:
                polylines.append(.init(
                    points: markerPoints(from: primitive),
                    style: style,
                    layer: layerName,
                    renderKind: .regular,
                    kind: .blockRef
                ))
                polylineEntityCount += 1
            case SKCADPrimitiveUnknownProxy:
                polylines.append(.init(
                    points: markerPoints(from: primitive),
                    style: style,
                    layer: layerName,
                    renderKind: .regular,
                    kind: .unknownProxy
                ))
                polylineEntityCount += 1
            default:
                break
            }
        }

        guard let bounds = computeBounds(segments: segments, polylines: polylines, circles: circles, texts: texts) else {
            throw NSError(domain: "LibreDWGBridge", code: 2003, userInfo: [
                NSLocalizedDescriptionKey: "LibreDWG 已读取实体，但无法计算图纸范围。",
            ])
        }

        let drawableObjectCount = segments.count + polylines.count + circles.count + texts.count
        let fontDiagnostics = fontDiagnostics(from: texts)
        let styleTableSummary = fixedCString(from: &result.styleTableSummary)
        let diagnostic = DWGLightweightDiagnostic(
            dwgVersion: dwgVersionDisplay(from: &result),
            totalObjectCount: max(0, Int(result.totalObjectCount)),
            drawableObjectCount: drawableObjectCount,
            unsupportedObjectTypes: unsupportedObjectTypesText(from: &result),
            textEncoding: resolvedTextEncoding(preferredCodePage: preferredCodePage, result: result),
            styleFonts: fontDiagnostics.styleFonts,
            bigFonts: fontDiagnostics.bigFonts,
            parseDurationMilliseconds: parseDurationMilliseconds,
            estimatedMemoryMB: estimateMemoryMegabytes(
                primitiveCount: Int(result.primitiveCount),
                segments: segments,
                polylines: polylines,
                circles: circles,
                texts: texts
            ),
            failureReason: nil
        )

        return DXFPreviewModel(
            segments: segments,
            polylines: polylines,
            circles: circles,
            texts: texts,
            arcCount: arcCount,
            polylineEntityCount: polylineEntityCount,
            sourceObjectCount: Int(result.totalObjectCount),
            unsupportedEntityCount: Int(result.unsupportedEntityCount),
            unsupportedEntitySummary: unsupportedSummary(from: &result),
            textDecodingHint: decodingHint(
                preferredCodePage: preferredCodePage,
                preferredBigFont: preferredBigFont,
                result: result,
                swiftTextPrimitiveCount: swiftTextPrimitiveCount,
                swiftSuspiciousTextCount: swiftSuspiciousTextCount,
                swiftMojibakeTextCount: swiftMojibakeTextCount,
                textStyleDiagnostics: textStyleDiagnostics
            ),
            dwgDiagnostic: diagnostic,
            styleTableSummary: styleTableSummary.isEmpty ? nil : styleTableSummary,
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
        rawTextBytesHex: String?,
        preferredCodePage: Int32?,
        preferredBigFont: Int32?,
        styleName: String?,
        fontFile: String?,
        styleBigFontFile: String?
    ) -> (text: String, codePage: Int32?) {
        let selectedProfile = preferredBigFont
            .flatMap(CADTextBigFontProfile.init(rawValue:)) ?? .auto
        let profile = selectedProfile == .auto
            ? CADTextBigFontProfile.inferred(
                styleName: styleName,
                fontFile: fontFile,
                bigFontFile: styleBigFontFile
            )
            : selectedProfile
        return CADTextNormalizer.bestEffortNormalizedText(
            decodedText: raw,
            rawTextBytesHex: rawTextBytesHex,
            preferredCodePage: preferredCodePage,
            bigFontProfile: profile
        )
    }

    private static func decodedCString(_ raw: UnsafeMutablePointer<CChar>?) -> String? {
        guard let text = lossyCString(raw) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let nativeParseLock = NSLock()

    private static func shouldAttemptAC1036Compatibility(for fileURL: URL) -> Bool {
        readDWGHeaderMagic(fileURL: fileURL) == "AC1036"
    }

    private static func makeAC1036CompatibilityCopy(for fileURL: URL) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sitekeeper-ac1036-\(UUID().uuidString)")
            .appendingPathExtension("dwg")
        try FileManager.default.copyItem(at: fileURL, to: tempURL)
        let handle = try FileHandle(forWritingTo: tempURL)
        defer {
            try? handle.close()
        }
        try handle.seek(toOffset: 0)
        handle.write(Data("AC1032".utf8))
        return tempURL
    }

    private static func readDWGHeaderMagic(fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer {
            try? handle.close()
        }
        guard let data = try? handle.read(upToCount: 6),
              data.count == 6 else { return nil }
        return String(data: data, encoding: .ascii)
    }

    private static func lossyCString(_ raw: UnsafeMutablePointer<CChar>?) -> String? {
        guard let raw else { return nil }
        return lossyCString(UnsafePointer(raw))
    }

    private static func lossyCString(_ raw: UnsafePointer<CChar>?) -> String? {
        guard let raw else { return nil }
        let length = strlen(raw)
        guard length > 0 else { return "" }
        let bytes = UnsafeRawPointer(raw).assumingMemoryBound(to: UInt8.self)
        let buffer = UnsafeBufferPointer(start: bytes, count: length)
        return String(decoding: buffer, as: UTF8.self)
    }

    private static func decodingHint(
        preferredCodePage: Int32?,
        preferredBigFont: Int32?,
        result: SKCADParseResult,
        swiftTextPrimitiveCount: Int,
        swiftSuspiciousTextCount: Int,
        swiftMojibakeTextCount: Int,
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

        let rawSuspiciousCount = Int(result.suspiciousTextCount)
        let textCount = swiftTextPrimitiveCount > 0 ? swiftTextPrimitiveCount : Int(result.textPrimitiveCount)
        let suspiciousCount = swiftTextPrimitiveCount > 0 ? swiftSuspiciousTextCount : rawSuspiciousCount
        if textCount > 0 {
            if suspiciousCount > 0 {
                parts.append("重算疑似乱码 \(suspiciousCount)/\(textCount)")
            } else {
                parts.append("文字 \(textCount) 条")
            }
            if swiftMojibakeTextCount > 0 && swiftMojibakeTextCount != suspiciousCount {
                parts.append("典型乱码 \(swiftMojibakeTextCount)")
            }
            if rawSuspiciousCount > suspiciousCount {
                parts.append("原始疑似 \(rawSuspiciousCount)")
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

    private static func buildFailureDiagnosticMessage(
        failureReason: String,
        result: inout SKCADParseResult,
        preferredCodePage: Int32?,
        parseDurationMilliseconds: Int
    ) -> String {
        let reason = failureReason.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReason = reason.isEmpty ? "未知解析错误" : reason
        let totalObjectCount = max(0, Int(result.totalObjectCount))
        let primitiveCount = max(0, Int(result.primitiveCount))
        let estimatedMemoryMB = estimateMemoryMegabytes(
            primitiveCount: primitiveCount,
            segments: [],
            polylines: [],
            circles: [],
            texts: []
        )
        let fields: [String] = [
            "打开失败：\(trimmedReason)",
            "DWG 版本：\(dwgVersionDisplay(from: &result))",
            "对象总数：\(totalObjectCount)",
            "可绘制对象：\(primitiveCount)",
            "对象预算：\(Int(result.objectLimit))",
            "实体预算：\(Int(result.primitiveLimit))",
            "primitive 内存预算：\(memoryMegabytesText(result.primitiveMemoryBudget))",
            "primitive 缓冲估算：\(memoryMegabytesText(result.estimatedPrimitiveMemory))",
            "未支持对象类型：\(unsupportedObjectTypesText(from: &result))",
            "文字编码：\(resolvedTextEncoding(preferredCodePage: preferredCodePage, result: result))",
            "STYLE 字体：-",
            "大字体：-",
            "解析耗时：\(parseDurationMilliseconds) ms",
            String(format: "内存估计：%.2f MB", estimatedMemoryMB),
        ]
        return fields.joined(separator: "；")
    }

    private static func memoryMegabytesText(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "0 MB" }
        return String(format: "%.2f MB", Double(bytes) / 1024.0 / 1024.0)
    }

    private static func dwgVersionDisplay(from result: inout SKCADParseResult) -> String {
        let description = fixedCString(from: &result.dwgVersionDescription)
        if !description.isEmpty {
            return description
        }
        let code = fixedCString(from: &result.dwgVersionCode)
        if !code.isEmpty {
            return code
        }
        return "未知 DWG 版本"
    }

    private static func unsupportedObjectTypesText(from result: inout SKCADParseResult) -> String {
        let summary = unsupportedSummary(from: &result) ?? ""
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        if result.unsupportedEntityCount > 0 {
            return "共 \(Int(result.unsupportedEntityCount)) 个未支持对象"
        }
        return "无"
    }

    private static func resolvedTextEncoding(preferredCodePage: Int32?, result: SKCADParseResult) -> String {
        if let preferredCodePage, preferredCodePage > 0 {
            return codePageName(for: preferredCodePage)
        }
        let effective = Int(result.effectiveCodepage)
        if effective > 0 {
            return nativeCodePageName(for: effective)
        }
        let header = Int(result.headerCodepage)
        if header > 0 {
            return nativeCodePageName(for: header)
        }
        return "自动/未知"
    }

    private static func fontDiagnostics(from texts: [DXFPreviewModel.TextEntity]) -> (styleFonts: String, bigFonts: String) {
        var styleAndFont: [String: Int] = [:]
        var bigFonts: [String: Int] = [:]
        for text in texts {
            let style = text.styleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let font = text.fontFile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let bigFont = text.bigFontFile?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !style.isEmpty || !font.isEmpty {
                let key = "\(style.isEmpty ? "-" : style)/\(font.isEmpty ? "-" : font)"
                styleAndFont[key, default: 0] += 1
            }
            if !bigFont.isEmpty {
                bigFonts[bigFont, default: 0] += 1
            }
        }
        let dominantStyle = dominantLabel(from: styleAndFont) ?? "-"
        let dominantBigFont = dominantLabel(from: bigFonts) ?? "-"
        return (dominantStyle, dominantBigFont)
    }

    private static func dominantLabel(from histogram: [String: Int]) -> String? {
        histogram.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.localizedStandardCompare(rhs.key) == .orderedDescending
            }
            return lhs.value < rhs.value
        }?.key
    }

    private static func estimateMemoryMegabytes(
        primitiveCount: Int,
        segments: [DXFPreviewModel.Segment],
        polylines: [DXFPreviewModel.Polyline],
        circles: [DXFPreviewModel.Circle],
        texts: [DXFPreviewModel.TextEntity]
    ) -> Double {
        var estimatedBytes = max(primitiveCount, 0) * MemoryLayout<SKCADPrimitive>.stride
        estimatedBytes += segments.count * MemoryLayout<DXFPreviewModel.Segment>.stride
        estimatedBytes += polylines.count * MemoryLayout<DXFPreviewModel.Polyline>.stride
        estimatedBytes += circles.count * MemoryLayout<DXFPreviewModel.Circle>.stride
        estimatedBytes += texts.count * MemoryLayout<DXFPreviewModel.TextEntity>.stride
        for polyline in polylines {
            estimatedBytes += polyline.points.count * MemoryLayout<CGPoint>.stride
        }
        for text in texts {
            estimatedBytes += (text.value.utf8.count + 1)
            estimatedBytes += (text.rawValue?.utf8.count ?? 0)
            estimatedBytes += (text.rawTextBytesHex?.utf8.count ?? 0)
            estimatedBytes += (text.styleName?.utf8.count ?? 0)
            estimatedBytes += (text.fontFile?.utf8.count ?? 0)
            estimatedBytes += (text.bigFontFile?.utf8.count ?? 0)
        }
        return Double(max(estimatedBytes, 0)) / 1_048_576.0
    }

    private static func fixedCString<T>(from fixedBuffer: inout T) -> String {
        withUnsafeBytes(of: &fixedBuffer) { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: CChar.self).baseAddress else {
                return ""
            }
            let text = (lossyCString(baseAddress) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text
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
            return lossyCString(baseAddress) ?? ""
        }
    }

    private static func unsupportedSummary(from result: inout SKCADParseResult) -> String? {
        withUnsafeBytes(of: &result.unsupportedEntitySummary) { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: CChar.self).baseAddress else {
                return nil
            }
            let text = (lossyCString(baseAddress) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }
}
