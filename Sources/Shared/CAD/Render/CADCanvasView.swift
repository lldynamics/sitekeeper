import Foundation
import SwiftUI

struct CADCanvasControlCommand: Equatable, Identifiable {
    enum Kind: Equatable {
        case zoomIn
        case zoomOut
        case fitToView
        case focusSearchResult(
            entityID: SiteKeeperCADKernel.CADEntity.ID,
            bounds: SiteKeeperCADKernel.CADBounds,
            fallbackPoint: SiteKeeperCADKernel.CADPoint
        )
        case clearSearchHighlight
    }

    let id: UUID
    let kind: Kind

    init(kind: Kind) {
        self.id = UUID()
        self.kind = kind
    }
}

struct CADCanvasFeatureOptions: Equatable {
    var rendersTextOverlays: Bool
    var rendersLineTypes: Bool
    var rendersLineWeights: Bool
    var rendersDimensionDetails: Bool
    var publishesSnapPoints: Bool
    var publishesSnapIntersections: Bool
    var rendersHatchBoundaries: Bool
    var rendersHatches: Bool
    var rendersPlaceholders: Bool

    static let performanceDefault = CADCanvasFeatureOptions(
        rendersTextOverlays: true,
        rendersLineTypes: false,
        rendersLineWeights: false,
        rendersDimensionDetails: false,
        publishesSnapPoints: false,
        publishesSnapIntersections: false,
        rendersHatchBoundaries: false,
        rendersHatches: false,
        rendersPlaceholders: false
    )

    static let fullDetail = CADCanvasFeatureOptions(
        rendersTextOverlays: true,
        rendersLineTypes: true,
        rendersLineWeights: true,
        rendersDimensionDetails: true,
        publishesSnapPoints: true,
        publishesSnapIntersections: true,
        rendersHatchBoundaries: true,
        rendersHatches: true,
        rendersPlaceholders: true
    )

    var enabledCount: Int {
        [
            rendersTextOverlays,
            rendersLineTypes,
            rendersLineWeights,
            rendersDimensionDetails,
            publishesSnapPoints,
            publishesSnapIntersections,
            rendersHatchBoundaries,
            rendersHatches,
            rendersPlaceholders
        ].filter { $0 }.count
    }

    func allows(_ command: SiteKeeperCADKernel.CADRenderCommand) -> Bool {
        switch command {
        case .text:
            return rendersTextOverlays
        case .hatch:
            return rendersHatchBoundaries || rendersHatches
        case .imagePlaceholder, .unsupportedPlaceholder:
            return rendersPlaceholders
        default:
            return true
        }
    }

    func allows(_ entity: SiteKeeperCADKernel.CADEntity) -> Bool {
        if !rendersHatchBoundaries, !rendersHatches, entity.kind == .hatch {
            return false
        }
        if !rendersPlaceholders,
           SiteKeeperCADKernel.CADDatabase.isPlaceholderEntity(entity) {
            return false
        }
        if !rendersPlaceholders {
            switch entity.kind {
            case .image, .table, .xref, .proxy, .unsupported:
                return false
            default:
                break
            }
        }
        if !rendersTextOverlays {
            switch entity.kind {
            case .text, .mtext, .attrib:
                return false
            default:
                break
            }
        }
        return true
    }
}

struct CADCanvasTextImportOptions: Equatable {
    var preferredTextCodePage: Int32?
    var preferredTextBigFont: Int32?
    var fontMappings: [CADRendererFontMapping]
    var preferredDisplayFontName: String?

    init(
        preferredTextCodePage: Int32? = nil,
        preferredTextBigFont: Int32? = nil,
        fontMappings: [CADRendererFontMapping] = [],
        preferredDisplayFontName: String? = nil
    ) {
        self.preferredTextCodePage = preferredTextCodePage
        self.preferredTextBigFont = preferredTextBigFont
        self.fontMappings = fontMappings
        self.preferredDisplayFontName = preferredDisplayFontName
    }

    static let automatic = CADCanvasTextImportOptions(
        preferredTextCodePage: nil,
        preferredTextBigFont: nil,
        fontMappings: [],
        preferredDisplayFontName: nil
    )
}

#if os(iOS) && canImport(MetalKit)
import MetalKit
import UIKit

