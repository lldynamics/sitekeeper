extension SiteKeeperCADKernel {
    struct CADPerformanceTrace: Equatable, Codable {
        var fileSizeBytes: Int
        var entityCount: Int
        var visibleEntityCount: Int
        var renderCommandCount: Int
        var drawCallCount: Int
        var tileCount: Int
        var spatialIndexBuildMs: Double
        var resolveMs: Double
        var renderMs: Double
        var firstFrameMs: Double
        var frameTimeMilliseconds: Double
        var peakMemoryMB: Double
        var skippedEntityCount: Int
        var warnings: [String]

        init(
            fileSizeBytes: Int = 0,
            entityCount: Int = 0,
            visibleEntityCount: Int = 0,
            renderCommandCount: Int? = nil,
            commandCount: Int = 0,
            drawCallCount: Int? = nil,
            tileCount: Int = 0,
            spatialIndexBuildMs: Double = 0,
            resolveMs: Double = 0,
            renderMs: Double = 0,
            firstFrameMs: Double = 0,
            frameTimeMilliseconds: Double? = nil,
            peakMemoryMB: Double = 0,
            skippedEntityCount: Int = 0,
            warnings: [String] = [],
            elapsedMilliseconds: Double = 0
        ) {
            let resolvedCommandCount = renderCommandCount ?? commandCount
            self.fileSizeBytes = fileSizeBytes
            self.entityCount = entityCount
            self.visibleEntityCount = visibleEntityCount
            self.renderCommandCount = resolvedCommandCount
            self.drawCallCount = drawCallCount ?? resolvedCommandCount
            self.tileCount = tileCount
            self.spatialIndexBuildMs = spatialIndexBuildMs
            self.resolveMs = resolveMs
            self.renderMs = renderMs
            self.firstFrameMs = firstFrameMs
            self.frameTimeMilliseconds = frameTimeMilliseconds ?? (firstFrameMs > 0 ? firstFrameMs : elapsedMilliseconds)
            self.peakMemoryMB = peakMemoryMB
            self.skippedEntityCount = skippedEntityCount
            self.warnings = warnings
        }

        var commandCount: Int {
            get { renderCommandCount }
            set { renderCommandCount = newValue }
        }

        var elapsedMilliseconds: Double {
            get { frameTimeMilliseconds }
            set { frameTimeMilliseconds = newValue }
        }
    }
}
