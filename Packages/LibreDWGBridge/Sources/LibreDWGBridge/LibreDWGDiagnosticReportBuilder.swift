import Foundation

public enum LibreDWGDiagnosticReportBuilder {
    public static func makeReport(
        fileURL: URL,
        preferredCodePage: Int32?,
        preferredBigFont: Int32?
    ) throws -> String {
        var lines: [String] = []
        lines.append("CAD 图纸诊断日志")
        lines.append("生成时间：\(dateTimeFormatter.string(from: Date()))")
        lines.append("")
        lines.append("## 文件")
        lines.append("文件名：\(fileURL.lastPathComponent)")
        lines.append("路径：\(fileURL.path)")
        lines.append("大小：\(fileSizeText(fileURL))")
        lines.append("修改时间：\(modifiedTimeText(fileURL))")
        lines.append("DWG 文件头：\(dwgMagicText(fileURL))")
        lines.append("文件头 Hex：\(headerHex(fileURL))")
        lines.append("")
        lines.append("## 当前预览设置")
        lines.append("正文编码：\(codePageDisplayName(preferredCodePage))")
        lines.append("SHX/大字体：\(bigFontDisplayName(preferredBigFont))")
        lines.append("")

        let currentModelResult = Result {
            try LibreDWGNativeParser.parse(
                fileURL: fileURL,
                preferredCodePage: preferredCodePage,
                preferredBigFont: preferredBigFont
            )
        }

        lines.append("## 当前解析摘要")
        switch currentModelResult {
        case .success(let model):
            lines.append("状态：成功")
            lines.append("对象总数：\(model.sourceObjectCount)")
            lines.append("可绘制对象：\(model.segments.count + model.polylines.count + model.circles.count + model.texts.count)")
            lines.append("文字段数：\(model.texts.count)")
            lines.append("未支持对象：\(model.unsupportedEntityCount)")
            if let unsupported = model.unsupportedEntitySummary, !unsupported.isEmpty {
                lines.append("未支持对象明细：\(unsupported)")
            }
            if let hint = model.textDecodingHint, !hint.isEmpty {
                lines.append("文字提示：\(hint)")
            }
            if let styleTable = model.styleTableSummary, !styleTable.isEmpty {
                lines.append("STYLE 表：\(styleTable)")
            }
            if let diagnostic = model.dwgDiagnostic {
                lines.append("DWG 版本：\(diagnostic.dwgVersion)")
                lines.append("解析耗时：\(diagnostic.parseDurationMilliseconds) ms")
                lines.append(String(format: "内存估计：%.2f MB", diagnostic.estimatedMemoryMB))
            }
        case .failure(let error):
            lines.append("状态：失败")
            lines.append("错误：\(error.localizedDescription)")
        }
        lines.append("")

        if case .success(let model) = currentModelResult {
            let auto = LibreDWGTextAutoDetector.detect(model: model)
            lines.append("## 文字自动识别")
            lines.append("推荐编码：\(codePageDisplayName(auto.codePage))")
            lines.append("推荐大字体：\(bigFontDisplayName(auto.bigFont))")
            lines.append("评分：\(auto.score)")
            lines.append("摘要：\(auto.summary)")
            if let styleSummary = auto.styleSummary, !styleSummary.isEmpty {
                lines.append("STYLE 采样：\(styleSummary)")
            }
            if let rawSample = auto.rawTextBytesHexSample, !rawSample.isEmpty {
                lines.append("raw text bytes：\(rawSample)")
            }
            lines.append("")
        } else {
            lines.append("## 文字自动识别")
            lines.append("当前解析失败，未做额外重复解析。请根据上方错误处理图纸后重试。")
            lines.append("")
        }

        lines.append("## 渲染组合评分")
        if case .success(let model) = currentModelResult {
            for probe in textRenderProbeCandidates(preferredCodePage: preferredCodePage, preferredBigFont: preferredBigFont) {
                lines.append(contentsOf: makeRenderProbeLines(model: model, codePage: probe.codePage, bigFont: probe.bigFont, title: probe.title))
                lines.append("")
            }
        } else {
            lines.append("当前解析失败，已跳过多组合重复解析，避免继续放大内存占用。")
            lines.append("")
        }

        lines.append("## 现场建议")
        lines.append("1. 如果中文乱码，优先尝试 GBK/GB18030 + 自动 SHX。")
        lines.append("2. 字体别名已覆盖常见 gbcbig/tssdeng/tssdchn/gbenor/gbeitc、hztxt/simplex/txt/romans、hzfs/simfang/fangsong/fsdb、Big5/mingliu/kaiu。")
        lines.append("3. 如果未支持对象里出现 PROXY_ENTITY/AEC 或大量 UNKNOWN，通常是天正/AEC 对象，建议让对方另存为普通 AutoCAD DWG 或导出 PDF/DXF。")
        lines.append("4. 现场反馈问题时，请同时发送本日志和原 DWG 文件。")
        return lines.joined(separator: "\n")
    }

