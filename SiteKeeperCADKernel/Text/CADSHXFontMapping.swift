extension SiteKeeperCADKernel {
    struct CADSHXFontMapping: Equatable, Codable {
        var sourceName: String
        var replacementFamily: String
        var languageHint: String?

        static let defaultMappings: [CADSHXFontMapping] = [
            CADSHXFontMapping(sourceName: "txt.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "simplex.shx", replacementFamily: "Helvetica", languageHint: nil),
            CADSHXFontMapping(sourceName: "hztxt.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "hzfs.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans"),
            CADSHXFontMapping(sourceName: "gbcbig.shx", replacementFamily: "PingFang SC", languageHint: "zh-Hans")
        ]
    }
}
