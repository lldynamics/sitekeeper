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

    static func inferred(
        from fontFile: String?,
        customMappings: [CADSHXFontCatalog.CustomMapping] = []
    ) -> CADTextBigFontProfile {
        inferred(styleName: nil, fontFile: fontFile, bigFontFile: nil, customMappings: customMappings)
    }

    static func inferred(
        styleName: String?,
        fontFile: String?,
        bigFontFile: String?,
        customMappings: [CADSHXFontCatalog.CustomMapping] = []
    ) -> CADTextBigFontProfile {
        CADSHXFontCatalog.match(
            styleName: styleName,
            fontFile: fontFile,
            bigFontFile: bigFontFile,
            customMappings: customMappings
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
            return "\(source): \(alias) -> \(profile.diagnosticName)"
        }
    }

    struct CustomMapping {
        let sourceKind: String
        let pattern: String
        let profile: CADTextBigFontProfile

        init?(
            sourceKind: String,
            pattern: String,
            profile: CADTextBigFontProfile?
        ) {
            let normalizedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedPattern.isEmpty, let profile, profile != .auto else { return nil }
            self.sourceKind = Self.normalizedSourceKind(sourceKind)
            self.pattern = normalizedPattern
            self.profile = profile
        }

        func accepts(source: String) -> Bool {
            sourceKind == "any" || sourceKind == source
        }

        private static func normalizedSourceKind(_ raw: String) -> String {
            switch raw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .lowercased() {
            case "bigfont", "big_font", "bigfontfile", "bigfont_file", "big":
                return "bigfont"
            case "font", "fontfile", "font_file":
                return "font"
            case "style", "stylename", "style_name":
                return "style"
            default:
                return "any"
            }
        }
    }

    static func match(
        styleName: String?,
        fontFile: String?,
        bigFontFile: String?,
        customMappings: [CustomMapping] = []
    ) -> Match? {
        let orderedSources: [(label: String, value: String?)] = [
            ("bigfont", bigFontFile),
            ("font", fontFile),
            ("style", styleName),
        ]

        var best: Match?
        for source in orderedSources {
            let sourceTokens = tokens(from: source.value)
            for candidate in customMatches(
                sourceLabel: source.label,
                sourceTokens: sourceTokens,
                mappings: customMappings
            ) {
                if best == nil || candidate.confidence > best!.confidence {
                    best = candidate
                }
            }
            for token in sourceTokens {
                guard let candidate = match(token: token, source: source.label) else { continue }
                if best == nil || candidate.confidence > best!.confidence {
                    best = candidate
                }
            }
        }
        return best
    }

    static func diagnosticSummary(
        styleName: String?,
        fontFile: String?,
        bigFontFile: String?,
        customMappings: [CustomMapping] = []
    ) -> String? {
        match(
            styleName: styleName,
            fontFile: fontFile,
            bigFontFile: bigFontFile,
            customMappings: customMappings
        )?.summary
    }

    private static func customMatches(
        sourceLabel: String,
        sourceTokens: [String],
        mappings: [CustomMapping]
    ) -> [Match] {
        guard !sourceTokens.isEmpty, !mappings.isEmpty else { return [] }
        let sourceTokenSet = Set(sourceTokens)
        return mappings.compactMap { mapping -> Match? in
            guard mapping.accepts(source: sourceLabel) else { return nil }
            let mappingTokens = tokens(from: mapping.pattern)
            guard let alias = mappingTokens.first(where: { sourceTokenSet.contains($0) }) else {
                return nil
            }
            return Match(
                profile: mapping.profile,
                alias: alias,
                source: "项目替代/\(sourceLabel)",
                confidence: 1_000 + sourceWeight(sourceLabel)
            )
        }
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
            .replacingOccurrences(of: "\\.(shx|shp|fon)$", with: "", options: .regularExpression)
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
        ("gcbig", 96), ("gbbig", 94), ("gbtxt", 88), ("gbtxt1", 84),
        ("gbenor", 92), ("gbeitc", 90), ("gbhz", 88), ("gbfs", 86),
        ("gbhz1", 84), ("gbhz2", 84), ("gbst1", 78), ("gbst2", 78),
        ("gbfang", 84), ("gbfangsong", 84), ("gbst", 78), ("gblong", 78),
        ("hzd", 88), ("hzdx", 82), ("hzdxt", 82), ("hzdw", 76),
        ("hzxy", 76), ("hzzd", 74), ("hzt", 70), ("hz", 60), ("hzst", 78),
        ("hzsong", 78), ("hzhei", 76), ("hzxbs", 74), ("hzxk", 72),
        ("tssdeng", 98), ("tssdchn", 98), ("tssd", 96), ("tss", 84),
        ("tssdeng2", 90), ("tssdeng3", 90), ("tssdchn2", 90),
        ("tch", 72), ("thchn", 72), ("china", 70), ("chinese", 70),
        ("chinesegb", 86), ("chineses", 84), ("chinese_s", 84),
    ])

    private static let hztxtAliases = table([
        ("hztxt", 100), ("hztxt1", 96), ("hztxt2", 96), ("hztxt3", 92),
        ("hztxt", 96), ("hztext", 92), ("hzdx", 84), ("hzdxt", 84),
        ("hzxk", 82), ("hzdd", 78), ("hzzd", 78), ("hzt", 70),
        ("hztxt_e", 88), ("hztext_e", 86), ("hzshx", 78),
        ("txt", 72), ("txt1", 70), ("txt2", 70), ("simplex", 70),
        ("simplex8", 68), ("simplexgb", 76), ("romans", 66), ("romanc", 64), ("romand", 64),
        ("iso", 58), ("isocp", 58), ("isocp2", 58), ("gdt", 56),
        ("standard", 42),
    ])

    private static let hzfsAliases = table([
        ("hzfs", 100), ("hzfs1", 96), ("hzfs2", 96), ("hzfangsong", 96),
        ("fs", 82), ("fs1", 78), ("fs2", 78), ("fsdb", 90), ("fsdb_e", 90), ("gbhzfs", 92),
        ("fsgb", 88),
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
                repairUTF8DecodedAsLatin1Mojibake(in: shxDecoded),
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
            score: textCandidateScore(normalizedDecoded),
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
            let score = textCandidateScore(normalized)
                + codePagePreferenceBias(codePage, preferredCodePage: preferredCodePage)
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
            let score = mojibakeRepairScore(candidate)
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

    private static func repairUTF8DecodedAsLatin1Mojibake(in raw: String) -> String {
        guard raw.unicodeScalars.contains(where: { (0x00A0...0x00FF).contains($0.value) }) else {
            return raw
        }
        let scalars = raw.unicodeScalars
        let bytes = scalars.compactMap { scalar -> UInt8? in
            windows1252Byte(for: scalar)
        }
        guard bytes.count == scalars.count,
              let decoded = String(data: Data(bytes), encoding: .utf8),
              shouldPreferMojibakeRepair(raw: raw, decoded: decoded) else {
            return raw
        }
        return decoded
    }

    private static func windows1252Byte(for scalar: Unicode.Scalar) -> UInt8? {
        if scalar.value <= 0x00FF {
            return UInt8(scalar.value)
        }
        switch scalar.value {
        case 0x20AC:
            return 0x80
        case 0x201A:
            return 0x82
        case 0x0192:
            return 0x83
        case 0x201E:
            return 0x84
        case 0x2026:
            return 0x85
        case 0x2020:
            return 0x86
        case 0x2021:
            return 0x87
        case 0x02C6:
            return 0x88
        case 0x2030:
            return 0x89
        case 0x0160:
            return 0x8A
        case 0x2039:
            return 0x8B
        case 0x0152:
            return 0x8C
        case 0x017D:
            return 0x8E
        case 0x2018:
            return 0x91
        case 0x2019:
            return 0x92
        case 0x201C:
            return 0x93
        case 0x201D:
            return 0x94
        case 0x2022:
            return 0x95
        case 0x2013:
            return 0x96
        case 0x2014:
            return 0x97
        case 0x02DC:
            return 0x98
        case 0x2122:
            return 0x99
        case 0x0161:
            return 0x9A
        case 0x203A:
            return 0x9B
        case 0x0153:
            return 0x9C
        case 0x017E:
            return 0x9E
        case 0x0178:
            return 0x9F
        default:
            return nil
        }
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
        var bestScore = mojibakeRepairScore(raw)
        var seen: Set<UInt> = []
        for codePage in legacyChineseCodePageCandidates(for: profile) {
            guard let encoding = stringEncoding(for: codePage),
                  seen.insert(encoding.rawValue).inserted,
                  let legacyData = raw.data(using: encoding),
                  let decoded = String(data: legacyData, encoding: .utf8) else {
                continue
            }
            let score = mojibakeRepairScore(decoded)
            if score > bestScore + 6 || isLikelyLegacyDecodedUTF8MojibakeRepair(raw: raw, decoded: decoded) {
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
            let score = textCandidateScore(decoded)
                + codePagePreferenceBias(codePage, preferredCodePage: nil)
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
        if mojibakeRepairScore(candidate) > mojibakeRepairScore(current) + 4 {
            return true
        }
        let currentHasMojibake = current.unicodeScalars.contains { (0x00A0...0x00FF).contains($0.value) || $0.value == 0xFFFD }
        return currentHasMojibake && candidateScore >= currentScore - 4
    }

    private static func codePagePreferenceBias(_ codePage: Int32, preferredCodePage: Int32?) -> Int {
        var bias = 0
        if preferredCodePage == codePage {
            bias += 20
        }
        switch codePage {
        case 936, 54936:
            bias += 18
        case 65001:
            bias += 6
        case 950:
            if preferredCodePage != 950 {
                bias -= 6
            }
        case 932, 949:
            if preferredCodePage == codePage {
                bias -= 4
            } else {
                bias -= 24
            }
        default:
            break
        }
        return bias
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
            if isCJKIdeograph(value) {
                score += 12
            } else if isEastAsianPunctuation(value) {
                score += 2
            } else if isFullwidthASCII(value) {
                score += 1
            } else if isHalfwidthKatakana(value) {
                score -= 16
            } else if isBoxDrawing(value) {
                score -= 18
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

    private static func textCandidateScore(_ text: String) -> Int {
        mojibakeRepairScore(text)
    }

    private static func isCJKOrPrivateUse(_ value: UInt32) -> Bool {
        isCJKIdeograph(value) || (0xE000...0xF8FF).contains(value)
    }

    private static func isCJKIdeograph(_ value: UInt32) -> Bool {
        (0x3400...0x4DBF).contains(value) ||
            (0x4E00...0x9FFF).contains(value) ||
            (0xF900...0xFAFF).contains(value)
    }

    private static func isEastAsianPunctuation(_ value: UInt32) -> Bool {
        (0x3000...0x303F).contains(value)
    }

    private static func isFullwidthASCII(_ value: UInt32) -> Bool {
        (0xFF01...0xFF5E).contains(value)
    }

    private static func isHalfwidthKatakana(_ value: UInt32) -> Bool {
        (0xFF61...0xFF9F).contains(value)
    }

    private static func isBoxDrawing(_ value: UInt32) -> Bool {
        (0x2500...0x257F).contains(value)
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
        if mojibakeRepairScore(decoded) > mojibakeRepairScore(raw) + 6 {
            return true
        }
        if shorterRepair && rawSuspicion >= 2 && decodedQualityScore(decoded) + 18 >= decodedQualityScore(raw) {
            return true
        }
        return false
    }

    private static func shouldPreferMojibakeRepair(raw: String, decoded: String) -> Bool {
        guard raw != decoded,
              !decoded.unicodeScalars.contains(where: { $0.value == 0xFFFD || (0xE000...0xF8FF).contains($0.value) }) else {
            return false
        }
        let rawSuspicion = mojibakeSuspicionScore(raw)
        let decodedSuspicion = mojibakeSuspicionScore(decoded)
        if rawSuspicion > decodedSuspicion && mojibakeRepairScore(decoded) + 2 >= mojibakeRepairScore(raw) {
            return true
        }
        return mojibakeRepairScore(decoded) > mojibakeRepairScore(raw) + 6
    }

    private static func mojibakeRepairScore(_ text: String) -> Int {
        decodedQualityScore(text)
            + commonChineseScore(text)
            - mojibakeSuspicionScore(text) * 18
    }

    private static func commonChineseScore(_ text: String) -> Int {
        let common = Set("的一是在不了有和人这中大为上个国我以要他时来用们生到作地于出就分对成会可主发年动同工也能下过子说产种面而方后多定行学法所民得经十三之进着等部度家电力里如水化高自二理起小物现实加量都两体制机当使点从业本去把性好应开它合还因由其些然前外天政四日那社义事平形相全表间样与关各重新线内数正心反你明看原又么利比或但质气第向道命此变条只没结解问意建月公无系军很情者最立代想已通并提直题党程展五果料象员革位入常文总次品式活设及管特件长求老头基资边流路级少图山统接知较将组见计别她手角期根论运农指几九区强放决西被干做必战先回则任取据处队南给色光门即保治北造百规热领七海口东导器压志世金增争济阶油思术极交受联什认六共权收证改清美再采转更单风切打白教速花带安场身车例真务具万每目至达走积示议声报斗完类八离华名确才科张信马节话米整空元况今集温传土许步群广石记需段研界拉林律叫且究观越织装影算低持音众书布复容儿须际商非验连断深难近矿千周委素技备半办青省列习响约支般史感劳便团往酸历市克何除消构府称太准精值号率族维划选标写存候毛亲快效斯院查江型眼王按格养易置派层片始却专状育厂京识适属圆包火住调满县局照参红细引听该铁价严龙飞")
        var score = 0
        for scalar in text.unicodeScalars {
            if common.contains(Character(scalar)) {
                score += 3
            }
        }
        score += cadVocabularyHitCount(text) * 12
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
            } else if isHalfwidthKatakana(value) || isBoxDrawing(value) {
                score += 2
            } else if (0x0080...0x009F).contains(value) {
                score += 2
            } else if (0x00A0...0x00FF).contains(value) {
                score += 1
            }
        }

        let suspiciousFragments = [
            "涓", "鐨", "鏂", "鍙", "杩", "锛", "銆", "鈥", "澶", "笁",
            "鍗", "闂", "瀛", "妗", "骞", "鐢", "皵", "抽潰", "藉伐",
            "寤虹", "缁撴", "缁欐", "娑堥", "鏍囬", "杞寸", "閰嶇",
            "鐓ф", "鍥炶", "鎻掑", "妗ユ", "绾跨", "璐熻", "绯荤",
            "鍥剧", "鎬", "搴", "佹", "犲", "朵", "槸", "侀", "垪",
            "銝", "靘", "摰", "餈", "撖", "榛", "瘜", "寰", "閬", "頧",
            "ä", "å", "æ", "ç", "è", "é", "Ä", "Å", "Æ", "Ç", "È", "É",
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
