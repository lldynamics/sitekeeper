import Foundation
import Testing
@testable import sitekeeper

struct CADPoCCleanupTests {
    @Test func productionCADRouteUsesMetalLibreDWGPoC() throws {
        let root = try Self.repositoryRoot()
        let routeSource = try Self.sourceText(root, "Sources/Features/项目/CADViewerRoute.swift")
        #expect(routeSource.contains("struct CADViewerRoute"))
        #expect(routeSource.contains("CADMetalLibreDWGPoCEntry("))
    }

    @Test func productionCADTargetsDoNotReferenceRemovedPreviewRoutes() throws {
        let root = try Self.repositoryRoot()
        let productionText = try [
            root.appendingPathComponent("Sources"),
            root.appendingPathComponent("SiteKeeperCADKernel")
        ].map { try Self.swiftSourceText(under: $0) }.joined(separator: "\n")
        let retiredTerms = [
            "diagnostic" + "Only",
            "CAD" + "TileViewer",
            "Unsupported" + "CADViewerEngine",
            "CAD" + "ConversionPipeline",
            "Sidecar" + "GeometrySource",
            "DWG" + "DiagnosticImportEngine",
            "CAD" + "FallbackViewer"
        ]
        for term in retiredTerms {
            #expect(productionText.contains(term) == false)
        }
    }

    @Test func originalDrawingDownloadActionRemainsAvailable() throws {
        let root = try Self.repositoryRoot()
        let toolbarSource = try Self.sourceText(root, "Sources/Shared/CAD/Viewer/CADViewerToolbar.swift")
        #expect(toolbarSource.contains("ShareLink(item: fileURL)"))
        #expect(toolbarSource.contains("下载原图"))
    }

    @Test func cadPoCOptionalDetailFeaturesDefaultToPerformanceMode() throws {
        let defaults = CADCanvasFeatureOptions.performanceDefault
        #expect(defaults.rendersTextOverlays == false)
        #expect(defaults.publishesSnapPoints == false)
        #expect(defaults.rendersHatches == false)
        #expect(defaults.enabledCount == 0)

        let style = SiteKeeperCADKernel.CADRenderStyle(
            layerID: "0",
            colorARGB: 0xFF000000,
            lineWidth: 1
        )
        let text = SiteKeeperCADKernel.CADTextRun(
            rawText: "中文",
            insertionPoint: SiteKeeperCADKernel.CADPoint(x: 0, y: 0)
        )
        let hatchPath = SiteKeeperCADKernel.CADPath(elements: [
            .move(to: SiteKeeperCADKernel.CADPoint(x: 0, y: 0)),
            .line(to: SiteKeeperCADKernel.CADPoint(x: 10, y: 0)),
            .close
        ])

        #expect(defaults.allows(.polyline([], closed: false, style: style)))
        #expect(defaults.allows(.text(text, style: style)) == false)
        #expect(defaults.allows(.hatch(hatchPath, style: style)) == false)
        #expect(CADCanvasFeatureOptions.fullDetail.allows(.text(text, style: style)))
        #expect(CADCanvasFeatureOptions.fullDetail.allows(.hatch(hatchPath, style: style)))

        let root = try Self.repositoryRoot()
        let hostSource = try Self.sourceText(root, "Sources/Features/项目/CADCanvasHost.swift")
        let toolbarSource = try Self.sourceText(root, "Sources/Shared/CAD/Viewer/CADViewerToolbar.swift")
        #expect(hostSource.contains("cadPerformanceMenu"))
        #expect(toolbarSource.contains("文字显示"))
        #expect(toolbarSource.contains("吸附点"))
        #expect(toolbarSource.contains("填充细节"))
    }

    @Test func drawingBusinessTypesRemainCompilable() {
        let projectId = UUID()
        let drawing = ProjectDrawing(
            projectId: projectId,
            name: "施工图",
            fileName: "floor-plan.dwg",
            fileType: "dwg"
        )
        #expect(drawing.projectId == projectId)
        #expect(drawing.fileName == "floor-plan.dwg")
        #expect(CADDrawingCapability.isCADFile(extension: drawing.fileType))
    }

    @Test func cadCoreRendererAndImportMinimumPathRemainUsable() async throws {
        let file = SiteKeeperCADKernel.CADFile(
            url: URL(fileURLWithPath: "/tmp/cad-poc.json"),
            format: .intermediateJSON
        )
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
        #expect(frame.commands.isEmpty == false)

        let dxfURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-poc-\(UUID().uuidString)")
            .appendingPathExtension("dxf")
        let dxf = """
        0
        SECTION
        2
        ENTITIES
        0
        LINE
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
        ENDSEC
        0
        EOF
        """
        try dxf.write(to: dxfURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dxfURL) }

        let imported = try await SiteKeeperCADKernel.DXFImportEngine().importDrawing(
            file: SiteKeeperCADKernel.CADFile(url: dxfURL, format: .dxf)
        )
        #expect(imported.entities.count == 1)
        #expect(imported.entities.first?.kind == .line)
    }

    private static func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            let projectFile = url.appendingPathComponent("project.yml")
            if FileManager.default.fileExists(atPath: projectFile.path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private static func sourceText(_ root: URL, _ relativePath: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static func swiftSourceText(under directory: URL) throws -> String {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return ""
        }

        var combined = ""
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            combined += try String(contentsOf: fileURL, encoding: .utf8)
            combined += "\n"
        }
        return combined
    }
}
