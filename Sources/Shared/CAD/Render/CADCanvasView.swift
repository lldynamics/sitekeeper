import Foundation
import SwiftUI

struct CADCanvasControlCommand: Equatable, Identifiable {
    enum Kind: Equatable {
        case zoomIn
        case zoomOut
        case fitToView
    }

    let id: UUID
    let kind: Kind

    init(kind: Kind) {
        self.id = UUID()
        self.kind = kind
    }
}

#if os(iOS) && canImport(MetalKit)
import MetalKit
import UIKit

struct CADCanvasView: UIViewRepresentable {
    let fileURL: URL
    let visibleLayerIDs: Set<String>?
    let initialViewState: CADRendererViewState?
    let controlCommand: CADCanvasControlCommand?
    let debugTextOverlays: Bool
    let callbacks: CADRendererCallbacks
    let onLayersChanged: ([CADPoC.CADLayer]) -> Void

    init(
        fileURL: URL,
        visibleLayerIDs: Set<String>? = nil,
        initialViewState: CADRendererViewState? = nil,
        controlCommand: CADCanvasControlCommand? = nil,
        debugTextOverlays: Bool = false,
        callbacks: CADRendererCallbacks = CADRendererCallbacks(),
        onLayersChanged: @escaping ([CADPoC.CADLayer]) -> Void = { _ in }
    ) {
        self.fileURL = fileURL
        self.visibleLayerIDs = visibleLayerIDs
        self.initialViewState = initialViewState
        self.controlCommand = controlCommand
        self.debugTextOverlays = debugTextOverlays
        self.callbacks = callbacks
        self.onLayersChanged = onLayersChanged
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
        context.coordinator.onLayersChanged = onLayersChanged
        context.coordinator.callbacks = callbacks
        context.coordinator.renderer.callbacks = callbacks
        context.coordinator.renderer.setVisibleLayerIDs(visibleLayerIDs)
        context.coordinator.renderer.setDebugTextOverlays(debugTextOverlays)
        context.coordinator.renderer.applyInitialViewStateIfNeeded(initialViewState, contentScale: uiView.contentScaleFactor)
        context.coordinator.applyControlCommandIfNeeded(controlCommand, in: uiView)
        context.coordinator.loadIfNeeded(fileURL: fileURL)
        uiView.setNeedsDisplay()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let renderer = CADPoC.CADMetalRenderer()
        weak var view: MTKView?
        private var loadedFileURL: URL?
        private var importTask: Task<Void, Never>?
        private var lastTrace: CADPoC.CADOpenTrace?
        private var lastPinchLocation: CGPoint?
        private var lastControlCommandID: UUID?
        var callbacks = CADRendererCallbacks()
        var onLayersChanged: ([CADPoC.CADLayer]) -> Void = { _ in }

        deinit {
            importTask?.cancel()
        }

        func loadIfNeeded(fileURL: URL) {
            guard loadedFileURL != fileURL else { return }
            loadedFileURL = fileURL
            importTask?.cancel()
            importTask = Task { [weak self] in
                let file = SiteKeeperCADKernel.CADFile(url: fileURL)
                let engine = CADPoC.LibreDWGNativeImportEngine()
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
            callbacks.onOpenTraceChange(result.trace)
            logTrace(result.trace)
            onLayersChanged(result.database.layers)
            guard result.trace.openedForRender else {
                renderer.updateEntities([])
                view?.setNeedsDisplay()
                return
            }
            renderer.updateEntities(result.database.entities)
            view?.setNeedsDisplay()
        }

        @MainActor
        private func applyUnsupportedTrace(file: SiteKeeperCADKernel.CADFile, source: String) {
            let trace = CADPoC.CADOpenTrace.unsupported(fileName: file.displayName, importSource: source)
            lastTrace = trace
            callbacks.onOpenTraceChange(trace)
            logTrace(trace)
            onLayersChanged([])
            renderer.updateEntities([])
            view?.setNeedsDisplay()
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
            }
            renderer.setInteractionPhase(.stable)
            view.setNeedsDisplay()
        }

        private func logTrace(_ trace: CADPoC.CADOpenTrace) {
            #if DEBUG
            if let data = try? JSONEncoder().encode(trace),
               let json = String(data: data, encoding: .utf8) {
                print("CADOpenTrace \(json)")
            }
            #endif
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
    var visibleLayerIDs: Set<String>? = nil
    var initialViewState: CADRendererViewState? = nil
    var controlCommand: CADCanvasControlCommand? = nil
    var callbacks: CADRendererCallbacks = CADRendererCallbacks()
    var onLayersChanged: ([CADPoC.CADLayer]) -> Void = { _ in }

    var body: some View {
        Color.white
    }
}
#endif
