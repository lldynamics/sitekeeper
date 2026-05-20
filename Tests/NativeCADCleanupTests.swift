import Foundation
import Testing
@testable import sitekeeper

struct NativeCADCleanupTests {
    @Test func productionCADRouteUsesNativeCADViewerEntry() throws {
        let root = try Self.repositoryRoot()
        let routeSource = try Self.sourceText(root, "Sources/Features/项目/CADViewerRoute.swift")
        #expect(routeSource.contains("struct CADViewerRoute"))
        #expect(routeSource.contains("NativeCADViewerEntry("))
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
        let chromeSource = try Self.sourceText(root, "Sources/Features/项目/CADPreviewContainer+Chrome.swift")
        #expect(toolbarSource.contains("ShareLink(item: fileURL)"))
        #expect(toolbarSource.contains("下载原图"))
        #expect(toolbarSource.contains("用其他软件打开"))
        #expect(chromeSource.contains("用其他软件打开"))
        #expect(chromeSource.contains("showShareSheet = true"))
    }

    @Test func nativeCADOptionalDetailFeaturesDefaultToPerformanceMode() throws {
        let defaults = CADCanvasFeatureOptions.performanceDefault
        #expect(defaults.rendersTextOverlays == true)
        #expect(defaults.publishesSnapPoints == false)
        #expect(defaults.rendersHatches == false)
        #expect(defaults.rendersPlaceholders == false)
        #expect(defaults.enabledCount == 1)

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
        #expect(defaults.allows(.text(text, style: style)))
        #expect(defaults.allows(.hatch(hatchPath, style: style)) == false)
        #expect(defaults.allows(.unsupportedPlaceholder(entityID: "P1", bounds: .empty, reason: "proxy")) == false)
        #expect(defaults.allows(SiteKeeperCADKernel.CADEntity(kind: .line, path: hatchPath, bounds: hatchPath.bounds)))
        #expect(defaults.allows(SiteKeeperCADKernel.CADEntity(kind: .hatch, path: hatchPath, bounds: hatchPath.bounds)) == false)
        #expect(defaults.allows(SiteKeeperCADKernel.CADEntity(kind: .image, bounds: hatchPath.bounds, unsupportedReason: "placeholder")) == false)
        #expect(CADCanvasFeatureOptions.fullDetail.allows(.text(text, style: style)))
        #expect(CADCanvasFeatureOptions.fullDetail.allows(.hatch(hatchPath, style: style)))
        #expect(CADCanvasFeatureOptions.fullDetail.allows(.unsupportedPlaceholder(entityID: "P1", bounds: .empty, reason: "proxy")))
        #expect(CADCanvasFeatureOptions.fullDetail.allows(SiteKeeperCADKernel.CADEntity(kind: .hatch, path: hatchPath, bounds: hatchPath.bounds)))

        let root = try Self.repositoryRoot()
        let chromeSource = try Self.sourceText(root, "Sources/Features/项目/CADPreviewContainer+Chrome.swift")
        let toolbarSource = try Self.sourceText(root, "Sources/Shared/CAD/Viewer/CADViewerToolbar.swift")
        #expect(chromeSource.contains("cadPerformanceMenu"))
        #expect(toolbarSource.contains("文字显示"))
        #expect(toolbarSource.contains("文字搜索索引"))
        #expect(toolbarSource.contains("吸附点"))
        #expect(toolbarSource.contains("填充细节"))
        #expect(toolbarSource.contains("占位对象"))
        #expect(toolbarSource.contains("兼容渲染") == false)
        #expect(chromeSource.contains("toggleCADCoreGraphicsRenderer") == false)
        #expect(chromeSource.contains("cadDrawingLayoutMenu"))
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

    @Test func cadDiagnosticEventsUseStructuredRuntimeLogInsteadOfPrint() throws {
        NativeCAD.CADDiagnosticLog.removeAllForTesting()
        NativeCAD.CADDiagnosticLog.recordEncoded(
            category: "cad.test",
            message: "structured diagnostic event",
            payload: ["stage": "render", "state": "captured"]
        )

        let entry = try #require(NativeCAD.CADDiagnosticLog.recentEntries(limit: 1).first)
        #expect(entry.category == "cad.test")
        #expect(entry.message == "structured diagnostic event")
        #expect(entry.payloadJSON?.contains("\"stage\":\"render\"") == true)

        let root = try Self.repositoryRoot()
        let productionDiagnosticSources = [
            "Sources/Shared/CAD/Import/LibreDWGNativeImportEngine.swift",
            "Sources/Shared/CAD/Render/CADCanvasView.swift",
            "Sources/Shared/CAD/Render/CADMetalRenderer.swift"
        ]
        for sourcePath in productionDiagnosticSources {
            let source = try Self.sourceText(root, sourcePath)
            #expect(source.containsDirectDebugLoggingCall == false)
        }
    }

    @Test func cadCoreRendererAndImportMinimumPathRemainUsable() async throws {
        let file = SiteKeeperCADKernel.CADFile(
            url: URL(fileURLWithPath: "/tmp/cad-native.json"),
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

        let commands = NativeCAD.CADRenderPipeline().commands(from: database.entities)
        #expect(commands.isEmpty == false)

        let dxfURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cad-native-\(UUID().uuidString)")
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

private extension String {
    var containsDirectDebugLoggingCall: Bool {
        split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("print(")
                || trimmed.hasPrefix("debugPrint(")
                || trimmed.hasPrefix("NSLog(")
        }
    }
}
