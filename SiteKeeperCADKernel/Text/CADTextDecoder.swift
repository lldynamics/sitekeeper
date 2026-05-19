import Foundation

extension SiteKeeperCADKernel {
    struct CADDecodedText: Equatable, Codable {
        var decodedText: String
        var decodeMethod: String
        var warnings: [String]
    }

    struct CADTextDecoder {
        func decode(rawText: String, textStyle: CADTextStyle? = nil) -> CADDecodedText {
            var warnings: [String] = []
            let unicodeDecoded = decodeUnicodeEscapes(in: rawText, warnings: &warnings)
            let cifDecoded = decodeCIFBigFontEscapeSequences(
                in: unicodeDecoded,
                textStyle: textStyle,
                warnings: &warnings
            )
            let mifDecoded = decodeMIFBigFontEscapeSequences(
                in: cifDecoded,
                textStyle: textStyle,
                warnings: &warnings
            )
            let shxHexDecoded = decodeSHXBigFontHexEscapes(
                in: mifDecoded,
                textStyle: textStyle,
                warnings: &warnings
            )
            let bareSHXHexDecoded = decodeBareSHXBigFontHexRuns(
                in: shxHexDecoded,
                textStyle: textStyle,
                warnings: &warnings
            )
            let decoded = repairMojibakeIfNeeded(bareSHXHexDecoded, textStyle: textStyle, warnings: &warnings)
            let method: String
            if decoded == rawText {
                method = "rawString"
            } else if mifDecoded != cifDecoded {
                method = "mifEscape"
            } else if cifDecoded != unicodeDecoded {
                method = "cifEscape"
            } else if shxHexDecoded != mifDecoded || bareSHXHexDecoded != shxHexDecoded {
                method = "shxBigFontHex"
            } else if unicodeDecoded != rawText {
                method = "unicodeEscape"
            } else {
                method = "encodingRepair"
            }
            return CADDecodedText(decodedText: decoded, decodeMethod: method, warnings: warnings)
        }

        func decode(_ data: Data, encoding: String.Encoding = .utf8) -> String {
            String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
        }

        private func decodeUnicodeEscapes(in value: String, warnings: inout [String]) -> String {
            let pattern = #"\\?U\+([0-9A-Fa-f]{4,6})"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return value
            }

            var output = value
            let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
            for match in matches.reversed() {
                guard
                    let fullRange = Range(match.range(at: 0), in: output),
                    let hexRange = Range(match.range(at: 1), in: output),
                    let scalarValue = UInt32(output[hexRange], radix: 16),
                    let scalar = UnicodeScalar(scalarValue)
                else {
                    warnings.append("CAD_TEXT_INVALID_UNICODE_ESCAPE")
                    continue
                }
                output.replaceSubrange(fullRange, with: String(Character(scalar)))
            }
            return output
        }

        private func decodeCIFBigFontEscapeSequences(
            in value: String,
            textStyle: CADTextStyle?,
            warnings: inout [String]
        ) -> String {
            let pattern = #"\\[Cc]([0-9A-Fa-f]{4,8});?(?![0-9A-Fa-f])"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return value
            }