struct CADCanvasView: UIViewRepresentable {
    let fileURL: URL
    let selectedLayoutID: String?
    let visibleLayerIDs: Set<String>?
    let initialViewState: CADRendererViewState?
    let controlCommand: CADCanvasControlCommand?
    let featureOptions: CADCanvasFeatureOptions
    let textImportOptions: CADCanvasTextImportOptions
    let buildsTextSearchIndex: Bool
    let debugTextOverlays: Bool
    let callbacks: CADRendererCallbacks
    let onLayoutsChanged: ([CADPoC.CADLayout]) -> Void
    let onLayersChanged: ([CADPoC.CADLayer]) -> Void
    let onSearchIndexChanged: (SiteKeeperCADKernel.CADTextSearchIndex?) -> Void

    init(
        fileURL: URL,
        selectedLayoutID: String? = nil,
        visibleLayerIDs: Set<String>? = nil,
        initialViewState: CADRendererViewState? = nil,
        controlCommand: CADCanvasControlCommand? = nil,
        featureOptions: CADCanvasFeatureOptions = .performanceDefault,
        textImportOptions: CADCanvasTextImportOptions = .automatic,
        buildsTextSearchIndex: Bool = false,
        debugTextOverlays: Bool = false,
        callbacks: CADRendererCallbacks = CADRendererCallbacks(),
        onLayoutsChanged: @escaping ([CADPoC.CADLayout]) -> Void = { _ in },
        onLayersChanged: @escaping ([CADPoC.CADLayer]) -> Void = { _ in },
        onSearchIndexChanged: @escaping (SiteKeeperCADKernel.CADTextSearchIndex?) -> Void = { _ in }
    ) {
        self.fileURL = fileURL
        self.selectedLayoutID = selectedLayoutID
        self.visibleLayerIDs = visibleLayerIDs
        self.initialViewState = initialViewState
        self.controlCommand = controlCommand
        self.featureOptions = featureOptions
        self.textImportOptions = textImportOptions
        self.buildsTextSearchIndex = buildsTextSearchIndex
        self.debugTextOverlays = debugTextOverlays
        self.callbacks = callbacks
        self.onLayoutsChanged = onLayoutsChanged
        self.onLayersChanged = onLayersChanged
        self.onSearchIndexChanged = onSearchIndexChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let renderer = context.coordinator.renderer
        let view = MTKView(frame: .zero, device: renderer.device)
        view.backgroundColor = .systemBackground
        view.clearColor = MTLClearColor(red: 0.972, green: 0.976, blue: 0.984, alpha: 1)
        view.colorPixelFormat = renderer.colorPixelFormat
        view.delegate = renderer
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.framebufferOnly = true
        view.contentMode = .redraw

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)

        context.coordinator.view = view
        DispatchQueue.main.async {
            view.setNeedsDisplay()
        }
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.onLayoutsChanged = onLayoutsChanged
        context.coordinator.onLayersChanged = onLayersChanged
        context.coordinator.onSearchIndexChanged = onSearchIndexChanged
        context.coordinator.callbacks = callbacks
        context.coordinator.renderer.callbacks = callbacks
        context.coordinator.renderer.setSelectedLayoutID(selectedLayoutID)
        context.coordinator.renderer.setVisibleLayerIDs(visibleLayerIDs)
        context.coordinator.renderer.setFeatureOptions(featureOptions)
        context.coordinator.setBuildsTextSearchIndex(buildsTextSearchIndex)
        context.coordinator.renderer.setDebugTextOverlays(debugTextOverlays)
        context.coordinator.renderer.applyInitialViewStateIfNeeded(initialViewState, contentScale: uiView.contentScaleFactor)
        context.coordinator.applyControlCommandIfNeeded(controlCommand, in: uiView)
        context.coordinator.loadIfNeeded(fileURL: fileURL, textImportOptions: textImportOptions)
        uiView.setNeedsDisplay()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let renderer = CADPoC.CADMetalRenderer()
        weak var view: MTKView?
        private struct LoadedImportKey: Equatable {
            var fileURL: URL
            var textImportOptions: CADCanvasTextImportOptions
        }

        private var loadedImportKey: LoadedImportKey?
        private var importTask: Task<Void, Never>?
        private var lastTrace: CADPoC.CADOpenTrace?
        private var lastDatabase: SiteKeeperCADKernel.CADDatabase?
        private var lastPinchLocation: CGPoint?
        private var lastControlCommandID: UUID?
        private var buildsTextSearchIndex = false
        var callbacks = CADRendererCallbacks()
        var onLayoutsChanged: ([CADPoC.CADLayout]) -> Void = { _ in }
        var onLayersChanged: ([CADPoC.CADLayer]) -> Void = { _ in }
        var onSearchIndexChanged: (SiteKeeperCADKernel.CADTextSearchIndex?) -> Void = { _ in }

