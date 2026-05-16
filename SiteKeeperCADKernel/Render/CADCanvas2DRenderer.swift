import Foundation

extension SiteKeeperCADKernel {
    final class CADCanvas2DRenderer: CADRenderEngine {
        private var preparedDatabase: CADDatabase?
        private let textEngine: CADTextEngine
        private let cache: CADRenderCache

        init(textEngine: CADTextEngine = CADTextEngine(), cache: CADRenderCache = CADRenderCache()) {
            self.textEngine = textEngine
            self.cache = cache
        }

        func prepare(database: CADDatabase) async throws {
            preparedDatabase = database
            cache.removeAll()
        }

        func render(viewport: CADViewport, options: CADRenderOptions = CADRenderOptions()) async throws -> CADRenderFrame {
            guard let preparedDatabase else {
                throw CADRenderError.databaseNotPrepared
            }
            try Task.checkCancellation()
            await Task.yield()
            let frame = makeFrame(database: preparedDatabase, viewport: viewport, options: options)
            try Task.checkCancellation()
            await Task.yield()
            return frame
        }

        func makeFrame(
            database: CADDatabase,
            viewport: CADViewport? = nil,
            options: CADRenderOptions = CADRenderOptions()
        ) -> CADRenderFrame {
            let frameStart = Date()
            let requestedViewportBounds = requestedClipBounds(viewport: viewport, options: options)
            let visibleLayers = options.visibleLayerIDs ?? database.visibleLayerIDs
            let viewportTileKey = CADRenderCache.viewportTileKey(
                databaseID: database.id,
                layoutID: options.layoutID ?? viewport?.layoutID,
                viewportID: viewport?.id,
                viewportBounds: requestedViewportBounds,
                visibleLayerIDs: visibleLayers,
                deviceScale: options.deviceScale,
                phase: options.interactionPhase,
                budget: options.renderBudget
            )
            if options.enableCache, let cached = cache.viewportTile(for: viewportTileKey) {
                return cached
            }

            let resolveStart = Date()
            let resolved = CADDrawableEntityResolver().resolve(
                database: database,
                viewport: viewport,
                options: options,
                cache: options.enableCache ? cache : nil
            )
            let resolveMs = milliseconds(since: resolveStart)

            let spatialStart = Date()
            let spatialIndex = CADSpatialIndex(entities: resolved.entities)
            let spatialIndexBuildMs = milliseconds(since: spatialStart)

            let viewportBounds = resolved.clipBounds.isEmpty ? requestedViewportBounds : resolved.clipBounds
            let visibleIDs = Set(
                spatialIndex.query(
                    viewportBounds,
                    layerIDs: visibleLayers,
                    layoutID: resolved.layout.id
                )
            )
            let visibleEntities = resolved.entities.filter { visibleIDs.contains($0.id) }
            var commands: [CADRenderCommand] = []
            var textTraces: [CADTextTrace] = []
            var skippedEntityCount = max(resolved.entities.count - visibleEntities.count, 0)
            var warnings = resolved.diagnostics.entries
                .filter { $0.severity == .warning || $0.severity == .error || $0.severity == .blocker }
                .map { "\($0.code): \($0.message)" }

            if spatialIndex.missingBoundsCount > 0 {
                appendWarning(
                    "CAD_SPATIAL_INDEX_EMPTY_BOUNDS: \(spatialIndex.missingBoundsCount) entities had empty bounds.",
                    to: &warnings
                )
            }

            let renderStart = Date()
            var didHitCommandBudget = false
            var didHitTimeBudget = false

            renderLoop: for (offset, entity) in visibleEntities.enumerated() {
                guard entity.visibility == .visible else {
                    skippedEntityCount += 1
                    continue
                }

                let lodDecision = options.lodPolicy.decision(
                    for: entity,
                    totalEntityCount: resolved.entities.count,
                    zoomScale: options.deviceScale,
                    interactionPhase: options.interactionPhase
                )

                let layer = database.layer(id: entity.layerID) ?? .default
                let style = CADRenderStyle(
                    layerID: entity.layerID,
                    colorARGB: entity.color == 0x00000000 ? layer.colorARGB : entity.color,
                    lineWidth: entity.lineWeight < 0 ? layer.lineWeight : entity.lineWeight
                )

                switch lodDecision {
                case .render:
                    break
                case let .placeholder(reason):
                    let placeholder = CADRenderCommand.unsupportedPlaceholder(
                        entityID: entity.id.uuidString,
                        bounds: CADSpatialIndex.effectiveBounds(for: entity),
                        reason: reason
                    )
                    guard appendCommands([placeholder], to: &commands, budget: options.renderBudget) else {
                        skippedEntityCount += visibleEntities.count - offset
                        didHitCommandBudget = true
                        appendWarning("CAD_RENDER_BUDGET_EXCEEDED: render command budget exhausted.", to: &warnings)
                        break renderLoop
                    }
                    skippedEntityCount += 1
                    appendWarning("\(reason): \(entity.id.uuidString)", to: &warnings)
                    continue
                case let .skip(reason):
                    skippedEntityCount += 1
                    appendWarning("\(reason): \(entity.id.uuidString)", to: &warnings)
                    continue
                }

                let entityCommands = makeCommands(
                    for: entity,
                    style: style,
                    database: database,
                    textTraces: &textTraces
                )
                guard appendCommands(entityCommands, to: &commands, budget: options.renderBudget) else {
                    skippedEntityCount += visibleEntities.count - offset
                    didHitCommandBudget = true
                    appendWarning("CAD_RENDER_BUDGET_EXCEEDED: render command budget exhausted.", to: &warnings)
                    break renderLoop
                }

                if milliseconds(since: renderStart) >= options.renderBudget.maxFrameTimeMilliseconds {
                    skippedEntityCount += max(visibleEntities.count - offset - 1, 0)
                    didHitTimeBudget = true
                    appendWarning("CAD_RENDER_TIME_BUDGET_EXCEEDED: frame time budget exhausted.", to: &warnings)
                    break renderLoop
                }
            }

            if didHitCommandBudget || didHitTimeBudget {
                appendWarning("CAD_RENDER_DEFERRED_ENTITIES: remaining entities should be rendered in a later frame.", to: &warnings)
            }

            let renderMs = milliseconds(since: renderStart)
            let firstFrameMs = milliseconds(since: frameStart)
            let drawCallCount = commands.reduce(0) { $0 + $1.drawCallCost }
            let performance = CADPerformanceTrace(
                fileSizeBytes: fileSizeBytes(for: database.sourceFile),
                entityCount: resolved.entities.count,
                visibleEntityCount: visibleEntities.count,
                renderCommandCount: commands.count,
                drawCallCount: drawCallCount,
                tileCount: viewportBounds.isEmpty ? 0 : 1,
                spatialIndexBuildMs: spatialIndexBuildMs,
                resolveMs: resolveMs,
                renderMs: renderMs,
                firstFrameMs: firstFrameMs,
                frameTimeMilliseconds: firstFrameMs,
                peakMemoryMB: estimatePeakMemoryMB(entityCount: resolved.entities.count, commandCount: commands.count),
                skippedEntityCount: skippedEntityCount,
                warnings: warnings
            )

            let frameBounds = viewportBounds.isEmpty
                ? visibleEntities.reduce(CADBounds.empty) { $0.union(CADSpatialIndex.effectiveBounds(for: $1)) }
                : viewportBounds

            let frame = CADRenderFrame(
                databaseID: database.id,
                bounds: frameBounds,
                commands: commands,
                textTraces: textTraces,
                performance: performance
            )
            if options.enableCache {
                cache.storeViewportTile(frame, for: viewportTileKey)
            }
            return frame
        }

