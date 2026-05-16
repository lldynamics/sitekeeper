extension SiteKeeperCADKernel {
    struct DWGOpenPipelineTrace: Equatable, Codable {
        var fileName: String
        var fileSize: Int
        var dwgVersion: String?
        var libreDwgAvailable: Bool
        var dwgreadJsonExitCode: Int?
        var dwgreadDxfExitCode: Int?
        var dwg2dxfExitCode: Int?
        var jsonRawEntityCount: Int
        var dxfRawEntityCount: Int
        var adapterEntityCount: Int
        var databaseEntityCount: Int
        var drawableEntityCount: Int
        var renderCommandCount: Int
        var extents: CADBounds?
        var currentLayout: String?
        var visibleLayerCount: Int
        var viewport: CADViewport?
        var openState: CADOpenStatus
        var failureStage: String

        init(
            fileName: String,
            fileSize: Int = 0,
            dwgVersion: String? = nil,
            libreDwgAvailable: Bool = false,
            dwgreadJsonExitCode: Int? = nil,
            dwgreadDxfExitCode: Int? = nil,
            dwg2dxfExitCode: Int? = nil,
            jsonRawEntityCount: Int = 0,
            dxfRawEntityCount: Int = 0,
            adapterEntityCount: Int = 0,
            databaseEntityCount: Int = 0,
            drawableEntityCount: Int = 0,
            renderCommandCount: Int = 0,
            extents: CADBounds? = nil,
            currentLayout: String? = nil,
            visibleLayerCount: Int = 0,
            viewport: CADViewport? = nil,
            openState: CADOpenStatus = .unsupported,
            failureStage: String = "unknown"
        ) {
            self.fileName = fileName
            self.fileSize = fileSize
            self.dwgVersion = dwgVersion
            self.libreDwgAvailable = libreDwgAvailable
            self.dwgreadJsonExitCode = dwgreadJsonExitCode
            self.dwgreadDxfExitCode = dwgreadDxfExitCode
            self.dwg2dxfExitCode = dwg2dxfExitCode
            self.jsonRawEntityCount = jsonRawEntityCount
            self.dxfRawEntityCount = dxfRawEntityCount
            self.adapterEntityCount = adapterEntityCount
            self.databaseEntityCount = databaseEntityCount
            self.drawableEntityCount = drawableEntityCount
            self.renderCommandCount = renderCommandCount
            self.extents = extents
            self.currentLayout = currentLayout
            self.visibleLayerCount = visibleLayerCount
            self.viewport = viewport
            self.openState = openState
            self.failureStage = failureStage
        }
    }
}
