import Foundation

extension SiteKeeperCADKernel {
    struct CADDecodedText: Equatable, Codable {
        var decodedText: String
        var decodeMethod: String
        var warnings: [String]
    }

    struct CADTextDecoder {
        func decode(rawText: String) -> CADDecodedText {
            var warnings: [String] = []
            let unicodeDecoded = decodeUnicodeEscapes(in: rawText, warnings: &warnings)
            let mifDecoded = decodeMIFEscapeSequences(in: unicodeDecoded, warnings: &warnings)
            let decoded = repairMojibakeIfNeeded(mifDecoded, warnings: &warnings)
            let method: String
            if decoded == rawText {
                method = "rawString"
            } else if mifDecoded != unicodeDecoded {
                method = "mifEscape"
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

        private func decodeMIFEscapeSequences(in value: String, warnings: inout [String]) -> String {
            let pattern = #"\\?M\+[0-9A-Za-z]([0-9A-Fa-f]{4})"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return value
            }

            var output = value
            let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
            for match in matches.reversed() {
                guard
                    let fullRange = Range(match.range(at: 0), in: output),
                    let hexRange = Range(match.range(at: 1), in: output),
                    let decoded = decodeHexBytes(String(output[hexRange]))
                else {
                    warnings.append("CAD_TEXT_INVALID_MIF_ESCAPE")
                    continue
                }
                output.replaceSubrange(fullRange, with: decoded)
            }
            return output
        }

        private func repairMojibakeIfNeeded(_ value: String, warnings: inout [String]) -> String {
            guard !value.containsCJKScalars,
                  value.unicodeScalars.contains(where: { (0x80...0xFF).contains($0.value) }),
                  let data = value.singleByteData,
                  let repaired = decodeChineseBytes(data),
                  repaired.containsCJKScalars else {
                return value
            }
            warnings.append("CAD_TEXT_GBK_MOJIBAKE_REPAIRED")
            return repaired
        }

        private func decodeHexBytes(_ hex: String) -> String? {
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
            return decodeChineseBytes(Data(bytes))
        }

        private func decodeChineseBytes(_ data: Data) -> String? {
            for encoding in Self.chineseEncodings {
                guard let decoded = String(data: data, encoding: encoding),
                      !decoded.containsUnicodeReplacementCharacter,
                      !decoded.isEmpty else {
                    continue
                }
                return decoded
            }
            return nil
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

        private static var chineseEncodings: [String.Encoding] {
            [gb18030Encoding, gbkEncoding, gb2312Encoding]
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
