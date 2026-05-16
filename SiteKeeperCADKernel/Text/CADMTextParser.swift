import Foundation

extension SiteKeeperCADKernel {
    struct CADMTextParser {
        struct Result: Equatable, Codable {
            var plainText: String
            var warnings: [String]
        }

        func parse(_ raw: String) -> Result {
            var output = ""
            var warnings: [String] = []
            var index = raw.startIndex

            while index < raw.endIndex {
                let character = raw[index]
                if character == "{" || character == "}" {
                    warnings.appendOnce("CAD_MTEXT_GROUPING_REMOVED")
                    index = raw.index(after: index)
                    continue
                }

                guard character == "\\" else {
                    output.append(character)
                    index = raw.index(after: index)
                    continue
                }

                let controlStart = index
                index = raw.index(after: index)
                guard index < raw.endIndex else {
                    output.append("\\")
                    continue
                }

                let control = raw[index]
                switch control {
                case "P":
                    output.append("\n")
                    index = raw.index(after: index)
                case "~":
                    output.append(" ")
                    index = raw.index(after: index)
                case "L", "l", "O", "o", "K", "k":
                    warnings.appendOnce("CAD_MTEXT_INLINE_FORMAT_REMOVED")
                    index = raw.index(after: index)
                case "\\":
                    output.append("\\")
                    index = raw.index(after: index)
                case "S":
                    let stackStart = raw.index(after: index)
                    let stackEnd = raw[stackStart...].firstIndex(of: ";") ?? raw.endIndex
                    let stackContent = String(raw[stackStart..<stackEnd])
                    output.append(simplifyStackedText(stackContent))
                    warnings.appendOnce("CAD_MTEXT_STACK_SIMPLIFIED")
                    index = stackEnd < raw.endIndex ? raw.index(after: stackEnd) : stackEnd
                case "A", "C", "c", "F", "f", "H", "h", "Q", "q", "T", "W", "w":
                    warnings.appendOnce("CAD_MTEXT_INLINE_FORMAT_REMOVED")
                    index = skipFormatControl(from: index, in: raw)
                default:
                    warnings.appendOnce("CAD_MTEXT_UNKNOWN_CONTROL:\(control)")
                    output.append(raw[controlStart])
                    output.append(control)
                    index = raw.index(after: index)
                }
            }

            let plainText = output
                .replacingOccurrences(of: "\r\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Result(plainText: plainText, warnings: warnings)
        }

        private func skipFormatControl(from controlIndex: String.Index, in raw: String) -> String.Index {
            let next = raw.index(after: controlIndex)
            guard next < raw.endIndex else {
                return next
            }
            guard let semicolon = raw[next...].firstIndex(of: ";") else {
                return next
            }
            return raw.index(after: semicolon)
        }

        private func simplifyStackedText(_ value: String) -> String {
            let separators = CharacterSet(charactersIn: "^#/")
            return value
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "/")
        }
    }
}

private extension Array where Element == String {
    mutating func appendOnce(_ value: String) {
        guard !contains(value) else { return }
        append(value)
    }
}
