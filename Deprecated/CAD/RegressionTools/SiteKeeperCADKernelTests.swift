import Foundation
import Testing
@testable import sitekeeper

struct SiteKeeperCADKernelTests {
    @Test func unsupportedImportEngineReturnsInstalledError() async {
        let engine = SiteKeeperCADKernel.UnsupportedCADImportEngine()
        let result = await engine.importDatabase(
            SiteKeeperCADKernel.CADImportRequest(
                file: SiteKeeperCADKernel.CADFile(url: URL(fileURLWithPath: "/tmp/test.dwg"))
            )
        )

        #expect(result.status == .unsupported)
        #expect(result.diagnostics.entries.first?.message == "CAD engine is not installed")
    }

    @Test func rendererConsumesCADDatabaseAndProducesRenderCommands() {
        let file = SiteKeeperCADKernel.CADFile(url: URL(fileURLWithPath: "/tmp/test.json"), format: .intermediateJSON)
        var database = SiteKeeperCADKernel.CADDatabase(file: file)
        let path = SiteKeeperCADKernel.CADPath(elements: [
            .move(to: SiteKeeperCADKernel.CADPoint(x: 0, y: 0)),
            .line(to: SiteKeeperCADKernel.CADPoint(x: 10, y: 0))
        ])
        database.append(
            SiteKeeperCADKernel.CADEntity(
                kind: .line,
                path: path,
                bounds: path.bounds
            )
        )

        let frame = SiteKeeperCADKernel.CADCanvas2DRenderer().makeFrame(database: database)

        #expect(frame.databaseID == database.id)
        #expect(frame.commands.count == 2)
        #expect(frame.performance.entityCount == 1)
        #expect(frame.performance.visibleEntityCount == 1)
        #expect(frame.performance.drawCallCount == 1)
    }

    @Test func intermediateJSONImporterBuildsCADDatabase() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let payload = """
        {
          "layers": [{ "id": "0", "name": "0" }],
          "xrefs": [{ "id": "xref-1", "name": "floor-ref", "path": "floor.dwg", "isResolved": false, "diagnostics": { "entries": [] } }],
          "blocks": [{ "id": "B1", "name": "DOOR", "basePoint": { "x": 0, "y": 0 }, "entities": [] }],
          "entities": [{ "handle": "A1", "layerID": "0", "start": { "x": 0, "y": 0 }, "end": { "x": 5, "y": 0 } }]
        }
        """
        try payload.data(using: .utf8)?.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await SiteKeeperCADKernel.IntermediateJSONImportEngine().importDatabase(
            SiteKeeperCADKernel.CADImportRequest(file: SiteKeeperCADKernel.CADFile(url: url))
        )

