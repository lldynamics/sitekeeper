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
            return [936, 54936, 950, 932, 949, 65001]
        case .gbcbig, .hztxt, .hzfs:
            return [936, 54936, 65001]
        case .big5:
            return [950, 65001]
        case .disabled:
            return []
        }
    }

    static func inferred(from fontFile: String?) -> CADTextBigFontProfile {
        inferred(styleName: nil, fontFile: fontFile, bigFontFile: nil)
    }

    static func inferred(styleName: String?, fontFile: String?, bigFontFile: String?) -> CADTextBigFontProfile {
        CADSHXFontCatalog.match(
            styleName: styleName,
            fontFile: fontFile,
            bigFontFile: bigFontFile
        )?.profile ?? .auto
    }
}

enum CADSHXFontCatalog {
    struct Match {
        let profile: CADTextBigFontProfile
        let alias: String
        let source: String
        let confidence: Int

        var summary: String {
            "\(source): \(alias) -> \(profile.diagnosticName)"
        }
    }

    static func match(styleName: String?, fontFile: String?, bigFontFile: String?) -> Match? {
        let orderedSources: [(label: String, value: String?)] = [
            ("bigfont", bigFontFile),
            ("font", fontFile),
            ("style", styleName),
        ]

        var best: Match?
        for source in orderedSources {
            for token in tokens(from: source.value) {
                guard let candidate = match(token: token, source: source.label) else { continue }
                if best == nil || candidate.confidence > best!.confidence {
                    best = candidate
                }
            }
        }
        return best
    }

    static func diagnosticSummary(styleName: String?, fontFile: String?, bigFontFile: String?) -> String? {
        match(styleName: styleName, fontFile: fontFile, bigFontFile: bigFontFile)?.summary
    }

    private static func match(token: String, source: String) -> Match? {
        if let confidence = big5Aliases[token] {
            return Match(profile: .big5, alias: token, source: source, confidence: confidence + sourceWeight(source))
        }
        if let confidence = hzfsAliases[token] {
            return Match(profile: .hzfs, alias: token, source: source, confidence: confidence + sourceWeight(source))
        }
        if let confidence = hztxtAliases[token] {
            return Match(profile: .hztxt, alias: token, source: source, confidence: confidence + sourceWeight(source))
        }
        if let confidence = gbcbigAliases[token] {
            return Match(profile: .gbcbig, alias: token, source: source, confidence: confidence + sourceWeight(source))
        }
        return nil
    }

    private static func sourceWeight(_ source: String) -> Int {
        switch source {
        case "bigfont":
            return 30
        case "font":
            return 20
        case "style":
            return 10
        default:
            return 0
        }
    }

    private static func tokens(from value: String?) -> [String] {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let folded = trimmed
            .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        let stripped = folded
            .replacingOccurrences(of: "\\.(shx|shp|ttf|ttc|otf|fon)$", with: "", options: .regularExpression)
        let separators = CharacterSet(charactersIn: "/\\._- ()[]{}<>+")
        let parts = stripped.components(separatedBy: separators).filter { !$0.isEmpty }
        var result = [stripped]
        result.append(contentsOf: parts)
        result.append(contentsOf: parts.map { $0.replacingOccurrences(of: "@", with: "") })
        return Array(Set(result))
    }

    private static func table(_ entries: [(String, Int)]) -> [String: Int] {
        Dictionary(entries, uniquingKeysWith: max)
    }

    private static let gbcbigAliases = table([
        ("gbcbig", 100), ("gbcbiggb", 98), ("gbcbig5", 96), ("gb", 64),
        ("gbenor", 92), ("gbeitc", 90), ("gbhz", 88), ("gbfs", 86),
        ("gbfang", 84), ("gbfangsong", 84), ("gbst", 78), ("gblong", 78),
        ("hzd", 88), ("hzdx", 82), ("hzdxt", 82), ("hzdw", 76),
        ("hzxy", 76), ("hzzd", 74), ("hzt", 70), ("hz", 60),
        ("tssdeng", 98), ("tssdchn", 98), ("tssd", 96), ("tss", 84),
        ("tssdeng2", 90), ("tssdeng3", 90), ("tssdchn2", 90),
        ("tch", 72), ("thchn", 72), ("china", 70), ("chinese", 70),
        ("simsun", 62), ("simhei", 62), ("msyh", 58), ("yahei", 58),
    ])

    private static let hztxtAliases = table([
        ("hztxt", 100), ("hztxt1", 96), ("hztxt2", 96), ("hztxt3", 92),
        ("hztxt", 96), ("hztext", 92), ("hzdx", 84), ("hzdxt", 84),
        ("hzxk", 82), ("hzdd", 78), ("hzzd", 78), ("hzt", 70),
        ("txt", 72), ("txt1", 70), ("txt2", 70), ("simplex", 70),
        ("simplex8", 68), ("romans", 66), ("romanc", 64), ("romand", 64),
        ("iso", 58), ("isocp", 58), ("isocp2", 58), ("gdt", 56),
        ("standard", 42),
    ])

