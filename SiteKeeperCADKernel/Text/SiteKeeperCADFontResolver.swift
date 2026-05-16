import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension SiteKeeperCADKernel {
    struct CADResolvedFont: Equatable, Codable {
        var styleName: String
        var requestedFont: String?
        var fontFile: String?
        var bigFontFile: String?
        var selectedFontName: String
        var fontWasAvailable: Bool
        var fallbackReason: String?
        var fallbackUsed: Bool
        var missingFonts: [String]
        var missingBigFonts: [String]
        var warnings: [String]
    }

    struct CADFontResolver {
        var shxMappings: [CADSHXFontMapping] = CADSHXFontMapping.defaultMappings

        func resolve(style: CADTextStyle, displayText: String) -> CADResolvedFont {
            var warnings: [String] = []
            let fontName = cleaned(style.fontName)
            let bigFontName = cleaned(style.bigFontName)
            let containsCJK = displayText.containsCJKScalars
            let usesSHXFont = isSHXFont(fontName)
            let mapped = shxMappings.first {
                $0.sourceName.caseInsensitiveCompare(fontName ?? "") == .orderedSame
            }
            let runtimeProbe = CADRuntimeFontProbe()
            var missingFonts: [String] = []
            var missingBigFonts: [String] = []
            var fallbackReason: String?

            if fontName == nil {
                warnings.append("CAD_TEXT_FONT_MISSING")
            }

            if containsCJK, bigFontName == nil {
                warnings.append("CAD_TEXT_BIGFONT_MISSING")
            }

            if let bigFontName,
               !runtimeProbe.isNamedFontAvailable(bigFontName) {
                missingBigFonts.append(bigFontName)
                warnings.append("CAD_TEXT_BIGFONT_UNAVAILABLE:\(bigFontName)")
            }

            var candidates: [CADRuntimeFontProbe.FontCandidate] = []
            if usesSHXFont {
                if containsCJK {
                    warnings.append("CAD_TEXT_SHX_SKIPPED_FOR_UNICODE")
                    fallbackReason = "unicode-cjk-shx-bypassed"
                    candidates = cjkFallbackCandidates()
                } else {
                    warnings.append("CAD_TEXT_SHX_MAPPED_TO_SYSTEM_FONT")
                    fallbackReason = "shx-font-mapped"
                    if let mappedFamily = cleaned(mapped?.replacementFamily) {
                        candidates.append(.named(mappedFamily))
                    }
                    candidates.append(.system)
                }
            } else if let fontName {
                candidates.append(.named(fontName))
                if containsCJK {
                    candidates.append(contentsOf: cjkFallbackCandidates())
                } else {
                    candidates.append(.system)
                }
            } else {
                fallbackReason = "requested-font-missing"
                if containsCJK {
                    candidates = cjkFallbackCandidates()
                } else {
                    candidates = [.system]
                }
            }

            let uniqueCandidates = dedupe(candidates)
            let resolved = resolveFirstAvailable(
                uniqueCandidates,
                runtimeProbe: runtimeProbe,
                missingFonts: &missingFonts,
                warnings: &warnings
            )
            if fallbackReason == nil, resolved.fallbackApplied {
                fallbackReason = "requested-font-unavailable"
            }

            return CADResolvedFont(
                styleName: style.name,
                requestedFont: fontName,
                fontFile: fontName,
                bigFontFile: bigFontName,
                selectedFontName: resolved.name,
                fontWasAvailable: resolved.wasAvailable,
                fallbackReason: fallbackReason,
                fallbackUsed: fallbackReason != nil || resolved.fallbackApplied,
                missingFonts: missingFonts,
                missingBigFonts: missingBigFonts,
                warnings: warnings
            )
        }

        private func cjkFallbackCandidates() -> [CADRuntimeFontProbe.FontCandidate] {
            [
                .named("PingFang SC"),
                .named("Hiragino Sans GB"),
                .named("Heiti SC"),
                .named("Songti SC"),
                .named("Noto Sans CJK SC"),
                .named("Source Han Sans SC"),
                .system
            ]
        }

        private func dedupe(_ candidates: [CADRuntimeFontProbe.FontCandidate]) -> [CADRuntimeFontProbe.FontCandidate] {
            var seen = Set<String>()
            var output: [CADRuntimeFontProbe.FontCandidate] = []
            output.reserveCapacity(candidates.count)
            for candidate in candidates {
                let key: String
                switch candidate {
                case let .named(name):
                    key = "named:\(name.lowercased())"
                case .system:
                    key = "system"
                }
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                output.append(candidate)
            }
            return output
        }

        private func resolveFirstAvailable(
            _ candidates: [CADRuntimeFontProbe.FontCandidate],
            runtimeProbe: CADRuntimeFontProbe,
            missingFonts: inout [String],
            warnings: inout [String]
        ) -> (name: String, wasAvailable: Bool, fallbackApplied: Bool) {
            var firstNamedCandidate: String?
            for candidate in candidates {
                switch candidate {
                case let .named(name):
                    if firstNamedCandidate == nil {
                        firstNamedCandidate = name
                    }
                    if runtimeProbe.isNamedFontAvailable(name) {
                        let fallbackApplied = firstNamedCandidate != nil &&
                            name.caseInsensitiveCompare(firstNamedCandidate ?? name) != .orderedSame
                        return (name: name, wasAvailable: true, fallbackApplied: fallbackApplied)
                    }
                    missingFonts.append(name)
                    warnings.append("CAD_TEXT_FONT_UNAVAILABLE:\(name)")
                case .system:
                    let system = runtimeProbe.systemFontName()
                    let fallbackApplied = firstNamedCandidate != nil
                    return (name: system, wasAvailable: true, fallbackApplied: fallbackApplied)
                }
            }
            let system = runtimeProbe.systemFontName()
            warnings.append("CAD_TEXT_SYSTEM_FONT_UNAVAILABLE")
            return (name: system, wasAvailable: false, fallbackApplied: true)
        }

        private func cleaned(_ value: String?) -> String? {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }

        private func isSHXFont(_ value: String?) -> Bool {
            guard let value else { return false }
            let lowercased = value.lowercased()
            return lowercased.hasSuffix(".shx") || shxMappings.contains {
                $0.sourceName.caseInsensitiveCompare(value) == .orderedSame
            }
        }
    }

    private struct CADRuntimeFontProbe {
        enum FontCandidate {
            case named(String)
            case system
        }

        func isNamedFontAvailable(_ name: String) -> Bool {
            #if canImport(UIKit)
            return UIFont(name: name, size: 12) != nil
            #elseif canImport(AppKit)
            return NSFont(name: name, size: 12) != nil
            #else
            return false
            #endif
        }

        func systemFontName() -> String {
            #if canImport(UIKit)
            return UIFont.systemFont(ofSize: 12).fontName
            #elseif canImport(AppKit)
            return NSFont.systemFont(ofSize: 12).fontName
            #else
            return "System"
            #endif
        }
    }
}

private extension String {
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
}