        #expect(result.status == .rendered)
        #expect(result.database?.entities.count == 1)
        #expect(result.database?.blocks.first?.name == "DOOR")
        #expect(result.database?.xrefs.first?.name == "floor-ref")
    }

    @Test func intermediateJSONFixtureImportsRealDatabaseAndProducesRenderableFrame() async throws {
        let fixtureURL = repoRootURL()
            .appendingPathComponent("samples/cad/intermediate/simple_floor_plan.json")
        let file = SiteKeeperCADKernel.CADFile(url: fixtureURL, format: .intermediateJSON)
        let importer = SiteKeeperCADKernel.IntermediateJSONImportEngine()
        let database = try await importer.importDrawing(file: file)

        #expect(database.drawingId == UUID(uuidString: "8D0D0F9E-3F83-4A59-A0F3-1E6D6D3E9C41"))
        #expect(database.entities.count == 11)
        #expect(database.blocks.count == 1)
        #expect(database.entities.contains { $0.kind == .line })
        #expect(database.entities.contains { $0.kind == .lwPolyline })
        #expect(database.entities.contains { $0.kind == .circle })
        #expect(database.entities.contains { $0.kind == .arc })
        #expect(database.entities.contains { $0.kind == .text })
        #expect(database.entities.contains { $0.kind == .mtext })
        #expect(database.entities.contains { $0.kind == .insert })
        #expect(database.entities.contains { $0.kind == .attrib })
        #expect(database.entities.contains { $0.kind == .dimension })
        #expect(database.entities.contains { $0.kind == .hatch })
        #expect(database.entities.allSatisfy { !$0.bounds.isEmpty })

        let wall = try #require(database.entities.first(where: { $0.sourceHandle == "wall-001" }))
        #expect(wall.bounds == SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 8000, maxY: 0))

        let spatialIndex = SiteKeeperCADKernel.CADSpatialIndex(database: database)
        #expect(spatialIndex.entityCount == 11)
        #expect(spatialIndex.missingBoundsCount == 0)
        let viewportIDs = spatialIndex.query(
            SiteKeeperCADKernel.CADBounds(minX: 1100, minY: 1100, maxX: 1900, maxY: 1900),
            layerIDs: ["A-WALL"],
            layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id
        )
        #expect(viewportIDs.count == 2)
        #expect(
            database.entities.contains {
                viewportIDs.contains($0.id) && $0.kind == .circle
            }
        )

        let resolved = SiteKeeperCADKernel.CADBlockResolver().resolve(entities: database.entities, in: database)
        #expect(resolved.count == 13)
        let insertedDoorLeaf = try #require(resolved.first(where: { $0.sourceHandle == "blk-line-001" }))
        #expect(insertedDoorLeaf.path?.points.first?.isClose(to: SiteKeeperCADKernel.CADPoint(x: 1000, y: 0)) == true)
        #expect(insertedDoorLeaf.path?.points.last?.isClose(to: SiteKeeperCADKernel.CADPoint(x: 1900, y: 0)) == true)

        let viewer = SiteKeeperCADKernel.SiteKeeperCADViewerEngine(
            importEngines: [SiteKeeperCADKernel.IntermediateJSONImportEngine()],
            renderer: SiteKeeperCADKernel.CADCanvas2DRenderer()
        )
        let openResult = try await viewer.open(file: file)
        #expect(openResult.status == .rendered)

        let viewportBounds = database.extents.expanded(by: 100)
        let viewport = SiteKeeperCADKernel.CADViewport(
            id: "fixture-model",
            layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id,
            viewCenter: viewportBounds.center,
            viewHeight: max(viewportBounds.height, 1),
            clipBounds: viewportBounds
        )
        let options = SiteKeeperCADKernel.CADRenderOptions(
            layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id,
            viewportBounds: viewportBounds
        )
        let frame = try await viewer.render(viewport: viewport, options: options)
        #expect(!frame.commands.isEmpty)
        #expect(frame.performance.renderCommandCount > 0)
        #expect(frame.performance.visibleEntityCount > 0)

        let textRuns = frame.commands.compactMap { command -> SiteKeeperCADKernel.CADTextRun? in
            if case let .text(run, _) = command {
                return run
            }
            return nil
        }
        let unicodeRun = try #require(textRuns.first(where: { $0.rawText == "\\U+4E2D\\U+6587" }))
        #expect(unicodeRun.displayText == "中文")
        let diameterRun = try #require(textRuns.first(where: { $0.rawText.contains("%%c20") }))
        #expect(diameterRun.displayText.contains("∅20"))

        let clipped = try await viewer.render(
            viewport: SiteKeeperCADKernel.CADViewport(
                id: "fixture-clip",
                layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id,
                viewCenter: SiteKeeperCADKernel.CADPoint(x: 1500, y: 1500),
                viewHeight: 1200,
                clipBounds: SiteKeeperCADKernel.CADBounds(minX: 1000, minY: 1000, maxX: 2000, maxY: 2000)
            ),
            options: SiteKeeperCADKernel.CADRenderOptions(
                layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id,
                viewportBounds: SiteKeeperCADKernel.CADBounds(minX: 1000, minY: 1000, maxX: 2000, maxY: 2000)
            )
        )
        #expect(clipped.performance.visibleEntityCount < frame.performance.visibleEntityCount)
        #expect(!clipped.commands.isEmpty)

        try await viewer.setLayerVisible("A-WALL", visible: false)
        let hiddenFrame = try await viewer.render(viewport: viewport, options: options)
        #expect(hiddenFrame.commands.allSatisfy { renderCommandLayerID($0) != "A-WALL" })

        let encodedFrame = try JSONEncoder().encode(frame)
        #expect(!encodedFrame.isEmpty)
    }

    @Test func dxfImporterBuildsSimpleFixtureDatabase() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("dxf")
        let payload = """
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        5
        L1
        8
        A-WALL
        10
        0
        20
        0
        11
        100
        21
        0
        0
        TEXT
        5
        T1
        8
        A-TEXT
        10
        10
        20
        20
        1
        一层配电箱
        0
        ENDSEC
        0
        EOF
        """
        try payload.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await SiteKeeperCADKernel.DXFImportEngine().importDatabase(
            SiteKeeperCADKernel.CADImportRequest(file: SiteKeeperCADKernel.CADFile(url: url))
        )

        #expect(result.status == .rendered)
        #expect(result.database?.entities.count == 2)
        #expect(result.database?.layers.map(\.id).sorted() == ["A-TEXT", "A-WALL"])
        #expect(result.database?.entities.first(where: { $0.kind == .text })?.rawText == "一层配电箱")
    }

    @Test func dxfImportEngineParsesTablesBlocksAndCommon2DEntities() async throws {
        let fixtureURL = repoRootURL()
            .appendingPathComponent("samples/cad/dxf/simple_floor_plan.dxf")
        let file = SiteKeeperCADKernel.CADFile(url: fixtureURL, format: .dxf)

        let result = await SiteKeeperCADKernel.DXFImportEngine().importDatabase(
            SiteKeeperCADKernel.CADImportRequest(file: file)
        )
        let database = try #require(result.database)

        #expect(result.status == .rendered)
        #expect(database.units.name == "millimeter")
        #expect(database.units.metersPerDrawingUnit == 0.001)
        #expect(database.blocks.contains { $0.name == "DOOR" })
        #expect(database.layers.contains { $0.id == "A-WALL" })
        #expect(database.layers.contains { $0.id == "A-DOOR" })
        #expect(database.layers.contains { $0.id == "A-TEXT" })
        #expect(database.layers.contains { $0.id == "A-HATCH" })
        #expect(database.layers.first(where: { $0.id == "A-HIDDEN" })?.isVisible == false)
        #expect(database.textStyles.contains { $0.id == "Standard" && $0.fontName == "SimSun.ttf" })

        #expect(database.entities.contains { $0.kind == .line })
        #expect(database.entities.contains { $0.kind == .lwPolyline })
        #expect(database.entities.contains { $0.kind == .polyline })
        #expect(database.entities.contains { $0.kind == .circle })
        #expect(database.entities.contains { $0.kind == .arc })
        #expect(database.entities.contains { $0.kind == .ellipse })
        #expect(database.entities.contains { $0.kind == .text })
        #expect(database.entities.contains { $0.kind == .mtext })
        #expect(database.entities.contains { $0.kind == .attrib })
        #expect(database.entities.contains { $0.kind == .dimension })
        #expect(database.entities.contains { $0.kind == .hatch })
        #expect(database.entities.contains { $0.kind == .insert })
        #expect(database.entities.contains { $0.kind == .image })
        #expect(database.entities.contains { $0.kind == .unsupported })
        #expect(database.entities.allSatisfy { !$0.bounds.isEmpty })

        let unsupported = database.entities.first(where: { $0.kind == .unsupported })
        #expect(unsupported?.unsupportedReason?.contains("Unsupported DXF entity") == true)
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_DXF_SPLINE_SIMPLIFIED" })
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_DXF_DIMENSION_SIMPLIFIED" })
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_DXF_HATCH_SIMPLIFIED" })
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_DXF_IMAGE_PLACEHOLDER" })
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_DXF_ENTITY_UNSUPPORTED" })

        let resolved = SiteKeeperCADKernel.CADBlockResolver().resolve(entities: database.entities, in: database)
        let doorLeaf = try #require(resolved.first(where: { $0.sourceHandle == "B001" }))
        #expect(doorLeaf.path?.points.first?.isClose(to: SiteKeeperCADKernel.CADPoint(x: 1800, y: 0)) == true)
        #expect(doorLeaf.path?.points.last?.isClose(to: SiteKeeperCADKernel.CADPoint(x: 2700, y: 0)) == true)
    }

    @Test func dxfRegressionSampleSupportsRenderLayerSearchAndMeasure() async throws {
        let fixtureURL = repoRootURL()
            .appendingPathComponent("samples/cad/dxf/simple_floor_plan.dxf")
        let viewer = SiteKeeperCADKernel.SiteKeeperCADViewerEngine(
            importEngines: [SiteKeeperCADKernel.DXFImportEngine()],
            renderer: SiteKeeperCADKernel.CADCanvas2DRenderer()
        )

        let openResult = try await viewer.open(
            file: SiteKeeperCADKernel.CADFile(url: fixtureURL, format: .dxf)
        )
        let database = try #require(openResult.database)
        let viewportBounds = database.extents.expanded(by: 100)
        let viewport = SiteKeeperCADKernel.CADViewport(
            id: "dxf-regression",
            layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id,
            viewCenter: viewportBounds.center,
            viewHeight: max(viewportBounds.height, 1),
            clipBounds: viewportBounds
        )
        let options = SiteKeeperCADKernel.CADRenderOptions(
            layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id,
            viewportBounds: viewportBounds
        )

        let frame = try await viewer.render(viewport: viewport, options: options)
        #expect(!frame.commands.isEmpty)
        #expect(frame.commands.contains { command in
            if case .circle = command { return true }
            return false
        })
        #expect(frame.commands.contains { command in
            if case .arc = command { return true }
            return false
        })
        #expect(frame.commands.contains { command in
            if case .text = command { return true }
            return false
        })
        #expect(frame.commands.contains { command in
            if case .unsupportedPlaceholder = command { return true }
            return false
        })
        #expect(frame.commands.allSatisfy { renderCommandLayerID($0) != "A-HIDDEN" })

        let searchResults = try await viewer.searchText("中文")
        #expect(searchResults.count >= 1)
        let diameterSearch = try await viewer.searchText("∅20")
        #expect(diameterSearch.count >= 1)

        let measurement = try await viewer.measure(
            SiteKeeperCADKernel.CADMeasureInput(
                points: [
                    SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
                    SiteKeeperCADKernel.CADPoint(x: 3000, y: 4000)
                ],
                unit: "m"
            )
        )
        #expect(measurement.value == 5)

        try await viewer.setLayerVisible("A-WALL", visible: false)
        let hiddenFrame = try await viewer.render(viewport: viewport, options: options)
        #expect(hiddenFrame.commands.allSatisfy { renderCommandLayerID($0) != "A-WALL" })
    }

    @Test func dwgDiagnosticImporterBuildsCADDatabaseWithoutDrawableGeometry() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("dwg")
        try Data("AC1032 mock dwg payload".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await SiteKeeperCADKernel.DWGImportEngine().importDatabase(
            SiteKeeperCADKernel.CADImportRequest(file: SiteKeeperCADKernel.CADFile(url: url))
        )
        let database = try #require(result.database)

        #expect(result.status == .diagnosticOnly)
        #expect(database.sourceFile.format == .dwg)
        #expect(database.geometryParsed == false)
        #expect(database.drawableEntityCount == 0)
        #expect(database.placeholderEntityCount == 0)
        #expect(database.isDiagnosticOnly)
        #expect(database.importSource == "sitekeeper.dwg.diagnostic")
        #expect(database.entities.count == 0)
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_DWG_IMPORT_ENGINE_CONNECTED" })
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_DWG_VERSION_DETECTED" })
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_DWG_DIAGNOSTIC_ONLY" })

        let frame = SiteKeeperCADKernel.CADCanvas2DRenderer().makeFrame(database: database)
        #expect(frame.commands.isEmpty)
    }

    @Test func dwgImportEngineUsesGeometryAdapterBeforeDiagnosticPlaceholder() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("dwg")
        try Data("AC1032 mock dwg payload".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await SiteKeeperCADKernel.DWGImportEngine(
            geometryAdapter: MockDWGGeometryAdapter()
        ).importDatabase(
            SiteKeeperCADKernel.CADImportRequest(file: SiteKeeperCADKernel.CADFile(url: url))
        )
        let database = try #require(result.database)

        #expect(result.status == .rendered)
        #expect(database.sourceFile.format == .dwg)
        #expect(database.geometryParsed)
        #expect(database.drawableEntityCount > 0)
        #expect(database.hasRenderableContent)
        #expect(database.layers.map(\.id) == ["S-WALL", "A-TEXT"])
        #expect(database.layouts.map(\.id) == ["model"])
        #expect(database.blocks.first?.name == "WINDOW")
        #expect(database.xrefs.first?.name == "xref-structure")
        #expect(database.entities.count == 2)
        #expect(database.entities.contains { $0.kind == .line && $0.sourceHandle == "DWG-L1" })
        #expect(database.entities.contains { $0.displayText == "地下室外墙" && $0.textStyleId == "china-standard" })
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_DWG_GEOMETRY_ADAPTER_USED" })
        #expect(!database.diagnostics.entries.contains { $0.code == "CAD_DWG_DIAGNOSTIC_ONLY" })

        let frame = SiteKeeperCADKernel.CADCanvas2DRenderer().makeFrame(database: database)
        #expect(frame.commands.contains { command in
            if case .lineTo = command { return true }
            return false
        })
        #expect(frame.textTraces.first?.displayText == "地下室外墙")
    }

    @Test func dwgImportEngineUsesRegisteredSidecarJSONAdapter() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let dwgURL = folder.appendingPathComponent("registered-sidecar.dwg")
        let sidecarURL = folder.appendingPathComponent("drawing.sitekeeper-cad.json")
        try Data("AC1032 mock dwg payload".utf8).write(to: dwgURL)
        let sidecarPayload = """
        {
          "units": { "name": "millimeter", "metersPerDrawingUnit": 0.001 },
          "extents": { "minX": 0, "minY": 0, "maxX": 120, "maxY": 60 },
          "layers": [
            { "id": "A-WALL", "name": "墙体" },
            { "id": "A-TEXT", "name": "文字" }
          ],
          "layouts": [{ "id": "model", "name": "Model", "isModelSpace": true }],
          "entities": [
            {
              "handle": "SIDE-L1",
              "type": "line",
              "layerID": "A-WALL",
              "start": { "x": 0, "y": 0 },
              "end": { "x": 100, "y": 0 }
            },
            {
              "handle": "SIDE-T1",
              "type": "text",
              "layerID": "A-TEXT",
              "insertionPoint": { "x": 12, "y": 18 },
              "rawText": "结构平面图",
              "displayText": "结构平面图",
              "textStyleId": "standard"
            }
          ],
          "xrefs": [{ "id": "xref-sidecar", "name": "建筑底图", "path": "arch.dwg", "isResolved": false, "diagnostics": { "entries": [] } }]
        }
        """
        try sidecarPayload.write(to: sidecarURL, atomically: true, encoding: .utf8)

        SiteKeeperCADKernel.CADDWGGeometryAdapterRegistry.reset()
        SiteKeeperCADKernel.CADDWGGeometryAdapterRegistry.register(
            SiteKeeperCADKernel.DWGSidecarJSONGeometryAdapter()
        )
        defer { SiteKeeperCADKernel.CADDWGGeometryAdapterRegistry.reset() }

        let result = await SiteKeeperCADKernel.DWGImportEngine().importDatabase(
            SiteKeeperCADKernel.CADImportRequest(file: SiteKeeperCADKernel.CADFile(url: dwgURL))
        )
        let database = try #require(result.database)
        let frame = SiteKeeperCADKernel.CADCanvas2DRenderer().makeFrame(database: database)

        #expect(SiteKeeperCADKernel.CADDWGGeometryAdapterRegistry.registeredAdapterIDs() == ["sitekeeper.dwg.libredwg"])
        #expect(result.status == .rendered)
        #expect(database.sourceFile.url == dwgURL)
        #expect(database.importSource == "sitekeeper.dwg.libredwg")
        #expect(database.geometryParsed)
        #expect(database.drawableEntityCount > 0)
        #expect(database.hasRenderableContent)
        #expect(database.entities.count == 2)
        #expect(database.xrefs.first?.name == "建筑底图")
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_DWG_LIBREDWG_WORKER_JSON_USED" })
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_DWG_GEOMETRY_ADAPTER_USED" })
        #expect(!database.diagnostics.entries.contains { $0.code == "CAD_DWG_DIAGNOSTIC_ONLY" })
        #expect(frame.textTraces.first?.displayText == "结构平面图")
    }

    @Test func dwgImportEngineFindsPerDrawingLibreDWGSidecar() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let dwgURL = folder.appendingPathComponent("per-drawing-sidecar.dwg")
        let sidecarURL = dwgURL.appendingPathExtension("sitekeeper-cad.json")
        try Data("AC1032 mock dwg payload".utf8).write(to: dwgURL)
        let sidecarPayload = """
        {
          "schema": "sitekeeper-cad-worker-v1",
          "importSource": "sitekeeper.dwg.libredwg",
          "geometryParsed": true,
          "isDiagnosticOnly": false,
          "units": { "name": "unitless" },
          "extents": { "minX": 0, "minY": 0, "maxX": 10, "maxY": 0 },
          "layers": [{ "id": "0", "name": "0" }],
          "layouts": [{ "id": "model", "name": "Model", "isModelSpace": true }],
          "entities": [
            {
              "handle": "PER-DWG-L1",
              "type": "LINE",
              "layerID": "0",
              "start": { "x": 0, "y": 0 },
              "end": { "x": 10, "y": 0 },
              "bounds": { "minX": 0, "minY": 0, "maxX": 10, "maxY": 0 }
            }
          ]
        }
        """
        try sidecarPayload.write(to: sidecarURL, atomically: true, encoding: .utf8)

        let result = await SiteKeeperCADKernel.DWGImportEngine().importDatabase(
            SiteKeeperCADKernel.CADImportRequest(file: SiteKeeperCADKernel.CADFile(url: dwgURL))
        )
        let database = try #require(result.database)
        let frame = SiteKeeperCADKernel.CADCanvas2DRenderer().makeFrame(database: database)

        #expect(result.status == .rendered)
        #expect(database.importSource == "sitekeeper.dwg.libredwg")
        #expect(database.geometryParsed)
        #expect(database.drawableEntityCount == 1)
        #expect(frame.performance.renderCommandCount > 0)
    }

    @Test func DWGSmokeTest_AC1032_441174_LibreDWG() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DWGSmokeTest_AC1032_441174_LibreDWG-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let dwgURL = folder.appendingPathComponent("AC1032_441174.dwg")
        let sidecarURL = folder.appendingPathComponent("drawing.sitekeeper-cad.json")
        try Data("AC1032 441174 smoke dwg payload without worker geometry".utf8).write(to: dwgURL)

        SiteKeeperCADKernel.CADDWGGeometryAdapterRegistry.reset()
        defer { SiteKeeperCADKernel.CADDWGGeometryAdapterRegistry.reset() }

        let diagnosticResult = await SiteKeeperCADKernel.DWGImportEngine().importDatabase(
            SiteKeeperCADKernel.CADImportRequest(file: SiteKeeperCADKernel.CADFile(url: dwgURL))
        )
        let diagnosticDatabase = try #require(diagnosticResult.database)
        let diagnosticCodes = Set(diagnosticDatabase.diagnostics.entries.map(\.code))

        #expect(diagnosticResult.status == .diagnosticOnly)
        #expect(diagnosticDatabase.importSource == "sitekeeper.dwg.diagnostic")
        #expect(diagnosticDatabase.geometryParsed == false)
        #expect(diagnosticDatabase.drawableEntityCount == 0)
        #expect(diagnosticCodes.contains("CAD_DWG_GEOMETRY_SOURCE_MISSING"))
        #expect(diagnosticCodes.contains("CAD_DWG_VERSION_DETECTED"))
        #expect(
            diagnosticDatabase.diagnostics.entries.contains {
                $0.code == "CAD_DWG_VERSION_DETECTED" && ($0.detail?.contains("AC1032") ?? false)
            }
        )

        let diagnosticRoute = CADOpenRoute.unsupported(
            CADOpenResult(
                drawingId: UUID(),
                openState: .diagnosticOnly,
                message: CADViewerMessages.onlinePreviewUnavailableMessage,
                technicalDetails: nil
            )
        )
        #expect(
            CADPreviewContainer.shouldEnterInteractiveCADCanvas(
                isCADFile: true,
                rendererBound: true,
                route: diagnosticRoute
            ) == false
        )

        let workerPayload = """
        {
          "schema": "sitekeeper-cad-worker-v1",
          "drawingId": "44117400-0000-0000-0000-000000001032",
          "importSource": "sitekeeper.dwg.libredwg",
          "geometryParsed": true,
          "isDiagnosticOnly": false,
          "units": { "name": "millimeter", "metersPerDrawingUnit": 0.001 },
          "extents": { "minX": 0, "minY": 0, "maxX": 4400, "maxY": 1800 },
          "layers": [
            { "id": "A-WALL", "name": "墙体", "isVisible": true },
            { "id": "A-TEXT", "name": "文字", "isVisible": true }
          ],
          "layouts": [
            { "id": "model", "name": "Model", "isModelSpace": true }
          ],
          "textStyles": [
            { "id": "standard", "name": "Standard" }
          ],
          "blocks": [],
          "entities": [
            {
              "handle": "441174-L1",
              "type": "LINE",
              "layerID": "A-WALL",
              "start": { "x": 0, "y": 0 },
              "end": { "x": 4400, "y": 0 },
              "bounds": { "minX": 0, "minY": 0, "maxX": 4400, "maxY": 0 }
            },
            {
              "handle": "441174-L2",
              "type": "LWPOLYLINE",
              "layerID": "A-WALL",
              "points": [
                { "x": 0, "y": 0 },
                { "x": 4400, "y": 0 },
                { "x": 4400, "y": 1800 },
                { "x": 0, "y": 1800 }
              ],
              "isClosed": true,
              "bounds": { "minX": 0, "minY": 0, "maxX": 4400, "maxY": 1800 }
            },
            {
              "handle": "441174-T1",
              "type": "TEXT",
              "layerID": "A-TEXT",
              "rawText": "\\\\U+4E2D\\\\U+6587%%c20",
              "displayText": "中文∅20",
              "textStyleId": "standard",
              "textStyleName": "Standard",
              "insertionPoint": { "x": 200, "y": 300 },
              "bounds": { "minX": 200, "minY": 300, "maxX": 520, "maxY": 420 }
            }
          ],
          "xrefs": [],
          "diagnostics": {
            "entries": [
              {
                "severity": "info",
                "code": "CAD_WORKER_GEOMETRY_PARSED",
                "message": "LibreDWG worker generated SiteKeeper CAD JSON.",
                "detail": "dwgread-json"
              }
            ]
          },
          "performanceTrace": {
            "fileSizeBytes": 44,
            "entityCount": 3,
            "visibleEntityCount": 3,
            "renderCommandCount": 0,
            "drawCallCount": 0,
            "tileCount": 0,
            "spatialIndexBuildMs": 0,
            "resolveMs": 0,
            "renderMs": 0,
            "firstFrameMs": 0,
            "frameTimeMilliseconds": 0,
            "peakMemoryMB": 0,
            "skippedEntityCount": 0,
            "warnings": []
          },
          "textTrace": [
            {
              "entityId": "441174-T1",
              "entityType": "text",
              "rawText": "\\\\U+4E2D\\\\U+6587%%c20",
              "decodedText": "中文%%c20",
              "normalizedText": "中文∅20",
              "displayText": "中文∅20",
              "textStyleName": "Standard",
              "selectedFontName": "worker-unresolved",
              "fontWasAvailable": true,
              "fallbackReason": "resolved-in-app-cad-text-engine",
              "warnings": []
            }
          ]
        }
        """
        try workerPayload.write(to: sidecarURL, atomically: true, encoding: .utf8)

        let viewer = SiteKeeperCADKernel.SiteKeeperCADViewerEngine(
            importEngines: [SiteKeeperCADKernel.DWGImportEngine()],
            renderer: SiteKeeperCADKernel.CADCanvas2DRenderer()
        )
        let openResult = try await viewer.open(file: SiteKeeperCADKernel.CADFile(url: dwgURL, format: .dwg))
        let database = try #require(openResult.database)

        #expect(openResult.status == .rendered)
        #expect(database.importSource == "sitekeeper.dwg.libredwg")
        #expect(database.geometryParsed)
        #expect(database.drawableEntityCount > 0)
        #expect(database.layers.count > 0)
        #expect(database.layouts.count > 0)
        #expect(database.extents.isEmpty == false)
        #expect(database.performanceTrace.renderCommandCount > 0)
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_WORKER_GEOMETRY_PARSED" })
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_DWG_LIBREDWG_WORKER_JSON_USED" })

        let frame = try await viewer.render(
            viewport: SiteKeeperCADKernel.CADViewport(
                id: "smoke-viewport",
                layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id,
                clipBounds: database.extents
            ),
            options: SiteKeeperCADKernel.CADRenderOptions(
                layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id,
                viewportBounds: database.extents
            )
        )
        #expect(frame.performance.renderCommandCount > 0)
        #expect(!frame.commands.isEmpty)

        let renderedRoute = CADOpenRoute.online(
            CADOpenResult(
                drawingId: UUID(),
                openState: .rendered,
                message: "",
                technicalDetails: nil
            )
        )
        #expect(
            CADPreviewContainer.shouldEnterInteractiveCADCanvas(
                isCADFile: true,
                rendererBound: true,
                route: renderedRoute
            )
        )

        let failedFolder = folder.appendingPathComponent("failed-worker", isDirectory: true)
        try FileManager.default.createDirectory(at: failedFolder, withIntermediateDirectories: true)
        let failedDWGURL = failedFolder.appendingPathComponent("AC1032_441174_failed.dwg")
        let failedSidecarURL = failedFolder.appendingPathComponent("drawing.sitekeeper-cad.json")
        try Data("AC1032 441174 failed worker dwg payload".utf8).write(to: failedDWGURL)
        let failedWorkerPayload = """
        {
          "schema": "sitekeeper-cad-worker-v1",
          "drawingId": "44117400-0000-0000-0000-000000001033",
          "importSource": "sitekeeper.dwg.libredwg",
          "geometryParsed": false,
          "isDiagnosticOnly": true,
          "units": { "name": "unitless" },
          "extents": { "minX": 0, "minY": 0, "maxX": 0, "maxY": 0 },
          "layers": [{ "id": "0", "name": "0" }],
          "layouts": [{ "id": "model", "name": "Model", "isModelSpace": true }],
          "textStyles": [{ "id": "standard", "name": "Standard" }],
          "blocks": [],
          "entities": [],
          "xrefs": [],
          "diagnostics": {
            "entries": [
              {
                "severity": "warning",
                "code": "LIBREDWG_JSON_IMPORT_FAILED",
                "message": "dwgread JSON parse failed",
                "detail": "raw JSON could not be decoded"
              },
              {
                "severity": "warning",
                "code": "LIBREDWG_DWG2DXF_FAILED",
                "message": "dwg2dxf did not produce DXF",
                "detail": "unsupported DWG section"
              }
            ]
          }
        }
        """
        try failedWorkerPayload.write(to: failedSidecarURL, atomically: true, encoding: .utf8)

        let failedOpenResult = try await SiteKeeperCADKernel.SiteKeeperCADViewerEngine(
            importEngines: [SiteKeeperCADKernel.DWGImportEngine()],
            renderer: SiteKeeperCADKernel.CADCanvas2DRenderer()
        ).open(file: SiteKeeperCADKernel.CADFile(url: failedDWGURL, format: .dwg))
        let failedDatabase = try #require(failedOpenResult.database)
        let failedCodes = Set(failedDatabase.diagnostics.entries.map(\.code))

        #expect(failedOpenResult.status == .diagnosticOnly)
        #expect(failedDatabase.importSource == "sitekeeper.dwg.libredwg")
        #expect(failedDatabase.geometryParsed == false)
        #expect(failedDatabase.drawableEntityCount == 0)
        #expect(failedCodes.contains("LIBREDWG_JSON_IMPORT_FAILED"))
        #expect(failedCodes.contains("LIBREDWG_DWG2DXF_FAILED"))
        #expect(failedCodes.contains("CAD_DWG_GEOMETRY_NOT_DRAWABLE"))
    }

    @Test func dwgImportEngineDefaultOnlyReadsWorkerJSONAndDoesNotRunLibreDWGCommands() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let dwgURL = folder.appendingPathComponent("no-worker-output.dwg")
        try Data("AC1032 mock dwg payload".utf8).write(to: dwgURL)

        SiteKeeperCADKernel.CADDWGGeometryAdapterRegistry.reset()
        defer { SiteKeeperCADKernel.CADDWGGeometryAdapterRegistry.reset() }

        let result = await SiteKeeperCADKernel.DWGImportEngine().importDatabase(
            SiteKeeperCADKernel.CADImportRequest(file: SiteKeeperCADKernel.CADFile(url: dwgURL))
        )
        let database = try #require(result.database)
        let diagnosticCodes = Set(database.diagnostics.entries.map(\.code))

        #expect(result.status == .diagnosticOnly)
        #expect(database.drawableEntityCount == 0)
        #expect(database.geometryParsed == false)
        #expect(database.isDiagnosticOnly)
        #expect(diagnosticCodes.contains("CAD_DWG_GEOMETRY_SOURCE_MISSING"))
        #expect(!diagnosticCodes.contains("CAD_DWG_LIBREDWG_SOURCE_SELECTED"))
        #expect(!diagnosticCodes.contains("CAD_DWG_LIBREDWG_JSON_USED"))
        #expect(!diagnosticCodes.contains("CAD_DWG_LIBREDWG_DXF_USED"))
        #expect(!diagnosticCodes.contains("CAD_DWG_LIBREDWG_DXF_FALLBACK_USED"))
    }

    @Test func externalSDKImportEngineMapsAdapterOutputIntoCADDatabase() async throws {
        let url = URL(fileURLWithPath: "/tmp/external-input.dwg")
        let viewer = SiteKeeperCADKernel.SiteKeeperCADViewerEngine(
            importEngines: [
                SiteKeeperCADKernel.ExternalCADSDKImportEngine(adapter: MockExternalCADSDKAdapter())
            ],
            renderer: SiteKeeperCADKernel.CADCanvas2DRenderer()
        )

        let result = try await viewer.open(file: SiteKeeperCADKernel.CADFile(url: url, format: .dwg))
        let database = try #require(result.database)

        #expect(result.status == .rendered)
        #expect(database.sourceFile.format == .dwg)
        #expect(database.importSource == "test.external-adapter")
        #expect(database.geometryParsed)
        #expect(database.drawableEntityCount > 0)
        #expect(database.layers.map(\.id) == ["A-WALL"])
        #expect(database.layouts.map(\.id) == ["model"])
        #expect(database.blocks.first?.name == "DOOR")
        #expect(database.xrefs.first?.name == "xref-floor")
        #expect(database.entities.count == 2)
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_EXTERNAL_ADAPTER_USED" })

        let frame = try await viewer.render(
            viewport: SiteKeeperCADKernel.CADViewport(id: "v1", layoutID: "model"),
            options: SiteKeeperCADKernel.CADRenderOptions()
        )
        #expect(frame.commands.count == 3)
        #expect(frame.textTraces.first?.displayText == "一层配电箱")
    }

    @Test func viewerOpenRequiresRenderCommandsForRenderedState() async throws {
        let url = URL(fileURLWithPath: "/tmp/external-render-gate.dwg")
        let viewer = SiteKeeperCADKernel.SiteKeeperCADViewerEngine(
            importEngines: [
                SiteKeeperCADKernel.ExternalCADSDKImportEngine(adapter: MockExternalCADSDKAdapter())
            ],
            renderer: EmptyCommandRenderEngine()
        )

        let result = try await viewer.open(file: SiteKeeperCADKernel.CADFile(url: url, format: .dwg))
        let database = try #require(result.database)

        #expect(result.status == .diagnosticOnly)
        #expect(database.drawableEntityCount > 0)
        #expect(database.performanceTrace.renderCommandCount == 0)
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_RENDER_COMMANDS_EMPTY" })
    }

    @Test func externalSDKSnapshotOnlyImportProducesImagePlaceholder() async throws {
        let engine = SiteKeeperCADKernel.ExternalCADSDKImportEngine(adapter: SnapshotOnlyExternalCADSDKAdapter())
        let result = await engine.importDatabase(
            SiteKeeperCADKernel.CADImportRequest(
                file: SiteKeeperCADKernel.CADFile(url: URL(fileURLWithPath: "/tmp/snapshot.dwg"), format: .dwg)
            )
        )
        let database = try #require(result.database)
        let frame = SiteKeeperCADKernel.CADCanvas2DRenderer().makeFrame(database: database)
        let hasSnapshotPlaceholder = frame.commands.contains { command in
            if case .imagePlaceholder = command {
                return true
            }
            return false
        }

        #expect(result.status == .diagnosticOnly)
        #expect(database.entities.first?.kind == .image)
        #expect(database.geometryParsed == false)
        #expect(database.drawableEntityCount == 0)
        #expect(database.placeholderEntityCount == 1)
        #expect(database.diagnostics.entries.contains { $0.code == "CAD_EXTERNAL_RENDER_SNAPSHOT_AVAILABLE" })
        #expect(hasSnapshotPlaceholder)
    }

    @Test func entityTypesCoverRequiredStageThreeSurface() {
        let required: Set<SiteKeeperCADKernel.CADEntityKind> = [
            .line,
            .polyline,
            .lwPolyline,
            .circle,
            .arc,
            .ellipse,
            .spline,
            .text,
            .mtext,
            .insert,
            .attrib,
            .dimension,
            .hatch,
            .image,
            .table,
            .xref,
            .proxy,
            .unsupported
        ]

        #expect(required.isSubset(of: Set(SiteKeeperCADKernel.CADEntityKind.allCases)))
    }

    @Test func databaseModelsAreCodableAndPreserveRequiredFields() throws {
        let file = SiteKeeperCADKernel.CADFile(
            url: URL(fileURLWithPath: "/tmp/model.dwg"),
            displayName: "model.dwg",
            format: .dwg
        )
        let text = SiteKeeperCADKernel.CADTextRun(
            rawText: "%%C100",
            displayText: "直径100",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 1, y: 2),
            textStyleId: "cn-standard"
        )
        let diagnostics = SiteKeeperCADKernel.CADDrawingDiagnostics(entries: [
            SiteKeeperCADKernel.CADDrawingDiagnostics.Entry(
                severity: .warning,
                code: "CAD_PROXY_PRESERVED",
                message: "Proxy object preserved.",
                detail: "AB12"
            )
        ])
        let textEntity = SiteKeeperCADKernel.CADEntity(
            kind: .text,
            layerID: "A-WALL",
            color: 0xFF111111,
            lineType: "CONTINUOUS",
            lineWeight: 0.25,
            text: text,
            bounds: SiteKeeperCADKernel.CADBounds(minX: 1, minY: 2, maxX: 1, maxY: 2),
            sourceHandle: "T1"
        )
        let unsupportedEntity = SiteKeeperCADKernel.CADEntity(
            kind: .proxy,
            layerID: "A-WALL",
            color: 0xFF222222,
            lineType: "DASHED",
            lineWeight: 0.35,
            bounds: .empty,
            sourceHandle: "AB12",
            diagnostics: diagnostics,
            unsupportedReason: "Proxy object preserved."
        )
        let database = SiteKeeperCADKernel.CADDatabase(
            file: file,
            units: SiteKeeperCADKernel.CADUnits(name: "millimeter", metersPerDrawingUnit: 0.001),
            extents: SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 100, maxY: 50),
            layers: [SiteKeeperCADKernel.CADLayer(id: "A-WALL", name: "A-WALL")],
            layouts: [.modelSpace],
            entities: [textEntity, unsupportedEntity],
            textStyles: [SiteKeeperCADKernel.CADTextStyle(id: "cn-standard", name: "中文样式")],
            xrefs: [SiteKeeperCADKernel.CADXref(name: "xref-floor", path: "floor.dwg")]
        )

        let data = try JSONEncoder().encode(database)
        let decoded = try JSONDecoder().decode(SiteKeeperCADKernel.CADDatabase.self, from: data)

        #expect(decoded.drawingId == database.drawingId)
        #expect(decoded.sourceFile.displayName == "model.dwg")
        #expect(decoded.units.metersPerDrawingUnit == 0.001)
        #expect(decoded.extents.width == 100)
        #expect(decoded.entities[0].rawText == "%%C100")
        #expect(decoded.entities[0].displayText == "直径100")
        #expect(decoded.entities[0].textStyleId == "cn-standard")
        #expect(decoded.entities[1].type == .proxy)
        #expect(decoded.entities[1].diagnostics.entries.first?.code == "CAD_PROXY_PRESERVED")
        #expect(decoded.entityCount == 2)
        #expect(decoded.drawableEntityCount == 1)
        #expect(decoded.placeholderEntityCount == 1)
        #expect(decoded.geometryParsed)
    }

    @Test func viewerEngineManagesLayersLayoutsRenderMeasureAndSearch() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let payload = """
        {
          "units": { "name": "millimeter", "metersPerDrawingUnit": 0.001 },
          "extents": { "isEmpty": false, "minX": 0, "minY": 0, "maxX": 10, "maxY": 10 },
          "layers": [{ "id": "0", "name": "0" }],
          "layouts": [{ "id": "model", "name": "Model", "isModelSpace": true }],
          "entities": [
            { "handle": "L1", "layerID": "0", "type": "line", "start": { "x": 0, "y": 0 }, "end": { "x": 5, "y": 0 } },
            { "handle": "T1", "layerID": "0", "type": "text", "start": { "x": 2, "y": 2 }, "end": { "x": 2, "y": 2 }, "rawText": "\\\\P阀门A", "displayText": "阀门A", "textStyleId": "standard" }
          ]
        }
        """
        try payload.data(using: .utf8)?.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let viewer = SiteKeeperCADKernel.SiteKeeperCADViewerEngine(
            importEngines: [SiteKeeperCADKernel.IntermediateJSONImportEngine()],
            renderer: SiteKeeperCADKernel.CADCanvas2DRenderer()
        )
        let result = try await viewer.open(file: SiteKeeperCADKernel.CADFile(url: url))

        #expect(result.status == .rendered)
        let layerIds = try await viewer.getLayers().map(\.id)
        let layoutIds = try await viewer.getLayouts().map(\.id)
        #expect(layerIds == ["0"])
        #expect(layoutIds == ["model"])

        try await viewer.setLayerVisible("0", visible: false)
        let hiddenFrame = try await viewer.render(
            viewport: SiteKeeperCADKernel.CADViewport(id: "v1", layoutID: "model"),
            options: SiteKeeperCADKernel.CADRenderOptions()
        )
        #expect(hiddenFrame.commands.isEmpty)

        try await viewer.setLayerVisible("0", visible: true)
        try await viewer.setCurrentLayout("model")
        let visibleFrame = try await viewer.render(
            viewport: SiteKeeperCADKernel.CADViewport(id: "v1", layoutID: "model"),
            options: SiteKeeperCADKernel.CADRenderOptions()
        )
        #expect(visibleFrame.commands.count == 3)

        let measurement = try await viewer.measure(
            SiteKeeperCADKernel.CADMeasureInput(points: [
                SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
                SiteKeeperCADKernel.CADPoint(x: 3, y: 4)
            ])
        )
        #expect(measurement.value == 5)

        let matches = try await viewer.searchText("阀门")
        #expect(matches.count == 1)
        #expect(matches.first?.text == "阀门A")
        #expect(matches.first?.layoutId == "model")
        #expect(matches.first?.targetViewport.layoutID == "model")
    }

    @Test func measureToolConvertsUnitsAndScreenCoordinates() {
        let tool = SiteKeeperCADKernel.CADMeasureTool(
            units: SiteKeeperCADKernel.CADUnits(name: "millimeter", metersPerDrawingUnit: 0.001)
        )

        let continuous = tool.measure(
            SiteKeeperCADKernel.CADMeasureInput(
                mode: .polyline,
                points: [
                    SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
                    SiteKeeperCADKernel.CADPoint(x: 3_000, y: 4_000),
                    SiteKeeperCADKernel.CADPoint(x: 6_000, y: 8_000)
                ],
                unit: "m"
            )
        )
        #expect(continuous.value == 10)
        #expect(continuous.segments.map(\.length) == [5, 5])
        #expect(continuous.rawDrawingValue == 10_000)

        let area = tool.measure(
            SiteKeeperCADKernel.CADMeasureInput(
                mode: .area,
                points: [
                    SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
                    SiteKeeperCADKernel.CADPoint(x: 2_000, y: 0),
                    SiteKeeperCADKernel.CADPoint(x: 2_000, y: 1_000),
                    SiteKeeperCADKernel.CADPoint(x: 0, y: 1_000)
                ],
                unit: "m"
            )
        )
        #expect(area.value == 2)
        #expect(area.area == 2)
        #expect(area.perimeter == 6)
        #expect(area.areaUnit == "m^2")

        let mapper = SiteKeeperCADKernel.CADMarkupCoordinateMapper(
            viewport: SiteKeeperCADKernel.CADViewport(
                id: "screen",
                layoutID: "model",
                viewCenter: .zero,
                viewHeight: 100
            ),
            screenSize: SiteKeeperCADKernel.CADScreenSize(width: 200, height: 100)
        )
        let screenMeasurement = tool.measure(
            SiteKeeperCADKernel.CADMeasureInput(
                points: [
                    SiteKeeperCADKernel.CADPoint(x: 100, y: 50),
                    SiteKeeperCADKernel.CADPoint(x: 150, y: 50)
                ],
                coordinateSpace: .screen,
                coordinateMapper: mapper
            )
        )
        #expect(screenMeasurement.value == 50)
        #expect(screenMeasurement.worldPoints[0].isClose(to: .zero))
        #expect(screenMeasurement.worldPoints[1].isClose(to: SiteKeeperCADKernel.CADPoint(x: 50, y: 0)))
    }

    @Test func textSearchIndexReturnsBusinessLocationPayload() {
        let text = SiteKeeperCADKernel.CADTextRun(
            rawText: "一层阀门编号A-01需要复核",
            displayText: "一层阀门编号A-01需要复核",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 100, y: 200),
            height: 5
        )
        let entity = SiteKeeperCADKernel.CADEntity(
            kind: .mtext,
            layoutID: "model",
            text: text,
            bounds: SiteKeeperCADKernel.CADBounds(minX: 100, minY: 200, maxX: 160, maxY: 210)
        )
        let database = SiteKeeperCADKernel.CADDatabase(
            file: SiteKeeperCADKernel.CADFile(url: URL(fileURLWithPath: "/tmp/search.json")),
            entities: [entity]
        )

        let result = SiteKeeperCADKernel.CADTextSearchIndex(database: database).search("阀门").first

        #expect(result?.entityID == entity.id)
        #expect(result?.entityId == entity.id)
        #expect(result?.layoutId == "model")
        #expect(result?.bounds.contains(SiteKeeperCADKernel.CADPoint(x: 100, y: 200)) == true)
        #expect(result?.previewText.contains("阀门") == true)
        #expect(result?.targetViewport.layoutID == "model")
        #expect(result?.targetViewport.clipBounds.intersects(result?.bounds ?? .empty) == true)
    }

    @Test func markupCoordinateMapperBindsIssueMarkersToWorldCoordinates() {
        let drawingId = UUID()
        let viewport = SiteKeeperCADKernel.CADViewport(
            id: "v1",
            layoutID: "model",
            viewCenter: .zero,
            viewHeight: 100
        )
        let mapper = SiteKeeperCADKernel.CADMarkupCoordinateMapper(
            viewport: viewport,
            screenSize: SiteKeeperCADKernel.CADScreenSize(width: 200, height: 100),
            drawingId: drawingId
        )

        let marker = mapper.makeIssueMarker(
            drawingId: drawingId,
            screenPoint: SiteKeeperCADKernel.CADPoint(x: 150, y: 50),
            title: "整改点"
        )

        #expect(marker.drawingId == drawingId)
        #expect(marker.layoutId == "model")
        #expect(marker.worldPoint.isClose(to: SiteKeeperCADKernel.CADPoint(x: 50, y: 0)))
        #expect(mapper.screenPoint(for: marker)?.isClose(to: SiteKeeperCADKernel.CADPoint(x: 150, y: 50)) == true)

        let zoomedMapper = SiteKeeperCADKernel.CADMarkupCoordinateMapper(
            viewport: SiteKeeperCADKernel.CADViewport(
                id: "v2",
                layoutID: "model",
                viewCenter: SiteKeeperCADKernel.CADPoint(x: 10, y: 0),
                viewHeight: 50
            ),
            screenSize: SiteKeeperCADKernel.CADScreenSize(width: 200, height: 100),
            drawingId: drawingId
        )
        let remappedScreenPoint = zoomedMapper.screenPoint(for: marker)
        #expect(remappedScreenPoint?.isClose(to: SiteKeeperCADKernel.CADPoint(x: 180, y: 50)) == true)
        #expect(remappedScreenPoint.map { zoomedMapper.worldPoint(forScreenPoint: $0).isClose(to: marker.worldPoint) } == true)

        let otherLayoutMapper = SiteKeeperCADKernel.CADMarkupCoordinateMapper(
            viewport: SiteKeeperCADKernel.CADViewport(id: "v3", layoutID: "paper", viewHeight: 100),
            screenSize: SiteKeeperCADKernel.CADScreenSize(width: 200, height: 100),
            drawingId: drawingId
        )
        #expect(otherLayoutMapper.screenPoint(for: marker) == nil)
    }

    @Test func textEngineDecodesNormalizesParsesAndResolvesChineseText() {
        let engine = SiteKeeperCADKernel.CADTextEngine()
        let style = SiteKeeperCADKernel.CADTextStyle(
            id: "cn-shx",
            name: "中文SHX",
            fontName: "txt.shx"
        )

        let run = engine.makeTextRun(
            rawText: #"普通中文 \U+4E2D%%d%%p%%c%%%{\fSimSun|b0|i0;\S1/2;} \P完成"#,
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            style: style
        )

        #expect(run.decodedText.contains("普通中文 中"))
        #expect(run.normalizedText.contains("°±∅%"))
        #expect(run.displayText.contains("1/2"))
        #expect(run.displayText.contains("完成"))
        #expect(run.selectedFontName == "PingFang SC")
        #expect(run.fontWasAvailable)
        #expect(run.fallbackReason == "unicode-cjk-shx-bypassed")
        #expect(run.decodeMethod == "unicodeEscape")
        #expect(run.warnings.contains("CAD_TEXT_SHX_SKIPPED_FOR_UNICODE"))
        #expect(run.warnings.contains("CAD_TEXT_BIGFONT_MISSING"))
        #expect(!run.selectedFontName.lowercased().contains(".shx"))
    }

    @Test func textEngineValidatesRuntimeFontAvailabilityAndFallsBackForChinese() {
        let engine = SiteKeeperCADKernel.CADTextEngine()
        let style = SiteKeeperCADKernel.CADTextStyle(
            id: "missing-font",
            name: "MissingFont",
            fontName: "DefinitelyMissingCADFont"
        )

        let run = engine.makeTextRun(
            rawText: "普通中文管线标注",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            style: style
        )

        #expect(run.fontWasAvailable)
        #expect(run.fallbackReason == "requested-font-unavailable")
        #expect(run.warnings.contains { $0 == "CAD_TEXT_FONT_UNAVAILABLE:DefinitelyMissingCADFont" })
        #expect(!run.selectedFontName.lowercased().contains("missing"))
        #expect(!run.selectedFontName.lowercased().hasSuffix(".shx"))
    }

    @Test func rendererUsesTextEngineAndWritesTextTraceJSONL() async throws {
        let file = SiteKeeperCADKernel.CADFile(
            url: URL(fileURLWithPath: "/tmp/text-trace.json"),
            format: .intermediateJSON
        )
        let textEntity = SiteKeeperCADKernel.CADEntity(
            kind: .text,
            layerID: "0",
            text: SiteKeeperCADKernel.CADTextRun(
                rawText: #"阀门\U+4E00%%c100"#,
                insertionPoint: SiteKeeperCADKernel.CADPoint(x: 2, y: 3),
                textStyleId: "standard"
            ),
            bounds: SiteKeeperCADKernel.CADBounds(minX: 2, minY: 3, maxX: 2, maxY: 3),
            sourceHandle: "T100"
        )
        let database = SiteKeeperCADKernel.CADDatabase(
            file: file,
            layers: [.default],
            entities: [textEntity],
            textStyles: [
                SiteKeeperCADKernel.CADTextStyle(
                    id: "standard",
                    name: "Standard",
                    fontName: nil,
                    bigFontName: nil
                )
            ]
        )
        let renderer = SiteKeeperCADKernel.CADCanvas2DRenderer()
        try await renderer.prepare(database: database)

        let frame = try await renderer.render(
            viewport: SiteKeeperCADKernel.CADViewport(id: "v1", layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id),
            options: SiteKeeperCADKernel.CADRenderOptions()
        )

        guard case let .text(run, _) = frame.commands.first else {
            Issue.record("Expected first render command to be text.")
            return
        }
        #expect(run.displayText == "阀门一∅100")
        #expect(run.warnings.contains("CAD_TEXT_FONT_MISSING"))
        #expect(run.warnings.contains("CAD_TEXT_BIGFONT_MISSING"))
        #expect(frame.textTraces.count == 1)
        #expect(frame.textTraces[0].displayText == "阀门一∅100")
        #expect(frame.textTraces[0].selectedFontName == "PingFang SC")
        #expect(frame.textTraces[0].fontWasAvailable)
        #expect(frame.textTraces[0].fallbackReason == "requested-font-missing")

        let traceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("jsonl")
        let fontDiagnosticsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: traceURL) }
        defer { try? FileManager.default.removeItem(at: fontDiagnosticsURL) }
        try frame.writeTextTrace(to: traceURL)
        try frame.writeFontDiagnostics(to: fontDiagnosticsURL)

        let lines = try String(contentsOf: traceURL, encoding: .utf8)
            .split(separator: "\n")
        #expect(lines.count == 1)

        let decodedTrace = try JSONDecoder().decode(
            SiteKeeperCADKernel.CADTextTrace.self,
            from: Data(lines[0].utf8)
        )
        #expect(decodedTrace.entityType == "text")
        #expect(decodedTrace.rawText == #"阀门\U+4E00%%c100"#)
        #expect(decodedTrace.decodedText == "阀门一%%c100")
        #expect(decodedTrace.normalizedText == "阀门一∅100")
        #expect(decodedTrace.displayText == "阀门一∅100")
        #expect(decodedTrace.warnings.contains("CAD_TEXT_FONT_MISSING"))
        #expect(decodedTrace.fontWasAvailable)
        #expect(decodedTrace.fallbackReason == "requested-font-missing")

        let decodedFontDiagnostics = try JSONDecoder().decode(
            [SiteKeeperCADKernel.CADFontDiagnosticsEntry].self,
            from: Data(contentsOf: fontDiagnosticsURL)
        )
        #expect(decodedFontDiagnostics.count == 1)
        #expect(decodedFontDiagnostics[0].requestedFont == nil)
        #expect(decodedFontDiagnostics[0].resolvedFont == "PingFang SC")
        #expect(decodedFontDiagnostics[0].fallbackUsed)
    }

    @Test func blockResolverExpandsNestedInsertTransformAndAttrib() {
        let line = SiteKeeperCADKernel.CADPath(elements: [
            .move(to: SiteKeeperCADKernel.CADPoint(x: 0, y: 0)),
            .line(to: SiteKeeperCADKernel.CADPoint(x: 1, y: 0))
        ])
        let symbol = SiteKeeperCADKernel.CADBlock(
            id: "symbol",
            name: "SYMBOL",
            entities: [
                SiteKeeperCADKernel.CADEntity(
                    kind: .line,
                    layerID: "0",
                    path: line,
                    bounds: line.bounds
                )
            ]
        )
        let nestedInsert = SiteKeeperCADKernel.CADEntity(
            kind: .insert,
            layerID: "0",
            blockName: "SYMBOL",
            transform: .translation(x: 3, y: 0)
        )
        let door = SiteKeeperCADKernel.CADBlock(
            id: "door",
            name: "DOOR",
            entities: [nestedInsert]
        )
        let topTransform = SiteKeeperCADKernel.CADTransform
            .translation(x: 10, y: 10)
            .concatenating(.rotation(.pi / 2))
            .concatenating(.scale(2))
        let topInsert = SiteKeeperCADKernel.CADEntity(
            kind: .insert,
            layerID: "A-DOOR",
            text: SiteKeeperCADKernel.CADTextRun(
                rawText: "D-01",
                insertionPoint: SiteKeeperCADKernel.CADPoint(x: 1, y: 1)
            ),
            blockName: "DOOR",
            transform: topTransform
        )
        let database = SiteKeeperCADKernel.CADDatabase(
            file: SiteKeeperCADKernel.CADFile(url: URL(fileURLWithPath: "/tmp/block.json")),
            blocks: [symbol, door],
            entities: [topInsert]
        )

        let resolved = SiteKeeperCADKernel.CADBlockResolver().resolve(entities: database.entities, in: database)

        #expect(resolved.count == 2)
        let resolvedLine = resolved.first { $0.path != nil }
        let resolvedText = resolved.first { $0.kind == .attrib }
        #expect(resolvedLine?.layerID == "A-DOOR")
        #expect(resolvedText?.layerID == "A-DOOR")
        #expect(resolvedText?.text?.insertionPoint.isClose(to: SiteKeeperCADKernel.CADPoint(x: 8, y: 12)) == true)
        #expect(resolvedLine?.path?.points.first?.isClose(to: SiteKeeperCADKernel.CADPoint(x: 10, y: 16)) == true)
        #expect(resolvedLine?.path?.points.last?.isClose(to: SiteKeeperCADKernel.CADPoint(x: 10, y: 18)) == true)
    }

    @Test func layoutResolverSupportsPaperSpaceViewportClipping() {
        let insidePath = SiteKeeperCADKernel.CADPath(elements: [
            .move(to: SiteKeeperCADKernel.CADPoint(x: 1, y: 1)),
            .line(to: SiteKeeperCADKernel.CADPoint(x: 2, y: 2))
        ])
        let outsidePath = SiteKeeperCADKernel.CADPath(elements: [
            .move(to: SiteKeeperCADKernel.CADPoint(x: 10, y: 10)),
            .line(to: SiteKeeperCADKernel.CADPoint(x: 11, y: 11))
        ])
        let paperText = SiteKeeperCADKernel.CADTextRun(
            rawText: "图框",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 0, y: 0)
        )
        let paperLayout = SiteKeeperCADKernel.CADLayout(
            id: "layout-1",
            name: "Layout 1",
            isModelSpace: false,
            viewportIDs: ["vp-1"]
        )
        let database = SiteKeeperCADKernel.CADDatabase(
            file: SiteKeeperCADKernel.CADFile(url: URL(fileURLWithPath: "/tmp/layout.json")),
            layouts: [.modelSpace, paperLayout],
            entities: [
                SiteKeeperCADKernel.CADEntity(kind: .line, path: insidePath, bounds: insidePath.bounds),
                SiteKeeperCADKernel.CADEntity(kind: .line, path: outsidePath, bounds: outsidePath.bounds),
                SiteKeeperCADKernel.CADEntity(
                    kind: .text,
                    layoutID: "layout-1",
                    text: paperText,
                    bounds: SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 0, maxY: 0)
                )
            ],
            viewports: [
                SiteKeeperCADKernel.CADViewport(
                    id: "vp-1",
                    layoutID: "layout-1",
                    clipBounds: SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 5, maxY: 5)
                )
            ]
        )

        let resolved = SiteKeeperCADKernel.CADLayoutResolver().resolve(
            database: database,
            viewport: SiteKeeperCADKernel.CADViewport(id: "screen", layoutID: "layout-1"),
            options: SiteKeeperCADKernel.CADRenderOptions(layoutID: "layout-1")
        )

        #expect(resolved.layout.id == "layout-1")
        #expect(resolved.entities.count == 2)
        #expect(resolved.entities.filter { $0.layoutID == "layout-1" }.count == 2)
        #expect(resolved.entities.contains { $0.diagnostics.entries.contains { $0.code == "CAD_LAYOUT_VIEWPORT_CLIPPED" } })
    }

    @Test func rendererResolvesBlocksDimensionsHatchesAndSplinesBeforeCommands() {
        let symbolPath = SiteKeeperCADKernel.CADPath(elements: [
            .move(to: SiteKeeperCADKernel.CADPoint(x: 0, y: 0)),
            .line(to: SiteKeeperCADKernel.CADPoint(x: 5, y: 0))
        ])
        let block = SiteKeeperCADKernel.CADBlock(
            id: "fixture",
            name: "FIXTURE",
            entities: [
                SiteKeeperCADKernel.CADEntity(kind: .line, path: symbolPath, bounds: symbolPath.bounds)
            ]
        )
        let dimensionPath = SiteKeeperCADKernel.CADPath(elements: [
            .move(to: SiteKeeperCADKernel.CADPoint(x: 0, y: 2)),
            .line(to: SiteKeeperCADKernel.CADPoint(x: 10, y: 2))
        ])
        let hatchPath = SiteKeeperCADKernel.CADPath(elements: [
            .move(to: SiteKeeperCADKernel.CADPoint(x: 0, y: 0)),
            .line(to: SiteKeeperCADKernel.CADPoint(x: 2, y: 0)),
            .line(to: SiteKeeperCADKernel.CADPoint(x: 2, y: 2)),
            .close
        ])
        let splinePath = SiteKeeperCADKernel.CADPath(elements: [
            .move(to: SiteKeeperCADKernel.CADPoint(x: 0, y: 4)),
            .curve(
                to: SiteKeeperCADKernel.CADPoint(x: 4, y: 4),
                control1: SiteKeeperCADKernel.CADPoint(x: 1, y: 6),
                control2: SiteKeeperCADKernel.CADPoint(x: 3, y: 2)
            )
        ])
        let database = SiteKeeperCADKernel.CADDatabase(
            file: SiteKeeperCADKernel.CADFile(url: URL(fileURLWithPath: "/tmp/resolve.json")),
            blocks: [block],
            entities: [
                SiteKeeperCADKernel.CADEntity(kind: .insert, blockName: "FIXTURE", transform: .translation(x: 10, y: 0)),
                SiteKeeperCADKernel.CADEntity(kind: .dimension, path: dimensionPath, bounds: dimensionPath.bounds),
                SiteKeeperCADKernel.CADEntity(kind: .hatch, path: hatchPath, bounds: hatchPath.bounds),
                SiteKeeperCADKernel.CADEntity(kind: .spline, path: splinePath, bounds: splinePath.bounds)
            ]
        )

        let frame = SiteKeeperCADKernel.CADCanvas2DRenderer().makeFrame(database: database)

        #expect(frame.performance.entityCount > database.entities.count)
        #expect(frame.performance.renderCommandCount == frame.commands.count)
        #expect(frame.performance.visibleEntityCount == frame.performance.entityCount)
        #expect(frame.commands.count >= 7)
    }

    @Test func spatialIndexFiltersViewportLayerAndLayout() {
        let modelLine = makeLineEntity(
            x1: 0,
            y1: 0,
            x2: 2,
            y2: 0,
            layerID: "A-WALL",
            layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id
        )
        let otherLayer = makeLineEntity(
            x1: 0,
            y1: 1,
            x2: 2,
            y2: 1,
            layerID: "A-DOOR",
            layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id
        )
        let paperEntity = makeLineEntity(
            x1: 0,
            y1: 0,
            x2: 2,
            y2: 0,
            layerID: "A-WALL",
            layoutID: "paper"
        )
        let outside = makeLineEntity(
            x1: 20,
            y1: 0,
            x2: 22,
            y2: 0,
            layerID: "A-WALL",
            layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id
        )
        let textWithoutBounds = SiteKeeperCADKernel.CADEntity(
            kind: .text,
            layerID: "A-WALL",
            text: SiteKeeperCADKernel.CADTextRun(
                rawText: "门",
                insertionPoint: SiteKeeperCADKernel.CADPoint(x: 1, y: 1)
            )
        )
        let index = SiteKeeperCADKernel.CADSpatialIndex(
            entities: [modelLine, otherLayer, paperEntity, outside, textWithoutBounds]
        )

        let ids = index.query(
            SiteKeeperCADKernel.CADBounds(minX: -1, minY: -1, maxX: 3, maxY: 3),
            layerIDs: ["A-WALL"],
            layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id
        )

        #expect(ids.contains(modelLine.id))
        #expect(ids.contains(textWithoutBounds.id))
        #expect(!ids.contains(otherLayer.id))
        #expect(!ids.contains(paperEntity.id))
        #expect(!ids.contains(outside.id))
        #expect(index.entityCount == 5)
        #expect(index.missingBoundsCount == 0)
    }

    @Test func rendererUsesViewportSpatialQueryAndRenderBudget() {
        let entities = (0..<100).map { index in
            makeLineEntity(
                x1: Double(index * 10),
                y1: 0,
                x2: Double(index * 10 + 5),
                y2: 0
            )
        }
        let database = SiteKeeperCADKernel.CADDatabase(
            file: SiteKeeperCADKernel.CADFile(url: URL(fileURLWithPath: "/tmp/budget.json")),
            entities: entities
        )

        let frame = SiteKeeperCADKernel.CADCanvas2DRenderer().makeFrame(
            database: database,
            options: SiteKeeperCADKernel.CADRenderOptions(
                viewportBounds: SiteKeeperCADKernel.CADBounds(minX: -1, minY: -1, maxX: 95, maxY: 1),
                renderBudget: SiteKeeperCADKernel.CADRenderBudget(maxRenderCommands: 6, maxFrameTimeMilliseconds: 500)
            )
        )

        #expect(frame.performance.visibleEntityCount == 10)
        #expect(frame.performance.renderCommandCount == 6)
        #expect(frame.performance.drawCallCount == 3)
        #expect(frame.performance.skippedEntityCount > 0)
        #expect(frame.performance.spatialIndexBuildMs >= 0)
        #expect(frame.performance.resolveMs >= 0)
        #expect(frame.performance.renderMs >= 0)
        #expect(frame.performance.firstFrameMs >= 0)
        #expect(frame.performance.warnings.contains { $0.contains("CAD_RENDER_BUDGET_EXCEEDED") })
    }

    @Test func lodPolicySkipsSmallTextHatchAndZoomingDetails() {
        let line = makeLineEntity(x1: 0, y1: 0, x2: 200, y2: 0)
        let text = SiteKeeperCADKernel.CADEntity(
            kind: .text,
            text: SiteKeeperCADKernel.CADTextRun(
                rawText: "小字",
                insertionPoint: SiteKeeperCADKernel.CADPoint(x: 10, y: 10),
                height: 1
            ),
            bounds: SiteKeeperCADKernel.CADBounds(minX: 10, minY: 10, maxX: 10, maxY: 10)
        )
        let hatchPath = SiteKeeperCADKernel.CADPath(
            elements: (0..<64).map {
                .line(to: SiteKeeperCADKernel.CADPoint(x: Double($0), y: Double($0 % 2)))
            }
        )
        let hatch = SiteKeeperCADKernel.CADEntity(
            kind: .hatch,
            path: hatchPath,
            bounds: hatchPath.bounds
        )
        let database = SiteKeeperCADKernel.CADDatabase(
            file: SiteKeeperCADKernel.CADFile(url: URL(fileURLWithPath: "/tmp/lod.json")),
            entities: [line, text, hatch]
        )

        let zoomedOut = SiteKeeperCADKernel.CADCanvas2DRenderer().makeFrame(
            database: database,
            options: SiteKeeperCADKernel.CADRenderOptions(deviceScale: 0.01)
        )
        #expect(zoomedOut.commands.count == 2)
        #expect(zoomedOut.performance.warnings.contains { $0.contains("CAD_LOD_SMALL_TEXT_SKIPPED") })
        #expect(zoomedOut.performance.warnings.contains { $0.contains("CAD_HATCH_SKIPPED_LOW_ZOOM") })

        let zooming = SiteKeeperCADKernel.CADCanvas2DRenderer().makeFrame(
            database: database,
            options: SiteKeeperCADKernel.CADRenderOptions(
                interactionPhase: .zooming,
                renderBudget: .interactive
            )
        )
        #expect(zooming.commands.count == 2)
        #expect(zooming.performance.warnings.contains { $0.contains("CAD_LOD_ZOOMING_TEXT_SKIPPED") })
        #expect(zooming.performance.warnings.contains { $0.contains("CAD_LOD_ZOOMING_HATCH_SKIPPED") })
    }

    @Test func renderCacheStoresLayoutViewportTextAndBlockResolution() {
        let cache = SiteKeeperCADKernel.CADRenderCache()
        let symbolPath = SiteKeeperCADKernel.CADPath(elements: [
            .move(to: SiteKeeperCADKernel.CADPoint(x: 0, y: 0)),
            .line(to: SiteKeeperCADKernel.CADPoint(x: 5, y: 0))
        ])
        let block = SiteKeeperCADKernel.CADBlock(
            id: "tag",
            name: "TAG",
            entities: [
                SiteKeeperCADKernel.CADEntity(kind: .line, path: symbolPath, bounds: symbolPath.bounds)
            ]
        )
        let insert = SiteKeeperCADKernel.CADEntity(
            kind: .insert,
            text: SiteKeeperCADKernel.CADTextRun(
                rawText: "A-01",
                insertionPoint: SiteKeeperCADKernel.CADPoint(x: 1, y: 1)
            ),
            blockName: "TAG"
        )
        let database = SiteKeeperCADKernel.CADDatabase(
            file: SiteKeeperCADKernel.CADFile(url: URL(fileURLWithPath: "/tmp/cache.json")),
            blocks: [block],
            entities: [insert]
        )
        let renderer = SiteKeeperCADKernel.CADCanvas2DRenderer(cache: cache)

        let first = renderer.makeFrame(database: database)
        let second = renderer.makeFrame(database: database)

        #expect(first.commands == second.commands)
        #expect(cache.layoutCacheCount == 1)
        #expect(cache.blockResolutionCacheCount == 1)
        #expect(cache.textLayoutCacheCount == 1)
        #expect(cache.viewportTileCacheCount == 1)
    }

    @Test func regressionSuiteSummarizesLaunchReadinessAndCodablePayload() throws {
        let readySamples = (0..<27).map { index in
            SiteKeeperCADKernel.CADRegressionSuite.SampleResult(
                fileName: "ready-\(index).dwg",
                openSucceeded: true,
                isBlank: false,
                chineseReadable: true,
                unsupportedEntityRatio: 0.02,
                firstFrameMs: 900,
                renderMs: 40,
                qualityScore: 86,
                launchReady: true
            )
        }
        let riskySamples = (0..<3).map { index in
            SiteKeeperCADKernel.CADRegressionSuite.SampleResult(
                fileName: "risky-\(index).dwg",
                openSucceeded: true,
                isBlank: false,
                chineseReadable: false,
                missingFonts: ["missing.shx"],
                unsupportedEntityRatio: 0.18,
                firstFrameMs: 1_400,
                renderMs: 70,
                qualityScore: 58,
                launchReady: false
            )
        }
        let suite = SiteKeeperCADKernel.CADRegressionSuite(results: readySamples + riskySamples)
        let summary = suite.summarize()

        #expect(summary.sampleCount == 30)
        #expect(summary.majorContentDisplayableCount == 27)
        #expect(summary.blankCount == 0)
        #expect(summary.missingFontCount == 3)
        #expect(summary.launchReady)

        let data = try JSONEncoder().encode(suite)
        let decoded = try JSONDecoder().decode(SiteKeeperCADKernel.CADRegressionSuite.self, from: data)
        #expect(decoded.summarize() == summary)
    }
}

