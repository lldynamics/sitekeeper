import Foundation
import Testing
@testable import sitekeeper

struct CADPoCLineImportTests {
    @Test func libreDWGNativePoCImportsDXFLineOnly() async throws {
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
        #expect(result.trace.entityCount == 1)
        #expect(result.trace.drawableEntityCount == 1)
        #expect(result.trace.openedForRender)
        #expect(result.database.entities.count == 1)
        #expect(result.database.entities.first?.kind == .line)
        #expect(result.database.entities.first?.layerID == "WALL")
        #expect(result.database.extents == SiteKeeperCADKernel.CADBounds(minX: 0, minY: 0, maxX: 100, maxY: 50))
    }

    @Test func libreDWGNativePoCImportsDWGWhenConvertedDXFArtifactExists() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-dwg-line-poc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let dwgURL = directory.appendingPathComponent("simple.dwg")
        let dxfURL = directory.appendingPathComponent("simple.dxf")
        try Data("AC1032\n".utf8).write(to: dwgURL)
        try Self.twoLineDXF.write(to: dxfURL, atomically: true, encoding: .utf8)

        let engine = CADPoC.LibreDWGNativeImportEngine()
        let dwgFile = SiteKeeperCADKernel.CADFile(url: dwgURL, format: .dwg)

        #expect(engine.canImport(file: dwgFile))

        let result = try await engine.importDrawingWithTrace(file: dwgFile)

        #expect(result.trace.rawLineCount == 2)
        #expect(result.trace.entityCount == 2)
        #expect(result.trace.drawableEntityCount == 2)
        #expect(result.trace.openedForRender)
        #expect(result.trace.importSource.contains("converted-dxf-artifact"))
        #expect(result.database.sourceFile.url == dwgURL)
        #expect(result.database.importSource == result.trace.importSource)
        #expect(result.database.entities.allSatisfy { $0.kind == .line })
        #expect(result.database.extents == SiteKeeperCADKernel.CADBounds(minX: -20, minY: 0, maxX: 100, maxY: 80))
    }

    @Test func libreDWGNativePoCDoesNotImportDWGWithoutConvertedDXFArtifact() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-dwg-no-artifact-\(UUID().uuidString)")
            .appendingPathExtension("dwg")
        try Data("AC1032\n".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = CADPoC.LibreDWGNativeImportEngine()

        #expect(!engine.canImport(file: SiteKeeperCADKernel.CADFile(url: url, format: .dwg)))
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
}
