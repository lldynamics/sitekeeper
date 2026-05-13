import Foundation

enum CADTextBigFontProfile: Int32 {
    case auto = 0
    case gbcbig = 1
    case hztxt = 2
    case hzfs = 3
    case big5 = 4
    case disabled = 9

    var codePageCandidates: [Int32] {
        switch self {
        case .auto:
            return [936, 54936, 950, 65001]
        case .gbcbig, .hztxt, .hzfs:
            return [936, 54936, 65001]
        case .big5:
            return [950, 65001]
        case .disabled:
            return []
        }
    }

    static func inferred(from fontFile: String?) -> CADTextBigFontProfile {
        guard let fontFile else { return .auto }
        let normalized = fontFile
            .lowercased()
            .replacingOccurrences(of: ".shx", with: "")
            .replacingOccurrences(of: ".ttf", with: "")
            .replacingOccurrences(of: ".otf", with: "")
        if normalized.contains("big5") || normalized.contains("chineset") {
            return .big5
        }
        if normalized.contains("hzfs") ||
            normalized.contains("simfang") ||
            normalized.contains("fangsong") ||
            normalized.contains("fs") {
            return .hzfs
        }
        if normalized.contains("hztxt") || normalized.contains("txt") {
            return .hztxt
        }
        if normalized.contains("gbcbig") ||
            normalized.contains("tssdeng") ||
            normalized.contains("tssdchn") ||
            normalized.contains("gb") ||
            normalized.contains("tssd") ||
            normalized.contains("hzd") ||
            normalized.contains("simhei") ||
            normalized.contains("simsun") ||
            normalized.contains("china") ||
            normalized.contains("chinese") {
            return .gbcbig
        }
        return .auto
    }
}

