import Foundation
import SwiftUI

#if os(iOS) && canImport(MetalKit)
import MetalKit
import UIKit

struct CADCanvasView: UIViewRepresentable {
    let fileURL: URL

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
        pan.maximumNumberOfTouches = 2
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
        context.coordinator.loadIfNeeded(fileURL: fileURL)
        uiView.setNeedsDisplay()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let renderer = CADPoC.CADMetalRenderer()
        weak var view: MTKView?
        private var loadedFileURL: URL?
        private var importTask: Task<Void, Never>?
        private var lastTrace: CADPoC.CADOpenTrace?

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
            logTrace(result.trace)
            guard result.trace.drawableEntityCount > 0 else {
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
            logTrace(trace)
            renderer.updateEntities([])
            view?.setNeedsDisplay()
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
            let delta = recognizer.translation(in: view)
            renderer.applyPan(deltaPoints: delta, contentScale: view.contentScaleFactor)
            recognizer.setTranslation(.zero, in: view)
            view.setNeedsDisplay()
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard let view else { return }
            renderer.applyZoom(scale: recognizer.scale)
            recognizer.scale = 1
            view.setNeedsDisplay()
        }

        @objc func handleDoubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let view else { return }
            renderer.resetView()
            view.setNeedsDisplay()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

#else
struct CADCanvasView: View {
    let fileURL: URL

    var body: some View {
        Color.white
    }
}
#endif
