extension CADPoC {
    struct CADOpenTrace: Equatable, Codable {
        var fileName: String
        var importSource: String
        var rawLineCount: Int
        var entityCount: Int
        var drawableEntityCount: Int
        var bounds: SiteKeeperCADKernel.CADBounds
        var openedForRender: Bool

        init(
            fileName: String,
            importSource: String,
            rawLineCount: Int = 0,
            entityCount: Int = 0,
            drawableEntityCount: Int = 0,
            bounds: SiteKeeperCADKernel.CADBounds = .empty,
            openedForRender: Bool? = nil
        ) {
            self.fileName = fileName
            self.importSource = importSource
            self.rawLineCount = rawLineCount
            self.entityCount = entityCount
            self.drawableEntityCount = drawableEntityCount
            self.bounds = bounds
            self.openedForRender = openedForRender ?? (drawableEntityCount > 0)
        }

        static func unsupported(fileName: String, importSource: String) -> CADOpenTrace {
            CADOpenTrace(
                fileName: fileName,
                importSource: importSource,
                rawLineCount: 0,
                entityCount: 0,
                drawableEntityCount: 0,
                bounds: .empty,
                openedForRender: false
            )
        }
    }
}
