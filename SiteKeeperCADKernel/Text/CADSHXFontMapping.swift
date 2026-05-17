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
            CADSHXFontMapping(sourceName: "isocp.shx", replacementFamily: "Helvetica", languageHint: nil),
            CADSHXFontMapping(sourceName: "hztxt.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hzfs.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hzdx.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hzst.shx", replacementFamily: "Songti SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbcbig.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbhzfs.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbhzdx.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "chineses.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "chineset.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hant"),
            CADSHXFontMapping(sourceName: "tssdchn.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "tssdeng.shx", replacementFamily: "Helvetica", languageHint: nil),
            CADSHXFontMapping(sourceName: "simsun.shx", replacementFamily: "Songti SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "big5.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hant")
        ]
    }
}
