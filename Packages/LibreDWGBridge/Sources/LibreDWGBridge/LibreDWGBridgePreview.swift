import Foundation
import SwiftUI

public struct LibreDWGBridgePreview: View {
    public let fileURL: URL
    public let preferredCodePage: Int32?
    public let preferredBigFont: Int32?
    public let onCanvasTransformChange: (LibreDWGCanvasTransformSnapshot) -> Void
    public let onSnapPointsChange: ([LibreDWGSnapPointPayload]) -> Void
    public let onTextAutoDetectionChange: (LibreDWGTextAutoDetectionSnapshot) -> Void

    @State private var state: PreviewState = .loading
    @State private var loadTask: Task<Void, Never>?
    @State private var loadTimeoutTask: Task<Void, Never>?

    public init(
        fileURL: URL,
        preferredCodePage: Int32? = nil,
        preferredBigFont: Int32? = nil,
        onCanvasTransformChange: @escaping (LibreDWGCanvasTransformSnapshot) -> Void = { _ in },
        onSnapPointsChange: @escaping ([LibreDWGSnapPointPayload]) -> Void = { _ in },
        onTextAutoDetectionChange: @escaping (LibreDWGTextAutoDetectionSnapshot) -> Void = { _ in }
    ) {
        self.fileURL = fileURL
        self.preferredCodePage = preferredCodePage
        self.preferredBigFont = preferredBigFont
        self.onCanvasTransformChange = onCanvasTransformChange
        self.onSnapPointsChange = onSnapPointsChange
        self.onTextAutoDetectionChange = onTextAutoDetectionChange
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .task(id: taskIdentity) {
                startLoadingPreview()
            }
            .onDisappear {
                cancelLoadingPreview()
            }
    }

    private var taskIdentity: String {
        "\(fileURL.path)#\(preferredCodePage.map(String.init) ?? "auto")#\(preferredBigFont.map(String.init) ?? "auto")"
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("正在加载图纸…")
                .controlSize(.large)
        case .dxf(let model, let sourceHint):
            DXFCanvasPreview(
                model: model,
                sourceHint: sourceHint,
                fileURL: fileURL,
                onCanvasTransformChange: onCanvasTransformChange,
                onSnapPointsChange: onSnapPointsChange
            )
        case .pdf(let url, let sourceHint):
            PDFSidecarPreview(fileURL: url, sourceHint: sourceHint)
        case .dwgMetadata(let info):
            DWGMetadataPreview(fileURL: fileURL, info: info)
        case .failed(let reason):
            ContentUnavailableView(
                "图纸预览失败",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(reason)
            )
        }
    }

    private var timeoutMessage: String {
        "DWG 解析超过 20 秒，已停止等待本次预览。建议导出 CAD 诊断日志，检查 DWG 版本、对象数量、未支持实体和文字编码。"
    }

    @MainActor
    private func startLoadingPreview() {
        cancelLoadingPreview()
        state = .loading
        let identity = taskIdentity
        let currentFileURL = fileURL
        let currentPreferredCodePage = preferredCodePage
        let currentPreferredBigFont = preferredBigFont

        let task = Task.detached(priority: .userInitiated) {
            let loadedState = await LibreDWGPreviewEngine.load(
                fileURL: currentFileURL,
                preferredCodePage: currentPreferredCodePage,
                preferredBigFont: currentPreferredBigFont
            )
            await MainActor.run {
                guard identity == taskIdentity, !Task.isCancelled else { return }
                loadTimeoutTask?.cancel()
                loadTimeoutTask = nil
                loadTask = nil
                state = loadedState
                postTextAutoDetectionIfAvailable(for: loadedState, fileURL: currentFileURL)
            }
        }

        loadTask = task
        let timeoutReason = timeoutMessage
        loadTimeoutTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled else { return }
            task.cancel()
            let timeoutState = Self.timeoutFallbackState(
                fileURL: currentFileURL,
                message: timeoutReason
            )
            await MainActor.run {
                guard identity == taskIdentity else { return }
                state = timeoutState
                loadTask = nil
                loadTimeoutTask = nil
            }
        }
    }

    @MainActor
    private func cancelLoadingPreview() {
        loadTask?.cancel()
        loadTask = nil
        loadTimeoutTask?.cancel()
        loadTimeoutTask = nil
    }

    nonisolated private static func timeoutFallbackState(
        fileURL: URL,
        message: String
    ) -> PreviewState {
        guard fileURL.pathExtension.lowercased() == "dwg",
              let info = try? DWGMetadata.from(fileURL: fileURL, hints: [message]) else {
            return .failed(message)
        }
        return .dwgMetadata(info)
    }

    @MainActor
    private func postTextAutoDetectionIfAvailable(for loadedState: PreviewState, fileURL: URL) {
        guard case .dxf(let model, _) = loadedState,
              fileURL.pathExtension.lowercased() == "dwg",
              !model.texts.isEmpty else { return }
        let result = LibreDWGTextAutoDetector.detect(model: model)
        onTextAutoDetectionChange(
            LibreDWGTextAutoDetectionSnapshot(
                codePage: result.codePage,
                bigFont: result.bigFont,
                styleName: result.styleName,
                fontFile: result.fontFile,
                bigFontFile: result.bigFontFile,
                autoDetectScore: result.score,
                styleSummary: result.styleSummary,
                rawTextBytesHexSample: result.rawTextBytesHexSample,
                detectionSummary: result.detectionSummary,
                summary: result.summary
            )
        )
    }
}