enum CADTextNormalizer {
    static func normalize(_ raw: String, bigFontProfile: CADTextBigFontProfile = .auto) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let unicodeDecoded = decodeUnicodeEscapes(in: trimmed)
        let bigFontDecoded = decodeBigFontUnicodeEscapes(in: unicodeDecoded, profile: bigFontProfile)
        let shxDecoded = decodeNumericSHXEscapes(in: bigFontDecoded, profile: bigFontProfile)
        let repaired = bestTextCandidate(
            from: [
                shxDecoded,
                repairSingleByteMojibake(in: shxDecoded, profile: bigFontProfile),
                repairLegacyChineseDecodedUTF8Mojibake(in: shxDecoded, profile: bigFontProfile),
                repairMixedSingleByteMojibake(in: shxDecoded, profile: bigFontProfile),
            ]
        )
        let stripped = stripFormattingRuns(in: repaired)
        let collapsed = stripped
            .replacingOccurrences(of: "%%c", with: "Φ", options: .caseInsensitive)
            .replacingOccurrences(of: "%%d", with: "°", options: .caseInsensitive)
            .replacingOccurrences(of: "%%p", with: "±", options: .caseInsensitive)
            .replacingOccurrences(of: "%%u", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "%%o", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")

        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func diagnosticScore(_ text: String) -> Int {
        decodedQualityScore(text)
    }

    private static func bestTextCandidate(from candidates: [String]) -> String {
        var best: (text: String, score: Int)?
        for candidate in candidates {
            guard !candidate.isEmpty else { continue }
            let score = decodedQualityScore(candidate)
            if best == nil || score > best!.score {
                best = (candidate, score)
            }
        }
        return best?.text ?? candidates.first ?? ""
    }

    private static func decodeBigFontUnicodeEscapes(in raw: String, profile: CADTextBigFontProfile) -> String {
        let pattern = #"\\M\+[0-9A-Fa-f]([0-9A-Fa-f]{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        let nsRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        var result = raw

        for match in regex.matches(in: raw, range: nsRange).reversed() {
            guard match.numberOfRanges == 2,
                  let fullRange = Range(match.range(at: 0), in: result),
                  let hexRange = Range(match.range(at: 1), in: raw),
                  let value = UInt16(raw[hexRange], radix: 16) else {
                continue
            }

            let bytes = [UInt8(value >> 8), UInt8(value & 0x00FF)]
            let replacement = decodeBytes(bytes, profile: profile) ??
                UnicodeScalar(UInt32(value)).map { String(Character($0)) } ??
                String(result[fullRange])
            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }

    private static func decodeNumericSHXEscapes(in raw: String, profile: CADTextBigFontProfile) -> String {
        let pattern = #"(?:%%[0-9]{3})+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        let nsRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        var result = raw

        for match in regex.matches(in: raw, range: nsRange).reversed() {
            guard let fullRange = Range(match.range(at: 0), in: result),
                  let rawRange = Range(match.range(at: 0), in: raw) else {
                continue
            }

            let run = String(raw[rawRange])
            let values = run.split(separator: "%", omittingEmptySubsequences: true)
                .compactMap { Int($0) }
            guard !values.isEmpty else { continue }

            let bytes = values.compactMap { value -> UInt8? in
                guard (0...255).contains(value) else { return nil }
                return UInt8(value)
            }
            let replacement: String
            if bytes.count == values.count,
               let decoded = decodeBytes(bytes, profile: profile) {
                replacement = decoded
            } else {
                replacement = values
                    .map { fallbackSHXValue($0) }
                    .joined()
            }
            result.replaceSubrange(fullRange, with: replacement)
        }

        return result
    }

    private static func fallbackSHXValue(_ value: Int) -> String {
        switch value {
        case 176:
            return "°"
        case 177:
            return "±"
        case 216:
            return "Ø"
        case 0...127:
            return UnicodeScalar(value).map { String(Character($0)) } ?? ""
        default:
            return String(format: "%%%%%.3d", value)
        }
    }

    private static func repairSingleByteMojibake(in raw: String, profile: CADTextBigFontProfile) -> String {
        guard profile != .disabled,
              raw.unicodeScalars.contains(where: { (0x00A0...0x00FF).contains($0.value) }) else {
            return raw
        }
        let scalars = raw.unicodeScalars
        let bytes = scalars.compactMap { scalar -> UInt8? in
            guard scalar.value <= 0x00FF else { return nil }
            return UInt8(scalar.value)
        }
        guard bytes.count == scalars.count,
              let repaired = decodeBytes(bytes, profile: profile),
              decodedQualityScore(repaired) > decodedQualityScore(raw) + 12 else {
            return raw
        }
        return repaired
    }

    private static func repairMixedSingleByteMojibake(in raw: String, profile: CADTextBigFontProfile) -> String {
        guard profile != .disabled,
              raw.unicodeScalars.contains(where: { (0x00A0...0x00FF).contains($0.value) }) else {
            return raw
        }

        var result = ""
        var latinRun: [UInt8] = []

        func flushLatinRun() {
            guard !latinRun.isEmpty else { return }
            if let decoded = decodeBytes(latinRun, profile: profile),
               decodedQualityScore(decoded) > decodedQualityScore(String(bytes: latinRun, encoding: .isoLatin1) ?? "") + 8 {
                result += decoded
            } else {
                result += latinRun.compactMap { UnicodeScalar(Int($0)).map(String.init) }.joined()
            }
            latinRun.removeAll()
        }

        for scalar in raw.unicodeScalars {
            if scalar.value <= 0x00FF {
                latinRun.append(UInt8(scalar.value))
            } else {
                flushLatinRun()
                result.append(String(scalar))
            }
        }
        flushLatinRun()

        return decodedQualityScore(result) > decodedQualityScore(raw) + 8 ? result : raw
    }

    private static func repairLegacyChineseDecodedUTF8Mojibake(
        in raw: String,
        profile: CADTextBigFontProfile
    ) -> String {
        guard profile != .disabled,
              raw.unicodeScalars.contains(where: { isCJKOrPrivateUse($0.value) }) else {
            return raw
        }

        var best = raw
        var bestScore = decodedQualityScore(raw)
        var seen: Set<UInt> = []
        for codePage in legacyChineseCodePageCandidates(for: profile) {
            guard let encoding = stringEncoding(for: codePage),
                  seen.insert(encoding.rawValue).inserted,
                  let legacyData = raw.data(using: encoding),
                  let decoded = String(data: legacyData, encoding: .utf8) else {
                continue
            }
            let score = decodedQualityScore(decoded)
            if score > bestScore + 8 || isLikelyLegacyDecodedUTF8MojibakeRepair(raw: raw, decoded: decoded) {
                best = decoded
                bestScore = score
            }
        }
        return best
    }

    private static func legacyChineseCodePageCandidates(for profile: CADTextBigFontProfile) -> [Int32] {
        switch profile {
        case .auto:
            return [54936, 936, 950]
        case .gbcbig, .hztxt, .hzfs:
            return [54936, 936]
        case .big5:
            return [950]
        case .disabled:
            return []
        }
    }

    private static func decodeBytes(_ bytes: [UInt8], profile: CADTextBigFontProfile) -> String? {
        guard profile != .disabled,
              !bytes.isEmpty,
              bytes.contains(where: { $0 >= 0x80 }) else {
            return nil
        }
        let data = Data(bytes)
        var best: (text: String, score: Int)?
        var seen: Set<UInt> = []

        for codePage in profile.codePageCandidates {
            guard let encoding = stringEncoding(for: codePage),
                  seen.insert(encoding.rawValue).inserted,
                  let decoded = String(data: data, encoding: encoding) else {
                continue
            }
            let score = decodedQualityScore(decoded)
            if best == nil || score > best!.score {
                best = (decoded, score)
            }
        }

        return best?.text
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
            } else if (0xE000...0xF8FF).contains(value) {
                score -= 36
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

    private static func isCJKOrPrivateUse(_ value: UInt32) -> Bool {
        (0x3400...0x4DBF).contains(value) ||
            (0x4E00...0x9FFF).contains(value) ||
            (0xE000...0xF8FF).contains(value) ||
            (0xF900...0xFAFF).contains(value)
    }

    private static func isLikelyLegacyDecodedUTF8MojibakeRepair(raw: String, decoded: String) -> Bool {
        guard raw != decoded,
              !decoded.unicodeScalars.contains(where: { $0.value == 0xFFFD || (0xE000...0xF8FF).contains($0.value) }),
              decoded.unicodeScalars.contains(where: { isCJKOrPrivateUse($0.value) }) else {
            return false
        }

        let rawSuspicion = mojibakeSuspicionScore(raw)
        let decodedSuspicion = mojibakeSuspicionScore(decoded)
        let decodedVocabulary = cadVocabularyHitCount(decoded)
        let shorterRepair = raw.count >= decoded.count + 1

        if decodedVocabulary > 0 && rawSuspicion > decodedSuspicion {
            return true
        }
        if shorterRepair && rawSuspicion >= 2 && decodedQualityScore(decoded) + 18 >= decodedQualityScore(raw) {
            return true
        }
        return false
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
        var score = 0
        for term in commonTerms where text.contains(term) {
            score += term.count >= 2 ? 18 : 8
        }
        score += cadVocabularyHitCount(text) * 18
        let suspiciousGlyphs = [
            "Ê", "Ð", "Ä", "Ã", "Â", "Ó", "Æ", "Ë", "·", "µ", "Ç",
            "涓", "鐨", "鏂", "鍙", "杩", "锛", "銆", "鈥", "澶", "笁",
            "鍗", "闂", "瀛", "妗", "勾", "骞", "浠", "鍏", "湪", "绔",
            "鐢", "垫", "皵", "抽", "潰", "藉", "寤", "虹", "瓚", "缁",
            "撴", "瀯", "欐", "帓", "姘", "娑", "堥", "槻", "鏍", "囬",
            "珮", "杞", "嚎", "閰", "嶇", "數", "鐓", "ф", "槑", "炶",
            "矾", "鎻", "掑", "骇", "灦", "绾", "跨", "璐", "嵎", "荤",
            "粺", "鍥", "剧", "焊",
        ]
        for glyph in suspiciousGlyphs where text.contains(glyph) {
            score -= 18
        }
        return score
    }

    private static func cadVocabularyHitCount(_ text: String) -> Int {
        let compacted = text.replacingOccurrences(of: " ", with: "")
        let terms = [
            "平面", "立面", "剖面", "详图", "节点", "标高", "轴线", "尺寸",
            "配电", "回路", "照明", "插座", "桥架", "线管", "接地", "负荷",
            "施工", "建筑", "结构", "电气", "给排水", "消防", "弱电", "系统图",
            "图纸", "设备", "材料", "管线", "支架", "开关", "回填", "防火",
            "平面圖", "立面圖", "剖面圖", "詳圖", "節點", "標高", "軸線", "尺寸",
            "配電", "迴路", "照明", "插座", "橋架", "線管", "接地", "負荷",
            "施工", "建築", "結構", "電氣", "給排水", "消防", "弱電", "系統圖",
            "圖紙", "設備", "材料", "管線", "支架", "開關", "防火",
        ]
        return terms.reduce(0) { count, term in
            compacted.contains(term) ? count + 1 : count
        }
    }

    private static func mojibakeSuspicionScore(_ text: String) -> Int {
        var score = 0
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0xE000...0xF8FF).contains(value) || value == 0xFFFD {
                score += 3
            } else if (0x00A0...0x00FF).contains(value) {
                score += 1
            }
        }

        let suspiciousFragments = [
            "涓", "鐨", "鏂", "鍙", "杩", "锛", "銆", "鈥", "澶", "笁",
            "鍗", "闂", "瀛", "妗", "骞", "鐢", "皵", "抽潰", "藉伐",
            "寤虹", "缁撴", "缁欐", "娑堥", "鏍囬", "杞寸", "閰嶇",
            "鐓ф", "鍥炶", "鎻掑", "妗ユ", "绾跨", "璐熻", "绯荤",
            "鍥剧",
        ]
        for fragment in suspiciousFragments where text.contains(fragment) {
            score += 2
        }
        return score
    }

    private static func stripFormattingRuns(in raw: String) -> String {
        var result = ""
        var index = raw.startIndex

        while index < raw.endIndex {
            let character = raw[index]
            guard character == "\\" else {
                result.append(character)
                index = raw.index(after: index)
                continue
            }

            let codeIndex = raw.index(after: index)
            guard codeIndex < raw.endIndex else {
                result.append(character)
                index = codeIndex
                continue
            }

            let code = raw[codeIndex]
            switch code {
            case "P", "p":
                result.append("\n")
                index = raw.index(after: codeIndex)
            case "~":
                result.append(" ")
                index = raw.index(after: codeIndex)
            case "L", "l", "O", "o", "K", "k":
                index = raw.index(after: codeIndex)
            case "A", "a", "C", "c", "F", "f", "H", "h", "W", "w", "Q", "q", "T", "t":
                index = indexAfterSemicolon(in: raw, from: codeIndex) ?? raw.index(after: codeIndex)
            case "S", "s":
                let valueStart = raw.index(after: codeIndex)
                if let semicolon = raw[valueStart...].firstIndex(of: ";") {
                    result.append(normalizeStackedText(String(raw[valueStart..<semicolon])))
                    index = raw.index(after: semicolon)
                } else {
                    index = raw.index(after: codeIndex)
                }
            default:
                result.append(character)
                index = codeIndex
            }
        }

        return result
    }

    private static func indexAfterSemicolon(in raw: String, from codeIndex: String.Index) -> String.Index? {
        let valueStart = raw.index(after: codeIndex)
        guard valueStart < raw.endIndex,
              let semicolon = raw[valueStart...].firstIndex(of: ";") else {
            return nil
        }
        return raw.index(after: semicolon)
    }

    private static func normalizeStackedText(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "#", with: "/")
            .replacingOccurrences(of: "^", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeUnicodeEscapes(in raw: String) -> String {
        let pattern = #"\\U\+([0-9A-Fa-f]{4})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        let nsRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        var result = raw

        for match in regex.matches(in: raw, range: nsRange).reversed() {
            guard match.numberOfRanges == 2,
                  let fullRange = Range(match.range(at: 0), in: result),
                  let hexRange = Range(match.range(at: 1), in: raw),
                  let scalarValue = UInt32(raw[hexRange], radix: 16),
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }

        return result
    }
}
