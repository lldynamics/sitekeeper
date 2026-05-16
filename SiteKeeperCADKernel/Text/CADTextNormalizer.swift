import Foundation

extension SiteKeeperCADKernel {
    struct CADNormalizedText: Equatable, Codable {
        var normalizedText: String
        var warnings: [String]
    }

    struct CADTextNormalizer {
        func normalize(_ value: String) -> String {
            normalizeText(value).normalizedText
        }

        func normalizeText(_ value: String) -> CADNormalizedText {
            var warnings: [String] = []
            let symbolNormalized = normalizePercentControls(in: value, warnings: &warnings)
            let normalized = symbolNormalized
                .replacingOccurrences(of: "\\P", with: "\n")
                .replacingOccurrences(of: "\\~", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return CADNormalizedText(normalizedText: normalized, warnings: warnings)
        }

        private func normalizePercentControls(in value: String, warnings: inout [String]) -> String {
            var output = ""
            var index = value.startIndex

            while index < value.endIndex {
                if value[index] == "%",
                   value.distance(from: index, to: value.endIndex) >= 3 {
                    let next = value.index(after: index)
                    let third = value.index(after: next)
                    if value[next] == "%" {
                        let marker = value[third]
                        switch marker {
                        case "%":
                            output.append("%")
                            index = value.index(after: third)
                            continue
                        case "d", "D":
                            output.append("°")
                            index = value.index(after: third)
                            continue
                        case "p", "P":
                            output.append("±")
                            index = value.index(after: third)
                            continue
                        case "c", "C":
                            output.append("∅")
                            index = value.index(after: third)
                            continue
                        default:
                            warnings.append("CAD_TEXT_UNKNOWN_PERCENT_CONTROL:\(marker)")
                        }
                    }
                }

                output.append(value[index])
                index = value.index(after: index)
            }

            return output
        }
    }
}
