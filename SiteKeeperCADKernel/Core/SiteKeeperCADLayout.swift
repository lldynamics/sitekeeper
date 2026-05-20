extension SiteKeeperCADKernel {
    struct CADLayout: Identifiable, Equatable, Codable {
        var id: String
        var name: String
        var isModelSpace: Bool
        var paperBounds: CADBounds
        var viewportIDs: [String]

        init(
            id: String,
            name: String,
            isModelSpace: Bool = false,
            paperBounds: CADBounds = .empty,
            viewportIDs: [String] = []
        ) {
            self.id = id
            self.name = name
            self.isModelSpace = isModelSpace
            self.paperBounds = paperBounds
            self.viewportIDs = viewportIDs
        }

        static let modelSpace = CADLayout(id: "model", name: "Model", isModelSpace: true)
    }
}