    private static func makeRenderProbeLines(model: DXFPreviewModel, codePage: Int32?, bigFont: Int32?, title: String) -> [String] {
        var lines: [String] = []
        let profile = bigFont.flatMap(CADTextBigFontProfile.init(rawValue:)) ?? .auto
        var score = model.texts.count * 3 - min(model.unsupportedEntityCount, 200)
        var samples: [String] = []

        for text in model.texts.prefix(500) {
            let resolvedProfile = profile == .auto
                ? CADTextBigFontProfile.inferred(styleName: text.styleName, fontFile: text.fontFile, bigFontFile: text.bigFontFile)
                : profile
            let normalized = CADTextNormalizer.bestEffortNormalizedText(
                decodedText: text.rawValue ?? text.value,
                rawTextBytesHex: text.rawTextBytesHex,
                preferredCodePage: codePage,
                bigFontProfile: resolvedProfile
            )
            score += CADTextNormalizer.diagnosticScore(normalized.text)
            if samples.count < 10 {
                var parts = ["文字：\(normalized.text)"]
                if let rawValue = text.rawValue, rawValue != normalized.text {
                    parts.append("原始：\(rawValue)")
                }
                if let styleName = text.styleName {
                    parts.append("样式：\(styleName)")
                }
                if let fontFile = text.fontFile {
                    parts.append("字体：\(fontFile)")
                }
                if let bigFontFile = text.bigFontFile {
                    parts.append("大字体：\(bigFontFile)")
                }
                if let chosenCodepage = normalized.codePage {
                    parts.append("命中：\(codePageDisplayName(chosenCodepage))")
                }
                if let rawHex = text.rawTextBytesHex, !rawHex.isEmpty {
                    parts.append("raw：\(rawHex)")
                }
                samples.append("- \(parts.joined(separator: " | "))")
            }
        }

        lines.append("### \(title)")
        lines.append("状态：基于当前解析结果重算")
        lines.append("评分：\(score)")
        lines.append("文字段数：\(model.texts.count)")
        if !samples.isEmpty {
            lines.append("文字样本：")
            lines.append(contentsOf: samples)
        }
        return lines
    }

    private static func makeRenderProbeLines(fileURL: URL, codePage: Int32?, bigFont: Int32?, title: String) -> [String] {
        var lines: [String] = []
        lines.append("### \(title)")
        do {
            let model = try LibreDWGNativeParser.parse(
                fileURL: fileURL,
                preferredCodePage: codePage,
                preferredBigFont: bigFont
            )
            let score = renderScore(model)
            lines.append("状态：成功")
            lines.append("评分：\(score)")
            lines.append("文字段数：\(model.texts.count)")
            if let hint = model.textDecodingHint, !hint.isEmpty {
                lines.append("提示：\(hint)")
            }
            if !model.texts.isEmpty {
                lines.append("文字样本：")
                for text in model.texts.prefix(10) {
                    var parts = ["文字：\(text.value)"]
                    if let rawValue = text.rawValue, rawValue != text.value {
                        parts.append("原始：\(rawValue)")
                    }
                    if let styleName = text.styleName {
                        parts.append("样式：\(styleName)")
                    }
                    if let fontFile = text.fontFile {
                        parts.append("字体：\(fontFile)")
                    }
                    if let bigFontFile = text.bigFontFile {
                        parts.append("大字体：\(bigFontFile)")
                    }
                    if let chosenCodepage = text.chosenCodepage {
                        parts.append("命中：\(codePageDisplayName(Int32(chosenCodepage)))")
                    }
                    if let rawHex = text.rawTextBytesHex, !rawHex.isEmpty {
                        parts.append("raw：\(rawHex)")
                    }
                    lines.append("- \(parts.joined(separator: " | "))")
                }
            }
        } catch {
            lines.append("状态：失败")
            lines.append("错误：\(error.localizedDescription)")
        }
        return lines
    }