        private func makeCommands(
            for entity: CADEntity,
            style: CADRenderStyle,
            database: CADDatabase,
            textTraces: inout [CADTextTrace]
        ) -> [CADRenderCommand] {
            switch entity.kind {
            case .text, .mtext, .attrib:
                guard let text = entity.text else {
                    return unsupportedPlaceholder(for: entity, reason: "Text entity has no text payload.")
                }
                let resolvedText = makeResolvedTextRun(for: entity, text: text, database: database)
                textTraces.append(
                    resolvedText.makeTrace(entityId: entity.id.uuidString, entityType: entity.type)
                )
                return [.text(resolvedText, style: style)]
            case .hatch:
                guard let path = entity.path else {
                    return unsupportedPlaceholder(for: entity, reason: "Hatch entity has no boundary path.")
                }
                return [.hatch(path, style: style)]
            case .image:
                return [
                    .imagePlaceholder(
                        entityID: entity.id.uuidString,
                        bounds: CADSpatialIndex.effectiveBounds(for: entity),
                        reason: entity.unsupportedReason ?? "Image rendering is not implemented."
                    )
                ]
            case .circle:
                return circleCommand(for: entity, style: style)
            case .arc:
                return arcCommand(for: entity, style: style)
            case .ellipse:
                return ellipseCommand(for: entity, style: style)
            case .line:
                return lineCommands(for: entity, style: style)
            case .polyline, .lwPolyline, .spline, .dimension:
                return polylineCommands(for: entity, style: style)
            case .table, .xref, .proxy, .unsupported, .insert, .blockReference:
                if let path = entity.path {
                    return polylineCommands(for: entity, path: path, style: style)
                }
                return unsupportedPlaceholder(
                    for: entity,
                    reason: entity.unsupportedReason
                        ?? entity.diagnostics.entries.first?.message
                        ?? "Entity has no renderable geometry."
                )
            }
        }