            var output = value
            let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
            for match in matches.reversed() {
                guard
                    let fullRange = Range(match.range(at: 0), in: output),
                    let hexRange = Range(match.range(at: 1), in: output)
                else {
                    continue
                }

                let hex = String(output[hexRange])
                guard let decoded = decodeCIFHex(hex, textStyle: textStyle, warnings: &warnings) else {
                    warnings.appendOnce("CAD_TEXT_INVALID_CIF_ESCAPE")
                    continue
                }
                warnings.appendOnce("CAD_TEXT_BIGFONT_CIF_DECODED")
                output.replaceSubrange(fullRange, with: decoded)
            }
            return output
        }

        private func decodeMIFBigFontEscapeSequences(
            in value: String,
            textStyle: CADTextStyle?,
            warnings: inout [String]
        ) -> String {
            let pattern = #"\\?M\+[0-9A-Za-z]([0-9A-Fa-f]{4,8})"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return value
            }

            var output = value
            let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
            for match in matches.reversed() {
                guard
                    let fullRange = Range(match.range(at: 0), in: output),
                    let hexRange = Range(match.range(at: 1), in: output),
                    let decoded = decodeHexBytes(
                        String(output[hexRange]),
                        textStyle: textStyle,
                        warnings: &warnings,
                        warningPrefix: "CAD_TEXT_BIGFONT_MIF"
                    )
                else {
                    warnings.append("CAD_TEXT_INVALID_MIF_ESCAPE")
                    continue
                }
                warnings.appendOnce("CAD_TEXT_BIGFONT_MIF_DECODED")
                output.replaceSubrange(fullRange, with: decoded)
            }
            return output
        }

        private func decodeSHXBigFontHexEscapes(
            in value: String,
            textStyle: CADTextStyle?,
            warnings: inout [String]
        ) -> String {
            let markerPattern = #"\\?(?:SHX|BIGFONT|GBK|GB18030)\+([0-9A-Fa-f]{4,64})"#
            guard let regex = try? NSRegularExpression(pattern: markerPattern, options: [.caseInsensitive]) else {
                return value
            }

            var output = value
            let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
            for match in matches.reversed() {
                guard
                    let fullRange = Range(match.range(at: 0), in: output),
                    let hexRange = Range(match.range(at: 1), in: output),
                    let decoded = decodeHexBytes(
                        String(output[hexRange]),
                        textStyle: textStyle,
                        warnings: &warnings,
                        warningPrefix: "CAD_TEXT_SHX_BIGFONT"
                    )
                else {
                    warnings.appendOnce("CAD_TEXT_INVALID_SHX_BIGFONT_HEX")
                    continue
                }
                warnings.appendOnce("CAD_TEXT_SHX_BIGFONT_HEX_DECODED")
                output.replaceSubrange(fullRange, with: decoded)
            }

            return output
        }

        private func decodeCIFHex(
            _ hex: String,
            textStyle: CADTextStyle?,
            warnings: inout [String]
        ) -> String? {
            if let scalarValue = UInt32(hex, radix: 16),
               let scalar = UnicodeScalar(scalarValue),
               String(scalar).containsCJKScalars {
                warnings.appendOnce("CAD_TEXT_BIGFONT_CIF_UNICODE_DECODED")
                return String(Character(scalar))
            }

            guard hex.count.isMultiple(of: 2),
                  hexContainsNonASCIIByte(hex),
                  let decoded = decodeHexByteCandidate(hex, textStyle: textStyle),
                  decoded.text.containsCJKScalars else {
                return nil
            }
            warnings.appendOnce("CAD_TEXT_BIGFONT_CIF_\(decoded.encodingName)_DECODED")
            return decoded.text
        }

        private func decodeBareSHXBigFontHexRuns(
            in value: String,
            textStyle: CADTextStyle?,
            warnings: inout [String]
        ) -> String {
            guard textStyle?.usesSHXOrBigFont == true,
                  !value.containsCJKScalars,
                  let regex = try? NSRegularExpression(
                    pattern: #"(?:\\([0-9A-Fa-f]{4,128})(?![A-Za-z0-9])|(?<![A-Za-z0-9])([0-9A-Fa-f]{4,128})(?![A-Za-z0-9]))"#
                  ) else {
                return value
            }

            var output = value
            let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
            for match in matches.reversed() {
                guard
                    let fullRange = Range(match.range(at: 0), in: output),
                    let hexRange = Range(hexRange(for: match), in: output)
                else {
                    continue
                }

                let hex = String(output[hexRange])
                guard hex.count.isMultiple(of: 2),
                      hexContainsNonASCIIByte(hex),
                      let decoded = decodeHexByteCandidate(hex, textStyle: textStyle),
                      decoded.text.containsCJKScalars else {
                    continue
                }

                warnings.appendOnce("CAD_TEXT_SHX_BIGFONT_BARE_HEX_DECODED")
                warnings.appendOnce("CAD_TEXT_SHX_BIGFONT_BARE_\(decoded.encodingName)_DECODED")
                output.replaceSubrange(fullRange, with: decoded.text)
            }

            return output
        }

        private func hexRange(for match: NSTextCheckingResult) -> NSRange {
            let escapedRange = match.range(at: 1)
            if escapedRange.location != NSNotFound {
                return escapedRange
            }
            return match.range(at: 2)
        }

        private func repairMojibakeIfNeeded(
            _ value: String,
            textStyle: CADTextStyle?,
            warnings: inout [String]
        ) -> String {
            // Phase 1: pure single-byte mojibake (no CJK yet, all bytes < 0x100)
            if !value.containsCJKScalars,
               value.unicodeScalars.contains(where: { (0x80...0xFF).contains($0.value) }),
               let data = value.singleByteData,
               let decoded = decodeTextBytes(data, textStyle: textStyle),
               decoded.text.containsCJKScalars {
                warnings.appendOnce("CAD_TEXT_GBK_MOJIBAKE_REPAIRED")
                if textStyle?.usesSHXOrBigFont == true {
                    warnings.appendOnce("CAD_TEXT_SHX_BIGFONT_BYTES_DECODED")
                    warnings.appendOnce("CAD_TEXT_SHX_BIGFONT_BYTES_REPAIRED")
                }
                appendEncodingWarning(decoded.encodingName, warnings: &warnings)
                return decoded.text
            }

            // Phase 2: partial mojibake — the classic "部分文字显示" pattern.
            // LibreDWG decoded GBK text bytes as UTF-8.  Valid UTF-8 sequences
            // became real CJK characters; invalid sequences became U+FFFD.
            //
            // Strategy: walk the string, collect the bytes of CJK characters
            // via their UTF-8 encoding, and also collect the Latin-1-range bytes.
            // Re-decode the entire byte stream as GBK, compare replacement-char
            // counts, and use the result if it improves the output.
            if value.unicodeScalars.contains(where: { $0.value == 0xFFFD }) {
                if let repaired = repairPartialMojibake(value, textStyle: textStyle, warnings: &warnings) {
                    return repaired
                }
            }

            // Phase 3: valid-looking CJK mojibake. This happens when UTF-8 text
            // has already been decoded as GBK/GB18030 before reaching us, for
            // example "市政府施工图" becoming "甯傛斂搴滄柦宸ュ浘".
            if value.containsCJKScalars,
               let repaired = repairUTF8DecodedAsLegacyChinese(value, textStyle: textStyle, warnings: &warnings) {
                return repaired
            }

            return value
        }

        /// Attempt to repair a string that has a mix of valid CJK (from accidental
        /// valid UTF-8 subsequences in a GBK byte stream) and U+FFFD replacement
        /// characters (from invalid UTF-8 subsequences).
        private func repairPartialMojibake(
            _ value: String,
            textStyle: CADTextStyle?,
            warnings: inout [String]
        ) -> String? {
            // Approach: encode the *entire* string as UTF-8, then re-interpret
            // those UTF-8 bytes as GBK/GB18030/GB2312.  Although this round-trip
            // is lossy (the original GBK bytes are gone), the actual GBK codepoints
            // that survived as valid UTF-8 *tend* to map to nearby CJK codepoints
            // under the reverse transformation.  More importantly, U+FFFD (3-byte
            // UTF-8: EF BF BD) decodes under GBK as the well-known "锟斤拷"
            // placeholder, which is at least recognisable CJK instead of �.
            guard let utf8Data = value.data(using: .utf8) else { return nil }

            let replacementBefore = value.unicodeScalars.filter { $0.value == 0xFFFD }.count
            var best: (text: String, encoding: String, replacements: Int)?

            for candidate in Self.byteDecodeCandidates(for: textStyle) {
                guard let decoded = String(data: utf8Data, encoding: candidate.encoding),
                      !decoded.isEmpty else {
                    continue
                }
                let decodedReplacements = decoded.unicodeScalars.filter { $0.value == 0xFFFD }.count
                if decodedReplacements < replacementBefore,
                   decoded.containsCJKScalars {
                    if decodedReplacements < (best?.replacements ?? Int.max) {
                        best = (decoded, candidate.name, decodedReplacements)
                    }
                }
            }

            guard let best else { return nil }

            // Safety: only accept if the repair reduced replacement characters
            // by at least 20% of the original count (avoid false positives).
            guard best.replacements < replacementBefore,
                  (replacementBefore - best.replacements) >= max(1, replacementBefore / 5) else {
                return nil
            }

            warnings.appendOnce("CAD_TEXT_MIXED_MOJIBAKE_REPAIRED")
            warnings.appendOnce("CAD_TEXT_MIXED_\(best.encoding)_FALLBACK")
            appendEncodingWarning(best.encoding, warnings: &warnings)
            return best.text
        }

        private func repairUTF8DecodedAsLegacyChinese(
            _ value: String,
            textStyle: CADTextStyle?,
            warnings: inout [String]
        ) -> String? {
            let originalScore = Self.textRecoveryScore(value)
            var best: (text: String, encoding: String, score: Int)?

            for candidate in Self.byteDecodeCandidates(for: textStyle) where candidate.name != "UTF8" {
                guard let bytes = value.data(using: candidate.encoding),
                      let decoded = String(data: bytes, encoding: .utf8),
                      !decoded.isEmpty,
                      decoded.containsCJKScalars,
                      !decoded.containsUnicodeReplacementCharacter else {
                    continue
                }

                let score = Self.textRecoveryScore(decoded)
                if score >= originalScore + 80,
                   score > (best?.score ?? Int.min) {
                    best = (decoded, candidate.name, score)
                }
            }

            guard let best else { return nil }
            warnings.appendOnce("CAD_TEXT_UTF8_MOJIBAKE_REPAIRED")
            warnings.appendOnce("CAD_TEXT_UTF8_MOJIBAKE_FROM_\(best.encoding)")
            return best.text
        }

        private func decodeHexBytes(
            _ hex: String,
            textStyle: CADTextStyle?,
            warnings: inout [String],
            warningPrefix: String
        ) -> String? {
            guard hex.count.isMultiple(of: 2) else { return nil }
            guard let decoded = decodeHexByteCandidate(hex, textStyle: textStyle) else { return nil }
            warnings.appendOnce("\(warningPrefix)_\(decoded.encodingName)_DECODED")
            return decoded.text
        }

        private func decodeHexByteCandidate(_ hex: String, textStyle: CADTextStyle?) -> CADByteDecodedText? {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(hex.count / 2)
            var index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 2)
                guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
                bytes.append(byte)
                index = next
            }
            return decodeTextBytes(Data(bytes), textStyle: textStyle)
        }

        private func hexContainsNonASCIIByte(_ hex: String) -> Bool {
            var index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 2)
                if let byte = UInt8(hex[index..<next], radix: 16), byte >= 0x80 {
                    return true
                }
                index = next
            }
            return false
        }

        private func decodeTextBytes(_ data: Data, textStyle: CADTextStyle?) -> CADByteDecodedText? {
            for candidate in Self.byteDecodeCandidates(for: textStyle) {
                guard let decoded = String(data: data, encoding: candidate.encoding),
                      !decoded.containsUnicodeReplacementCharacter,
                      !decoded.isEmpty else {
                    continue
                }
                return CADByteDecodedText(text: decoded, encodingName: candidate.name)
            }
            return nil
        }

        private func appendEncodingWarning(_ encodingName: String, warnings: inout [String]) {
            switch encodingName {
            case "UTF8":
                warnings.appendOnce("CAD_TEXT_UTF8_BYTE_FALLBACK_DECODED")
            case "GBK":
                warnings.appendOnce("CAD_TEXT_GBK_FALLBACK_DECODED")
            case "GB18030":
                warnings.appendOnce("CAD_TEXT_GB18030_FALLBACK_DECODED")
            case "GB2312":
                warnings.appendOnce("CAD_TEXT_GB2312_FALLBACK_DECODED")
            case "BIG5":
                warnings.appendOnce("CAD_TEXT_BIG5_FALLBACK_DECODED")
            default:
                warnings.appendOnce("CAD_TEXT_BYTE_FALLBACK_DECODED:\(encodingName)")
            }
        }

        private struct CADByteDecodedText {
            var text: String
            var encodingName: String
        }

        private static let gb18030Encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )

        private static let gbkEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GBK_95.rawValue)
            )
        )

        private static let gb2312Encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_2312_80.rawValue)
            )
        )

        private static let big5Encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue)
            )
        )

        private static func byteDecodeCandidates(for textStyle: CADTextStyle?) -> [(encoding: String.Encoding, name: String)] {
            var candidates: [(encoding: String.Encoding, name: String)] = []
            if textStyle?.prefersBig5Bytes == true {
                candidates.append((big5Encoding, "BIG5"))
            }
            candidates.append(contentsOf: [
                (.utf8, "UTF8"),
                (gbkEncoding, "GBK"),
                (gb18030Encoding, "GB18030"),
                (gb2312Encoding, "GB2312"),
                (big5Encoding, "BIG5")
            ])
            var seen = Set<UInt>()
            return candidates.filter { candidate in
                seen.insert(candidate.encoding.rawValue).inserted
            }
        }

        private static func textRecoveryScore(_ value: String) -> Int {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return -10_000 }
            var score = 0
            for scalar in trimmed.unicodeScalars {
                switch scalar.value {
                case 0x3400...0x4DBF,
                     0x4E00...0x9FFF,
                     0xF900...0xFAFF,
                     0x20000...0x2A6DF,
                     0x2A700...0x2B73F,
                     0x2B740...0x2B81F,
                     0x2B820...0x2CEAF:
                    score += Self.isSuspiciousCADMojibakeScalar(scalar) ? -90 : 100
                case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
                    score += 10
                case 0xFFFD:
                    score -= 160
                case 0x5C, 0x7C, 0x7B, 0x7D, 0x3B:
                    score -= 12
                default:
                    if CharacterSet.controlCharacters.contains(scalar) {
                        score -= 80
                    } else {
                        score += 1
                    }
                }
            }
            return score
        }

        private static func isSuspiciousCADMojibakeScalar(_ scalar: UnicodeScalar) -> Bool {
            "甯傛斂搴滄柦宸ュ浘娴嬭瘯鏂囧瓧鍥剧焊绠＄嚎閰嶇數钃戣娂胕芼".unicodeScalars.contains(scalar)
        }
    }
}

