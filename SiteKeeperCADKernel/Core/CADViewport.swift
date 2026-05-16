extension SiteKeeperCADKernel {
    struct CADViewport: Identifiable, Equatable, Codable {
        var id: String
        var layoutID: String
        var viewCenter: CADPoint
        var viewHeight: Double
        var twistRadians: Double
        var clipBounds: CADBounds

        init(
            id: String,
            layoutID: String,
            viewCenter: CADPoint = .zero,
            viewHeight: Double = 1,
            twistRadians: Double = 0,
            clipBounds: CADBounds = .empty
        ) {
            self.id = id
            self.layoutID = layoutID
            self.viewCenter = viewCenter
            self.viewHeight = viewHeight
            self.twistRadians = twistRadians
            self.clipBounds = clipBounds
        }
    }
}