    private static func renderScore(_ model: DXFPreviewModel) -> Int {
        var score = model.texts.count * 3
        for text in model.texts.prefix(500) {
            score += CADTextNormalizer.diagnosticScore(text.value)
            if let chosen = text.chosenCodepage,
               chosen == 936 || chosen == 54936 || chosen == 950 || chosen == 65001 {
                score += 2
            }
        }
        score -= min(model.unsupportedEntityCount, 200)
        return score
    }

    private static func makeProbeLines(fileURL: URL, codePage: Int32?, title: String) -> [String] {
        var result = SKCADParseResult()
        let overrideCodePage = codePage ?? 0
        let success = fileURL.path.withCString { path in
            sk_libredwg_parse_file_with_codepage(path, Int32(overrideCodePage), &result)
        }
        defer {
            sk_libredwg_free_parse_result(&result)
        }

        var lines: [String] = []
        lines.append("### \(title)")
        lines.append("状态：\(success != 0 ? "成功" : "失败")")
        lines.append("读取状态 / 错误码：\(result.readStatus)")
        if let error = fixedString(&result.errorMessage), !error.isEmpty {
            lines.append("错误信息：\(error)")
        }
        lines.append("DWG 版本：\(versionSummary(&result))")
        lines.append("DWG header codepage：\(nativeCodePageDisplayName(Int(result.headerCodepage)))")
        lines.append("实际正文编码：\(nativeCodePageDisplayName(Int(result.effectiveCodepage)))")
        lines.append("对象总数：\(Int(result.totalObjectCount))")
        lines.append("可绘制 primitive：\(Int(result.primitiveCount))")
        lines.append("文字 primitive：\(Int(result.textPrimitiveCount))")
        lines.append("疑似乱码文字：\(Int(result.suspiciousTextCount))")
        lines.append("Mojibake 文字：\(Int(result.mojibakeTextCount))")
        lines.append("未支持对象：\(Int(result.unsupportedEntityCount))")
        if let unsupported = fixedString(&result.unsupportedEntitySummary), !unsupported.isEmpty {
            lines.append("未支持对象明细：\(unsupported)")
        }

        let primitiveStats = primitiveDiagnostics(from: &result)
        if !primitiveStats.entityCounts.isEmpty {
            lines.append("实体统计：\(primitiveStats.entityCounts.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")
        }
        if !primitiveStats.layerCounts.isEmpty {
            lines.append("图层 Top：\(topSummary(primitiveStats.layerCounts, limit: 10))")
        }
        if !primitiveStats.styleNames.isEmpty {
            lines.append("文字样式：\(primitiveStats.styleNames.sorted().joined(separator: ", "))")
        }
        if !primitiveStats.fontFiles.isEmpty {
            lines.append("字体文件：\(primitiveStats.fontFiles.sorted().joined(separator: ", "))")
        }
        if !primitiveStats.bigFontFiles.isEmpty {
            lines.append("大字体文件：\(primitiveStats.bigFontFiles.sorted().joined(separator: ", "))")
        }
        if !primitiveStats.chosenCodepages.isEmpty {
            lines.append("文字解码命中：\(topSummary(primitiveStats.chosenCodepages, limit: 8))")
        }
        if !primitiveStats.textSamples.isEmpty {
            lines.append("文字样本：")
            for sample in primitiveStats.textSamples {
                lines.append("- \(sample)")
            }
        }
        return lines
    }

    private struct PrimitiveStats {
        var entityCounts: [String: Int] = [:]
        var layerCounts: [String: Int] = [:]
        var styleNames: Set<String> = []
        var fontFiles: Set<String> = []
        var bigFontFiles: Set<String> = []
        var chosenCodepages: [String: Int] = [:]
        var textSamples: [String] = []
    }

