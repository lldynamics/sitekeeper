import Foundation
import CoreText
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
                displayText: displayText,
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
                .named("FangSong"),
                .named("STFangsong"),
                .named("FangSong_GB2312"),
                .named("SimFang"),
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
            displayText: String,
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
                    if let resolvedName = runtimeProbe.availableFontName(for: name) {
                        guard runtimeProbe.font(named: resolvedName, supports: displayText) else {
                            warnings.append("CAD_TEXT_FONT_LACKS_GLYPHS:\(name)")
                            continue
                        }
                        let fallbackApplied = firstNamedCandidate != nil &&
                            name.caseInsensitiveCompare(firstNamedCandidate ?? name) != .orderedSame
                        return (name: resolvedName, wasAvailable: true, fallbackApplied: fallbackApplied)
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
            availableFontName(for: name) != nil
        }

        func availableFontName(for name: String) -> String? {
            #if canImport(UIKit)
            if let font = UIFont(name: name, size: 12) {
                return font.fontName
            }
            let matchingFamily = UIFont.familyNames.first {
                $0.caseInsensitiveCompare(name) == .orderedSame
            }
            guard let family = matchingFamily,
                  let fontName = UIFont.fontNames(forFamilyName: family).first,
                  UIFont(name: fontName, size: 12) != nil else {
                return nil
            }
            return fontName
            #elseif canImport(AppKit)
            if let font = NSFont(name: name, size: 12) {
                return font.fontName
            }
            let matchingFamily = NSFontManager.shared.availableFontFamilies.first {
                $0.caseInsensitiveCompare(name) == .orderedSame
            }
            guard let family = matchingFamily,
                  let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                  let fontName = members.first?.first as? String,
                  NSFont(name: fontName, size: 12) != nil else {
                return nil
            }
            return fontName
            #else
            return nil
            #endif
        }

        func font(named name: String, supports text: String) -> Bool {
            let probeText = text.cjkCoverageProbeText
            guard !probeText.isEmpty else { return true }
            let font = CTFontCreateWithName(name as CFString, 12, nil)
            let characters = Array(probeText.utf16)
            guard !characters.isEmpty else { return true }
            var glyphs = Array(repeating: CGGlyph(), count: characters.count)
            return characters.withUnsafeBufferPointer { characterBuffer in
                glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                    guard let characterBase = characterBuffer.baseAddress,
                          let glyphBase = glyphBuffer.baseAddress else {
                        return false
                    }
                    return CTFontGetGlyphsForCharacters(font, characterBase, glyphBase, characters.count)
                }
            }
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

    var cjkCoverageProbeText: String {
        var scalars = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF:
                scalars.append(scalar)
            default:
                continue
            }
            if scalars.count >= 16 {
                break
            }
        }
        return String(scalars)
    }
}
