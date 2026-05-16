extension SiteKeeperCADKernel {
    struct CADLayer: Identifiable, Equatable, Codable {
        var id: String
        var name: String
        var isVisible: Bool
        var isLocked: Bool
        var colorARGB: UInt32
        var lineWeight: Double

        init(
            id: String,
            name: String,
            isVisible: Bool = true,
            isLocked: Bool = false,
            colorARGB: UInt32 = 0xFF2F3437,
            lineWeight: Double = 0.25
        ) {
            self.id = id
            self.name = name
            self.isVisible = isVisible
            self.isLocked = isLocked
            self.colorARGB = colorARGB
            self.lineWeight = lineWeight
        }

        static let `default` = CADLayer(id: "0", name: "0")
    }
}
