extension SiteKeeperCADKernel {
    struct CADDrawableEntitySet: Equatable, Codable {
        var layout: CADLayout
        var entities: [CADEntity]
        var clipBounds: CADBounds
        var diagnostics: CADDrawingDiagnostics
    }

    struct CADDrawableEntityResolver {
        var layoutResolver = CADLayoutResolver()
        var blockResolver = CADBlockResolver()
        var dimensionExploder = CADDimensionExploder()
        var hatchTessellator = CADHatchTessellator()
        var splineTessellator = CADSplineTessellator()
        var proxyHandler = CADProxyObjectHandler()

        func resolve(
            database: CADDatabase,
            viewport: CADViewport?,
            options: CADRenderOptions,
            cache: CADRenderCache? = nil
        ) -> CADDrawableEntitySet {
            let layoutKey = CADRenderCache.layoutKey(
                databaseID: database.id,
                layoutID: options.layoutID ?? viewport?.layoutID,
                viewportID: viewport?.id,
                viewportBounds: renderClipBounds(viewport: viewport, options: options)
            )
            let layoutResolution: CADLayoutResolution
            if let cached = cache?.layoutResolution(for: layoutKey) {
                layoutResolution = cached
            } else {
                layoutResolution = layoutResolver.resolve(
                    database: database,
                    viewport: viewport,
                    options: options
                )
                cache?.storeLayoutResolution(layoutResolution, for: layoutKey)
            }

            let blockKey = CADRenderCache.blockResolutionKey(databaseID: database.id, layoutKey: layoutKey)
            let blockResolved: [CADEntity]
            if let cached = cache?.blockResolution(for: blockKey) {
                blockResolved = cached
            } else {
                blockResolved = blockResolver.resolve(entities: layoutResolution.entities, in: database)
                cache?.storeBlockResolution(blockResolved, for: blockKey)
            }
            let drawable = blockResolved.flatMap { entity in
                resolveComplexEntity(entity, options: options, sourceEntityCount: blockResolved.count)
            }

            let diagnostics = drawable.reduce(layoutResolution.diagnostics) {
                $0.merging($1.diagnostics)
            }

            return CADDrawableEntitySet(
                layout: layoutResolution.layout,
                entities: drawable,
                clipBounds: layoutResolution.clipBounds,
                diagnostics: diagnostics
            )
        }

        private func renderClipBounds(viewport: CADViewport?, options: CADRenderOptions) -> CADBounds {
            if let viewport, !viewport.clipBounds.isEmpty {
                return viewport.clipBounds
            }
            return options.viewportBounds
        }

        private func resolveComplexEntity(
            _ entity: CADEntity,
            options: CADRenderOptions,
            sourceEntityCount: Int
        ) -> [CADEntity] {
            switch entity.kind {
            case .dimension:
                return dimensionExploder.explode(entity)
            case .hatch:
                return hatchTessellator.resolve(
                    entity,
                    options: options,
                    sourceEntityCount: sourceEntityCount
                )
            case .spline:
                return splineTessellator.resolve(entity)
            case .proxy:
                return [proxyHandler.handle(entity)]
            default:
                return [entity]
            }
        }
    }
}