private struct MockExternalCADSDKAdapter: SiteKeeperCADKernel.CADExternalSDKAdapter {
    let id = "test.external-adapter"

    func canImport(file: SiteKeeperCADKernel.CADFile) -> Bool {
        file.format == .dwg
    }

    func importDrawing(file _: SiteKeeperCADKernel.CADFile) async throws -> SiteKeeperCADKernel.CADExternalSDKDrawing {
        let path = SiteKeeperCADKernel.CADPath(elements: [
            .move(to: SiteKeeperCADKernel.CADPoint(x: 0, y: 0)),
            .line(to: SiteKeeperCADKernel.CADPoint(x: 100, y: 0))
        ])
        let line = SiteKeeperCADKernel.CADExternalSDKEntity(
            type: .line,
            layerId: "A-WALL",
            geometry: .path(path),
            sourceHandle: "L1"
        )
        let text = SiteKeeperCADKernel.CADExternalSDKEntity(
            type: .text,
            layerId: "A-WALL",
            text: SiteKeeperCADKernel.CADExternalSDKText(
                rawText: "一层配电箱",
                displayText: "一层配电箱",
                insertionPoint: SiteKeeperCADKernel.CADPoint(x: 10, y: 10)
            ),
            sourceHandle: "T1"
        )
        let block = SiteKeeperCADKernel.CADExternalSDKBlock(
            name: "DOOR",
            entities: [line],
            bounds: path.bounds
        )
        return SiteKeeperCADKernel.CADExternalSDKDrawing(
            units: SiteKeeperCADKernel.CADUnits(name: "millimeter", metersPerDrawingUnit: 0.001),
            extents: SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 100, maxY: 20),
            layers: [SiteKeeperCADKernel.CADLayer(id: "A-WALL", name: "墙体")],
            layouts: [SiteKeeperCADKernel.CADLayout(id: "model", name: "Model", isModelSpace: true)],
            entities: [line, text],
            blocks: [block],
            textStyles: [SiteKeeperCADKernel.CADTextStyle(id: "standard", name: "Standard")],
            xrefs: [SiteKeeperCADKernel.CADXref(name: "xref-floor", path: "floor.dwg")]
        )
    }
}

