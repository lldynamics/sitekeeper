import Foundation

public struct LibreDWGTextAutoDetectionResult: Sendable {
    public let codePage: Int32?
    public let bigFont: Int32?
    public let styleName: String?
    public let fontFile: String?
    public let bigFontFile: String?
    public let score: Int
    public let styleSummary: String?
    public let rawTextBytesHexSample: String?
    public let detectionSummary: String?
    public let summary: String

    public init(
        codePage: Int32?,
        bigFont: Int32?,
        styleName: String?,
        fontFile: String?,
        bigFontFile: String?,
        score: Int,
        styleSummary: String?,
        rawTextBytesHexSample: String?,
        detectionSummary: String?,
        summary: String
    ) {
        self.codePage = codePage
        self.bigFont = bigFont
        self.styleName = styleName
        self.fontFile = fontFile
        self.bigFontFile = bigFontFile
        self.score = score
        self.styleSummary = styleSummary
        self.rawTextBytesHexSample = rawTextBytesHexSample
        self.detectionSummary = detectionSummary
        self.summary = summary
    }
}

public enum LibreDWGTextAutoDetector {
    public static func detect(fileURL: URL) throws -> LibreDWGTextAutoDetectionResult {
        let model = try LibreDWGNativeParser.parse(
            fileURL: fileURL,
            preferredCodePage: nil,
            preferredBigFont: 0
        )
        return detect(model: model)
    }

    static func detect(model: DXFPreviewModel) -> LibreDWGTextAutoDetectionResult {
        let candidates = textProbeCandidates()

        var best: LibreDWGTextAutoDetectionResult?

        for candidate in candidates {
            let evaluated = evaluate(candidate: candidate, model: model)
            if best == nil || evaluated.score > best!.score {
                best = evaluated
            }
        }

        if let best {
            let profile = dominantTextProfile(from: model)
            let resolvedCodePage = best.codePage ?? profile.codePage
            let resolvedBigFont = best.bigFont ?? Int32(0)
            let aliasSummary = CADSHXFontCatalog.diagnosticSummary(
                styleName: profile.styleName,
                fontFile: profile.fontFile,
                bigFontFile: profile.bigFontFile
            ) ?? "-"
            let summaryParts = [
                best.summary,
                "单次解析重算",
                "STYLE \(profile.styleSummary ?? "-")",
                "字体映射 \(aliasSummary)",
                "样式 \(profile.styleName ?? "-")",
                "字体 \(profile.fontFile ?? "-")",
                "大字体 \(profile.bigFontFile ?? "-")",
            ]
            let summary = summaryParts.joined(separator: "，")
            return LibreDWGTextAutoDetectionResult(
                codePage: resolvedCodePage,
                bigFont: resolvedBigFont,
                styleName: profile.styleName,
                fontFile: profile.fontFile,
                bigFontFile: profile.bigFontFile,
                score: best.score,
                styleSummary: profile.styleSummary ?? model.styleTableSummary,
                rawTextBytesHexSample: profile.rawTextBytesHexSample,
                detectionSummary: summary,
                summary: summary
            )
        }
        let profile = dominantTextProfile(from: model)
        return LibreDWGTextAutoDetectionResult(
            codePage: profile.codePage,
            bigFont: 0,
            styleName: profile.styleName,
            fontFile: profile.fontFile,
            bigFontFile: profile.bigFontFile,
            score: 0,
            styleSummary: profile.styleSummary ?? model.styleTableSummary,
            rawTextBytesHexSample: profile.rawTextBytesHexSample,
            detectionSummary: "未找到可评分文字，已保留当前图纸文字方案。",
            summary: "未找到可评分文字，已保留当前图纸文字方案。"
        )
    }

    private static func textProbeCandidates() -> [(codePage: Int32?, bigFont: Int32?, name: String)] {
        var result: [(codePage: Int32?, bigFont: Int32?, name: String)] = []
        var seen = Set<String>()

        func append(_ codePage: Int32?, _ bigFont: Int32?, _ name: String) {
            let key = "\(codePage.map(String.init) ?? "auto")-\(bigFont.map(String.init) ?? "auto")"
            guard seen.insert(key).inserted else { return }
            result.append((codePage, bigFont, name))
        }

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
        append(950, 0, "Big5 / 自动 SHX")
        append(65001, 0, "UTF-8 / 自动 SHX")
        append(932, 0, "Shift-JIS / 自动 SHX")
        return result
    }

