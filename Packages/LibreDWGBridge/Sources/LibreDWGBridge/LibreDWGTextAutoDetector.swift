import Foundation

public struct LibreDWGTextAutoDetectionResult: Sendable {
    public let codePage: Int32?
    public let bigFont: Int32?
    public let score: Int
    public let summary: String

    public init(codePage: Int32?, bigFont: Int32?, score: Int, summary: String) {
        self.codePage = codePage
        self.bigFont = bigFont
        self.score = score
        self.summary = summary
    }
}

public enum LibreDWGTextAutoDetector {
    public static func detect(fileURL: URL) throws -> LibreDWGTextAutoDetectionResult {
        let candidates: [(codePage: Int32?, bigFont: Int32?, name: String)] = [
            (936, 0, "GBK / 自动 SHX"),
            (54936, 0, "GB18030 / 自动 SHX"),
            (950, 4, "Big5 / Big5"),
            (65001, 0, "UTF-8 / 自动 SHX"),
            (932, 0, "Shift-JIS / 自动 SHX"),
        ]

        var best: (result: LibreDWGTextAutoDetectionResult, model: DXFPreviewModel)?
        var failures: [String] = []

        for candidate in candidates {
            do {
                let model = try LibreDWGNativeParser.parse(
                    fileURL: fileURL,
                    preferredCodePage: candidate.codePage,
                    preferredBigFont: candidate.bigFont
                )
                let score = score(model: model)
                let summary = "\(candidate.name)，文字 \(model.texts.count) 段，评分 \(score)"
                let result = LibreDWGTextAutoDetectionResult(
                    codePage: candidate.codePage,
                    bigFont: candidate.bigFont,
                    score: score,
                    summary: summary
                )
                if best == nil || score > best!.result.score {
                    best = (result, model)
                }
            } catch {
                failures.append("\(candidate.name)：\(error.localizedDescription)")
            }
        }

        if let best {
            return best.result
        }
        throw NSError(domain: "LibreDWGBridge", code: 2101, userInfo: [
            NSLocalizedDescriptionKey: failures.first ?? "文字自动识别失败。",
        ])
    }

    private static func score(model: DXFPreviewModel) -> Int {
        var score = model.texts.count * 3
        for text in model.texts.prefix(500) {
            score += CADTextNormalizer.diagnosticScore(text.value)
            if let chosen = text.chosenCodepage {
                score += chosen == 936 || chosen == 54936 || chosen == 950 || chosen == 65001 ? 2 : 0
            }
        }
        if model.unsupportedEntityCount > 0 {
            score -= min(model.unsupportedEntityCount, 200)
        }
        return score
    }
}