private struct MockDWGGeometryAdapter: SiteKeeperCADKernel.CADDWGGeometryAdapter {
    let id = "test.dwg-geometry-adapter"

    func canImportDWG(file: SiteKeeperCADKernel.CADFile) -> Bool {
        file.format == .dwg
    }

    func importDWG(file _: SiteKeeperCADKernel.CADFile) async throws -> SiteKeeperCADKernel.CADExternalSDKDrawing {
        let linePath = SiteKeeperCADKernel.CADPath(elements: [
            .move(to: SiteKeeperCADKernel.CADPoint(x: 0, y: 0)),
            .line(to: SiteKeeperCADKernel.CADPoint(x: 80, y: 0))
        ])
        let line = SiteKeeperCADKernel.CADExternalSDKEntity(
            type: .line,
            layerId: "S-WALL",
            geometry: .path(linePath),
            sourceHandle: "DWG-L1"
        )
        let text = SiteKeeperCADKernel.CADExternalSDKEntity(
            type: .text,
            layerId: "A-TEXT",
            text: SiteKeeperCADKernel.CADExternalSDKText(
                rawText: "\\U+5730\\U+4E0B\\U+5BA4\\U+5916\\U+5899",
                decodedText: "地下室外墙",
                normalizedText: "地下室外墙",
                displayText: "地下室外墙",
                styleName: "ChinaStandard",
                selectedFontName: "PingFang SC",
                decodeMethod: "dwgGeometryAdapter",
                insertionPoint: SiteKeeperCADKernel.CADPoint(x: 10, y: 12),
                textStyleId: "china-standard",
                height: 3
            ),
            sourceHandle: "DWG-T1"
        )
        let block = SiteKeeperCADKernel.CADExternalSDKBlock(
            name: "WINDOW",
            entities: [line],
            bounds: linePath.bounds
        )

        return SiteKeeperCADKernel.CADExternalSDKDrawing(
            units: SiteKeeperCADKernel.CADUnits(name: "millimeter", metersPerDrawingUnit: 0.001),
            extents: SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 100, maxY: 40),
            layers: [
                SiteKeeperCADKernel.CADLayer(id: "S-WALL", name: "结构墙"),
                SiteKeeperCADKernel.CADLayer(id: "A-TEXT", name: "文字")
            ],
            layouts: [SiteKeeperCADKernel.CADLayout(id: "model", name: "Model", isModelSpace: true)],
            entities: [line, text],
            blocks: [block],
            textStyles: [
                SiteKeeperCADKernel.CADTextStyle(
                    id: "china-standard",
                    name: "ChinaStandard",
                    fontName: "simfang.ttf",
                    bigFontName: nil
                )
            ],
            xrefs: [
                SiteKeeperCADKernel.CADXref(
                    name: "xref-structure",
                    path: "structure.dwg",
                    isResolved: false
                )
            ]
        )
    }
}

