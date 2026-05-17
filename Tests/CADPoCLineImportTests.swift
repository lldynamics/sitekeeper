import Foundation
import CoreGraphics
import Darwin
import Testing
@testable import sitekeeper
#if os(iOS)
import UIKit
#endif

@Suite(.serialized)
struct CADPoCLineImportTests {
    @Test func rendererFrameDiagnosticsIdentifyWhiteScreenFailureLayer() {
        let layerFiltered = CADRendererPerformanceSnapshot(
            entityCountInViewport: 0,
            drawCallCount: 0,
            frameTimeMilliseconds: 1,
            skippedEntityCount: 0,
            visibleLayerCount: 1,
            totalLayerCount: 2,
            simplifiedMode: false,
            renderCommandCount: 0,
            totalEntityCount: 8,
            indexedEntityCount: 8,
            viewportEntityCountBeforeLayerFilter: 3,
            layerFilterActive: true,
            modelBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            viewportBounds: CGRect(x: 0, y: 0, width: 50, height: 50),
            modelBoundsValid: true,
            viewportBoundsValid: true,
            viewportIntersectsModel: true,
            vertexCount: 0
        )
        let viewportMiss = CADRendererPerformanceSnapshot(
            entityCountInViewport: 0,
            drawCallCount: 0,
            frameTimeMilliseconds: 1,
            skippedEntityCount: 0,
            visibleLayerCount: 2,
            totalLayerCount: 2,
            simplifiedMode: false,
            renderCommandCount: 0,
            totalEntityCount: 8,
            indexedEntityCount: 8,
            viewportEntityCountBeforeLayerFilter: 0,
            layerFilterActive: false,
            modelBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            viewportBounds: CGRect(x: 200, y: 200, width: 50, height: 50),
            modelBoundsValid: true,
            viewportBoundsValid: true,
            viewportIntersectsModel: false,
            vertexCount: 0
        )
        let commandMiss = CADRendererPerformanceSnapshot(
            entityCountInViewport: 2,
            drawCallCount: 0,
            frameTimeMilliseconds: 1,
            skippedEntityCount: 0,
            visibleLayerCount: 2,
            totalLayerCount: 2,
            simplifiedMode: false,
            renderCommandCount: 0,
            totalEntityCount: 8,
            indexedEntityCount: 8,
            viewportEntityCountBeforeLayerFilter: 2,
            layerFilterActive: false,
            modelBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            viewportBounds: CGRect(x: 0, y: 0, width: 50, height: 50),
            modelBoundsValid: true,
            viewportBoundsValid: true,
            viewportIntersectsModel: true,
            vertexCount: 0
        )
        let textOverlayMiss = CADRendererPerformanceSnapshot(
            entityCountInViewport: 2,
            drawCallCount: 2,
            frameTimeMilliseconds: 1,
            skippedEntityCount: 0,
            visibleLayerCount: 2,
            totalLayerCount: 2,
            simplifiedMode: false,
            renderCommandCount: 2,
            textCommandCount: 2,
            textOverlayCount: 0,
            totalEntityCount: 8,
            indexedEntityCount: 8,
            viewportEntityCountBeforeLayerFilter: 2,
            layerFilterActive: false,
            modelBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            viewportBounds: CGRect(x: 0, y: 0, width: 50, height: 50),
            modelBoundsValid: true,
            viewportBoundsValid: true,
            viewportIntersectsModel: true,
            vertexCount: 0
        )

        #expect(layerFiltered.rendererFailureLayer == "layer")
        #expect(viewportMiss.rendererFailureLayer == "viewport")
        #expect(commandMiss.rendererFailureLayer == "renderCommand")
        #expect(textOverlayMiss.rendererFailureLayer == "textOverlay")
        #expect(layerFiltered.hasActionableRendererFailure)
        #expect(textOverlayMiss.rendererDiagnosticSummary.contains("文字"))
    }

    @Test func rendererFrameDiagnosticsPassWhenCommandsReachOutput() {
        let snapshot = CADRendererPerformanceSnapshot(
            entityCountInViewport: 2,
            drawCallCount: 2,
            frameTimeMilliseconds: 1,
            skippedEntityCount: 0,
            visibleLayerCount: 2,
            totalLayerCount: 2,
            simplifiedMode: false,
            renderCommandCount: 2,
            textCommandCount: 0,
            textOverlayCount: 0,
            totalEntityCount: 2,
            indexedEntityCount: 2,
            viewportEntityCountBeforeLayerFilter: 2,
            layerFilterActive: false,
            modelBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            viewportBounds: CGRect(x: 0, y: 0, width: 50, height: 50),
            modelBoundsValid: true,
            viewportBoundsValid: true,
            viewportIntersectsModel: true,
            vertexCount: 12
        )

        #expect(snapshot.rendererFailureLayer == "none")
        #expect(!snapshot.hasActionableRendererFailure)
    }

