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
            let decoded = decodeUnicodeEscapes(in: rawText, warnings: &warnings)
            let method = decoded == rawText ? "rawString" : "unicodeEscape"
            return CADDecodedText(decodedText: decoded, decodeMethod: method, warnings: warnings)
        }

        func decode(_ data: Data, encoding: String.Encoding = .utf8) -> String {
            String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
        }

        private func decodeUnicodeEscapes(in value: String, warnings: inout [String]) -> String {
            let pattern = #"\\U\+([0-9A-Fa-f]{4,6})"#
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
    }
}
