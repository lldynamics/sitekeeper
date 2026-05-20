import CoreText
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension NativeCAD {
    typealias CADFontResolver = SiteKeeperCADKernel.CADFontResolver
}

struct CADImportedFontDescriptor: Equatable {
    var fontName: String
    var filePath: String
}

enum CADImportedFontRegistryError: LocalizedError {
    case unsupportedExtension(String)
    case unreadableFont(URL)
    case registrationFailed(String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedExtension(ext):
            return "暂只支持导入 TTF / OTF / TTC 字体文件，当前文件类型：\(ext)"
        case let .unreadableFont(url):
            return "无法读取字体文件：\(url.lastPathComponent)"
        case let .registrationFailed(reason):
            return "字体注册失败：\(reason)"
        }
    }
}

enum CADImportedFontRegistry {
    private static let probeText = "中文施工图ABC123"

    static func importFont(from sourceURL: URL) throws -> CADImportedFontDescriptor {
        let ext = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["ttf", "otf", "ttc"].contains(ext) else {
            throw CADImportedFontRegistryError.unsupportedExtension(ext.isEmpty ? "未知" : ext)
        }

        let shouldStopAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let destinationDirectory = try fontDirectory()
        let destinationURL = uniqueDestinationURL(
            in: destinationDirectory,
            preferredFileName: sourceURL.lastPathComponent
        )
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        let fontNames = try registerFont(at: destinationURL)
        let selectedName = availableFontName(from: fontNames, supporting: probeText) ?? fontNames.first
        guard let selectedName, !selectedName.isEmpty else {
            throw CADImportedFontRegistryError.unreadableFont(destinationURL)
        }
        return CADImportedFontDescriptor(fontName: selectedName, filePath: destinationURL.path)
    }

    @discardableResult
    static func registerFontIfNeeded(atPath path: String) -> [String] {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return (try? registerFont(at: URL(fileURLWithPath: trimmed))) ?? []
    }

    static func resolvedDisplayFontName(
        for choice: CADDrawingTextDisplayFont,
        importedFontName: String,
        importedFontPath: String
    ) -> String? {
        switch choice {
        case .auto:
            return nil
        case .system:
            return systemFontName()
        case .imported:
            registerFontIfNeeded(atPath: importedFontPath)
            let trimmed = importedFontName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return availableFontName(from: [trimmed], supporting: probeText)
        default:
            return availableFontName(from: choice.candidateFontNames, supporting: probeText)
        }
    }

    static func availableFontName(from candidates: [String], supporting text: String = probeText) -> String? {
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let resolved = availableFontName(for: trimmed, supporting: text) {
                return resolved
            }
        }
        return nil
    }

    private static func fontDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = base
            .appendingPathComponent("sitekeeper", isDirectory: true)
            .appendingPathComponent("cad-fonts", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func uniqueDestinationURL(in directory: URL, preferredFileName: String) -> URL {
        let sanitized = preferredFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "cad-font.ttf"
            : preferredFileName
        let base = (sanitized as NSString).deletingPathExtension
        let ext = (sanitized as NSString).pathExtension
        var candidate = directory.appendingPathComponent(sanitized)
        var counter = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let suffix = ext.isEmpty ? "" : ".\(ext)"
            candidate = directory.appendingPathComponent("\(base)-\(counter)\(suffix)")
            counter += 1
        }
        return candidate
    }

    private static func registerFont(at url: URL) throws -> [String] {
        let names = fontNames(in: url)
        guard !names.isEmpty else {
            throw CADImportedFontRegistryError.unreadableFont(url)
        }

        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !registered, let cfError = error?.takeRetainedValue() {
            let nsError = cfError as Error as NSError
            let alreadyRegistered = nsError.domain == kCTFontManagerErrorDomain as String
                && nsError.code == CTFontManagerError.alreadyRegistered.rawValue
            guard alreadyRegistered || availableFontName(from: names, supporting: probeText) != nil else {
                throw CADImportedFontRegistryError.registrationFailed(nsError.localizedDescription)
            }
        }
        return names
    }

    private static func fontNames(in url: URL) -> [String] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
            return []
        }
        var names: [String] = []
        for descriptor in descriptors {
            if let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String {
                names.append(name)
            }
            if let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String {
                names.append(family)
            }
        }
        var seen = Set<String>()
        return names.filter { name in
            let key = name.lowercased()
            return seen.insert(key).inserted
        }
    }

    private static func availableFontName(for name: String, supporting text: String) -> String? {
        #if canImport(UIKit)
        if let font = UIFont(name: name, size: 12), font.supportsCADImportedFontText(text) {
            return font.fontName
        }
        if let family = UIFont.familyNames.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
           let fontName = UIFont.fontNames(forFamilyName: family).first,
           let font = UIFont(name: fontName, size: 12),
           font.supportsCADImportedFontText(text) {
            return font.fontName
        }
        #elseif canImport(AppKit)
        if let font = NSFont(name: name, size: 12), font.supportsCADImportedFontText(text) {
            return font.fontName
        }
        if let family = NSFontManager.shared.availableFontFamilies.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
           let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
           let fontName = members.first?.first as? String,
           let font = NSFont(name: fontName, size: 12),
           font.supportsCADImportedFontText(text) {
            return font.fontName
        }
        #endif
        return nil
    }

    private static func systemFontName() -> String {
        #if canImport(UIKit)
        return UIFont.systemFont(ofSize: 12).fontName
        #elseif canImport(AppKit)
        return NSFont.systemFont(ofSize: 12).fontName
        #else
        return "System"
        #endif
    }
}

#if canImport(UIKit)
private extension UIFont {
    func supportsCADImportedFontText(_ text: String) -> Bool {
        let probe = text.cadImportedFontCJKProbeText
        guard !probe.isEmpty else { return true }
        let ctFont = CTFontCreateWithName(fontName as CFString, pointSize, nil)
        let characters = Array(probe.utf16)
        var glyphs = Array(repeating: CGGlyph(), count: characters.count)
        return characters.withUnsafeBufferPointer { characterBuffer in
            glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                guard let characterBase = characterBuffer.baseAddress,
                      let glyphBase = glyphBuffer.baseAddress else {
                    return false
                }
                return CTFontGetGlyphsForCharacters(ctFont, characterBase, glyphBase, characters.count)
            }
        }
    }
}
#elseif canImport(AppKit)
private extension NSFont {
    func supportsCADImportedFontText(_ text: String) -> Bool {
        let probe = text.cadImportedFontCJKProbeText
        guard !probe.isEmpty else { return true }
        let ctFont = CTFontCreateWithName(fontName as CFString, pointSize, nil)
        let characters = Array(probe.utf16)
        var glyphs = Array(repeating: CGGlyph(), count: characters.count)
        return characters.withUnsafeBufferPointer { characterBuffer in
            glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                guard let characterBase = characterBuffer.baseAddress,
                      let glyphBase = glyphBuffer.baseAddress else {
                    return false
                }
                return CTFontGetGlyphsForCharacters(ctFont, characterBase, glyphBase, characters.count)
            }
        }
    }
}
#endif

private extension String {
    var cadImportedFontCJKProbeText: String {
        var scalars = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x20000...0x2A6DF,
                 0x2A700...0x2B73F,
                 0x2B740...0x2B81F,
                 0x2B820...0x2CEAF:
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