        deinit {
            importTask?.cancel()
        }

        func loadIfNeeded(fileURL: URL, textImportOptions: CADCanvasTextImportOptions) {
            let importKey = LoadedImportKey(fileURL: fileURL, textImportOptions: textImportOptions)
            guard loadedImportKey != importKey else { return }
            loadedImportKey = importKey
            importTask?.cancel()
            importTask = Task { [weak self] in
                let file = SiteKeeperCADKernel.CADFile(url: fileURL)
                let engine = CADPoC.LibreDWGNativeImportEngine(
                    preferredTextCodePage: textImportOptions.preferredTextCodePage,
                    preferredTextBigFont: textImportOptions.preferredTextBigFont,
                    fontMappings: textImportOptions.fontMappings,
                    preferredDisplayFontName: textImportOptions.preferredDisplayFontName
                )
                guard engine.canImport(file: file) else {
                    self?.applyUnsupportedTrace(file: file, source: engine.id)
                    return
                }

                do {
                    let result = try await engine.importDrawingWithTrace(file: file)
                    self?.applyImportResult(result)
                } catch {
                    self?.applyUnsupportedTrace(file: file, source: engine.id)
                }
            }
        }

        @MainActor
        private func applyImportResult(_ result: CADPoC.CADImportResult) {
            lastTrace = result.trace
            lastDatabase = result.database
            renderer.setOpenTrace(result.trace)
            callbacks.onOpenTraceChange(result.trace)
            logTrace(result.trace)
            logTextTrace(result.database.textTrace, fileName: result.trace.fileName)
            onLayoutsChanged(result.database.layouts)
            onLayersChanged(result.database.layers)
            publishSearchIndex()
            guard result.trace.openedForRender else {
                renderer.updateDrawing(entities: [], layers: [])
                view?.setNeedsDisplay()
                return
            }
            renderer.updateDrawing(entities: result.database.entities, layers: result.database.layers)
            view?.setNeedsDisplay()
        }

        @MainActor
        private func applyUnsupportedTrace(file: SiteKeeperCADKernel.CADFile, source: String) {
            let trace = CADPoC.CADOpenTrace.unsupported(fileName: file.displayName, importSource: source)
            lastTrace = trace
            lastDatabase = nil
            renderer.setOpenTrace(trace)
            callbacks.onOpenTraceChange(trace)
            logTrace(trace)
            onLayoutsChanged([])
            onLayersChanged([])
            onSearchIndexChanged(nil)
            renderer.updateDrawing(entities: [], layers: [])
            view?.setNeedsDisplay()
        }

        @MainActor
        func setBuildsTextSearchIndex(_ enabled: Bool) {
            guard buildsTextSearchIndex != enabled else { return }
            buildsTextSearchIndex = enabled
            publishSearchIndex()
        }

        @MainActor
        private func publishSearchIndex() {
            guard buildsTextSearchIndex, let lastDatabase else {
                onSearchIndexChanged(nil)
                return
            }
            onSearchIndexChanged(SiteKeeperCADKernel.CADTextSearchIndex(database: lastDatabase))
        }

        func applyControlCommandIfNeeded(_ command: CADCanvasControlCommand?, in view: MTKView) {
            guard let command, command.id != lastControlCommandID else { return }
            lastControlCommandID = command.id
            let anchor = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            switch command.kind {
            case .zoomIn:
                renderer.applyZoomStep(
                    factor: 2.0,
                    anchorPoint: anchor,
                    contentScale: view.contentScaleFactor,
                    drawableSize: view.drawableSize,
                    viewSize: view.bounds.size
                )
            case .zoomOut:
                renderer.applyZoomStep(
                    factor: 1 / 2.0,
                    anchorPoint: anchor,
                    contentScale: view.contentScaleFactor,
                    drawableSize: view.drawableSize,
                    viewSize: view.bounds.size
                )
            case .fitToView:
                renderer.fitToView()
            case let .focusSearchResult(entityID, bounds, fallbackPoint):
                renderer.focusSearchResult(
                    entityID: entityID,
                    bounds: bounds,
                    fallbackPoint: fallbackPoint,
                    contentScale: view.contentScaleFactor,
                    drawableSize: view.drawableSize,
                    viewSize: view.bounds.size
                )
            case .clearSearchHighlight:
                renderer.clearSearchHighlight()
            }
            renderer.setInteractionPhase(.stable)
            view.setNeedsDisplay()
        }