private struct SnapshotOnlyExternalCADSDKAdapter: SiteKeeperCADKernel.CADExternalSDKAdapter {
    let id = "test.snapshot-only-adapter"

    func canImport(file: SiteKeeperCADKernel.CADFile) -> Bool {
        file.format == .dwg
    }

    func importDrawing(file _: SiteKeeperCADKernel.CADFile) async throws -> SiteKeeperCADKernel.CADExternalSDKDrawing {
        SiteKeeperCADKernel.CADExternalSDKDrawing(
            extents: SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 200, maxY: 100),
            renderSnapshot: SiteKeeperCADKernel.CADExternalSDKRenderSnapshot(
                bounds: SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 200, maxY: 100),
                pixelWidth: 800,
                pixelHeight: 400
            )
        )
    }
}

private actor EmptyCommandRenderEngine: SiteKeeperCADKernel.CADRenderEngine {
    private var preparedDatabase: SiteKeeperCADKernel.CADDatabase?

    func prepare(database: SiteKeeperCADKernel.CADDatabase) async throws {
        preparedDatabase = database
    }

    func render(
        viewport _: SiteKeeperCADKernel.CADViewport,
        options: SiteKeeperCADKernel.CADRenderOptions
    ) async throws -> SiteKeeperCADKernel.CADRenderFrame {
        let database = preparedDatabase
        let bounds = options.viewportBounds.isEmpty
            ? (database?.extents ?? SiteKeeperCADKernel.CADBounds(minX: -1, minY: -1, maxX: 1, maxY: 1))
            : options.viewportBounds
        let performance = SiteKeeperCADKernel.CADPerformanceTrace(
            fileSizeBytes: database?.sourceFile.byteCount ?? 0,
            entityCount: database?.entityCount ?? 0,
            visibleEntityCount: database?.drawableEntityCount ?? 0,
            renderCommandCount: 0,
            drawCallCount: 0,
            spatialIndexBuildMs: 0,
            resolveMs: 0,
            renderMs: 0,
            firstFrameMs: 0,
            frameTimeMilliseconds: 0,
            peakMemoryMB: 0,
            skippedEntityCount: 0,
            warnings: []
        )
        return SiteKeeperCADKernel.CADRenderFrame(
            databaseID: database?.id ?? UUID(),
            bounds: bounds,
            commands: [],
            performance: performance
        )
    }
}