        private func makeResolvedTextRun(
            for entity: CADEntity,
            text: CADTextRun,
            database: CADDatabase
        ) -> CADTextRun {
            var warnings = text.warnings
            warnings.append(contentsOf: entity.diagnostics.entries.map { "\($0.code): \($0.message)" })

            let style: CADTextStyle
            if let databaseStyle = database.textStyle(id: text.textStyleId) {
                style = databaseStyle
            } else {
                warnings.append("CAD_TEXT_STYLE_MISSING:\(text.textStyleId)")
                style = CADTextStyle(
                    id: text.textStyleId,
                    name: text.styleName.isEmpty ? text.textStyleId : text.styleName,
                    fixedHeight: text.height
                )
            }

            let cacheKey = CADRenderCache.textLayoutKey(entity: entity, style: style)
            if let cached = cache.textLayout(for: cacheKey) {
                return cached
            }

            let run = textEngine.makeTextRun(
                rawText: text.rawText,
                insertionPoint: text.insertionPoint,
                style: style,
                height: text.height,
                rotationRadians: text.rotationRadians,
                warnings: warnings
            )
            cache.storeTextLayout(run, for: cacheKey)
            return run
        }

        private func lineCommands(for entity: CADEntity, style: CADRenderStyle) -> [CADRenderCommand] {
            guard let path = entity.path else {
                return unsupportedPlaceholder(for: entity, reason: "Line entity has no path.")
            }
            let points = flattenedPoints(for: path)
            guard points.count >= 2 else {
                return unsupportedPlaceholder(for: entity, reason: "Line entity has fewer than two points.")
            }
            return [
                .moveTo(points[0], style: style),
                .lineTo(points[1], style: style)
            ]
        }

        private func polylineCommands(for entity: CADEntity, style: CADRenderStyle) -> [CADRenderCommand] {
            guard let path = entity.path else {
                return unsupportedPlaceholder(for: entity, reason: "Polyline entity has no path.")
            }
            return polylineCommands(for: entity, path: path, style: style)
        }

