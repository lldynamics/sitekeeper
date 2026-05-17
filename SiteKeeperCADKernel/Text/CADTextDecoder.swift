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
            let mifDecoded = decodeMIFBigFontEscapeSequences(
                in: unicodeDecoded,
                textStyle: textStyle,
                warnings: &warnings
            )
            let shxHexDecoded = decodeSHXBigFontHexEscapes(
                in: mifDecoded,
                textStyle: textStyle,
                warnings: &warnings
            )
            let decoded = repairMojibakeIfNeeded(shxHexDecoded, textStyle: textStyle, warnings: &warnings)
            let method: String
            if decoded == rawText {
                method = "rawString"
            } else if mifDecoded != unicodeDecoded {
                method = "mifEscape"
            } else if shxHexDecoded != mifDecoded {
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

        private func repairMojibakeIfNeeded(
            _ value: String,
            textStyle: CADTextStyle?,
            warnings: inout [String]
        ) -> String {
            guard !value.containsCJKScalars,
                  value.unicodeScalars.contains(where: { (0x80...0xFF).contains($0.value) }),
                  let data = value.singleByteData,
                  let decoded = decodeTextBytes(data, textStyle: textStyle),
                  decoded.text.containsCJKScalars else {
                return value
            }
            warnings.appendOnce("CAD_TEXT_GBK_MOJIBAKE_REPAIRED")
            if textStyle?.usesSHXOrBigFont == true {
                warnings.appendOnce("CAD_TEXT_SHX_BIGFONT_BYTES_DECODED")
                warnings.appendOnce("CAD_TEXT_SHX_BIGFONT_BYTES_REPAIRED")
            }
            appendEncodingWarning(decoded.encodingName, warnings: &warnings)
            return decoded.text
        }

        private func decodeHexBytes(
            _ hex: String,
            textStyle: CADTextStyle?,
            warnings: inout [String],
            warningPrefix: String
        ) -> String? {
            guard hex.count.isMultiple(of: 2) else { return nil }
            var bytes: [UInt8] = []
            bytes.reserveCapacity(hex.count / 2)
            var index = hex.startIndex
            while index < hex.endIndex {
                let next = hex.index(index, offsetBy: 2)
                guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
                bytes.append(byte)
                index = next
            }
            guard let decoded = decodeTextBytes(Data(bytes), textStyle: textStyle) else { return nil }
            warnings.appendOnce("\(warningPrefix)_\(decoded.encodingName)_DECODED")
            return decoded.text
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
                    || value.contains("gbcbig")
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