    private static func evaluate(
        candidate: (codePage: Int32?, bigFont: Int32?, name: String),
        model: DXFPreviewModel
    ) -> LibreDWGTextAutoDetectionResult {
        var score = model.texts.count * 3
        var codePageHits: [Int32: Int] = [:]
        var decodedCount = 0
        for text in model.texts.prefix(500) {
            let profile = bigFontProfile(for: candidate.bigFont, text: text)
            let normalized = CADTextNormalizer.bestEffortNormalizedText(
                decodedText: text.rawValue ?? text.value,
                rawTextBytesHex: text.rawTextBytesHex,
                preferredCodePage: candidate.codePage,
                bigFontProfile: profile
            )
            guard !normalized.text.isEmpty else { continue }
            decodedCount += 1
            score += CADTextNormalizer.diagnosticScore(normalized.text)
            if let chosen = normalized.codePage {
                codePageHits[chosen, default: 0] += 1
                score += chosen == 936 || chosen == 54936 || chosen == 950 || chosen == 65001 ? 2 : 0
            }
        }
        if model.unsupportedEntityCount > 0 {
            score -= min(model.unsupportedEntityCount, 200)
        }
        let resolvedCodePage = candidate.codePage ?? dominantValue(in: codePageHits)
        return LibreDWGTextAutoDetectionResult(
            codePage: resolvedCodePage,
            bigFont: candidate.bigFont,
            styleName: nil,
            fontFile: nil,
            bigFontFile: nil,
            score: score,
            styleSummary: nil,
            rawTextBytesHexSample: nil,
            detectionSummary: "\(candidate.name)，文字 \(decodedCount)/\(model.texts.count) 段，评分 \(score)",
            summary: "\(candidate.name)，文字 \(decodedCount)/\(model.texts.count) 段，评分 \(score)"
        )
    }

    private static func bigFontProfile(
        for bridgeCode: Int32?,
        text: DXFPreviewModel.TextEntity
    ) -> CADTextBigFontProfile {
        guard let bridgeCode,
              let profile = CADTextBigFontProfile(rawValue: bridgeCode),
              profile != .auto else {
            return CADTextBigFontProfile.inferred(
                styleName: text.styleName,
                fontFile: text.fontFile,
                bigFontFile: text.bigFontFile
            )
        }
        return profile
    }

    private static func dominantTextProfile(
        from model: DXFPreviewModel
    ) -> (
        styleName: String?,
        fontFile: String?,
        bigFontFile: String?,
        codePage: Int32?,
        styleSummary: String?,
        rawTextBytesHexSample: String?
    ) {
        var styleNames: [String: Int] = [:]
        var fontFiles: [String: Int] = [:]
        var bigFontFiles: [String: Int] = [:]
        var codePages: [Int32: Int] = [:]
        var profileTriples: [String: Int] = [:]
        var rawSamples: [String] = []

        for text in model.texts.prefix(2_000) {
            let styleName = normalizedTextField(text.styleName)
            let fontFile = normalizedTextField(text.fontFile)
            let bigFontFile = normalizedTextField(text.bigFontFile)
            if let styleName {
                styleNames[styleName, default: 0] += 1
            }
            if let fontFile {
                fontFiles[fontFile, default: 0] += 1
            }
            if let bigFontFile {
                bigFontFiles[bigFontFile, default: 0] += 1
            }
            if let chosen = text.chosenCodepage, chosen > 0 {
                codePages[Int32(chosen), default: 0] += 1
            }
            if styleName != nil || fontFile != nil || bigFontFile != nil {
                let key = "\(styleName ?? "-")/\(fontFile ?? "-")/\(bigFontFile ?? "-")"
                profileTriples[key, default: 0] += 1
            }
            if rawSamples.count < 3,
               let raw = normalizedTextField(text.rawTextBytesHex),
               !rawSamples.contains(raw) {
                rawSamples.append(raw)
            }
        }

        return (
            styleName: dominantValue(in: styleNames),
            fontFile: dominantValue(in: fontFiles),
            bigFontFile: dominantValue(in: bigFontFiles),
            codePage: dominantValue(in: codePages),
            styleSummary: dominantStyleSummary(from: profileTriples) ?? model.styleTableSummary,
            rawTextBytesHexSample: rawSamples.isEmpty ? nil : rawSamples.joined(separator: " | ")
        )
    }

    private static func dominantStyleSummary(from histogram: [String: Int]) -> String? {
        let sorted = histogram.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
            }
            return lhs.value > rhs.value
        }
        guard !sorted.isEmpty else { return nil }
        return sorted.prefix(5).map { "\($0.key) x\($0.value)" }.joined(separator: "；")
    }

    private static func normalizedTextField(_ value: String?) -> String? {
        let text = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func dominantValue<T: Comparable>(in counter: [T: Int]) -> T? {
        counter.max { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key > rhs.key
            }
            return lhs.value < rhs.value
        }?.key
    }
}