        private func polylineCommands(for entity: CADEntity, path: CADPath, style: CADRenderStyle) -> [CADRenderCommand] {
            let points = flattenedPoints(for: path)
            guard !points.isEmpty else {
                return unsupportedPlaceholder(for: entity, reason: "Path entity has no drawable points.")
            }
            return [
                .polyline(points, closed: path.elements.contains { if case .close = $0 { return true }; return false }, style: style)
            ]
        }

        private func circleCommand(for entity: CADEntity, style: CADRenderStyle) -> [CADRenderCommand] {
            let bounds = CADSpatialIndex.effectiveBounds(for: entity)
            guard !bounds.isEmpty else {
                return unsupportedPlaceholder(for: entity, reason: "Circle entity has no bounds.")
            }
            return [
                .circle(
                    center: center(of: bounds),
                    radius: min(bounds.width, bounds.height) / 2,
                    style: style
                )
            ]
        }

        private func arcCommand(for entity: CADEntity, style: CADRenderStyle) -> [CADRenderCommand] {
            let bounds = CADSpatialIndex.effectiveBounds(for: entity)
            guard !bounds.isEmpty else {
                return unsupportedPlaceholder(for: entity, reason: "Arc entity has no bounds.")
            }
            return [
                .arc(
                    center: center(of: bounds),
                    radius: min(bounds.width, bounds.height) / 2,
                    startAngle: 0,
                    endAngle: .pi,
                    style: style
                )
            ]
        }

        private func ellipseCommand(for entity: CADEntity, style: CADRenderStyle) -> [CADRenderCommand] {
            let bounds = CADSpatialIndex.effectiveBounds(for: entity)
            guard !bounds.isEmpty else {
                return unsupportedPlaceholder(for: entity, reason: "Ellipse entity has no bounds.")
            }
            return [
                .ellipse(
                    center: center(of: bounds),
                    radiusX: bounds.width / 2,
                    radiusY: bounds.height / 2,
                    rotationRadians: 0,
                    style: style
                )
            ]
        }

        private func flattenedPoints(for path: CADPath) -> [CADPoint] {
            if path.elements.contains(where: { if case .curve = $0 { return true }; return false }) {
                return CADSplineTessellator().flatten(path: path).points
            }
            return path.points
        }

        private func unsupportedPlaceholder(for entity: CADEntity, reason: String) -> [CADRenderCommand] {
            [
                .unsupportedPlaceholder(
                    entityID: entity.id.uuidString,
                    bounds: CADSpatialIndex.effectiveBounds(for: entity),
                    reason: reason
                )
            ]
        }

        private func appendCommands(
            _ newCommands: [CADRenderCommand],
            to commands: inout [CADRenderCommand],
            budget: CADRenderBudget
        ) -> Bool {
            guard commands.count + newCommands.count <= budget.maxRenderCommands else {
                return false
            }
            commands.append(contentsOf: newCommands)
            return true
        }

        private func appendWarning(_ warning: String, to warnings: inout [String]) {
            guard !warnings.contains(warning) else { return }
            warnings.append(warning)
        }

        private func requestedClipBounds(viewport: CADViewport?, options: CADRenderOptions) -> CADBounds {
            if let viewport, !viewport.clipBounds.isEmpty {
                return viewport.clipBounds
            }
            return options.viewportBounds
        }

        private func center(of bounds: CADBounds) -> CADPoint {
            CADPoint(x: (bounds.minX + bounds.maxX) / 2, y: (bounds.minY + bounds.maxY) / 2)
        }

        private func milliseconds(since start: Date) -> Double {
            Date().timeIntervalSince(start) * 1_000
        }

        private func fileSizeBytes(for file: CADFile) -> Int {
            if let byteCount = file.byteCount {
                return byteCount
            }
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.url.path),
                  let size = attributes[.size] as? NSNumber else {
                return 0
            }
            return size.intValue
        }

        private func estimatePeakMemoryMB(entityCount: Int, commandCount: Int) -> Double {
            Double(entityCount * 160 + commandCount * 96) / 1_048_576
        }
    }
}
