import Foundation

extension SiteKeeperCADKernel {
    struct CADTextTrace: Equatable, Codable {
        var entityId: String
        var entityType: String
        var rawText: String
        var decodedText: String
        var normalizedText: String
        var displayText: String
        var textStyleName: String
        var fontFile: String?
        var bigFontFile: String?
        var selectedFontName: String
        var fontWasAvailable: Bool
        var fallbackReason: String?
        var attributeTag: String?
        var rawTextBytesHex: String?
        var warnings: [String]

        enum CodingKeys: String, CodingKey {
            case entityId
            case entityType
            case rawText
            case decodedText
            case normalizedText
            case displayText
            case textStyleName
            case fontFile
            case bigFontFile
            case selectedFontName
            case fontWasAvailable
            case fallbackReason
            case attributeTag
            case rawTextBytesHex
            case warnings
        }

        init(
            entityId: String,
            entityType: String,
            rawText: String,
            decodedText: String,
            normalizedText: String,
            displayText: String,
            textStyleName: String,
            fontFile: String? = nil,
            bigFontFile: String? = nil,
            selectedFontName: String,
            fontWasAvailable: Bool = true,
            fallbackReason: String? = nil,
            attributeTag: String? = nil,
            rawTextBytesHex: String? = nil,
            warnings: [String] = []
        ) {
            self.entityId = entityId
            self.entityType = entityType
            self.rawText = rawText
            self.decodedText = decodedText
            self.normalizedText = normalizedText
            self.displayText = displayText
            self.textStyleName = textStyleName
            self.fontFile = fontFile
            self.bigFontFile = bigFontFile
            self.selectedFontName = selectedFontName
            self.fontWasAvailable = fontWasAvailable
            self.fallbackReason = fallbackReason
            self.attributeTag = attributeTag
            self.rawTextBytesHex = rawTextBytesHex
            self.warnings = warnings
        }

        func jsonLine() throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(self)
            return String(decoding: data, as: UTF8.self)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(entityId, forKey: .entityId)
            try container.encode(entityType, forKey: .entityType)
            try container.encode(rawText, forKey: .rawText)
            try container.encode(decodedText, forKey: .decodedText)
            try container.encode(normalizedText, forKey: .normalizedText)
            try container.encode(displayText, forKey: .displayText)
            try container.encode(textStyleName, forKey: .textStyleName)
            if let fontFile {
                try container.encode(fontFile, forKey: .fontFile)
            } else {
                try container.encodeNil(forKey: .fontFile)
            }
            if let bigFontFile {
                try container.encode(bigFontFile, forKey: .bigFontFile)
            } else {
                try container.encodeNil(forKey: .bigFontFile)
            }
            try container.encode(selectedFontName, forKey: .selectedFontName)
            try container.encode(fontWasAvailable, forKey: .fontWasAvailable)
            if let fallbackReason {
                try container.encode(fallbackReason, forKey: .fallbackReason)
            } else {
                try container.encodeNil(forKey: .fallbackReason)
            }
            if let attributeTag {
                try container.encode(attributeTag, forKey: .attributeTag)
            } else {
                try container.encodeNil(forKey: .attributeTag)
            }
            if let rawTextBytesHex {
                try container.encode(rawTextBytesHex, forKey: .rawTextBytesHex)
            } else {
                try container.encodeNil(forKey: .rawTextBytesHex)
            }
            try container.encode(warnings, forKey: .warnings)
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            entityId = try container.decode(String.self, forKey: .entityId)
            entityType = try container.decode(String.self, forKey: .entityType)
            rawText = try container.decode(String.self, forKey: .rawText)
            decodedText = try container.decode(String.self, forKey: .decodedText)
            normalizedText = try container.decode(String.self, forKey: .normalizedText)
            displayText = try container.decode(String.self, forKey: .displayText)
            textStyleName = try container.decode(String.self, forKey: .textStyleName)
            fontFile = try container.decodeIfPresent(String.self, forKey: .fontFile)
            bigFontFile = try container.decodeIfPresent(String.self, forKey: .bigFontFile)
            selectedFontName = try container.decode(String.self, forKey: .selectedFontName)
            fontWasAvailable = try container.decodeIfPresent(Bool.self, forKey: .fontWasAvailable) ?? true
            fallbackReason = try container.decodeIfPresent(String.self, forKey: .fallbackReason)
            attributeTag = try container.decodeIfPresent(String.self, forKey: .attributeTag)
            rawTextBytesHex = try container.decodeIfPresent(String.self, forKey: .rawTextBytesHex)
            warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
        }
    }

    struct CADFontDiagnosticsEntry: Equatable, Codable {
        var requestedFont: String?
        var resolvedFont: String
        var missingFonts: [String]
        var missingBigFonts: [String]
        var fallbackUsed: Bool
    }

    struct CADFontDiagnosticsJSONWriter {
        func write(from traces: [CADTextTrace], to url: URL) throws {
            let entries = traces.map(fontDiagnosticsEntry)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: url, options: [.atomic])
        }

        private func fontDiagnosticsEntry(from trace: CADTextTrace) -> CADFontDiagnosticsEntry {
            CADFontDiagnosticsEntry(
                requestedFont: trace.fontFile,
                resolvedFont: trace.selectedFontName,
                missingFonts: parseWarningValues(
                    from: trace.warnings,
                    prefix: "CAD_TEXT_FONT_UNAVAILABLE:"
                ),
                missingBigFonts: parseWarningValues(
                    from: trace.warnings,
                    prefix: "CAD_TEXT_BIGFONT_UNAVAILABLE:"
                ),
                fallbackUsed: trace.fallbackReason != nil
            )
        }

        private func parseWarningValues(from warnings: [String], prefix: String) -> [String] {
            var values: [String] = []
            var seen = Set<String>()
            for warning in warnings {
                guard warning.hasPrefix(prefix) else { continue }
                let value = String(warning.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, !seen.contains(value) else { continue }
                seen.insert(value)
                values.append(value)
            }
            return values
        }
    }

    struct CADTextTraceJSONLWriter {
        func write(_ traces: [CADTextTrace], to url: URL) throws {
            let body = try traces
                .map { try $0.jsonLine() }
                .joined(separator: "\n")
            let data = traces.isEmpty ? Data() : Data((body + "\n").utf8)
            try data.write(to: url, options: [.atomic])
        }
    }
}
