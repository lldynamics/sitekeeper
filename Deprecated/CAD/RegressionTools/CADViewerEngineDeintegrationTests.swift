import CoreGraphics
import Foundation
import Testing
@testable import sitekeeper

struct CADViewerEngineDeintegrationTests {
    @MainActor
    @Test func unsupportedEngineReturnsExplicitError() async {
        let engine = UnsupportedCADViewerEngine()
        do {
            _ = try await engine.open(file: sampleCADFile())
            #expect(Bool(false))
        } catch let error as CADViewerEngineError {
            #expect(error == .engineNotInstalled)
            #expect(error.errorDescription == "CAD engine is not installed")
        } catch {
            #expect(Bool(false))
        }
    }

    @MainActor
    @Test func cadOpenRouterRoutesDWGToUnsupportedWhenEngineMissing() async {
        CADViewerEngineRegistry.resetToUnsupported()
        let route = await CADOpenRouter.route(for: sampleCADFile())
        switch route {
        case .unsupported(let result):
            #expect(result.message == CADOpenRouter.unsupportedOnlineOpenMessage)
            #expect(result.openState == .failed || result.openState == .unsupported)
        case .online:
            #expect(Bool(false))
        }
    }

    @MainActor
    @Test func cadRendererBootstrapRegistersSiteKeeperCADKernel() async {
        CADRendererBootstrap.configure()
        defer {
            CADRendererProvider.clearRenderer()
            CADViewerEngineRegistry.resetToUnsupported()
        }

        #expect(CADRendererProvider.isRendererBound)
        #expect(CADViewerEngineRegistry.isInstalled)

        let route = await CADOpenRouter.route(for: sampleCADFile())
        switch route {
        case .unsupported(let result):
            #expect(result.openState == .diagnosticOnly)
            #expect(result.message == CADViewerMessages.onlinePreviewUnavailableMessage)
            #expect(!result.message.localizedCaseInsensitiveContains("importengine"))
            #expect(!result.message.localizedCaseInsensitiveContains("adapter"))
            #expect(!result.message.localizedCaseInsensitiveContains("caddatabase"))
        case .online:
            #expect(Bool(false))
        }
    }