        private func logTrace(_ trace: CADPoC.CADOpenTrace) {
            CADPoC.CADDiagnosticLog.recordEncoded(
                category: "cad.openTrace",
                message: "CAD open trace captured.",
                payload: trace
            )
        }

        private func logTextTrace(_ traces: [SiteKeeperCADKernel.CADTextTrace], fileName: String) {
            guard !traces.isEmpty else { return }
            struct TextTraceSample: Codable {
                var entityId: String
                var entityType: String
                var rawText: String
                var decodedText: String
                var displayText: String
                var textStyleName: String
                var fontFile: String?
                var bigFontFile: String?
                var selectedFontName: String
                var fontWasAvailable: Bool
                var warnings: [String]
            }

            let samples = traces.prefix(32).map {
                TextTraceSample(
                    entityId: $0.entityId,
                    entityType: $0.entityType,
                    rawText: $0.rawText,
                    decodedText: $0.decodedText,
                    displayText: $0.displayText,
                    textStyleName: $0.textStyleName,
                    fontFile: $0.fontFile,
                    bigFontFile: $0.bigFontFile,
                    selectedFontName: $0.selectedFontName,
                    fontWasAvailable: $0.fontWasAvailable,
                    warnings: $0.warnings
                )
            }

            CADPoC.CADDiagnosticLog.recordEncoded(
                category: "cad.textTrace",
                message: "CAD text trace captured.",
                payload: samples,
                coalescingKey: "cad.textTrace.\(fileName)"
            )
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let view else { return }
            updateInteractionPhase(for: recognizer)
            let delta = recognizer.translation(in: view)
            renderer.applyPan(deltaPoints: delta, contentScale: view.contentScaleFactor)
            recognizer.setTranslation(.zero, in: view)
            finishInteractionIfNeeded(for: recognizer)
            view.setNeedsDisplay()
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let view else { return }
            updateInteractionPhase(for: recognizer)
            let location = recognizer.location(in: view)
            if let lastPinchLocation {
                renderer.applyPan(
                    deltaPoints: CGPoint(
                        x: location.x - lastPinchLocation.x,
                        y: location.y - lastPinchLocation.y
                    ),
                    contentScale: view.contentScaleFactor
                )
            }
            lastPinchLocation = location
            renderer.applyZoom(
                scale: recognizer.scale,
                anchorPoint: location,
                contentScale: view.contentScaleFactor,
                drawableSize: view.drawableSize,
                viewSize: view.bounds.size
            )
            recognizer.scale = 1
            finishInteractionIfNeeded(for: recognizer)
            view.setNeedsDisplay()
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view else { return }
            renderer.applyDoubleTapZoom(
                anchorPoint: recognizer.location(in: view),
                contentScale: view.contentScaleFactor,
                drawableSize: view.drawableSize,
                viewSize: view.bounds.size
            )
            view.setNeedsDisplay()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        private func updateInteractionPhase(for recognizer: UIGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                renderer.setInteractionPhase(.zooming)
            default:
                break
            }
        }

        private func finishInteractionIfNeeded(for recognizer: UIGestureRecognizer) {
            switch recognizer.state {
            case .ended, .cancelled, .failed:
                renderer.setInteractionPhase(.stable)
                if recognizer is UIPinchGestureRecognizer {
                    lastPinchLocation = nil
                }
            default:
                break
            }
        }
    }
}

#else
struct CADCanvasView: View {
    let fileURL: URL
    var selectedLayoutID: String? = nil
    var visibleLayerIDs: Set<String>? = nil
    var initialViewState: CADRendererViewState? = nil
    var controlCommand: CADCanvasControlCommand? = nil
    var featureOptions: CADCanvasFeatureOptions = .performanceDefault
    var buildsTextSearchIndex: Bool = false
    var debugTextOverlays: Bool = false
    var callbacks: CADRendererCallbacks = CADRendererCallbacks()
    var onLayoutsChanged: ([CADPoC.CADLayout]) -> Void = { _ in }
    var onLayersChanged: ([CADPoC.CADLayer]) -> Void = { _ in }
    var onSearchIndexChanged: (SiteKeeperCADKernel.CADTextSearchIndex?) -> Void = { _ in }

    var body: some View {
        Color.white
    }
}
#endif