    private static func primitiveDiagnostics(from result: inout SKCADParseResult) -> PrimitiveStats {
        var stats = PrimitiveStats()
        guard let primitives = result.primitives, result.primitiveCount > 0 else { return stats }
        let buffer = UnsafeBufferPointer(start: primitives, count: Int(result.primitiveCount))
        for primitive in buffer {
            stats.entityCounts[primitiveKindName(primitive.kind), default: 0] += 1
            if let layer = string(primitive.layerName) {
                stats.layerCounts[layer, default: 0] += 1
            }
            guard isTextPrimitive(primitive.kind) else { continue }
            if let styleName = string(primitive.textStyleName) {
                stats.styleNames.insert(styleName)
            }
            if let fontFile = string(primitive.fontFile) {
                stats.fontFiles.insert(fontFile)
            }
            if let bigFontFile = string(primitive.bigFontFile) {
                stats.bigFontFiles.insert(bigFontFile)
            }
            if primitive.chosenCodepage > 0 {
                stats.chosenCodepages[codePageDisplayName(Int32(primitive.chosenCodepage)), default: 0] += 1
            }
            if stats.textSamples.count < 20 {
                let text = string(primitive.text) ?? ""
                let rawHex = string(primitive.rawTextBytesHex) ?? "-"
                let style = string(primitive.textStyleName) ?? "-"
                let font = string(primitive.fontFile) ?? "-"
                let bigFont = string(primitive.bigFontFile) ?? "-"
                stats.textSamples.append("文字：\(text) | 原始字节：\(rawHex) | 样式：\(style) | 字体：\(font) | 大字体：\(bigFont) | 编码：\(codePageDisplayName(Int32(primitive.chosenCodepage)))")
            }
        }
        return stats
    }

    private static func probeCandidates(preferredCodePage: Int32?) -> [(codePage: Int32?, title: String)] {
        var candidates: [(Int32?, String)] = []
        func append(_ codePage: Int32?, _ title: String) {
            if candidates.contains(where: { $0.0 == codePage }) { return }
            candidates.append((codePage, title))
        }
        append(preferredCodePage, "当前设置：\(codePageDisplayName(preferredCodePage))")
        append(nil, "自动正文编码")
        append(936, "GBK / CP936")
        append(54936, "GB18030 / CP54936")
        append(950, "Big5 / CP950")
        append(65001, "UTF-8 / CP65001")
        append(932, "Shift-JIS / CP932")
        return candidates
    }

    private static func textRenderProbeCandidates(
        preferredCodePage: Int32?,
        preferredBigFont: Int32?
    ) -> [(codePage: Int32?, bigFont: Int32?, title: String)] {
        var candidates: [(Int32?, Int32?, String)] = []
        var seen = Set<String>()

        func append(_ codePage: Int32?, _ bigFont: Int32?, _ title: String) {
            let key = "\(codePage.map(String.init) ?? "auto")-\(bigFont.map(String.init) ?? "auto")"
            guard seen.insert(key).inserted else { return }
            candidates.append((codePage, bigFont, title))
        }

        append(preferredCodePage, preferredBigFont, "当前设置：\(codePageDisplayName(preferredCodePage)) / \(bigFontDisplayName(preferredBigFont))")
        append(nil, 0, "自动正文 / 自动 SHX")
        append(936, 0, "GBK / 自动 SHX")
        append(936, 1, "GBK / GBCBIG")
        append(936, 2, "GBK / HZTXT")
        append(936, 3, "GBK / HZFS")
        append(54936, 0, "GB18030 / 自动 SHX")
        append(54936, 1, "GB18030 / GBCBIG")
        append(54936, 2, "GB18030 / HZTXT")
        append(54936, 3, "GB18030 / HZFS")
        append(950, 4, "Big5 / Big5")
        append(65001, 0, "UTF-8 / 自动 SHX")
        return candidates
    }

    private static func primitiveKindName(_ kind: SKCADPrimitiveKind) -> String {
        switch kind {
        case SKCADPrimitiveLine:
            return "LINE"
        case SKCADPrimitivePolyline:
            return "POLYLINE"
        case SKCADPrimitiveArc:
            return "ARC"
        case SKCADPrimitiveCircle:
            return "CIRCLE"
        case SKCADPrimitiveEllipse:
            return "ELLIPSE"
        case SKCADPrimitiveText:
            return "TEXT"
        case SKCADPrimitiveMText:
            return "MTEXT"
        case SKCADPrimitiveDimension:
            return "DIMENSION"
        case SKCADPrimitiveHatch:
            return "HATCH"
        case SKCADPrimitiveLeader:
            return "LEADER"
        case SKCADPrimitiveImage:
            return "IMAGE"
        case SKCADPrimitiveWipeout:
            return "WIPEOUT"
        case SKCADPrimitiveBlockRef:
            return "BLOCKREF"
        case SKCADPrimitiveUnknownProxy:
            return "UNKNOWN_PROXY"
        default:
            return "UNKNOWN"
        }
    }

