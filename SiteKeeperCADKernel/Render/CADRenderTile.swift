extension SiteKeeperCADKernel {
    struct CADRenderTile: Identifiable, Equatable, Hashable, Codable {
        var id: String
        var bounds: CADBounds
        var lodLevel: Int
    }
}