enum DXFPreviewParser {
    private struct DecodedTextPayload {
        let text: String
        let resolvedCodePage: Int32?
        let usedPreferredCodePage: Bool
    }

    static func parse(
        fileURL: URL,
        preferredCodePage: Int32? = nil,
        preferredBigFont: Int32? = nil
    ) throws -> DXFPreviewModel {
        let raw = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let decodedPayload = decodeText(raw, preferredCodePage: preferredCodePage)
        let text = decodedPayload.text
        let bigFontProfile = preferredBigFont
            .flatMap(CADTextBigFontProfile.init(rawValue:)) ?? .auto
        let pairs = dxfPairs(from: text)

        var segments: [DXFPreviewModel.Segment] = []
        var polylines: [DXFPreviewModel.Polyline] = []
        var circles: [DXFPreviewModel.Circle] = []
        var texts: [DXFPreviewModel.TextEntity] = []
        var arcCount = 0
        var polylineEntityCount = 0

        var type: String?
        var fields: [Int: [String]] = [:]
        var isCollectingPolyline = false
        var polylineClosed = false
        var polylineVertices: [CGPoint] = []
        var activePolylineLayer = "0"

        func flushEntity() {
            guard let type else { return }
            let layer = fields.firstString(8).flatMap { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            } ?? "0"
            switch type {
            case "LINE":
                if let x1 = fields.firstDouble(10),
                   let y1 = fields.firstDouble(20),
                   let x2 = fields.firstDouble(11),
                   let y2 = fields.firstDouble(21) {
                    segments.append(.init(
                        from: CGPoint(x: x1, y: y1),
                        to: CGPoint(x: x2, y: y2),
                        style: .default,
                        layer: layer
                    ))
                }
            case "LWPOLYLINE":
                let xs = fields.allDoubles(10)
                let ys = fields.allDoubles(20)
                let count = min(xs.count, ys.count)
                if count > 1 {
                    var points: [CGPoint] = (0..<count).map { CGPoint(x: xs[$0], y: ys[$0]) }
                    let flag = fields.firstInt(70) ?? 0
                    if (flag & 0x01) == 0x01, let first = points.first {
                        points.append(first)
                    }
                    polylines.append(.init(points: points, style: .default, layer: layer))
                    polylineEntityCount += 1
                }
            case "POLYLINE":
                isCollectingPolyline = true
                polylineClosed = ((fields.firstInt(70) ?? 0) & 0x01) == 0x01
                polylineVertices = []
                activePolylineLayer = layer
            case "VERTEX":
                guard isCollectingPolyline,
                      let x = fields.firstDouble(10),
                      let y = fields.firstDouble(20) else { break }
                polylineVertices.append(CGPoint(x: x, y: y))
            case "SEQEND":
                guard isCollectingPolyline else { break }
                var points = polylineVertices
                if polylineClosed, let first = points.first, points.count > 1 {
                    points.append(first)
                }
                if points.count > 1 {
                    polylines.append(.init(points: points, style: .default, layer: activePolylineLayer))
                    polylineEntityCount += 1
                }
                isCollectingPolyline = false
                polylineVertices = []
                activePolylineLayer = "0"
            case "CIRCLE":
                if let x = fields.firstDouble(10),
                   let y = fields.firstDouble(20),
                   let radius = fields.firstDouble(40),
                   radius > 0 {
                    circles.append(.init(
                        center: CGPoint(x: x, y: y),
                        radius: radius,
                        style: .default,
                        layer: layer
                    ))
                }
            case "ARC":
                if let centerX = fields.firstDouble(10),
                   let centerY = fields.firstDouble(20),
                   let radius = fields.firstDouble(40),
                   let start = fields.firstDouble(50),
                   let end = fields.firstDouble(51),
                   radius > 0 {
                    let arcPoints = sampleArcPoints(
                        center: CGPoint(x: centerX, y: centerY),
                        radius: radius,
                        startDegrees: start,
                        endDegrees: end
                    )
                    if arcPoints.count > 1 {
                        polylines.append(.init(points: arcPoints, style: .default, layer: layer))
                        arcCount += 1
                    }
                }
            case "SOLID", "TRACE", "3DFACE":
                if let x1 = fields.firstDouble(10),
                   let y1 = fields.firstDouble(20),
                   let x2 = fields.firstDouble(11),
                   let y2 = fields.firstDouble(21),
                   let x3 = fields.firstDouble(12),
                   let y3 = fields.firstDouble(22) {
                    var points = [
                        CGPoint(x: x1, y: y1),
                        CGPoint(x: x2, y: y2),
                        CGPoint(x: x3, y: y3),
                    ]
                    if let x4 = fields.firstDouble(13),
                       let y4 = fields.firstDouble(23) {
                        points.append(CGPoint(x: x4, y: y4))
                    }
                    if let first = points.first {
                        points.append(first)
                    }
                    if points.count > 2 {
                        polylines.append(.init(points: points, style: .default, layer: layer))
                    }
                }
            case "DIMENSION":
                if let x1 = fields.firstDouble(13),
                   let y1 = fields.firstDouble(23),
                   let x2 = fields.firstDouble(14),
                   let y2 = fields.firstDouble(24) {
                    polylines.append(.init(
                        points: [CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2)],
                        style: DXFPreviewModel.StrokeStyle(rgb: 0x008EA8, width: 0.9),
                        layer: layer,
                        renderKind: .dimension
                    ))
                }
                if let x = fields.firstDouble(11),
                   let y = fields.firstDouble(21),
                   let rawValue = fields.firstString(1) {
                    let normalized = normalizeDXFText(rawValue, bigFontProfile: bigFontProfile)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            rawValue: rawValue,
                            rawTextBytesHex: nil,
                            chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(53) ?? 0) * .pi / 180),
                            style: DXFPreviewModel.StrokeStyle(rgb: 0x008EA8, width: 0.9),
                            layer: layer,
                            renderKind: .dimension
                        ))
                    }
                }
            case "LEADER", "MULTILEADER":
                let xs = fields.allDoubles(10)
                let ys = fields.allDoubles(20)
                let count = min(xs.count, ys.count)
                if count > 1 {
                    let points = (0..<count).map { CGPoint(x: xs[$0], y: ys[$0]) }
                    polylines.append(.init(points: points, style: .default, layer: layer))
                }
                if let x = fields.firstDouble(11),
                   let y = fields.firstDouble(21),
                   let rawValue = fields.firstString(304) ?? fields.firstString(1) {
                    let normalized = normalizeDXFText(rawValue, bigFontProfile: bigFontProfile)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            rawValue: rawValue,
                            rawTextBytesHex: nil,
                            chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(50) ?? 0) * .pi / 180),
                            style: DXFPreviewModel.StrokeStyle(rgb: 0x7A3DB8, width: 0.8),
                            layer: layer,
                            renderKind: .leader
                        ))
                    }
                }
            case "HATCH":
                let xs = fields.allDoubles(10)
                let ys = fields.allDoubles(20)
                let count = min(xs.count, ys.count)
                if count > 1 {
                    var points = (0..<count).map { CGPoint(x: xs[$0], y: ys[$0]) }
                    if let first = points.first, let last = points.last,
                       (abs(first.x - last.x) > 0.0001 || abs(first.y - last.y) > 0.0001) {
                        points.append(first)
                    }
                    polylines.append(.init(
                        points: points,
                        style: DXFPreviewModel.StrokeStyle(rgb: 0xCC7A00, width: 0.7),
                        layer: layer,
                        renderKind: .hatch
                    ))
                    if let labelPoint = centroid(of: points),
                       let rawPattern = fields.firstString(2) {
                        let pattern = normalizeDXFText(rawPattern, bigFontProfile: bigFontProfile)
                        let label = hatchLabel(for: pattern, solidFlag: fields.firstInt(70))
                        if !label.isEmpty {
                            texts.append(.init(
                                point: labelPoint,
                                value: label,
                                rawValue: rawPattern,
                                rawTextBytesHex: nil,
                                chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
                                height: max(fields.firstDouble(41) ?? 2, 1.4),
                                rotation: 0,
                                style: DXFPreviewModel.StrokeStyle(rgb: 0xCC7A00, width: 0.7),
                                layer: layer,
                                renderKind: .hatch
                            ))
                        }
                    }
                }
            case "IMAGE", "WIPEOUT":
                if let x = fields.firstDouble(10),
                   let y = fields.firstDouble(20),
                   let ux = fields.firstDouble(11),
                   let uy = fields.firstDouble(21),
                   let vx = fields.firstDouble(12),
                   let vy = fields.firstDouble(22),
                   let width = fields.firstDouble(13),
                   let height = fields.firstDouble(23) {
                    let a = CGPoint(x: x, y: y)
                    let b = CGPoint(x: x + ux * width, y: y + uy * width)
                    let d = CGPoint(x: x + vx * height, y: y + vy * height)
                    let c = CGPoint(x: b.x + (d.x - a.x), y: b.y + (d.y - a.y))
                    let points = [a, b, c, d, a]
                    polylines.append(.init(points: points, style: .default, layer: layer))
                }
            case "TEXT", "ATTRIB":
                if let x = fields.firstDouble(10),
                   let y = fields.firstDouble(20),
                   let rawValue = fields.firstString(1) {
                    let styleName = fields.firstString(7)
                    let normalized = normalizeDXFText(rawValue, bigFontProfile: bigFontProfile)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            rawValue: rawValue,
                            rawTextBytesHex: nil,
                            chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(50) ?? 0) * .pi / 180),
                            style: .default,
                            layer: layer,
                            styleName: styleName,
                            renderKind: type == "ATTRIB" ? .attribute : .regular,
                            kind: type == "ATTRIB" ? .text : .text
                        ))
                    }
                }
            case "MTEXT":
                if let x = fields.firstDouble(10),
                   let y = fields.firstDouble(20) {
                    let styleName = fields.firstString(7)
                    let chunks = fields.allStrings(3)
                    let tail = fields.firstString(1).map { [$0] } ?? []
                    let merged = (chunks + tail).joined()
                    let normalized = normalizeDXFText(merged, bigFontProfile: bigFontProfile)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            rawValue: merged,
                            rawTextBytesHex: nil,
                            chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(50) ?? 0) * .pi / 180),
                            style: .default,
                            layer: layer,
                            styleName: styleName,
                            kind: .mtext
                        ))
                    }
                }
            default:
                break
            }
        }

        for pair in pairs {
            if pair.code == 0 {
                flushEntity()
                type = pair.value.uppercased()
                fields = [:]
            } else if type != nil {
                fields[pair.code, default: []].append(pair.value)
            }
        }
        flushEntity()

        let bounds = computeBounds(
            segments: segments,
            polylines: polylines,
            circles: circles,
            texts: texts
        )
        guard let bounds else {
            throw NSError(domain: "LibreDWGBridge", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "未识别到可绘制的 DXF 几何元素（当前支持 LINE / ARC / LWPOLYLINE / POLYLINE / CIRCLE / SOLID / 3DFACE / DIMENSION / TEXT / MTEXT / ATTRIB）。",
            ])
        }

        return DXFPreviewModel(
            segments: segments,
            polylines: polylines,
            circles: circles,
            texts: texts,
            arcCount: arcCount,
            polylineEntityCount: polylineEntityCount,
            textDecodingHint: decodingHint(
                preferredCodePage: preferredCodePage,
                resolvedCodePage: decodedPayload.resolvedCodePage,
                preferredBigFont: preferredBigFont,
                usedPreferredCodePage: decodedPayload.usedPreferredCodePage
            ),
            bounds: bounds
        )
    }

    private static func decodeText(_ data: Data, preferredCodePage: Int32?) -> DecodedTextPayload {
        let candidates: [(Int32?, String.Encoding)] = {
            var values: [(Int32?, String.Encoding)] = []
            if let preferredCodePage, let encoding = stringEncoding(for: preferredCodePage) {
                values.append((preferredCodePage, encoding))
            }
            values.append(contentsOf: [
                (65001, .utf8),
                (936, stringEncoding(for: 936)),
                (54936, stringEncoding(for: 54936)),
                (950, stringEncoding(for: 950)),
                (932, .shiftJIS),
                (949, stringEncoding(for: 949)),
                (20127, .ascii),
            ].compactMap { codePage, encoding in
                encoding.map { (codePage, $0) }
            })
            return values
        }()

        var seen: Set<UInt> = []
        var best: (text: String, score: Int, codePage: Int32?)?
        for (codePage, encoding) in candidates where seen.insert(encoding.rawValue).inserted {
            guard let decoded = String(data: data, encoding: encoding) else { continue }
            let score = decodedQualityScore(decoded)
            if let preferredCodePage, codePage == preferredCodePage {
                return DecodedTextPayload(
                    text: decoded,
                    resolvedCodePage: preferredCodePage,
                    usedPreferredCodePage: true
                )
            }
            if best == nil || score > best!.score {
                best = (decoded, score, codePage)
            }
        }
        if let best {
            return DecodedTextPayload(
                text: best.text,
                resolvedCodePage: best.codePage,
                usedPreferredCodePage: false
            )
        }
        return DecodedTextPayload(
            text: String(decoding: data, as: UTF8.self),
            resolvedCodePage: 65001,
            usedPreferredCodePage: false
        )
    }

    private static func stringEncoding(for codePage: Int32) -> String.Encoding? {
        let cfEncoding = CFStringConvertWindowsCodepageToEncoding(UInt32(codePage))
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        guard nsEncoding != UInt(kCFStringEncodingInvalidId) else { return nil }
        return String.Encoding(rawValue: nsEncoding)
    }

    private static func decodedQualityScore(_ text: String) -> Int {
        var score = 0
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x3400...0x4DBF).contains(value) ||
                (0x4E00...0x9FFF).contains(value) ||
                (0xF900...0xFAFF).contains(value) ||
                (0x3000...0x303F).contains(value) ||
                (0xFF00...0xFFEF).contains(value) {
                score += 12
            } else if value == 0xFFFD {
                score -= 40
            } else if (0x00A0...0x00FF).contains(value) {
                score -= 6
            } else if value == 0x3F {
                score -= 4
            } else if value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t" {
                score -= 12
            } else if value < 0x7F {
                score += 1
            }
        }
        score += cadVocabularyScore(text)
        return score
    }

    private static func cadVocabularyScore(_ text: String) -> Int {
        let commonTerms = [
            "平面", "立面", "剖面", "详图", "节点", "标高", "轴线", "尺寸",
            "配电", "回路", "照明", "插座", "桥架", "线管", "接地", "负荷", "施工",
            "建筑", "结构", "电气", "给排水", "消防", "弱电", "系统图", "配线",
            "平面圖", "立面圖", "剖面圖", "詳圖", "節點", "標高", "軸線", "尺寸",
            "配電", "迴路", "照明", "插座", "橋架", "線管", "接地", "負荷", "施工",
            "建築", "結構", "電氣", "給排水", "消防", "弱電", "系統圖", "配線",
        ]
        let suspiciousGlyphs = ["Ê", "Ð", "Ä", "Ã", "Â", "Ó", "Æ", "Ë", "·", "µ", "Ç"]
        var score = 0
        for term in commonTerms where text.contains(term) {
            score += 18
        }
        for glyph in suspiciousGlyphs where text.contains(glyph) {
            score -= 18
        }
        return score
    }

    private static func decodingHint(
        preferredCodePage: Int32?,
        resolvedCodePage: Int32?,
        preferredBigFont: Int32?,
        usedPreferredCodePage: Bool
    ) -> String? {
        let bodyText: String
        if usedPreferredCodePage, let preferredCodePage {
            bodyText = "正文 \(codePageName(for: preferredCodePage))"
        } else if let resolvedCodePage {
            bodyText = "正文自动命中 \(codePageName(for: resolvedCodePage))"
        } else {
            bodyText = "正文自动编码"
        }
        let shxText = preferredBigFont
            .flatMap(CADTextBigFontProfile.init(rawValue:))
            .map(bigFontName(for:)) ?? "自动 SHX"
        return "\(bodyText) / \(shxText)"
    }

    private static func codePageName(for codePage: Int32) -> String {
        switch codePage {
        case 936:
            return "GBK 936"
        case 950:
            return "Big5 950"
        case 54936:
            return "GB18030 54936"
        case 932:
            return "Shift-JIS 932"
        case 949:
            return "Korean 949"
        case 65001:
            return "UTF-8"
        case 20127:
            return "ASCII"
        default:
            return "代码页 \(Int(codePage))"
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

    private static func dxfPairs(from text: String) -> [(code: Int, value: String)] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [(code: Int, value: String)] = []
        var index = 0
        while index + 1 < lines.count {
            let codeText = lines[index].trimmingCharacters(in: .whitespaces)
            let valueText = lines[index + 1].trimmingCharacters(in: .whitespaces)
            if let code = Int(codeText) {
                result.append((code: code, value: valueText))
            }
            index += 2
        }
        return result
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
        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private static func sampleArcPoints(
        center: CGPoint,
        radius: CGFloat,
        startDegrees: CGFloat,
        endDegrees: CGFloat
    ) -> [CGPoint] {
        let twoPi = CGFloat.pi * 2
        let start = startDegrees * .pi / 180
        var end = endDegrees * .pi / 180
        while end < start {
            end += twoPi
        }
        let span = max(end - start, 0)
        let segments = max(Int(ceil(span / (.pi / 18))), 8)
        guard segments > 0 else { return [] }

        return (0...segments).map { index in
            let t = CGFloat(index) / CGFloat(segments)
            let angle = start + span * t
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private static func centroid(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let uniquePoints: [CGPoint]
        if points.count > 1, points.first == points.last {
            uniquePoints = Array(points.dropLast())
        } else {
            uniquePoints = points
        }
        guard !uniquePoints.isEmpty else { return nil }

        let sum = uniquePoints.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(
            x: sum.x / CGFloat(uniquePoints.count),
            y: sum.y / CGFloat(uniquePoints.count)
        )
    }

    private static func hatchLabel(for pattern: String, solidFlag: Int?) -> String {
        let normalized = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return ""
        }
        if normalized.caseInsensitiveCompare("SOLID") == .orderedSame || solidFlag == 1 {
            return "实填充"
        }
        return normalized
    }

    private static func normalizeDXFText(_ raw: String, bigFontProfile: CADTextBigFontProfile) -> String {
        CADTextNormalizer.normalize(raw, bigFontProfile: bigFontProfile)
    }
}

private extension Dictionary where Key == Int, Value == [String] {
    func firstDouble(_ code: Int) -> CGFloat? {
        self[code]?.first.flatMap { Double($0) }.map { CGFloat($0) }
    }

    func allDoubles(_ code: Int) -> [CGFloat] {
        (self[code] ?? []).compactMap { Double($0) }.map { CGFloat($0) }
    }

    func firstInt(_ code: Int) -> Int? {
        self[code]?.first.flatMap(Int.init)
    }

    func firstString(_ code: Int) -> String? {
        self[code]?.first
    }

    func allStrings(_ code: Int) -> [String] {
        self[code] ?? []
    }
}