    private static func isTextPrimitive(_ kind: SKCADPrimitiveKind) -> Bool {
        switch kind {
        case SKCADPrimitiveText, SKCADPrimitiveMText, SKCADPrimitiveDimension, SKCADPrimitiveLeader:
            return true
        default:
            return false
        }
    }

    private static func versionSummary(_ result: inout SKCADParseResult) -> String {
        let code = fixedString(&result.dwgVersionCode) ?? "-"
        let type = fixedString(&result.dwgVersionType) ?? "-"
        let desc = fixedString(&result.dwgVersionDescription) ?? "-"
        return "\(code) / \(type) / \(desc) / headerVersion=\(Int(result.dwgHeaderDwgVersion)) maint=\(Int(result.dwgHeaderMaintVersion))"
    }

    private static func fixedString<T>(_ value: inout T) -> String? {
        withUnsafeBytes(of: &value) { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: CChar.self).baseAddress else {
                return nil
            }
            let text = lossyCString(baseAddress).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }

    private static func string(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        let text = lossyCString(UnsafePointer(pointer)).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func lossyCString(_ pointer: UnsafePointer<CChar>) -> String {
        let length = strlen(pointer)
        guard length > 0 else { return "" }
        let bytes = UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self)
        let buffer = UnsafeBufferPointer(start: bytes, count: length)
        return String(decoding: buffer, as: UTF8.self)
    }

    private static func topSummary(_ values: [String: Int], limit: Int) -> String {
        values
            .sorted {
                if $0.value == $1.value {
                    return $0.key.localizedStandardCompare($1.key) == .orderedAscending
                }
                return $0.value > $1.value
            }
            .prefix(limit)
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
    }

    private static func codePageDisplayName(_ codePage: Int32?) -> String {
        guard let codePage, codePage > 0 else { return "自动/未知" }
        switch codePage {
        case 936:
            return "GBK CP936"
        case 54936:
            return "GB18030 CP54936"
        case 950:
            return "Big5 CP950"
        case 932:
            return "Shift-JIS CP932"
        case 949:
            return "Korean CP949"
        case 65001:
            return "UTF-8 CP65001"
        default:
            return "CP\(Int(codePage))"
        }
    }

    private static func nativeCodePageDisplayName(_ codePage: Int) -> String {
        switch codePage {
        case 0:
            return "UTF-8/未声明"
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
        case 255:
            return "未定义"
        default:
            return "DWG_CP\(codePage)"
        }
    }

    private static func bigFontDisplayName(_ code: Int32?) -> String {
        guard let code else { return "自动 SHX" }
        switch code {
        case 0:
            return "自动 SHX"
        case 1:
            return "GBCBIG"
        case 2:
            return "HZTXT"
        case 3:
            return "HZFS"
        case 4:
            return "Big5"
        case 9:
            return "关闭映射"
        default:
            return "大字体代码 \(Int(code))"
        }
    }

    private static func dwgMagicText(_ fileURL: URL) -> String {
        guard let raw = try? readPrefixBytes(fileURL, count: 6),
              !raw.isEmpty else {
            return "-"
        }
        let magic = raw.prefix(6)
        return String(data: magic, encoding: .ascii) ?? magic.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func headerHex(_ fileURL: URL) -> String {
        guard let raw = try? readPrefixBytes(fileURL, count: 32) else { return "-" }
        return raw.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func readPrefixBytes(_ fileURL: URL, count: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        return try handle.read(upToCount: count) ?? Data()
    }

    private static func fileSizeText(_ fileURL: URL) -> String {
        guard let bytes = fileSizeBytes(fileURL) else {
            return "-"
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private static func fileSizeBytes(_ fileURL: URL) -> UInt64? {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]) else {
            return nil
        }
        return UInt64(max(values.fileSize ?? values.totalFileAllocatedSize ?? 0, 0))
    }

    private static func modifiedTimeText(_ fileURL: URL) -> String {
        guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]),
              let modified = values.contentModificationDate else {
            return "-"
        }
        return dateTimeFormatter.string(from: modified)
    }

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
