import Foundation

extension SiteKeeperCADKernel {
    struct CADSHXFontMapping: Equatable, Codable {
        var sourceName: String
        var replacementFamily: String
        var languageHint: String?

        static let defaultMappings: [CADSHXFontMapping] = [
            CADSHXFontMapping(sourceName: "txt.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "simplex.shx", replacementFamily: "Helvetica", languageHint: nil),
            CADSHXFontMapping(sourceName: "romans.shx", replacementFamily: "Helvetica", languageHint: nil),
            CADSHXFontMapping(sourceName: "romanc.shx", replacementFamily: "Helvetica", languageHint: nil),
            CADSHXFontMapping(sourceName: "romand.shx", replacementFamily: "Helvetica", languageHint: nil),
            CADSHXFontMapping(sourceName: "isocp.shx", replacementFamily: "Helvetica", languageHint: nil),
            CADSHXFontMapping(sourceName: "isoct.shx", replacementFamily: "Helvetica", languageHint: nil),
            CADSHXFontMapping(sourceName: "hztxt.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hztxt1.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hztxt2.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hztext.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hzfs.shx", replacementFamily: "FangSong", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hzfs1.shx", replacementFamily: "FangSong", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hzfs2.shx", replacementFamily: "FangSong", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "fs.shx", replacementFamily: "FangSong", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "fs1.shx", replacementFamily: "FangSong", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "fs2.shx", replacementFamily: "FangSong", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "simfang.shx", replacementFamily: "FangSong", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "fangsong.shx", replacementFamily: "FangSong", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "fangsong_gb2312.shx", replacementFamily: "FangSong", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "stfangsong.shx", replacementFamily: "FangSong", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hzdx.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hzst.shx", replacementFamily: "Songti SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "song.shx", replacementFamily: "Songti SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "songti.shx", replacementFamily: "Songti SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "simsun.shx", replacementFamily: "Songti SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hzkai.shx", replacementFamily: "Kaiti SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "kaiti.shx", replacementFamily: "Kaiti SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "simkai.shx", replacementFamily: "Kaiti SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hzhei.shx", replacementFamily: "Heiti SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "simhei.shx", replacementFamily: "Heiti SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbcbig.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbcbiggb.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbhz.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbtxt.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbenor.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbeitc.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbhzfs.shx", replacementFamily: "FangSong", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbhzdx.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbfs.shx", replacementFamily: "FangSong", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbk.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbksong.shx", replacementFamily: "Songti SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbkfs.shx", replacementFamily: "FangSong", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbhei.shx", replacementFamily: "Heiti SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbst.shx", replacementFamily: "Songti SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "chineses.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "chinesegb.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "chineset.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hant"),
            CADSHXFontMapping(sourceName: "cht.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hant"),
            CADSHXFontMapping(sourceName: "mingliu.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hant"),
            CADSHXFontMapping(sourceName: "tssdchn.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "tssdeng.shx", replacementFamily: "Helvetica", languageHint: nil),
            CADSHXFontMapping(sourceName: "tssd.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hztssd.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "big5.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hant")
        ]

        static func mapping(
            for rawName: String?,
            in mappings: [CADSHXFontMapping] = CADSHXFontMapping.defaultMappings
        ) -> CADSHXFontMapping? {
            let keys = normalizedKeys(for: rawName)
            guard !keys.isEmpty else { return nil }
            return mappings.first { mapping in
                normalizedKeys(for: mapping.sourceName).contains { keys.contains($0) }
            }
        }

        static func normalizedKey(_ rawName: String?) -> String? {
            normalizedKeys(for: rawName).first
        }

        private static func normalizedKeys(for rawName: String?) -> Set<String> {
            guard let rawName else { return [] }
            let folded = rawName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(
                    options: [.caseInsensitive, .widthInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                .lowercased()
            guard !folded.isEmpty else { return [] }

            let separators = CharacterSet(charactersIn: "/\\:;|, \t\r\n()[]{}<>\"'")
            let tokens = folded
                .components(separatedBy: separators)
                .filter { !$0.isEmpty }
            let candidates = tokens.isEmpty ? [folded] : [folded] + tokens

            return Set(candidates.compactMap { token in
                let withoutSuffix = token.replacingOccurrences(
                    of: "\\.(shx|shp|fon)$",
                    with: "",
                    options: .regularExpression
                )
                let collapsed = withoutSuffix.replacingOccurrences(of: " ", with: "")
                return collapsed.isEmpty ? nil : collapsed
            })
        }
    }
}