    @MainActor
    @Test func cadRendererProviderOpensRenderableDXFFixtureThroughSiteKeeperKernel() async throws {
        CADRendererBootstrap.configure()
        defer {
            CADRendererProvider.clearRenderer()
            CADViewerEngineRegistry.resetToUnsupported()
        }

        let fixtureURL = repoRoot()
            .appendingPathComponent("samples/cad/fixtures/simple_site_plan.dxf")
        let fileSize = try FileManager.default
            .attributesOfItem(atPath: fixtureURL.path)[.size] as? NSNumber
        let cadFile = sampleCADFile(
            fileType: "dxf",
            fileURL: fixtureURL,
            displayName: fixtureURL.lastPathComponent,
            fileSizeBytes: fileSize?.intValue ?? 0
        )

        let route = await CADOpenRouter.route(for: cadFile)
        switch route {
        case .online(let result):
            #expect(result.supportsOnlineView)
            #expect(result.openState == .rendered)
            #expect(result.drawingId == cadFile.drawingId)
        case .unsupported(let result):
            Issue.record("DXF fixture should open through SiteKeeperCADKernel, got unsupported: \(result.message)")
        }

        let renderer = CADRendererProvider.renderer(
            for: fixtureURL,
            preferredTextCodePage: nil,
            preferredTextBigFont: nil,
            callbacks: CADRendererCallbacks()
        )
        #expect(renderer != nil)

        let kernelEngine = SiteKeeperCADKernel.SiteKeeperCADViewerEngine()
        let openResult = try await kernelEngine.open(file: SiteKeeperCADKernel.CADFile(url: fixtureURL))
        #expect(openResult.status == .rendered)
        let database = try #require(openResult.database)
        #expect(database.entities.count >= 6)

        let viewportBounds = database.extents.expanded(by: 100)
        let frame = try await kernelEngine.render(
            viewport: SiteKeeperCADKernel.CADViewport(
                id: "test-dxf-fixture",
                layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id,
                viewCenter: viewportBounds.center,
                viewHeight: max(viewportBounds.height, 1),
                clipBounds: viewportBounds
            ),
            options: SiteKeeperCADKernel.CADRenderOptions(
                layoutID: SiteKeeperCADKernel.CADLayout.modelSpace.id,
                viewportBounds: viewportBounds
            )
        )
        #expect(!frame.commands.isEmpty)
        #expect(frame.commands.contains { command in
            if case .text = command { return true }
            return false
        })
        #expect(frame.textTraces.contains { $0.displayText.contains("一层配电箱") })
    }

    @Test func diagnosticOnlyRouteDoesNotEnterInteractiveCanvas() {
        let diagnosticRoute = CADOpenRoute.unsupported(
            CADOpenResult(
                drawingId: UUID(),
                openState: .diagnosticOnly,
                message: CADViewerMessages.onlinePreviewUnavailableMessage,
                technicalDetails: nil
            )
        )
        let unsupportedRoute = CADOpenRoute.unsupported(
            CADOpenResult(
                drawingId: UUID(),
                openState: .unsupported,
                message: CADViewerMessages.onlinePreviewUnavailableMessage,
                technicalDetails: nil
            )
        )
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
                route: diagnosticRoute
            ) == false
        )
        #expect(
            CADPreviewContainer.shouldEnterInteractiveCADCanvas(
                isCADFile: true,
                rendererBound: true,
                route: unsupportedRoute
            ) == false
        )
        #expect(
            CADPreviewContainer.shouldEnterInteractiveCADCanvas(
                isCADFile: true,
                rendererBound: true,
                route: renderedRoute
            )
        )
    }

    @Test func formalUnavailableMessageDoesNotLeakTechnicalTerms() {
        let message = CADViewerMessages.onlinePreviewUnavailableMessage.lowercased()
        #expect(CADViewerMessages.onlinePreviewUnavailableMessage == "当前图纸暂不支持在线预览，可下载原图查看。")
        #expect(!message.contains("importengine"))
        #expect(!message.contains("adapter"))
        #expect(!message.contains("caddatabase"))
        #expect(!message.contains("geometry"))
        #expect(!message.contains("diagnostics"))
        #expect(!message.contains("内核已接管"))
    }

    @Test func technicalDiagnosticsCanBeEnabledForDebugOrInternalSwitch() {
        #expect(CADTechnicalDiagnosticsVisibility.isEnabled(isDebugBuild: true, internalSwitchOn: false))
        #expect(CADTechnicalDiagnosticsVisibility.isEnabled(isDebugBuild: false, internalSwitchOn: true))
        #expect(CADTechnicalDiagnosticsVisibility.isEnabled(isDebugBuild: false, internalSwitchOn: false) == false)
    }

    @MainActor
    @Test func previewDrawingURLStillWorksForExistingFile() throws {
        let fileName = "\(UUID().uuidString).dwg"
        let fileURL = DrawingStorage.fileURL(for: fileName)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("dwg".utf8).write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let drawing = ProjectDrawing(
            projectId: UUID(),
            name: "测试图纸",
            fileName: fileName,
            fileType: "dwg"
        )
        switch ProjectDetailAssetActions.previewDrawingURL(for: drawing) {
        case .success(let resolvedURL):
            #expect(resolvedURL.path == fileURL.path)
        case .failure:
            #expect(Bool(false))
        }
    }

    @Test func overlayAndIssueModelsRemainAvailable() {
        let drawingId = UUID()
        var snapshot = CADOverlaySnapshot()
        snapshot.issueMarkers.append(
            CADFallbackIssueMarker(
                point: CADPoint(CGPoint(x: 12, y: 34)),
                normalizedPoint: CADPoint(CGPoint(x: 0.25, y: 0.5)),
                drawingId: drawingId,
                layoutId: "model",
                worldPoint: CADPoint(CGPoint(x: 12, y: 34)),
                viewportTransform: nil,
                title: "问题点 1",
                note: "",
                photoFileName: nil,
                colorHex: "E24A7A",
                createdAt: "2026-05-14 00:00:00"
            )
        )
        #expect(snapshot.issueMarkers.count == 1)
        #expect(snapshot.issueMarkers[0].drawingId == drawingId)
        #expect(snapshot.issueMarkers[0].layoutId == "model")
        #expect(snapshot.issueMarkers[0].worldPoint == CADPoint(CGPoint(x: 12, y: 34)))
    }

    @Test func productionSourcesDoNotReferenceRemovedCADBridge() throws {
        let root = repoRoot()
        let productionFiles = [
            root.appendingPathComponent("project.yml"),
            root.appendingPathComponent("sitekeeper.xcodeproj/project.pbxproj")
        ]
        let removedBridgeToken = "libre" + "dwgbridge"
        let removedRendererToken = "libre" + "dwgcanvasrenderer"

        for file in productionFiles {
            let content = try String(contentsOf: file, encoding: .utf8).lowercased()
            #expect(!content.contains(removedBridgeToken))
            #expect(!content.contains(removedRendererToken))
        }

        let sourcesRoot = root.appendingPathComponent("Sources")
        let enumerator = FileManager.default.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let content = try String(contentsOf: fileURL, encoding: .utf8).lowercased()
            #expect(!content.contains("import " + removedBridgeToken))
            #expect(!content.contains(removedRendererToken))
            #expect(!content.contains(removedBridgeToken))
        }
    }

    private func sampleCADFile(
        fileType: String = "dwg",
        fileURL: URL? = nil,
        displayName: String? = nil,
        fileSizeBytes: Int = 1024
    ) -> CADFile {
        let resolvedURL = fileURL ?? URL(fileURLWithPath: "/tmp/sample.\(fileType)")
        return CADFile(
            id: UUID(),
            projectId: UUID(),
            drawingId: UUID(),
            fileURL: resolvedURL,
            displayName: displayName ?? resolvedURL.lastPathComponent,
            fileType: fileType,
            importedAt: "2026-05-14 00:00:00",
            fileSizeBytes: fileSizeBytes
        )
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