private extension SiteKeeperCADKernel.CADPoint {
    func isClose(to other: SiteKeeperCADKernel.CADPoint, tolerance: Double = 0.0001) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
    }
}

private func makeLineEntity(
    x1: Double,
    y1: Double,
    x2: Double,
    y2: Double,
    layerID: String = SiteKeeperCADKernel.CADLayer.default.id,
    layoutID: String = SiteKeeperCADKernel.CADLayout.modelSpace.id
) -> SiteKeeperCADKernel.CADEntity {
    let path = SiteKeeperCADKernel.CADPath(elements: [
        .move(to: SiteKeeperCADKernel.CADPoint(x: x1, y: y1)),
        .line(to: SiteKeeperCADKernel.CADPoint(x: x2, y: y2))
    ])
    return SiteKeeperCADKernel.CADEntity(
        kind: .line,
        layerID: layerID,
        layoutID: layoutID,
        path: path,
        bounds: path.bounds
    )
}

private func repoRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func renderCommandLayerID(_ command: SiteKeeperCADKernel.CADRenderCommand) -> String? {
    switch command {
    case let .moveTo(_, style):
        return style.layerID
    case let .lineTo(_, style):
        return style.layerID
    case let .polyline(_, _, style):
        return style.layerID
    case let .circle(_, _, style):
        return style.layerID
    case let .arc(_, _, _, _, style):
        return style.layerID
    case let .ellipse(_, _, _, _, style):
        return style.layerID
    case let .text(_, style):
        return style.layerID
    case let .hatch(_, style):
        return style.layerID
    case let .marker(_, _, style):
        return style.layerID
    case .imagePlaceholder, .unsupportedPlaceholder:
        return nil
    }
}
