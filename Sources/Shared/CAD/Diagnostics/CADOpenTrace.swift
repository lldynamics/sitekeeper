extension CADPoC {
    struct CADOpenTrace: Equatable, Codable {
        var fileName: String
        var importSource: String
        var rawLineCount: Int
        var rawPolylineCount: Int
        var rawCircleCount: Int
        var rawArcCount: Int
        var rawInsertCount: Int
        var rawEllipseCount: Int
        var rawSplineCount: Int
        var rawFilledShapeCount: Int
        var rawDimensionCount: Int
        var rawHatchCount: Int
        var rawTextCount: Int
        var expandedInsertEntityCount: Int
        var entityCount: Int
        var drawableEntityCount: Int
        var renderCommandCount: Int
        var bounds: SiteKeeperCADKernel.CADBounds
        var openedForRender: Bool

        init(
            fileName: String,
            importSource: String,
            rawLineCount: Int = 0,
            rawPolylineCount: Int = 0,
            rawCircleCount: Int = 0,
            rawArcCount: Int = 0,
            rawInsertCount: Int = 0,
            rawEllipseCount: Int = 0,
            rawSplineCount: Int = 0,
            rawFilledShapeCount: Int = 0,
            rawDimensionCount: Int = 0,
            rawHatchCount: Int = 0,
            rawTextCount: Int = 0,
            expandedInsertEntityCount: Int = 0,
            entityCount: Int = 0,
            drawableEntityCount: Int = 0,
            renderCommandCount: Int = 0,
            bounds: SiteKeeperCADKernel.CADBounds = .empty,
            openedForRender: Bool? = nil
        ) {
            self.fileName = fileName
            self.importSource = importSource
            self.rawLineCount = rawLineCount
            self.rawPolylineCount = rawPolylineCount
            self.rawCircleCount = rawCircleCount
            self.rawArcCount = rawArcCount
            self.rawInsertCount = rawInsertCount
            self.rawEllipseCount = rawEllipseCount
            self.rawSplineCount = rawSplineCount
            self.rawFilledShapeCount = rawFilledShapeCount
            self.rawDimensionCount = rawDimensionCount
            self.rawHatchCount = rawHatchCount
            self.rawTextCount = rawTextCount
            self.expandedInsertEntityCount = expandedInsertEntityCount
            self.entityCount = entityCount
            self.drawableEntityCount = drawableEntityCount
            self.renderCommandCount = renderCommandCount
            self.bounds = bounds
            self.openedForRender = openedForRender ?? (drawableEntityCount > 0 && renderCommandCount > 0)
        }

        static func unsupported(fileName: String, importSource: String) -> CADOpenTrace {
            CADOpenTrace(
                fileName: fileName,
                importSource: importSource,
                rawLineCount: 0,
                rawPolylineCount: 0,
                rawCircleCount: 0,
                rawArcCount: 0,
                rawEllipseCount: 0,
                rawSplineCount: 0,
                rawFilledShapeCount: 0,
                rawDimensionCount: 0,
                rawHatchCount: 0,
                rawTextCount: 0,
                entityCount: 0,
                drawableEntityCount: 0,
                renderCommandCount: 0,
                bounds: .empty,
                openedForRender: false
            )
        }
    }
}
