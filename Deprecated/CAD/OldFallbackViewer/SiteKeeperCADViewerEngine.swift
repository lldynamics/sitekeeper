extension SiteKeeperCADKernel {
    final class SiteKeeperCADViewerEngine: CADViewerEngine {
        private var importEngines: [any CADImportEngine]
        private var renderer: any CADRenderEngine
        private var database: CADDatabase?
        private var currentLayoutID: String?

        init(
            importEngines: [any CADImportEngine] = [
                IntermediateJSONImportEngine(),
                DXFImportEngine(),
                ExternalCADSDKImportEngine(),
                DWGImportEngine(),
                UnsupportedCADImportEngine()
            ],
            renderer: any CADRenderEngine = CADCanvas2DRenderer()
        ) {
            self.importEngines = importEngines
            self.renderer = renderer
        }

        func open(file: CADFile) async throws -> CADOpenResult {
            guard let engine = importEngines.first(where: { $0.canImport(file: file) }) else {
                return .unsupported(CADImportError.unsupportedFormat(file.format).localizedDescription)
            }

            do {
                var importedDatabase = try await engine.importDrawing(file: file)
                currentLayoutID = importedDatabase.layouts.first(where: \.isModelSpace)?.id ?? importedDatabase.layouts.first?.id

                let importOnlyResult = CADOpenResult.evaluated(importedDatabase)
                guard importOnlyResult.status == .rendered else {
                    database = importedDatabase
                    return importOnlyResult
                }

                try await renderer.prepare(database: importedDatabase)
                let preflightFrame = try await preflightRenderFrame(for: importedDatabase)
                importedDatabase.performanceTrace = preflightFrame.performance
                if importedDatabase.textTrace.isEmpty, !preflightFrame.textTraces.isEmpty {
                    importedDatabase.textTrace = preflightFrame.textTraces
                }

                guard preflightFrame.performance.renderCommandCount > 0 else {
                    let warning = CADDrawingDiagnostics.Entry(
                        severity: .warning,
                        code: "CAD_RENDER_COMMANDS_EMPTY",
                        message: "DWG 已解析实体，但首帧未生成可绘制命令。",
                        detail: "drawableEntityCount=\(importedDatabase.drawableEntityCount), renderCommandCount=\(preflightFrame.performance.renderCommandCount)"
                    )
                    importedDatabase.diagnostics.append(warning)
                    importedDatabase.setImportMetadata(
                        geometryParsed: importedDatabase.geometryParsed,
                        isMetadataOnly: true
                    )
                    database = importedDatabase
                    return CADOpenResult(
                        status: .metadataOnly,
                        database: importedDatabase,
                        diagnostics: importedDatabase.diagnostics
                    )
                }

                importedDatabase.setImportMetadata(
                    geometryParsed: importedDatabase.geometryParsed,
                    isMetadataOnly: false
                )
                database = importedDatabase
                return CADOpenResult(
                    status: .rendered,
                    database: importedDatabase,
                    diagnostics: importedDatabase.diagnostics
                )
            } catch let error as CADImportError {
                switch error {
                case .engineNotInstalled, .unsupportedFormat:
                    return .unsupported(error.localizedDescription)
                case .invalidIntermediateJSON, .importerNotReady:
                    return CADOpenResult.failed(
                        CADDrawingDiagnostics(entries: [
                            CADDrawingDiagnostics.Entry(
                                severity: .error,
                                code: "CAD_IMPORT_FAILED",
                                message: error.localizedDescription,
                                detail: file.displayName
                            )
                        ])
                    )
                }
            }
        }

        func getLayers() async throws -> [CADLayer] {
            try requireDatabase().layers
        }

        func setLayerVisible(_ layerId: String, visible: Bool) async throws {
            var openDatabase = try requireDatabase()
            guard let index = openDatabase.layers.firstIndex(where: { $0.id == layerId }) else {
                throw CADViewerEngineError.layerNotFound(layerId)
            }
            openDatabase.layers[index].isVisible = visible
            database = openDatabase
            try await renderer.prepare(database: openDatabase)
        }

        func getLayouts() async throws -> [CADLayout] {
            try requireDatabase().layouts
        }

        func setCurrentLayout(_ layoutId: String) async throws {
            let openDatabase = try requireDatabase()
            guard openDatabase.layouts.contains(where: { $0.id == layoutId }) else {
                throw CADViewerEngineError.layoutNotFound(layoutId)
            }
            currentLayoutID = layoutId
        }

        func render(viewport: CADViewport, options: CADRenderOptions = CADRenderOptions()) async throws -> CADRenderFrame {
            _ = try requireDatabase()
            var renderOptions = options
            if renderOptions.layoutID == nil {
                renderOptions.layoutID = currentLayoutID
            }
            return try await renderer.render(viewport: viewport, options: renderOptions)
        }

        func render(_ database: CADDatabase, options: CADRenderOptions = CADRenderOptions()) -> CADRenderFrame {
            CADCanvas2DRenderer().makeFrame(database: database, options: options)
        }

        func measure(_ input: CADMeasureInput) async throws -> CADMeasureResult {
            let openDatabase = try requireDatabase()
            return CADMeasureTool(units: openDatabase.units).measure(input)
        }

        func searchText(_ keyword: String) async throws -> [CADTextSearchResult] {
            let openDatabase = try requireDatabase()
            return CADTextSearchIndex(database: openDatabase).search(keyword)
        }

        private func requireDatabase() throws -> CADDatabase {
            guard let database else {
                throw CADViewerEngineError.drawingNotOpen
            }
            return database
        }

        private func preflightRenderFrame(for database: CADDatabase) async throws -> CADRenderFrame {
            let layoutID = currentLayoutID
                ?? database.layouts.first(where: \.isModelSpace)?.id
                ?? database.layouts.first?.id
                ?? CADLayout.modelSpace.id
            let bounds = preflightBounds(for: database)
            let viewport = CADViewport(
                id: "open-preflight-\(database.id.uuidString)",
                layoutID: layoutID,
                viewCenter: bounds.center,
                viewHeight: max(bounds.height, 1),
                clipBounds: bounds
            )
            let visibleLayerIDs = Set(database.layers.filter(\.isVisible).map(\.id))
            let options = CADRenderOptions(
                layoutID: layoutID,
                visibleLayerIDs: visibleLayerIDs,
                viewportBounds: bounds,
                deviceScale: 1,
                interactionPhase: .stable,
                renderBudget: .standard,
                enableCache: false
            )
            return try await renderer.render(viewport: viewport, options: options)
        }

        private func preflightBounds(for database: CADDatabase) -> CADBounds {
            let entityBounds = database.entities.reduce(CADBounds.empty) { partial, entity in
                partial.union(CADSpatialIndex.effectiveBounds(for: entity))
            }
            let baseBounds: CADBounds
            if !database.extents.isEmpty {
                baseBounds = database.extents
            } else if !entityBounds.isEmpty {
                baseBounds = entityBounds
            } else {
                baseBounds = CADBounds(minX: -1, minY: -1, maxX: 1, maxY: 1)
            }
            let referenceSize = max(baseBounds.width, baseBounds.height, 1)
            return baseBounds.expanded(by: max(referenceSize * 0.01, 0.5))
        }
    }
}