private extension SiteKeeperCADKernel.CADTextStyle {
    var usesSHXOrBigFont: Bool {
        [fontName, bigFontName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains { value in
                value.hasSuffix(".shx")
                    || value.contains("bigfont")
                    || value.contains("hztxt")
                    || value.contains("hzfs")
                    || value.contains("hzdx")
                    || value.contains("hzst")
                    || value.contains("gbhz")
                    || value.contains("gbcbig")
                    || value.contains("gbk")
                    || value.contains("gb2312")
                    || value.contains("gb18030")
                    || value.contains("chineses")
                    || value.contains("chineset")
                    || value.contains("tssd")
            }
    }

    var prefersBig5Bytes: Bool {
        [fontName, bigFontName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains { value in
                value.contains("big5")
                    || value.contains("chineset")
                    || value.contains("traditional")
            }
    }
}

private extension String {
    var containsUnicodeReplacementCharacter: Bool {
        unicodeScalars.contains { $0.value == 0xFFFD }
    }

    var containsCJKScalars: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x20000...0x2A6DF,
                 0x2A700...0x2B73F,
                 0x2B740...0x2B81F,
                 0x2B820...0x2CEAF:
                return true
            default:
                return false
            }
        }
    }

    var singleByteData: Data? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(unicodeScalars.count)
        for scalar in unicodeScalars {
            guard scalar.value <= 0xFF else { return nil }
            bytes.append(UInt8(scalar.value))
        }
        return Data(bytes)
    }
}

private extension Array where Element == String {
    mutating func appendOnce(_ value: String) {
        guard !contains(value) else { return }
        append(value)
    }
}
