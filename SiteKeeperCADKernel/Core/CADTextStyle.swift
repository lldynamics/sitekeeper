extension SiteKeeperCADKernel {
    struct CADTextStyle: Identifiable, Equatable, Codable {
        var id: String
        var name: String
        var fontName: String?
        var bigFontName: String?
        var fixedHeight: Double?
        var widthFactor: Double
        var obliqueAngleRadians: Double

        init(
            id: String,
            name: String,
            fontName: String? = nil,
            bigFontName: String? = nil,
            fixedHeight: Double? = nil,
            widthFactor: Double = 1,
            obliqueAngleRadians: Double = 0
        ) {
            self.id = id
            self.name = name
            self.fontName = fontName
            self.bigFontName = bigFontName
            self.fixedHeight = fixedHeight
            self.widthFactor = widthFactor
            self.obliqueAngleRadians = obliqueAngleRadians
        }

        static let `default` = CADTextStyle(id: "standard", name: "Standard")
    }
}