    @Test func libreDWGNativePoCImportsDXFBasic2DGeometry() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-line-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        5
        A1
        8
        WALL
        10
        0
        20
        0
        11
        100
        21
        50
        0
        CIRCLE
        8
        IGNORED
        10
        30
        20
        30
        40
        10
        0
        LWPOLYLINE
        5
        A2
        8
        WALL
        70
        1
        10
        120
        20
        0
        10
        200
        20
        0
        10
        200
        20
        40
        0
        ARC
        5
        A3
        8
        CURVE
        10
        150
        20
        70
        40
        10
        50
        0
        51
        90
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = CADPoC.LibreDWGNativeImportEngine()
        let result = try await engine.importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )

        #expect(result.trace.rawLineCount == 1)
        #expect(result.trace.rawPolylineCount == 1)
        #expect(result.trace.rawCircleCount == 1)
        #expect(result.trace.rawArcCount == 1)
        #expect(result.trace.entityCount == 4)
        #expect(result.trace.drawableEntityCount == 4)
        #expect(result.trace.renderCommandCount == 4)
        #expect(result.trace.openedForRender)
        #expect(result.database.entities.count == 4)
        #expect(result.database.entities.first?.kind == .line)
        #expect(result.database.entities.first?.layerID == "WALL")
        #expect(result.database.entities.contains { $0.kind == .lwPolyline })
        #expect(result.database.entities.contains { $0.kind == .circle })
        #expect(result.database.entities.contains { $0.kind == .arc })
        #expect(result.database.extents == SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 200, maxY: 80))

        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)
        #expect(commands.count == 4)
    }

    @Test func libreDWGNativePoCImportsLegacyPolylineVertices() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-polyline-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        POLYLINE
        5
        P1
        8
        WALL
        70
        1
        0
        VERTEX
        10
        0
        20
        0
        0
        VERTEX
        10
        100
        20
        0
        0
        VERTEX
        10
        100
        20
        40
        0
        SEQEND
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )

        #expect(result.trace.rawPolylineCount == 1)
        #expect(result.trace.entityCount == 1)
        #expect(result.trace.drawableEntityCount == 1)
        #expect(result.database.entities.first?.kind == .polyline)
        #expect(result.database.entities.first?.layerID == "WALL")
        #expect(result.database.extents == SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 100, maxY: 40))
        #expect(CADPoC.CADRenderPipeline().commands(from: result.database.entities).count == 1)
    }

    @Test func libreDWGNativePoCTessellatesPolylineBulgeArcs() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-polyline-bulge-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        LWPOLYLINE
        5
        B1
        8
        ARC_WALL
        90
        2
        10
        0
        20
        0
        42
        -1
        10
        100
        20
        0
        0
        POLYLINE
        5
        B2
        8
        ARC_WALL
        0
        VERTEX
        10
        200
        20
        0
        42
        -1
        0
        VERTEX
        10
        300
        20
        0
        0
        SEQEND
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entitiesByHandle = Dictionary(uniqueKeysWithValues: result.database.entities.compactMap { entity in
            entity.sourceHandle.map { ($0, entity) }
        })
        let lwPolyline = try #require(entitiesByHandle["B1"])
        let legacyPolyline = try #require(entitiesByHandle["B2"])
        let lwPoints = try #require(lwPolyline.path?.points)
        let legacyPoints = try #require(legacyPolyline.path?.points)
        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)

        #expect(result.trace.rawPolylineCount == 2)
        #expect(result.trace.drawableEntityCount == 2)
        #expect(lwPolyline.kind == .lwPolyline)
        #expect(legacyPolyline.kind == .polyline)
        #expect(lwPoints.count > 8)
        #expect(legacyPoints.count > 8)
        #expect(lwPolyline.bounds.maxY > 49)
        #expect(legacyPolyline.bounds.maxY > 49)
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_LWPOLYLINE_BULGE_TESSELLATED" })
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_POLYLINE_BULGE_TESSELLATED" })
        #expect(commands.count == 2)
    }

    @Test func libreDWGNativePoCCoversCommonAuxiliary2DEntities() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-aux-entities-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        POINT
        5
        PT1
        8
        MARK
        10
        5
        20
        6
        0
        XLINE
        5
        XL1
        8
        GRID
        10
        0
        20
        0
        11
        1
        21
        0
        0
        RAY
        5
        R1
        8
        GRID
        10
        0
        20
        0
        11
        0
        21
        1
        0
        LEADER
        5
        LD1
        8
        NOTE
        10
        0
        20
        0
        10
        20
        20
        10
        10
        30
        20
        10
        0
        MLINE
        5
        ML1
        8
        WALL
        11
        40
        21
        0
        11
        40
        21
        40
        0
        SOLID
        5
        S1
        8
        FILL
        10
        50
        20
        0
        11
        70
        21
        0
        12
        70
        22
        20
        13
        50
        23
        20
        0
        IMAGE
        5
        IMG1
        8
        REF
        10
        80
        20
        0
        11
        1
        21
        0
        12
        0
        22
        1
        13
        30
        23
        20
        0
        WIPEOUT
        5
        W1
        8
        MASK
        14
        120
        24
        0
        14
        140
        24
        0
        14
        140
        24
        20
        14
        120
        24
        20
        0
        ACAD_PROXY_ENTITY
        5
        PX1
        8
        PROXY
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)

        #expect(result.trace.entityCount == 9)
        #expect(result.trace.drawableEntityCount == 7)
        #expect(result.database.placeholderEntityCount == 2)
        #expect(result.database.entities.contains { $0.kind == .point })
        #expect(result.database.entities.contains { $0.sourceHandle == "IMG1" && $0.kind == .image })
        #expect(result.database.entities.contains { $0.sourceHandle == "PX1" && $0.kind == .unsupported })
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_IMAGE_PLACEHOLDER" })
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_WIPEOUT_DEGRADED_TO_BOUNDARY" })
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_DXF_UNSUPPORTED_ENTITY" })
        #expect(commands.contains { command in
            if case .marker = command { return true }
            return false
        })
        #expect(commands.contains { command in
            if case .imagePlaceholder = command { return true }
            return false
        })
    }

    @Test func libreDWGNativeShimMapsProxyAndTianzhengProxyAsNonDrawableDiagnostics() throws {
        let engine = CADPoC.LibreDWGNativeImportEngine()
        #expect(engine.entityKindForNativeKindForTesting(Int32(SiteKeeperLibreDWGEntityKindProxy.rawValue)) == .proxy)
        #expect(engine.entityKindForNativeKindForTesting(Int32(SiteKeeperLibreDWGEntityKindTianzhengProxy.rawValue)) == .proxy)

        var nativeEntity = SiteKeeperLibreDWGEntity()
        nativeEntity.kind = Int32(SiteKeeperLibreDWGEntityKindTianzhengProxy.rawValue)
        nativeEntity.layerName = strdup("TCH_LAYER")
        nativeEntity.sourceHandle = strdup("PX-TCH")
        nativeEntity.objectName = strdup("TCH_WALL")
        nativeEntity.unsupportedReason = strdup("Tianzheng/TCH proxy object preserved as diagnostic metadata.")
        nativeEntity.colorARGB = 0xFF22AAFF
        nativeEntity.lineWeight = 2
        defer {
            free(nativeEntity.layerName)
            free(nativeEntity.sourceHandle)
            free(nativeEntity.objectName)
            free(nativeEntity.unsupportedReason)
        }

        let entity = try #require(engine.makeNativeEntityForTesting(nativeEntity))
        let database = SiteKeeperCADKernel.CADDatabase(
            file: SiteKeeperCADKernel.CADFile(url: URL(fileURLWithPath: "/tmp/proxy.dwg"), format: .dwg),
            entities: [entity]
        )
        let renderCommandCount = CADPoC.CADRenderPipeline().commands(from: database.entities).count
        let trace = CADPoC.CADOpenTrace(
            fileName: "proxy.dwg",
            importSource: engine.id,
            rawProxyEntityCount: 1,
            rawTianzhengProxyCount: 1,
            exportedProxyEntityCount: 1,
            exportedTianzhengProxyCount: 1,
            entityCount: database.entityCount,
            drawableEntityCount: database.drawableEntityCount,
            renderCommandCount: renderCommandCount
        )

        #expect(entity.kind == .proxy)
        #expect(entity.layerID == "TCH_LAYER")
        #expect(entity.sourceHandle == "PX-TCH")
        #expect(entity.unsupportedReason?.contains("Tianzheng") == true)
        #expect(entity.diagnostics.entries.contains { $0.code == "CAD_POC_LIBREDWG_TIANZHENG_PROXY_ENTITY" })
        #expect(!entity.isRenderable)
        #expect(database.entityCount == 1)
        #expect(database.drawableEntityCount == 0)
        #expect(database.placeholderEntityCount == 1)
        #expect(!database.geometryParsed)
        #expect(renderCommandCount == 0)
        #expect(!trace.openedForRender)
    }

    @Test func libreDWGNativeShimPreservesPaperSpaceLayoutOnImportedEntities() throws {
        let engine = CADPoC.LibreDWGNativeImportEngine()
        let points = UnsafeMutablePointer<SiteKeeperLibreDWGPoint>.allocate(capacity: 2)
        points.initialize(to: SiteKeeperLibreDWGPoint(x: 0, y: 0))
        points.advanced(by: 1).initialize(to: SiteKeeperLibreDWGPoint(x: 10, y: 0))

        var nativeEntity = SiteKeeperLibreDWGEntity()
        nativeEntity.kind = Int32(SiteKeeperLibreDWGEntityKindLine.rawValue)
        nativeEntity.points = points
        nativeEntity.pointCount = 2
        nativeEntity.layerName = strdup("PAPER")
        nativeEntity.sourceHandle = strdup("PAPER-LINE")
        nativeEntity.layoutSpace = 1
        nativeEntity.colorARGB = 0xFF00AAFF
        nativeEntity.lineWeight = 2
        defer {
            points.deinitialize(count: 2)
            points.deallocate()
            free(nativeEntity.layerName)
            free(nativeEntity.sourceHandle)
        }

        let entity = try #require(engine.makeNativeEntityForTesting(nativeEntity))

        #expect(entity.kind == .line)
        #expect(entity.layoutID == "paper")
        #expect(entity.layerID == "PAPER")
        #expect(entity.bounds.minX == 0)
        #expect(entity.bounds.maxX == 10)
    }

    @Test func libreDWGNativePoCImportsTextThroughTextEngine() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-text-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        TEXT
        5
        T1
        8
        NOTE
        10
        0
        20
        0
        40
        10
        1
        %%c20
        0
        MTEXT
        5
        T2
        8
        NOTE
        10
        0
        20
        20
        40
        12
        1
        \\U+4E2D\\U+6587
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let displayTexts = result.database.entities.compactMap(\.displayText)
        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)

        #expect(result.trace.rawTextCount == 2)
        #expect(result.trace.entityCount == 2)
        #expect(result.trace.drawableEntityCount == 2)
        #expect(result.database.entities.allSatisfy { $0.kind == .text || $0.kind == .mtext })
        #expect(displayTexts.contains("∅20"))
        #expect(displayTexts.contains("中文"))
        #expect(commands.count == 2)
        #expect(commands.allSatisfy { command in
            if case .text = command {
                return true
            }
            return false
        })
    }

    @Test func cadMetalPoCRenderPipelineKeepsChineseTextInStableOverview() async throws {
        let textRun = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: "\\U+4E2D\\U+6587",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 10, y: 10),
            style: .default,
            height: 2.5
        )
        let entity = SiteKeeperCADKernel.CADEntity(
            kind: .text,
            layerID: "NOTE",
            color: 0xFFFFFFFF,
            text: textRun,
            bounds: SiteKeeperCADKernel.CADBounds(minX: 10, minY: 10, maxX: 20, maxY: 13)
        )
        let output = CADPoC.CADRenderPipeline(
            lodPolicy: SiteKeeperCADKernel.CADLODPolicy(minTextHeightOnScreen: 2)
        ).renderOutput(
            from: [entity],
            totalEntityCount: 50_001,
            zoomScale: 1,
            interactionPhase: .stable
        )

        #expect(textRun.displayText == "中文")
        #expect(output.commands.count == 1)
        #expect(output.performance.skippedEntityCount == 0)
        if case let .text(renderedText, style)? = output.commands.first {
            #expect(renderedText.displayText == "中文")
            #expect(style.colorARGB == 0xFFFFFFFF)
        } else {
            Issue.record("Expected stable overview render output to keep Chinese text")
        }
    }

    #if os(iOS)
    @Test func cadMetalPoCRasterizesChineseTextOverlayPixels() throws {
        let font = UIFont(name: "PingFangSC-Regular", size: 24) ?? .systemFont(ofSize: 24)
        let image = try #require(CADPoC.CADMetalRenderer.makeTextOverlayRasterImage(
            displayText: "中文123",
            font: font,
            textColor: .black,
            scale: 2
        ))
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        try pixels.withUnsafeMutableBytes { rawPixels in
            let context = try #require(CGContext(
                data: rawPixels.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let hasTextPixels = stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }

        #expect(width > 20)
        #expect(height > 20)
        #expect(hasTextPixels)
    }

    @Test func cadMetalPoCRasterizesChineseWhenPreferredFontIsLatinOnly() throws {
        let font = UIFont(name: "Helvetica", size: 24) ?? .systemFont(ofSize: 24)
        let image = try #require(CADPoC.CADMetalRenderer.makeTextOverlayRasterImage(
            displayText: "消防水泵123",
            font: font,
            textColor: .black,
            scale: 2
        ))
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        try pixels.withUnsafeMutableBytes { rawPixels in
            let context = try #require(CGContext(
                data: rawPixels.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let nonTransparentPixels = stride(from: 3, to: pixels.count, by: 4).filter { pixels[$0] > 0 }.count

        #expect(width > 40)
        #expect(height > 20)
        #expect(nonTransparentPixels > 40)
    }

    @Test func cadMetalPoCBuildsTextureAtlasForChineseText() throws {
        let renderer = CADPoC.CADMetalRenderer()
        try #require(renderer.isAvailable)
        let textRun = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: "消防水泵123",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 10, y: 10),
            style: .default,
            height: 4
        )
        let entity = SiteKeeperCADKernel.CADEntity(
            kind: .text,
            layerID: "TEXT",
            text: textRun,
            bounds: SiteKeeperCADKernel.CADBounds(minX: 10, minY: 10, maxX: 40, maxY: 16)
        )
        renderer.updateDrawing(entities: [entity], layers: [.default])
        let commands = CADPoC.CADRenderPipeline().commands(from: [entity])
        let snapshot = try #require(renderer.textAtlasSnapshotForTesting(
            commands: commands,
            drawableSize: CGSize(width: 800, height: 600),
            viewSize: CGSize(width: 400, height: 300),
            contentScale: 2
        ))

        #expect(snapshot.textCount == 1)
        #expect(snapshot.uniqueTextureCount == 7)
        #expect(snapshot.vertexCount == 42)
        #expect(snapshot.atlasSize.width > 0)
        #expect(snapshot.atlasSize.height > 0)
    }

    @Test func cadMetalPoCUsesFontAdvanceInsteadOfRasterPaddingForGlyphSpacing() throws {
        let renderer = CADPoC.CADMetalRenderer()
        try #require(renderer.isAvailable)
        let font = UIFont(name: "PingFangSC-Regular", size: 24) ?? .systemFont(ofSize: 24)
        let text = "消防水泵"
        let singleGlyphImageWidths = text.compactMap { character in
            CADPoC.CADMetalRenderer.makeTextOverlayRasterImage(
                displayText: String(character),
                font: font,
                textColor: .black,
                scale: 2
            )?.size.width
        }.reduce(CGFloat(0), +)
        let expectedAdvance = CADPoC.CADMetalRenderer.textAdvanceWidthForTesting(text: text, font: font)
        let atlasLayoutWidth = renderer.textAtlasLayoutWidthForTesting(
            displayText: text,
            font: font,
            widthFactor: 1,
            contentScale: 2
        )

        #expect(singleGlyphImageWidths > expectedAdvance + 12)
        #expect(abs(atlasLayoutWidth - expectedAdvance) < 8)
    }

    @Test func cadMetalPoCReusesGlyphsForRepeatedText() throws {
        let renderer = CADPoC.CADMetalRenderer()
        try #require(renderer.isAvailable)
        let first = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: "中文",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            style: .default,
            height: 3
        )
        let second = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: "中文",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 20, y: 0),
            style: .default,
            height: 3
        )
        let entities = [
            SiteKeeperCADKernel.CADEntity(
                kind: .text,
                layerID: "TEXT",
                text: first,
                bounds: SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 10, maxY: 4)
            ),
            SiteKeeperCADKernel.CADEntity(
                kind: .text,
                layerID: "TEXT",
                text: second,
                bounds: SiteKeeperCADKernel.CADBounds(minX: 20, minY: 0, maxX: 30, maxY: 4)
            )
        ]
        renderer.updateDrawing(entities: entities, layers: [.default])
        let commands = CADPoC.CADRenderPipeline().commands(from: entities)
        let snapshot = try #require(renderer.textAtlasSnapshotForTesting(
            commands: commands,
            drawableSize: CGSize(width: 800, height: 600),
            viewSize: CGSize(width: 400, height: 300),
            contentScale: 2
        ))

        #expect(snapshot.textCount == 2)
        #expect(snapshot.uniqueTextureCount == 2)
        #expect(snapshot.vertexCount == 24)
    }

    @Test func cadMetalPoCReusesSharedChineseGlyphsAcrossDifferentTextRuns() throws {
        let renderer = CADPoC.CADMetalRenderer()
        try #require(renderer.isAvailable)
        let first = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: "消防水泵",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            style: .default,
            height: 3
        )
        let second = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: "消防泵房",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 20, y: 0),
            style: .default,
            height: 3
        )
        let entities = [
            SiteKeeperCADKernel.CADEntity(
                kind: .text,
                layerID: "TEXT",
                text: first,
                bounds: SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 10, maxY: 4)
            ),
            SiteKeeperCADKernel.CADEntity(
                kind: .text,
                layerID: "TEXT",
                text: second,
                bounds: SiteKeeperCADKernel.CADBounds(minX: 20, minY: 0, maxX: 30, maxY: 4)
            )
        ]
        renderer.updateDrawing(entities: entities, layers: [.default])
        let commands = CADPoC.CADRenderPipeline().commands(from: entities)
        let snapshot = try #require(renderer.textAtlasSnapshotForTesting(
            commands: commands,
            drawableSize: CGSize(width: 800, height: 600),
            viewSize: CGSize(width: 400, height: 300),
            contentScale: 2
        ))

        #expect(snapshot.textCount == 2)
        #expect(snapshot.uniqueTextureCount == 5)
        #expect(snapshot.vertexCount == 48)
    }

    @Test func cadMetalPoCReusesAtlasTextureAcrossFrames() throws {
        let renderer = CADPoC.CADMetalRenderer()
        try #require(renderer.isAvailable)
        let textRun = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: "消防泵房",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 12, y: 18),
            style: .default,
            height: 4
        )
        let entity = SiteKeeperCADKernel.CADEntity(
            kind: .text,
            layerID: "TEXT",
            text: textRun,
            bounds: SiteKeeperCADKernel.CADBounds(minX: 12, minY: 18, maxX: 28, maxY: 24)
        )
        renderer.updateDrawing(entities: [entity], layers: [.default])
        let commands = CADPoC.CADRenderPipeline().commands(from: [entity])

        let first = try #require(renderer.textAtlasSnapshotForTesting(
            commands: commands,
            drawableSize: CGSize(width: 800, height: 600),
            viewSize: CGSize(width: 400, height: 300),
            contentScale: 2
        ))
        let second = try #require(renderer.textAtlasSnapshotForTesting(
            commands: commands,
            drawableSize: CGSize(width: 800, height: 600),
            viewSize: CGSize(width: 400, height: 300),
            contentScale: 2
        ))

        #expect(first.cacheEntryCount == 1)
        #expect(second.cacheEntryCount == 1)
        #expect(second.cacheHitCount > first.cacheHitCount)
        #expect(second.vertexCount == first.vertexCount)
    }

    @Test func cadMetalPoCTextOverlayUsesDrawableToViewScaleForCoordinates() throws {
        let point = CADPoC.CADMetalRenderer.textOverlayViewPointForTesting(
            drawablePoint: SIMD2<Double>(150, 100),
            drawableSize: CGSize(width: 300, height: 200),
            viewSize: CGSize(width: 100, height: 100),
            fallbackScale: 2
        )

        #expect(abs(point.x - 50) < 0.001)
        #expect(abs(point.y - 50) < 0.001)
    }

    @Test func cadMetalPoCTextOverlayCenterRotatesAroundInsertionPoint() throws {
        let center = CADPoC.CADMetalRenderer.textOverlayCenterForTesting(
            insertionScreen: CGPoint(x: 100, y: 100),
            width: 40,
            height: 10,
            alignmentOffset: .zero,
            rotationRadians: Double.pi / 2
        )

        #expect(abs(center.x - 95) < 0.001)
        #expect(abs(center.y - 80) < 0.001)
    }

    @Test func cadMetalPoCTextOverlayFontSizeTracksDeepZoom() throws {
        let fontSize = CADPoC.CADMetalRenderer.textOverlayFontSizeForTesting(
            textHeight: 2,
            modelScale: 180,
            contentScale: 2
        )

        #expect(fontSize > 96)
        #expect(fontSize <= 256)
    }
    #endif

    @Test func cadTextEngineSkipsLatinFontWhenChineseGlyphsAreMissing() throws {
        let textRun = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: "中文123",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            style: SiteKeeperCADKernel.CADTextStyle(
                id: "latin",
                name: "Latin",
                fontName: "Helvetica"
            )
        )

        #expect(textRun.displayText == "中文123")
        #expect(textRun.fontWasAvailable)
        #expect(textRun.selectedFontName.localizedCaseInsensitiveContains("Helvetica") == false)
        #expect(textRun.warnings.contains("CAD_TEXT_FONT_LACKS_GLYPHS:Helvetica"))
    }

    @Test func libreDWGNativePoCAggregatesDXFFontDiagnosticsFromStyleTable() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-font-diagnostics-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        TABLES
        0
        TABLE
        2
        STYLE
        0
        STYLE
        2
        CHINESE_SHX
        3
        missingfont.shx
        4
        missingbigfont.shx
        40
        0
        41
        1
        0
        ENDTAB
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        TEXT
        5
        FT1
        8
        NOTE
        10
        0
        20
        0
        40
        10
        7
        CHINESE_SHX
        1
        \\U+4E2D\\U+6587
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let text = try #require(result.database.entities.first?.text)
        let diagnosticCodes = Set(result.database.diagnostics.entries.map(\.code))

        #expect(text.displayText == "中文")
        #expect(text.fontFile == "missingfont.shx")
        #expect(text.bigFontFile == "missingbigfont.shx")
        #expect(text.selectedFontName.localizedCaseInsensitiveContains("missingfont") == false)
        #expect(text.warnings.contains("CAD_TEXT_SHX_SKIPPED_FOR_UNICODE"))
        #expect(text.warnings.contains("CAD_TEXT_BIGFONT_UNAVAILABLE:missingbigfont.shx"))
        #expect(result.database.textTrace.contains { $0.entityId == "FT1" && $0.displayText == "中文" })
        #expect(diagnosticCodes.contains("CAD_TEXT_SHX_SKIPPED_FOR_UNICODE"))
        #expect(diagnosticCodes.contains("CAD_TEXT_BIGFONT_UNAVAILABLE"))
        #expect(diagnosticCodes.contains("CAD_TEXT_FONT_FALLBACK_USED"))
    }

    @Test func libreDWGNativePoCTextBoundsIncludeRotationAndWidthFactor() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-rotated-text-bounds-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        TEXT
        5
        RT1
        8
        NOTE
        10
        0
        20
        0
        40
        10
        41
        2
        50
        90
        1
        ABCD
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entity = try #require(result.database.entities.first)
        let text = try #require(entity.text)

        #expect(text.displayText == "ABCD")
        #expect(abs((text.widthFactor ?? 0) - 2) < 0.0001)
        #expect(abs(text.rotationRadians - Double.pi / 2) < 0.0001)
        #expect(entity.bounds.minX < -9.9)
        #expect(entity.bounds.maxX < 0.001)
        #expect(entity.bounds.maxY > 47.9)
        #expect(entity.bounds.width < 10.2)
        #expect(entity.bounds.height > 47.9)
    }

    @Test func cadTextEngineDecodesLegacyCIFAndMIFChineseText() throws {
        let engine = SiteKeeperCADKernel.CADTextEngine()
        let cifText = engine.makeTextRun(
            rawText: "U+4E2DU+6587",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            style: .default
        )
        let mifText = engine.makeTextRun(
            rawText: "\\M+5D6D0\\M+5CEC4",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            style: .default
        )

        #expect(cifText.displayText == "中文")
        #expect(cifText.decodeMethod == "unicodeEscape")
        #expect(mifText.displayText == "中文")
        #expect(mifText.decodeMethod == "mifEscape")
    }

    @Test func cadTextEngineDecodesMarkedSHXAndBigFontHexBytes() throws {
        let textRun = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: "\\SHX+D6D0\\BIGFONT+CEC4",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            style: SiteKeeperCADKernel.CADTextStyle(
                id: "hztxt",
                name: "HZTXT",
                fontName: "hztxt.shx",
                bigFontName: "gbcbig.shx"
            )
        )

        #expect(textRun.displayText == "中文")
        #expect(textRun.decodeMethod == "shxBigFontHex")
        #expect(textRun.warnings.contains("CAD_TEXT_SHX_BIGFONT_HEX_DECODED"))
        #expect(textRun.warnings.contains { $0.hasPrefix("CAD_TEXT_SHX_BIGFONT_") && $0.hasSuffix("_DECODED") })
    }

    @Test func cadTextEngineDecodesMarkedBig5BigFontHexBytes() throws {
        let rawBytes = try #require(Self.encodedBytes("中文", using: Self.big5Encoding))
        let hex = rawBytes.map { String(format: "%02X", $0) }.joined()
        let textRun = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: "\\BIGFONT+\(hex)",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            style: SiteKeeperCADKernel.CADTextStyle(
                id: "big5",
                name: "BIG5",
                fontName: "txt.shx",
                bigFontName: "big5.shx"
            )
        )

        #expect(textRun.displayText == "中文")
        #expect(textRun.decodeMethod == "shxBigFontHex")
        #expect(textRun.warnings.contains("CAD_TEXT_SHX_BIGFONT_BIG5_DECODED"))
    }

    @Test func libreDWGNativePoCUsesPreferredBig5CodePageForNativeTextBytes() throws {
        let engine = CADPoC.LibreDWGNativeImportEngine(preferredTextCodePage: 950)
        let rawBytes = try #require(Self.encodedBytes("中文", using: Self.big5Encoding))
        let rawText = Self.nativeCString(bytes: rawBytes)
        var nativeEntity = SiteKeeperLibreDWGEntity()
        nativeEntity.kind = Int32(SiteKeeperLibreDWGEntityKindText.rawValue)
        nativeEntity.layerName = strdup("TEXT")
        nativeEntity.sourceHandle = strdup("BIG5-TEXT")
        nativeEntity.rawText = rawText
        nativeEntity.textStyleName = strdup("BIG5")
        nativeEntity.fontName = strdup("txt.shx")
        nativeEntity.bigFontName = strdup("big5.shx")
        nativeEntity.colorARGB = 0xFF111111
        nativeEntity.lineWeight = 2
        nativeEntity.textX = 10
        nativeEntity.textY = 20
        nativeEntity.textHeight = 3
        defer {
            free(nativeEntity.layerName)
            free(nativeEntity.sourceHandle)
            rawText.deallocate()
            free(nativeEntity.textStyleName)
            free(nativeEntity.fontName)
            free(nativeEntity.bigFontName)
        }

        let entity = try #require(engine.makeNativeEntityForTesting(nativeEntity))
        let text = try #require(entity.text)

        #expect(text.rawText == "中文")
        #expect(text.displayText == "中文")
        #expect(text.bigFontFile == "big5.shx")
        #expect(entity.bounds.minX <= 10)
        #expect(entity.bounds.maxX >= 10)
        #expect(entity.bounds.minY <= 20)
        #expect(entity.bounds.maxY >= 20)
    }

    @Test func cadTextEngineDecodesGB18030MIFBigFontBytes() throws {
        let rawBytes = try #require(Self.encodedBytes("𠀀", using: Self.gb18030Encoding))
        let hex = rawBytes.map { String(format: "%02X", $0) }.joined()
        let textRun = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: "\\M+5\(hex)",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            style: SiteKeeperCADKernel.CADTextStyle(
                id: "gbcbig",
                name: "GBCBIG",
                fontName: "hztxt.shx",
                bigFontName: "gbcbig.shx"
            )
        )

        #expect(textRun.displayText == "𠀀")
        #expect(textRun.decodeMethod == "mifEscape")
        #expect(textRun.warnings.contains("CAD_TEXT_BIGFONT_MIF_DECODED"))
        #expect(textRun.warnings.contains("CAD_TEXT_BIGFONT_MIF_GB18030_DECODED"))
    }

    @Test func cadTextEngineRepairsGBKMojibakeChineseText() throws {
        let textRun = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: "ÖÐÎÄ123",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            style: .default
        )

        #expect(textRun.displayText == "中文123")
        #expect(textRun.decodeMethod == "encodingRepair")
        #expect(textRun.warnings.contains("CAD_TEXT_GBK_MOJIBAKE_REPAIRED"))
    }

    @Test func cadTextEngineRepairsGB18030BigFontMojibakeText() throws {
        let rawText = try #require(Self.singleByteString("𠀀层", using: Self.gb18030Encoding))
        let textRun = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: rawText,
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            style: SiteKeeperCADKernel.CADTextStyle(
                id: "gbcbig",
                name: "GBCBIG",
                fontName: "hztxt.shx",
                bigFontName: "gbcbig.shx"
            )
        )

        #expect(textRun.displayText == "𠀀层")
        #expect(textRun.decodeMethod == "encodingRepair")
        #expect(textRun.warnings.contains("CAD_TEXT_SHX_BIGFONT_BYTES_DECODED"))
        #expect(textRun.warnings.contains("CAD_TEXT_GB18030_FALLBACK_DECODED"))
    }

    @Test func renderPipelineDoesNotLetGeometryBudgetStarveChineseText() throws {
        let lineEntities = (0..<24).map { index in
            SiteKeeperCADKernel.CADEntity(
                kind: .line,
                layerID: "WALL",
                path: SiteKeeperCADKernel.CADPath(elements: [
                    .move(to: SiteKeeperCADKernel.CADPoint(x: Double(index), y: 0)),
                    .line(to: SiteKeeperCADKernel.CADPoint(x: Double(index), y: 100))
                ]),
                bounds: SiteKeeperCADKernel.CADBounds(
                    minX: Double(index),
                    minY: 0,
                    maxX: Double(index),
                    maxY: 100
                )
            )
        }
        let textRun = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: "中文",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 10, y: 10),
            style: .default,
            height: 2.5
        )
        let textEntity = SiteKeeperCADKernel.CADEntity(
            kind: .text,
            layerID: "NOTE",
            text: textRun,
            bounds: SiteKeeperCADKernel.CADBounds(minX: 10, minY: 10, maxX: 16, maxY: 13)
        )

        let output = CADPoC.CADRenderPipeline().renderOutput(
            from: lineEntities + [textEntity],
            zoomScale: 10,
            interactionPhase: .stable,
            renderBudget: SiteKeeperCADKernel.CADRenderBudget(maxRenderCommands: 10)
        )

        #expect(output.commands.contains { command in
            if case let .text(text, _) = command {
                return text.displayText == "中文"
            }
            return false
        })
        guard case .text = output.commands.first else {
            Issue.record("Expected stable render priority to emit text before line geometry consumes the budget")
            return
        }
    }

    @Test func cadTextSearchIndexReturnsEntityBoundsForZoomTarget() throws {
        let textRun = SiteKeeperCADKernel.CADTextEngine().makeTextRun(
            rawText: "A区消防泵房",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 120, y: 80),
            style: .default,
            height: 3
        )
        let textBounds = SiteKeeperCADKernel.CADBounds(minX: 120, minY: 80, maxX: 142, maxY: 84)
        let textEntity = SiteKeeperCADKernel.CADEntity(
            kind: .text,
            layerID: "TEXT",
            text: textRun,
            bounds: textBounds,
            sourceHandle: "TXT-SEARCH"
        )
        let database = SiteKeeperCADKernel.CADDatabase(
            file: SiteKeeperCADKernel.CADFile(url: URL(fileURLWithPath: "/tmp/search.dxf"), format: .dxf),
            extents: textBounds,
            layers: [SiteKeeperCADKernel.CADLayer(id: "TEXT", name: "TEXT")],
            layouts: [.modelSpace],
            entities: [textEntity],
            importSource: "sitekeeper.test"
        )

        let result = SiteKeeperCADKernel.CADTextSearchIndex(database: database).search("消防")

        #expect(result.count == 1)
        #expect(result.first?.entityId == textEntity.id)
        #expect(result.first?.bounds.intersects(textBounds) == true)
        #expect(result.first?.targetViewport.clipBounds.intersects(textBounds) == true)
        #expect(result.first?.previewText == "A区消防泵房")
    }

    #if os(iOS)
    @Test func cadMetalPoCSearchFocusProducesVisibleHighlight() throws {
        let line = Self.lineEntity(
            from: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            to: SiteKeeperCADKernel.CADPoint(x: 1_000, y: 0)
        )
        let targetBounds = SiteKeeperCADKernel.CADBounds(minX: 400, minY: -10, maxX: 430, maxY: 10)
        let target = SiteKeeperCADKernel.CADEntity(
            kind: .line,
            layerID: "WALL",
            color: 0xFF2563EB,
            path: SiteKeeperCADKernel.CADPath(elements: [
                .move(to: SiteKeeperCADKernel.CADPoint(x: 400, y: 0)),
                .line(to: SiteKeeperCADKernel.CADPoint(x: 430, y: 0))
            ]),
            bounds: targetBounds,
            sourceHandle: "SEARCH-L1"
        )
        let renderer = CADPoC.CADMetalRenderer()
        renderer.updateDrawing(entities: [line, target], layers: [.default])

        renderer.focusSearchResult(
            entityID: target.id,
            bounds: targetBounds,
            fallbackPoint: targetBounds.center,
            contentScale: 3,
            drawableSize: CGSize(width: 1200, height: 900),
            viewSize: CGSize(width: 400, height: 300)
        )

        #expect(renderer.searchHighlightVertexCountForTesting(
            drawableSize: CGSize(width: 1200, height: 900),
            viewSize: CGSize(width: 400, height: 300),
            contentScale: 3
        ) > 0)
    }
    #endif

    @Test func spatialIndexQueriesViewportLayerAndLayout() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-spatial-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        try Self.basic2DGeometryDXF.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = CADPoC.LibreDWGNativeImportEngine()
        let result = try await engine.importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )

        let index = CADPoC.CADSpatialIndex(entities: result.database.entities)
        let viewport = SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 110, maxY: 60)
        let visible = index.query(viewport)
        let wallVisible = index.query(viewport, layerIDs: ["WALL"])
        let wrongLayoutVisible = index.query(viewport, layoutID: "paper-space")
        let allBounds = SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 220, maxY: 100)
        let allWallVisible = index.query(allBounds, layerIDs: ["WALL"])
        let noLayerVisible = index.query(allBounds, layerIDs: [])

        #expect(index.entityCount == 4)
        #expect(index.indexedEntityCount == 4)
        #expect(visible.count == 2)
        #expect(visible.contains { $0.kind == .line })
        #expect(visible.contains { $0.kind == .circle })
        #expect(wallVisible.count == 1)
        #expect(wallVisible.first?.kind == .line)
        #expect(allWallVisible.count == 2)
        #expect(CADPoC.CADRenderPipeline().commands(from: allWallVisible).count == 2)
        #expect(noLayerVisible.isEmpty)
        #expect(wrongLayoutVisible.isEmpty)
    }

    @Test func libreDWGNativePoCImportsDXFModelAndPaperLayouts() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-layout-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        5
        M1
        8
        MODEL-WALL
        410
        Model
        10
        0
        20
        0
        11
        100
        21
        0
        0
        LINE
        5
        P1
        8
        PAPER-WALL
        67
        1
        410
        Layout1
        10
        1000
        20
        1000
        11
        1100
        21
        1000
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )

        let layoutsByID = Dictionary(uniqueKeysWithValues: result.database.layouts.map { ($0.id, $0) })
        let entitiesByHandle = Dictionary(uniqueKeysWithValues: result.database.entities.compactMap { entity in
            entity.sourceHandle.map { ($0, entity) }
        })
        let index = CADPoC.CADSpatialIndex(entities: result.database.entities)
        let paperViewport = SiteKeeperCADKernel.CADBounds(minX: 990, minY: 990, maxX: 1110, maxY: 1010)
        let paperEntities = index.query(paperViewport, layoutID: "Layout1")
        let modelEntitiesInPaper = index.query(paperViewport, layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id)

        #expect(layoutsByID[SiteKeeperCADKernel.CADLayout.modelSpace.id]?.isModelSpace == true)
        #expect(layoutsByID["Layout1"]?.isModelSpace == false)
        #expect(entitiesByHandle["M1"]?.layoutID == SiteKeeperCADKernel.CADLayout.modelSpace.id)
        #expect(entitiesByHandle["P1"]?.layoutID == "Layout1")
        #expect(paperEntities.compactMap(\.sourceHandle) == ["P1"])
        #expect(modelEntitiesInPaper.isEmpty)

        #if canImport(MetalKit)
        let renderer = CADPoC.CADMetalRenderer()
        renderer.updateDrawing(entities: result.database.entities, layers: result.database.layers)
        #expect(renderer.renderableEntityCountForTesting() == 2)
        renderer.setSelectedLayoutID("Layout1")
        #expect(renderer.renderableEntityCountForTesting() == 1)
        #expect(renderer.modelBoundsForTesting().minX == 1000)
        #expect(renderer.modelBoundsForTesting().maxX == 1100)
        #endif
    }

    @Test func cadMetalRendererExtractsNativeSnapPrimitives() throws {
        let horizontal = SiteKeeperCADKernel.CADEntity(
            kind: .line,
            layerID: "WALL",
            color: 0xFFFF0000,
            lineWeight: 1,
            path: SiteKeeperCADKernel.CADPath(elements: [
                .move(to: SiteKeeperCADKernel.CADPoint(x: 0, y: 0)),
                .line(to: SiteKeeperCADKernel.CADPoint(x: 100, y: 0))
            ]),
            bounds: SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 100, maxY: 0)
        )
        let vertical = SiteKeeperCADKernel.CADEntity(
            kind: .line,
            layerID: "GRID",
            color: 0xFF0000FF,
            lineWeight: 1,
            path: SiteKeeperCADKernel.CADPath(elements: [
                .move(to: SiteKeeperCADKernel.CADPoint(x: 50, y: -20)),
                .line(to: SiteKeeperCADKernel.CADPoint(x: 50, y: 20))
            ]),
            bounds: SiteKeeperCADKernel.CADBounds(minX: 50, minY: -20, maxX: 50, maxY: 20)
        )
        let circle = SiteKeeperCADKernel.CADEntity(
            kind: .circle,
            layerID: "COLUMN",
            color: 0xFF00AA00,
            lineWeight: 1,
            path: SiteKeeperCADKernel.CADPath(elements: [
                .move(to: SiteKeeperCADKernel.CADPoint(x: 120, y: 100)),
                .line(to: SiteKeeperCADKernel.CADPoint(x: 100, y: 120)),
                .line(to: SiteKeeperCADKernel.CADPoint(x: 80, y: 100)),
                .line(to: SiteKeeperCADKernel.CADPoint(x: 100, y: 80)),
                .close
            ]),
            bounds: SiteKeeperCADKernel.CADBounds(minX: 80, minY: 80, maxX: 120, maxY: 120)
        )

        let payloads = CADPoC.CADMetalRenderer.makeSnapPointPayloads(for: [horizontal, vertical, circle])

        #expect(payloads.containsSnap(kind: "endpoint", x: 0, y: 0))
        #expect(payloads.containsSnap(kind: "endpoint", x: 100, y: 0))
        #expect(payloads.containsSnap(kind: "midpoint", x: 50, y: 0))
        #expect(payloads.containsSnap(kind: "center", x: 100, y: 100))
        #expect(payloads.containsSnap(kind: "intersection", x: 50, y: 0))
        #expect(payloads.first { $0.snapKind == "intersection" }?.primitiveKind == "line")
    }

    @Test func cadViewerReconcilesStaleSavedLayerVisibility() throws {
        let layers = [
            CADPoC.CADLayer(id: "WALL", name: "WALL", isVisible: true),
            CADPoC.CADLayer(id: "GRID", name: "GRID", isVisible: false)
        ]

        #expect(CADMetalLibreDWGPoCEntry.defaultVisibleLayerIDs(layers) == Set(["WALL"]))
        #expect(CADMetalLibreDWGPoCEntry.reconciledVisibleLayerIDs(requested: Set(["OLD"]), importedLayers: layers) == Set(["WALL"]))
        #expect(CADMetalLibreDWGPoCEntry.reconciledVisibleLayerIDs(requested: Set(["OLD", "GRID"]), importedLayers: layers) == Set(["GRID"]))
        #expect(CADMetalLibreDWGPoCEntry.reconciledVisibleLayerIDs(requested: Set<String>(), importedLayers: layers) == Set<String>())
    }

    @Test func cadOverlaySnapshotConvertsLegacyCanvasAnnotationsToDrawingCoordinates() throws {
        let transform = CADNativeCanvasTransform(
            bounds: CGRect(x: 100, y: 200, width: 400, height: 300),
            size: CGSize(width: 800, height: 600),
            zoomScale: 1,
            panOffset: .zero
        )
        let noteCanvasPoint = CGPoint(x: 160, y: 180)
        let countCanvasPoint = CGPoint(x: 180, y: 220)
        let issueCanvasPoint = CGPoint(x: 220, y: 260)
        let arrowStart = CGPoint(x: 100, y: 110)
        let arrowEnd = CGPoint(x: 260, y: 170)
        var snapshot = CADOverlaySnapshot()
        snapshot.coordinateSpace = .canvas
        snapshot.arrowAnnotations = [
            CADArrowAnnotation(
                start: CADPoint(arrowStart),
                end: CADPoint(arrowEnd),
                lineWidth: 2,
                colorHex: "2F80ED",
                layerName: "现场批注",
                createdAt: "2026-05-17"
            )
        ]
        snapshot.notes = [
            CADTextNote(
                text: "现场复核",
                point: CADPoint(noteCanvasPoint),
                layoutId: nil,
                worldPoint: nil,
                createdAt: "2026-05-17",
                colorHex: "F2994A"
            )
        ]
        snapshot.countMarkers = [
            CADCountMarker(
                point: CADPoint(countCanvasPoint),
                layoutId: nil,
                worldPoint: nil,
                category: "点位",
                createdAt: "2026-05-17"
            )
        ]
        snapshot.issueMarkers = [
            CADFallbackIssueMarker(
                point: CADPoint(issueCanvasPoint),
                normalizedPoint: CADPoint(CGPoint(x: 0, y: 0)),
                drawingId: nil,
                layoutId: nil,
                worldPoint: nil,
                viewportTransform: nil,
                title: "问题点",
                note: "",
                photoFileName: nil,
                layerName: nil,
                measurementSummary: nil,
                colorHex: "E24A7A",
                createdAt: "2026-05-17"
            )
        ]

        snapshot.convertCanvasPointsToDrawingCoordinates(using: transform)

        #expect(snapshot.coordinateSpace == .drawing)
        Self.expectClose(snapshot.arrowAnnotations[0].start.cgPoint, transform.drawingPoint(fromCanvas: arrowStart))
        Self.expectClose(snapshot.arrowAnnotations[0].end.cgPoint, transform.drawingPoint(fromCanvas: arrowEnd))
        Self.expectClose(snapshot.notes[0].point.cgPoint, transform.drawingPoint(fromCanvas: noteCanvasPoint))
        Self.expectClose(snapshot.notes[0].worldPoint?.cgPoint, transform.drawingPoint(fromCanvas: noteCanvasPoint))
        Self.expectClose(snapshot.countMarkers[0].point.cgPoint, transform.drawingPoint(fromCanvas: countCanvasPoint))
        Self.expectClose(snapshot.countMarkers[0].worldPoint?.cgPoint, transform.drawingPoint(fromCanvas: countCanvasPoint))
        Self.expectClose(snapshot.issueMarkers[0].point.cgPoint, transform.drawingPoint(fromCanvas: issueCanvasPoint))
        Self.expectClose(snapshot.issueMarkers[0].worldPoint?.cgPoint, transform.drawingPoint(fromCanvas: issueCanvasPoint))
        #expect(snapshot.issueMarkers[0].normalizedPoint.x >= 0)
        #expect(snapshot.issueMarkers[0].normalizedPoint.x <= 1)
        #expect(snapshot.issueMarkers[0].normalizedPoint.y >= 0)
        #expect(snapshot.issueMarkers[0].normalizedPoint.y <= 1)
    }

    @Test func libreDWGNativePoCImportsLayerTableVisibilityAndColors() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-layer-table-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        TABLES
        0
        TABLE
        2
        LAYER
        0
        LAYER
        2
        WALL
        70
        0
        62
        1
        370
        35
        6
        HIDDEN
        0
        LAYER
        2
        GRID
        70
        0
        62
        -5
        0
        ENDTAB
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        5
        L1
        8
        WALL
        62
        3
        10
        0
        20
        0
        11
        100
        21
        0
        0
        LINE
        5
        L2
        8
        GRID
        10
        0
        20
        20
        11
        100
        21
        20
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let layersByID = Dictionary(uniqueKeysWithValues: result.database.layers.map { ($0.id, $0) })
        let entitiesByHandle = Dictionary(uniqueKeysWithValues: result.database.entities.compactMap { entity in
            entity.sourceHandle.map { ($0, entity) }
        })
        let visibleLayerIDs = Set(result.database.layers.filter(\.isVisible).map(\.id))
        let visibleEntities = CADPoC.CADSpatialIndex(entities: result.database.entities)
            .query(result.database.extents, layerIDs: visibleLayerIDs)
        let commands = CADPoC.CADRenderPipeline().commands(from: visibleEntities, layersByID: layersByID)

        #expect(result.trace.rawLineCount == 2)
        #expect(result.trace.drawableEntityCount == 2)
        #expect(layersByID["WALL"]?.isVisible == true)
        #expect(layersByID["GRID"]?.isVisible == false)
        #expect(layersByID["WALL"]?.colorARGB == 0xFFFF0000)
        #expect(layersByID["WALL"]?.lineType == "HIDDEN")
        #expect(abs((layersByID["WALL"]?.lineWeight ?? 0) - 0.35) < 0.0001)
        #expect(layersByID["GRID"]?.colorARGB == 0xFF0000FF)
        #expect(entitiesByHandle["L1"]?.color == 0xFF00FF00)
        #expect(entitiesByHandle["L2"]?.color == 0xFF0000FF)
        #expect(visibleEntities.count == 1)
        #expect(visibleEntities.first?.sourceHandle == "L1")
        #expect(commands.count == 1)
        if case let .polyline(_, _, style)? = commands.first {
            #expect(style.colorARGB == 0xFF00FF00)
            #expect(abs(style.lineWidth - 0.35) < 0.0001)
            #expect(style.lineType == "HIDDEN")
        } else {
            Issue.record("Expected a visible WALL polyline render command")
        }
    }

    #if os(iOS)
    @Test func cadMetalPoCRendersDashedLayerLineTypeAsSeparatedSegments() throws {
        let renderer = CADPoC.CADMetalRenderer()
        let path = SiteKeeperCADKernel.CADPath(elements: [
            .move(to: SiteKeeperCADKernel.CADPoint(x: 0, y: 0)),
            .line(to: SiteKeeperCADKernel.CADPoint(x: 500, y: 0))
        ])
        let entity = SiteKeeperCADKernel.CADEntity(
            kind: .line,
            layerID: "HIDDEN_LAYER",
            color: 0x00000000,
            lineType: "ByLayer",
            lineWeight: -1,
            path: path,
            bounds: path.bounds
        )
        let layer = SiteKeeperCADKernel.CADLayer(
            id: "HIDDEN_LAYER",
            name: "HIDDEN_LAYER",
            colorARGB: 0xFFFF0000,
            lineWeight: 0.5,
            lineType: "Hidden"
        )
        renderer.updateDrawing(entities: [entity], layers: [layer])

        let commands = CADPoC.CADRenderPipeline().commands(
            from: [entity],
            layersByID: [layer.id: layer]
        )
        guard case let .polyline(_, _, style)? = commands.first else {
            Issue.record("Expected by-layer line to produce a polyline command")
            return
        }
        #expect(style.colorARGB == 0xFFFF0000)
        #expect(abs(style.lineWidth - 0.5) < 0.0001)
        #expect(style.lineType == "Hidden")

        let dashedVertexCount = renderer.vertexCountForTesting(
            commands: commands,
            drawableSize: CGSize(width: 800, height: 600),
            viewSize: CGSize(width: 400, height: 300),
            contentScale: 2
        )
        let continuousVertexCount = renderer.vertexCountForTesting(
            commands: [
                .polyline(
                    path.points,
                    closed: false,
                    style: SiteKeeperCADKernel.CADRenderStyle(
                        layerID: "HIDDEN_LAYER",
                        colorARGB: 0xFFFF0000,
                        lineWidth: 0.5,
                        lineType: "Continuous"
                    )
                )
            ],
            drawableSize: CGSize(width: 800, height: 600),
            viewSize: CGSize(width: 400, height: 300),
            contentScale: 2
        )

        #expect(continuousVertexCount == 6)
        #expect(dashedVertexCount > continuousVertexCount)
    }
    #endif

    @Test func libreDWGNativePoCExpandsBlockInsertIntoRenderableEntities() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-block-insert-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        BLOCKS
        0
        BLOCK
        2
        DOOR
        10
        0
        20
        0
        0
        LINE
        5
        B1
        8
        0
        10
        0
        20
        0
        11
        10
        21
        0
        0
        ENDBLK
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        INSERT
        5
        I1
        8
        DOOR_LAYER
        2
        DOOR
        10
        100
        20
        50
        41
        2
        42
        2
        50
        90
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entity = try #require(result.database.entities.first)
        let points = try #require(entity.path?.points)
        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)

        #expect(result.trace.rawLineCount == 1)
        #expect(result.trace.entityCount == 1)
        #expect(result.trace.drawableEntityCount == 1)
        #expect(entity.kind == .line)
        #expect(entity.layerID == "DOOR_LAYER")
        #expect(points.count == 2)
        #expect(abs(points[0].x - 100) < 0.0001)
        #expect(abs(points[0].y - 50) < 0.0001)
        #expect(abs(points[1].x - 100) < 0.0001)
        #expect(abs(points[1].y - 70) < 0.0001)
        #expect(result.database.extents.minX >= 99.9999)
        #expect(result.database.extents.maxY <= 70.0001)
        #expect(commands.count == 1)
    }

    @Test func libreDWGNativePoCExpandsNestedBlockInsert() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-nested-block-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        BLOCKS
        0
        BLOCK
        2
        LEAF
        10
        0
        20
        0
        0
        LINE
        5
        N1
        8
        0
        10
        0
        20
        0
        11
        5
        21
        0
        0
        ENDBLK
        0
        BLOCK
        2
        PARENT
        10
        0
        20
        0
        0
        INSERT
        5
        N2
        8
        0
        2
        LEAF
        10
        10
        20
        0
        0
        ENDBLK
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        INSERT
        5
        N3
        8
        NESTED
        2
        PARENT
        10
        100
        20
        0
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entity = try #require(result.database.entities.first)
        let points = try #require(entity.path?.points)

        #expect(result.trace.drawableEntityCount == 1)
        #expect(entity.layerID == "NESTED")
        #expect(abs(points[0].x - 110) < 0.0001)
        #expect(abs(points[0].y - 0) < 0.0001)
        #expect(abs(points[1].x - 115) < 0.0001)
        #expect(abs(points[1].y - 0) < 0.0001)
    }

    @Test func libreDWGNativePoCTransformsInsertAttributesAndInheritsStyle() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-insert-attrib-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        BLOCKS
        0
        BLOCK
        2
        TAG_BLOCK
        10
        0
        20
        0
        0
        LINE
        5
        BA1
        8
        0
        10
        0
        20
        0
        11
        10
        21
        0
        0
        ENDBLK
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        INSERT
        5
        IA1
        8
        TAG_LAYER
        62
        1
        2
        TAG_BLOCK
        10
        100
        20
        50
        41
        2
        42
        2
        50
        90
        0
        ATTRIB
        5
        AT1
        8
        0
        10
        1
        20
        0
        40
        5
        1
        A-101
        0
        SEQEND
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entitiesByHandle = Dictionary(uniqueKeysWithValues: result.database.entities.compactMap { entity in
            entity.sourceHandle.map { ($0, entity) }
        })
        let line = try #require(entitiesByHandle["BA1"])
        let attrib = try #require(entitiesByHandle["AT1"])
        let linePoints = try #require(line.path?.points)
        let text = try #require(attrib.text)

        #expect(result.trace.entityCount == 2)
        #expect(result.trace.drawableEntityCount == 2)
        #expect(line.layerID == "TAG_LAYER")
        #expect(attrib.layerID == "TAG_LAYER")
        #expect(line.color == 0xFFFF0000)
        #expect(attrib.color == 0xFFFF0000)
        #expect(abs(linePoints[1].x - 100) < 0.0001)
        #expect(abs(linePoints[1].y - 70) < 0.0001)
        #expect(attrib.kind == .attrib)
        #expect(attrib.displayText == "A-101")
        #expect(abs(text.insertionPoint.x - 100) < 0.0001)
        #expect(abs(text.insertionPoint.y - 52) < 0.0001)
        #expect(abs(text.rotationRadians - Double.pi / 2) < 0.0001)
        #expect(CADPoC.CADRenderPipeline().commands(from: result.database.entities).contains {
            if case let .text(text, _) = $0 {
                return text.displayText == "A-101"
            }
            return false
        })
    }

    @Test func libreDWGNativePoCRendersATTDEFDefaultWhenInsertHasNoOverride() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-insert-attdef-default-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        BLOCKS
        0
        BLOCK
        2
        ROOM_TAG
        10
        0
        20
        0
        0
        ATTDEF
        5
        AD1
        8
        0
        10
        0
        20
        0
        40
        3
        50
        0
        1
        DEFAULT
        2
        ROOM
        0
        ENDBLK
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        INSERT
        5
        ID1
        8
        TAGS
        2
        ROOM_TAG
        10
        10
        20
        20
        50
        90
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entity = try #require(result.database.entities.first)
        let text = try #require(entity.text)

        #expect(result.trace.entityCount == 1)
        #expect(result.trace.drawableEntityCount == 1)
        #expect(entity.kind == .attrib)
        #expect(entity.layerID == "TAGS")
        #expect(entity.displayText == "DEFAULT")
        #expect(abs(text.insertionPoint.x - 10) < 0.0001)
        #expect(abs(text.insertionPoint.y - 20) < 0.0001)
        #expect(abs(text.rotationRadians - Double.pi / 2) < 0.0001)
        #expect(CADPoC.CADRenderPipeline().commands(from: result.database.entities).count == 1)
    }

    @Test func libreDWGNativePoCAttachedATTRIBOverridesMatchingATTDEF() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-insert-attrib-overrides-attdef-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        BLOCKS
        0
        BLOCK
        2
        ROOM_TAG
        10
        0
        20
        0
        0
        ATTDEF
        5
        AD2
        8
        0
        10
        0
        20
        0
        40
        3
        1
        DEFAULT
        2
        ROOM
        0
        ENDBLK
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        INSERT
        5
        ID2
        8
        TAGS
        2
        ROOM_TAG
        10
        100
        20
        50
        0
        ATTRIB
        5
        AT2
        8
        0
        10
        0
        20
        0
        40
        3
        1
        A-101
        2
        ROOM
        0
        SEQEND
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let texts = result.database.entities.compactMap(\.text)

        #expect(result.trace.entityCount == 1)
        #expect(result.trace.drawableEntityCount == 1)
        #expect(texts.map(\.displayText) == ["A-101"])
        #expect(!texts.contains { $0.displayText == "DEFAULT" })
        #expect(result.database.entities.first?.sourceHandle == "AT2")
    }

    @Test func libreDWGNativePoCExpandsMInsertArray() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-minsert-array-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        BLOCKS
        0
        BLOCK
        2
        GRID_MARK
        10
        0
        20
        0
        0
        LINE
        5
        GL1
        8
        0
        10
        0
        20
        0
        11
        5
        21
        0
        0
        ENDBLK
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        MINSERT
        5
        MI1
        8
        GRID
        2
        GRID_MARK
        10
        10
        20
        10
        70
        2
        71
        2
        44
        20
        45
        30
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let starts = result.database.entities.compactMap { $0.path?.points.first }
            .sorted { lhs, rhs in
                lhs.y == rhs.y ? lhs.x < rhs.x : lhs.y < rhs.y
            }

        #expect(result.trace.entityCount == 4)
        #expect(result.trace.drawableEntityCount == 4)
        #expect(result.trace.renderCommandCount == 4)
        #expect(starts.map { Int($0.x.rounded()) } == [10, 30, 10, 30])
        #expect(starts.map { Int($0.y.rounded()) } == [10, 10, 40, 40])
        #expect(result.database.extents.maxX == 35)
        #expect(result.database.extents.maxY == 40)
    }

    @Test func libreDWGNativePoCReportsMissingBlockInsertAsUnsupported() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-missing-block-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        INSERT
        5
        IM1
        8
        ISSUE
        2
        MISSING_BLOCK
        10
        5
        20
        6
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entity = try #require(result.database.entities.first)

        #expect(result.trace.entityCount == 1)
        #expect(result.trace.drawableEntityCount == 0)
        #expect(result.trace.renderCommandCount == 1)
        #expect(!result.trace.openedForRender)
        #expect(entity.kind == .unsupported)
        #expect(entity.unsupportedReason == "Referenced block is missing.")
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_INSERT_BLOCK_MISSING" })
    }

    @Test func libreDWGNativePoCReportsXrefInsertWithoutCountingDrawableGeometry() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-xref-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        BLOCKS
        0
        BLOCK
        2
        SITE_XREF
        70
        4
        1
        site-plan.dwg
        10
        0
        20
        0
        0
        ENDBLK
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        INSERT
        5
        XR1
        8
        XREF_LAYER
        2
        SITE_XREF
        10
        500
        20
        600
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entity = try #require(result.database.entities.first)
        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)

        #expect(result.trace.entityCount == 1)
        #expect(result.trace.drawableEntityCount == 0)
        #expect(result.database.placeholderEntityCount == 1)
        #expect(!result.trace.openedForRender)
        #expect(entity.kind == .xref)
        #expect(entity.layerID == "XREF_LAYER")
        #expect(entity.unsupportedReason?.contains("XREF SITE_XREF") == true)
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_XREF_NOT_LOADED" })
        #expect(commands.isEmpty)
    }

    @Test func libreDWGNativePoCRendersSimpleHatchFill() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-hatch-fill-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        HATCH
        5
        H1
        8
        HATCH
        10
        0
        20
        0
        10
        50
        20
        0
        10
        50
        20
        30
        10
        0
        20
        30
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entity = try #require(result.database.entities.first)
        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)

        #expect(result.trace.rawHatchCount == 1)
        #expect(result.trace.drawableEntityCount == 1)
        #expect(result.trace.openedForRender)
        #expect(entity.kind == .hatch)
        #expect(entity.path?.points.count == 4)
        #expect(result.database.extents == SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 50, maxY: 30))
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_HATCH_SIMPLE_FILL" })
        #expect(commands.count == 1)
        if case let .hatch(path, _)? = commands.first {
            let points = path.points
            #expect(points.count == 4)
            #expect(path.elements.contains {
                if case .close = $0 { return true }
                return false
            })
        } else {
            Issue.record("Expected HATCH fill command")
        }
    }

    @Test func libreDWGNativePoCShowsComplexHatchBoundaryOnly() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-hatch-complex-boundary-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        HATCH
        5
        H3
        8
        HATCH
        91
        2
        92
        1
        10
        0
        20
        0
        10
        80
        20
        0
        10
        80
        20
        40
        10
        0
        20
        40
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entity = try #require(result.database.entities.first)
        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)

        #expect(result.trace.rawHatchCount == 1)
        #expect(result.trace.drawableEntityCount == 1)
        #expect(result.trace.openedForRender)
        #expect(entity.kind == .hatch)
        #expect(entity.path?.points.count == 4)
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_HATCH_COMPLEX_BOUNDARY_DEGRADED" })
        #expect(commands.count == 1)
        if case let .polyline(points, closed, _)? = commands.first {
            #expect(points.count == 4)
            #expect(closed)
        } else {
            Issue.record("Expected complex HATCH boundary polyline command")
        }
    }

    @Test func renderPipelineFallsBackLargeHatchToBoundary() {
        let points = (0..<80).map { index in
            let angle = Double(index) / 80.0 * Double.pi * 2
            return SiteKeeperCADKernel.CADPoint(
                x: cos(angle) * 100,
                y: sin(angle) * 100
            )
        }
        let path = SiteKeeperCADKernel.CADPath(
            elements: [.move(to: points[0])] + points.dropFirst().map { .line(to: $0) } + [.close]
        )
        let entity = SiteKeeperCADKernel.CADEntity(
            kind: .hatch,
            layerID: "HATCH",
            path: path,
            bounds: path.bounds
        )

        let commands = CADPoC.CADRenderPipeline().commands(from: [entity])

        #expect(commands.count == 1)
        if case let .polyline(polylinePoints, closed, _)? = commands.first {
            #expect(polylinePoints.count == 80)
            #expect(closed)
        } else {
            Issue.record("Expected oversized HATCH to render as boundary polyline")
        }
    }

    @Test func libreDWGNativePoCKeepsUnresolvedHatchUnsupported() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-hatch-unsupported-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        HATCH
        5
        H2
        8
        HATCH
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entity = try #require(result.database.entities.first)
        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)

        #expect(result.trace.rawHatchCount == 1)
        #expect(result.trace.entityCount == 1)
        #expect(result.trace.drawableEntityCount == 0)
        #expect(result.trace.renderCommandCount == 0)
        #expect(!result.trace.openedForRender)
        #expect(entity.kind == .unsupported)
        #expect(entity.unsupportedReason == "HATCH boundary cannot be resolved by the CAD Metal PoC.")
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_HATCH_BOUNDARY_UNRESOLVED" })
        #expect(commands.isEmpty)
    }

    @Test func libreDWGNativePoCTessellatesEllipseToRenderablePath() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-ellipse-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        ELLIPSE
        5
        E1
        8
        CURVE
        10
        100
        20
        50
        11
        20
        21
        0
        40
        0.5
        41
        0
        42
        6.283185307179586
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entity = try #require(result.database.entities.first)
        let points = try #require(entity.path?.points)
        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)

        #expect(result.trace.rawEllipseCount == 1)
        #expect(result.trace.drawableEntityCount == 1)
        #expect(result.trace.openedForRender)
        #expect(entity.kind == .ellipse)
        #expect(points.count >= 16)
        #expect(abs(entity.bounds.minX - 80) < 0.0001)
        #expect(abs(entity.bounds.maxX - 120) < 0.0001)
        #expect(abs(entity.bounds.minY - 40) < 0.0001)
        #expect(abs(entity.bounds.maxY - 60) < 0.0001)
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_ELLIPSE_TESSELLATED" })
        #expect(commands.count == 1)
        if case let .polyline(points, closed, _)? = commands.first {
            #expect(points.count >= 16)
            #expect(closed)
        } else {
            Issue.record("Expected tessellated ELLIPSE polyline command")
        }
    }

    @Test func libreDWGNativePoCDegradesSplineToPolyline() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-spline-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        SPLINE
        5
        S1
        8
        CURVE
        70
        0
        10
        0
        20
        0
        10
        20
        20
        10
        10
        40
        20
        0
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entity = try #require(result.database.entities.first)
        let points = try #require(entity.path?.points)
        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)

        #expect(result.trace.rawSplineCount == 1)
        #expect(result.trace.drawableEntityCount == 1)
        #expect(entity.kind == .spline)
        #expect(points.count == 3)
        #expect(result.database.extents == SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 40, maxY: 10))
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_SPLINE_DEGRADED_TO_POLYLINE" })
        #expect(commands.count == 1)
        if case let .polyline(points, closed, _)? = commands.first {
            #expect(points.count == 3)
            #expect(!closed)
        } else {
            Issue.record("Expected degraded SPLINE polyline command")
        }
    }

    @Test func libreDWGNativePoCKeepsUnresolvedSplineUnsupported() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-spline-unsupported-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        SPLINE
        5
        S2
        8
        CURVE
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entity = try #require(result.database.entities.first)
        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)

        #expect(result.trace.rawSplineCount == 1)
        #expect(result.trace.entityCount == 1)
        #expect(result.trace.drawableEntityCount == 0)
        #expect(result.trace.renderCommandCount == 0)
        #expect(!result.trace.openedForRender)
        #expect(entity.kind == .unsupported)
        #expect(entity.unsupportedReason == "SPLINE control points cannot be resolved by the CAD Metal PoC.")
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_SPLINE_POINTS_UNRESOLVED" })
        #expect(commands.isEmpty)
    }

    @Test func libreDWGNativePoCSimplifiesDimensionToLineAndText() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-dimension-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        DIMENSION
        5
        D1
        8
        DIM
        13
        0
        23
        0
        14
        100
        24
        0
        11
        50
        21
        10
        42
        100
        1
        <>
        40
        5
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entity = try #require(result.database.entities.first)
        let points = try #require(entity.path?.points)
        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)

        #expect(result.trace.rawDimensionCount == 1)
        #expect(result.trace.entityCount == 1)
        #expect(result.trace.drawableEntityCount == 1)
        #expect(result.trace.openedForRender)
        #expect(entity.kind == .dimension)
        #expect(entity.displayText == "100")
        #expect(points.count == 4)
        #expect(points[0] == SiteKeeperCADKernel.CADPoint(x: 0, y: 0))
        #expect(points[1] == SiteKeeperCADKernel.CADPoint(x: 0, y: 10))
        #expect(points[2] == SiteKeeperCADKernel.CADPoint(x: 100, y: 10))
        #expect(points[3] == SiteKeeperCADKernel.CADPoint(x: 100, y: 0))
        #expect(result.database.extents.minX == 0)
        #expect(result.database.extents.maxX >= 100)
        #expect(result.database.extents.maxY >= 12.5)
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_DIMENSION_SIMPLIFIED" })
        #expect(commands.count == 4)
        #expect(commands.contains { command in
            if case .polyline = command {
                return true
            }
            return false
        })
        #expect(commands.filter { command in
            if case .hatch = command {
                return true
            }
            return false
        }.count == 2)
        let arrowTipPoints = commands.compactMap { command -> SiteKeeperCADKernel.CADPoint? in
            guard case let .hatch(path, _) = command else { return nil }
            return path.points.first
        }
        #expect(arrowTipPoints.contains(SiteKeeperCADKernel.CADPoint(x: 0, y: 10)))
        #expect(arrowTipPoints.contains(SiteKeeperCADKernel.CADPoint(x: 100, y: 10)))
        #expect(commands.contains { command in
            if case .text = command {
                return true
            }
            return false
        })
    }

    @Test func libreDWGNativePoCKeepsUnresolvedDimensionUnsupported() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-dimension-unsupported-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        DIMENSION
        5
        D2
        8
        DIM
        1
        <>
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await CADPoC.LibreDWGNativeImportEngine().importDrawingWithTrace(
            file: SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        )
        let entity = try #require(result.database.entities.first)
        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)

        #expect(result.trace.rawDimensionCount == 1)
        #expect(result.trace.entityCount == 1)
        #expect(result.trace.drawableEntityCount == 0)
        #expect(!result.trace.openedForRender)
        #expect(entity.kind == .unsupported)
        #expect(entity.unsupportedReason == "DIMENSION geometry cannot be resolved by the CAD Metal PoC.")
        #expect(result.database.diagnostics.entries.contains { $0.code == "CAD_POC_DIMENSION_GEOMETRY_UNRESOLVED" })
        #expect(commands.isEmpty)
    }

    @Test func renderPipelineAppliesLODWhileInteracting() throws {
        let tinyLine = Self.lineEntity(
            from: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            to: SiteKeeperCADKernel.CADPoint(x: 0.1, y: 0)
        )
        let mainLine = Self.lineEntity(
            from: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            to: SiteKeeperCADKernel.CADPoint(x: 100, y: 0)
        )
        let pipeline = CADPoC.CADRenderPipeline()

        let stableCommands = pipeline.commands(
            from: [tinyLine, mainLine],
            zoomScale: 1,
            interactionPhase: .stable
        )
        let interactiveCommands = pipeline.commands(
            from: [tinyLine, mainLine],
            zoomScale: 1,
            interactionPhase: .zooming
        )

        #expect(stableCommands.count == 2)
        #expect(interactiveCommands.count == 1)
    }

    @Test func renderPipelineKeepsZoomedInStableGeometryForLargeDrawings() throws {
        let microLine = Self.lineEntity(
            from: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
            to: SiteKeeperCADKernel.CADPoint(x: 0.01, y: 0)
        )
        let pipeline = CADPoC.CADRenderPipeline()

        let zoomedInStableCommands = pipeline.commands(
            from: [microLine],
            totalEntityCount: 100_000,
            zoomScale: 100,
            interactionPhase: .stable
        )
        let zoomedOutStableCommands = pipeline.commands(
            from: [microLine],
            totalEntityCount: 100_000,
            zoomScale: 0.01,
            interactionPhase: .stable
        )

        #expect(zoomedInStableCommands.count == 1)
        #expect(zoomedOutStableCommands.isEmpty)
    }

    @Test func renderPipelineStandardBudgetCoversLargeVisiblePlan() throws {
        let entityCount = 25_000
        let entities = (0..<entityCount).map { index in
            Self.lineEntity(
                from: SiteKeeperCADKernel.CADPoint(x: 0, y: Double(index)),
                to: SiteKeeperCADKernel.CADPoint(x: 100, y: Double(index))
            )
        }

        let output = CADPoC.CADRenderPipeline().renderOutput(from: entities)

        #expect(output.commands.count == entityCount)
        #expect(output.performance.renderCommandCount == entityCount)
        #expect(output.performance.skippedEntityCount == 0)
    }

    #if os(iOS)
    @Test func cadMetalPoCProgressivelyRendersLargeVisibleViewport() throws {
        let entityCount = 2_500
        let entities = (0..<entityCount).map { index in
            Self.lineEntity(
                from: SiteKeeperCADKernel.CADPoint(x: 0, y: Double(index)),
                to: SiteKeeperCADKernel.CADPoint(x: 100, y: Double(index))
            )
        }
        let viewport = entities.reduce(SiteKeeperCADKernel.CADBounds.empty) {
            $0.union(CADPoC.CADSpatialIndex.effectiveBounds(for: $1))
        }
        let renderer = CADPoC.CADMetalRenderer()
        renderer.updateDrawing(entities: entities, layers: [.default])

        let firstFrame = renderer.progressiveRenderOutputForTesting(
            visibleEntities: entities,
            viewportBounds: viewport,
            zoomScale: 1,
            phase: .stable
        )
        let secondFrame = renderer.progressiveRenderOutputForTesting(
            visibleEntities: entities,
            viewportBounds: viewport,
            zoomScale: 1,
            phase: .stable
        )

        #expect(firstFrame.commands.count < entityCount)
        #expect(secondFrame.commands.count > firstFrame.commands.count)
        #expect(firstFrame.performance.skippedEntityCount > 0)
        #expect(firstFrame.performance.warnings.contains("CAD_POC_PROGRESSIVE_RENDERING"))
    }
    #endif

    @Test func renderPipelineHonorsRenderBudgetAndReportsTrace() throws {
        let entities = [
            Self.lineEntity(
                from: SiteKeeperCADKernel.CADPoint(x: 0, y: 0),
                to: SiteKeeperCADKernel.CADPoint(x: 100, y: 0)
            ),
            Self.lineEntity(
                from: SiteKeeperCADKernel.CADPoint(x: 0, y: 10),
                to: SiteKeeperCADKernel.CADPoint(x: 100, y: 10)
            ),
            Self.lineEntity(
                from: SiteKeeperCADKernel.CADPoint(x: 0, y: 20),
                to: SiteKeeperCADKernel.CADPoint(x: 100, y: 20)
            )
        ]
        let output = CADPoC.CADRenderPipeline().renderOutput(
            from: entities,
            renderBudget: SiteKeeperCADKernel.CADRenderBudget(maxRenderCommands: 2)
        )

        #expect(output.commands.count == 2)
        #expect(output.performance.entityCount == 3)
        #expect(output.performance.visibleEntityCount == 3)
        #expect(output.performance.renderCommandCount == 2)
        #expect(output.performance.drawCallCount == 2)
        #expect(output.performance.skippedEntityCount == 1)
        #expect(output.performance.warnings.contains("CAD_POC_RENDER_BUDGET_EXCEEDED"))
    }

    @Test func libreDWGNativePoCReusesParsedImportCacheForSecondOpen() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-dxf-cache-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        5
        CACHED-L1
        8
        CACHE
        10
        0
        20
        0
        11
        100
        21
        0
        0
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = CADPoC.LibreDWGNativeImportEngine()
        let file = SiteKeeperCADKernel.CADFile(url: url, format: .dxf)
        let first = try await engine.importDrawingWithTrace(file: file)
        let second = try await engine.importDrawingWithTrace(file: file)

        #expect(!first.trace.importCacheHit)
        #expect(second.trace.importCacheHit)
        #expect(second.trace.entityCount == first.trace.entityCount)
        #expect(second.trace.drawableEntityCount == first.trace.drawableEntityCount)
        #expect(second.database.entities.map(\.sourceHandle) == first.database.entities.map(\.sourceHandle))
    }

    @Test func libreDWGNativePoCUsesInAppLibreDWGForDWGAndDoesNotPromoteEmptyGeometry() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-dwg-native-invalid-\(UUID().uuidString)")
            .appendingPathExtension("dwg")
        try Data("AC1032\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = CADPoC.LibreDWGNativeImportEngine()
        let file = SiteKeeperCADKernel.CADFile(url: url, format: .dwg)
        let result = try await engine.importDrawingWithTrace(file: file)
        let commands = CADPoC.CADRenderPipeline().commands(from: result.database.entities)

        #expect(engine.canImport(file: file))
        #expect(result.trace.importSource == "sitekeeper.poc.dwg-libredwg-ios.basic2d-v2")
        #expect(result.trace.drawableEntityCount == 0)
        #expect(result.trace.renderCommandCount == 0)
        #expect(!result.trace.openedForRender)
        #expect(!result.database.geometryParsed)
        #expect(result.database.isMetadataOnly)
        #expect(result.database.entities.isEmpty)
        #expect(commands.isEmpty)
        #expect(result.database.diagnostics.entries.contains {
            $0.code == "CAD_POC_LIBREDWG_IOS_NATIVE_USED"
        })
    }

    private static let twoLineDXF = """
    0
    SECTION
    2
    ENTITIES
    0
    LINE
    5
    A1
    8
    WALL
    10
    0
    20
    0
    11
    100
    21
    50
    0
    LINE
    5
    A2
    8
    GRID
    10
    -20
    20
    80
    11
    60
    21
    80
    0
    ENDSEC
    0
    EOF
    """

    private static let workerLineJSON = makeWorkerLineJSON(layerID: "WALL", maxX: 100, maxY: 50)

    private static let workerBasic2DJSON = """
    {
      "schema": "sitekeeper-cad-worker-v1",
      "drawingId": "44444444-4444-4444-4444-444444444444",
      "importSource": "sitekeeper.dwg.libredwg.line-worker",
      "geometryParsed": true,
      "isMetadataOnly": false,
      "units": { "name": "unitless" },
      "extents": { "minX": 0, "minY": 0, "maxX": 200, "maxY": 80 },
      "layers": [
        { "id": "WALL", "name": "WALL", "isVisible": true },
        { "id": "GRID", "name": "GRID", "isVisible": true },
        { "id": "CURVE", "name": "CURVE", "isVisible": true }
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
          "id": "44444444-4444-4444-4444-444444444401",
          "type": "line",
          "layerID": "WALL",
          "start": { "x": 0, "y": 0 },
          "end": { "x": 100, "y": 50 },
          "bounds": { "minX": 0, "minY": 0, "maxX": 100, "maxY": 50 },
          "sourceHandle": "A1"
        },
        {
          "id": "44444444-4444-4444-4444-444444444402",
          "type": "lwPolyline",
          "layerID": "WALL",
          "points": [
            { "x": 120, "y": 0 },
            { "x": 200, "y": 0 },
            { "x": 200, "y": 40 }
          ],
          "isClosed": true,
          "bounds": { "minX": 120, "minY": 0, "maxX": 200, "maxY": 40 },
          "sourceHandle": "P1"
        },
        {
          "id": "44444444-4444-4444-4444-444444444403",
          "type": "circle",
          "layerID": "GRID",
          "points": [
            { "x": 40, "y": 30 },
            { "x": 30, "y": 40 },
            { "x": 20, "y": 30 },
            { "x": 30, "y": 20 }
          ],
          "isClosed": true,
          "bounds": { "minX": 20, "minY": 20, "maxX": 40, "maxY": 40 },
          "sourceHandle": "C1"
        },
        {
          "id": "44444444-4444-4444-4444-444444444404",
          "type": "arc",
          "layerID": "CURVE",
          "points": [
            { "x": 160, "y": 70 },
            { "x": 157, "y": 77 },
            { "x": 150, "y": 80 }
          ],
          "bounds": { "minX": 150, "minY": 70, "maxX": 160, "maxY": 80 },
          "sourceHandle": "R1"
        }
      ],
      "xrefs": [],
      "importWarnings": []
    }
    """

    private static func makeWorkerLineJSON(layerID: String, maxX: Double, maxY: Double) -> String {
        """
    {
      "schema": "sitekeeper-cad-worker-v1",
      "drawingId": "11111111-1111-1111-1111-111111111111",
      "importSource": "sitekeeper.dwg.libredwg",
      "geometryParsed": true,
      "isMetadataOnly": false,
      "units": { "name": "unitless" },
      "extents": { "minX": 0, "minY": 0, "maxX": \(maxX), "maxY": \(maxY) },
      "layers": [
        { "id": "\(layerID)", "name": "\(layerID)", "isVisible": true }
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
          "id": "22222222-2222-2222-2222-222222222222",
          "type": "line",
          "layerID": "\(layerID)",
          "start": { "x": 0, "y": 0 },
          "end": { "x": \(maxX), "y": \(maxY) },
          "bounds": { "minX": 0, "minY": 0, "maxX": \(maxX), "maxY": \(maxY) },
          "sourceHandle": "A1"
        }
      ],
      "xrefs": [],
      "importWarnings": []
    }
    """
    }

    private static let workerDiagnosticOnlyJSON = """
    {
      "schema": "sitekeeper-cad-worker-v1",
      "drawingId": "33333333-3333-3333-3333-333333333333",
      "importSource": "sitekeeper.dwg.libredwg",
      "geometryParsed": false,
      "isMetadataOnly": true,
      "units": { "name": "unitless" },
      "extents": { "minX": 0, "minY": 0, "maxX": 0, "maxY": 0 },
      "layers": [
        { "id": "0", "name": "0", "isVisible": true }
      ],
      "layouts": [
        { "id": "model", "name": "Model", "isModelSpace": true }
      ],
      "blocks": [],
      "entities": [],
      "xrefs": [],
      "importWarnings": [
        "No drawable geometry was produced by the external worker."
      ]
    }
    """

    private static func expectClose(_ actual: CGPoint?, _ expected: CGPoint, tolerance: CGFloat = 0.0001) {
        guard let actual else {
            Issue.record("Expected point \(expected), got nil")
            return
        }
        #expect(abs(actual.x - expected.x) <= tolerance)
        #expect(abs(actual.y - expected.y) <= tolerance)
    }

    private static func lineEntity(
        from start: SiteKeeperCADKernel.CADPoint,
        to end: SiteKeeperCADKernel.CADPoint
    ) -> SiteKeeperCADKernel.CADEntity {
        let path = SiteKeeperCADKernel.CADPath(elements: [
            .move(to: start),
            .line(to: end)
        ])
        return SiteKeeperCADKernel.CADEntity(
            kind: .line,
            layerID: "WALL",
            color: 0xFF1F2937,
            path: path,
            bounds: path.bounds
        )
    }

    private static var gb18030Encoding: String.Encoding {
        String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
    }

    private static var big5Encoding: String.Encoding {
        String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue)
            )
        )
    }

    private static func encodedBytes(_ text: String, using encoding: String.Encoding) -> [UInt8]? {
        text.data(using: encoding).map { Array($0) }
    }

    private static func singleByteString(_ text: String, using encoding: String.Encoding) -> String? {
        guard let data = text.data(using: encoding) else { return nil }
        return String(data: data, encoding: .isoLatin1)
    }

    private static func nativeCString(bytes: [UInt8]) -> UnsafeMutablePointer<CChar> {
        let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count + 1)
        for (index, byte) in bytes.enumerated() {
            pointer[index] = CChar(bitPattern: byte)
        }
        pointer[bytes.count] = 0
        return pointer
    }

    private struct TestDWGGeometryAdapter: SiteKeeperCADKernel.CADDWGGeometryAdapter {
        let id = "sitekeeper.test.dwg.geometry-adapter"

        func canImportDWG(file: SiteKeeperCADKernel.CADFile) -> Bool {
            file.format == .dwg
        }

        func importDWG(file: SiteKeeperCADKernel.CADFile) async throws -> SiteKeeperCADKernel.CADExternalSDKDrawing {
            let start = SiteKeeperCADKernel.CADPoint(x: 0, y: 0)
            let end = SiteKeeperCADKernel.CADPoint(x: 120, y: 60)
            let path = SiteKeeperCADKernel.CADPath(elements: [
                .move(to: start),
                .line(to: end)
            ])
            let entity = SiteKeeperCADKernel.CADEntity(
                kind: .line,
                layerID: "WALL",
                color: 0xFF0A84FF,
                path: path,
                bounds: path.bounds,
                sourceHandle: "ADAPTER-L1"
            )
            let database = SiteKeeperCADKernel.CADDatabase(
                file: file,
                extents: path.bounds,
                layers: [SiteKeeperCADKernel.CADLayer(id: "WALL", name: "WALL")],
                layouts: [.modelSpace],
                entities: [entity],
                importSource: id
            )
            return SiteKeeperCADKernel.CADExternalSDKDrawing(database: database)
    }
}

    private static let basic2DGeometryDXF = """
    0
    SECTION
    2
    ENTITIES
    0
    LINE
    5
    A1
    8
    WALL
    10
    0
    20
    0
    11
    100
    21
    50
    0
    CIRCLE
    8
    IGNORED
    10
    30
    20
    30
    40
    10
    0
    LWPOLYLINE
    5
    A2
    8
    WALL
    70
    1
    10
    120
    20
    0
    10
    200
    20
    0
    10
    200
    20
    40
    0
    ARC
    5
    A3
    8
    CURVE
    10
    150
    20
    70
    40
    10
    50
    0
    51
    90
    0
    ENDSEC
    0
    EOF
    """
}

private extension Array where Element == CADRendererSnapPointPayload {
    func containsSnap(kind: String, x: Double, y: Double, tolerance: CGFloat = 0.0001) -> Bool {
        contains { payload in
            payload.snapKind == kind
                && abs(payload.point.x - CGFloat(x)) <= tolerance
                && abs(payload.point.y - CGFloat(y)) <= tolerance
        }
    }
}