    private static let hzfsAliases = table([
        ("hzfs", 100), ("hzfs1", 96), ("hzfs2", 96), ("hzfangsong", 96),
        ("fs", 82), ("fsdb", 90), ("fsdb_e", 90), ("gbhzfs", 92),
        ("simfang", 96), ("fangsong", 94), ("fang", 72), ("fsgb", 88),
        ("fzfs", 86), ("fzfangsong", 86), ("仿宋", 100), ("仿宋gb2312", 96),
        ("fangsong_gb2312", 96), ("stfangsong", 84), ("adobe fangsong std", 78),
    ])

    private static let big5Aliases = table([
        ("big5", 100), ("bigfont", 82), ("chineset", 96), ("chinese_t", 96),
        ("cht", 92), ("tw", 74), ("taiwan", 74), ("mingliu", 88),
        ("pmingliu", 88), ("kaiu", 86), ("msung", 82), ("msungstd", 82),
        ("bkai", 82), ("hk", 74), ("hkscs", 80), ("extfont", 70),
        ("extfont2", 70), ("繁体", 90), ("繁體", 90), ("細明體", 88),
        ("新細明體", 88), ("標楷體", 86),
    ])
}

private extension CADTextBigFontProfile {
    var diagnosticName: String {
        switch self {
        case .auto:
            return "AUTO"
        case .gbcbig:
            return "GBCBIG"
        case .hztxt:
            return "HZTXT"
        case .hzfs:
            return "HZFS"
        case .big5:
            return "BIG5"
        case .disabled:
            return "DISABLED"
        }
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

    static func looksSuspicious(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if looksLikeMojibake(trimmed) {
            return true
        }
        if trimmed.unicodeScalars.contains(where: { $0.value == 0xFFFD || (0xE000...0xF8FF).contains($0.value) }) {
            return true
        }
        return decodedQualityScore(trimmed) < -4
    }

    static func looksLikeMojibake(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if mojibakeSuspicionScore(trimmed) >= 2 {
            return true
        }
        let hasHighLatin = trimmed.unicodeScalars.contains { (0x00A0...0x00FF).contains($0.value) }
        let hasReadableChinese = trimmed.unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(scalar.value) ||
                (0x4E00...0x9FFF).contains(scalar.value) ||
                (0xF900...0xFAFF).contains(scalar.value)
        }
        return hasHighLatin && !hasReadableChinese
    }

    static func bestEffortNormalizedText(
        decodedText: String,
        rawTextBytesHex: String?,
        preferredCodePage: Int32?,
        bigFontProfile: CADTextBigFontProfile
    ) -> (text: String, codePage: Int32?) {
        let normalizedDecoded = normalize(decodedText, bigFontProfile: bigFontProfile)
        var best = (
            text: normalizedDecoded,
            score: decodedQualityScore(normalizedDecoded),
            codePage: preferredCodePage
        )

        guard let bytes = bytes(fromHexDump: rawTextBytesHex), !bytes.isEmpty else {
            return (best.text, best.codePage)
        }

        var codePages: [Int32] = []
        if let preferredCodePage {
            codePages.append(preferredCodePage)
        }
        codePages.append(contentsOf: bigFontProfile.codePageCandidates)
        codePages.append(contentsOf: [936, 54936, 950, 65001, 932, 949])

        var seen: Set<UInt> = []
        let data = Data(bytes)
        for codePage in codePages {
            guard let encoding = stringEncoding(for: codePage),
                  seen.insert(encoding.rawValue).inserted,
                  let decoded = String(data: data, encoding: encoding) else {
                continue
            }

            let normalized = normalize(decoded, bigFontProfile: bigFontProfile)
            guard !normalized.isEmpty else { continue }
            let score = decodedQualityScore(normalized)
            if score > best.score + 4 || shouldPreferRawByteDecode(current: best.text, candidate: normalized) {
                best = (normalized, score, codePage)
            }
        }

        return (best.text, best.codePage)
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

    private static func bytes(fromHexDump raw: String?) -> [UInt8]? {
        let tokens = (raw ?? "")
            .split { character in
                character == " " || character == "\n" || character == "\t" || character == "\r"
            }
        guard !tokens.isEmpty else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(tokens.count)
        for token in tokens {
            guard token != "...", token.count == 2, let value = UInt8(token, radix: 16) else {
                continue
            }
            bytes.append(value)
        }
        return bytes.isEmpty ? nil : bytes
    }

    private static func shouldPreferRawByteDecode(current: String, candidate: String) -> Bool {
        guard current != candidate,
              candidate.unicodeScalars.contains(where: { isCJKOrPrivateUse($0.value) }),
              !candidate.unicodeScalars.contains(where: { $0.value == 0xFFFD }) else {
            return false
        }
        let currentScore = decodedQualityScore(current)
        let candidateScore = decodedQualityScore(candidate)
        if candidateScore > currentScore {
            return true
        }
        let currentHasMojibake = current.unicodeScalars.contains { (0x00A0...0x00FF).contains($0.value) || $0.value == 0xFFFD }
        return currentHasMojibake && candidateScore >= currentScore - 4
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
