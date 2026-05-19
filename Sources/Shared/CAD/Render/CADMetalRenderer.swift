#if canImport(MetalKit)
import Foundation
import CoreText
import Metal
import MetalKit
import simd
#if os(iOS)
import UIKit
#endif

extension CADPoC {
    final class CADMetalRenderer: NSObject, MTKViewDelegate {
        typealias Kernel = SiteKeeperCADKernel

        let device: MTLDevice?
        let deviceName: String?
        let colorPixelFormat: MTLPixelFormat = .bgra8Unorm
        private(set) var lastFrameTrace = Kernel.CADPerformanceTrace()

        private let commandQueue: MTLCommandQueue?
        private let renderPipelineState: MTLRenderPipelineState?
        private let textRenderPipelineState: MTLRenderPipelineState?
        private var allRenderableEntities: [Kernel.CADEntity]
        private var entities: [Kernel.CADEntity]
        private var layersByID: [String: Kernel.CADLayer]
        private var spatialIndex: CADSpatialIndex
        private var modelBounds: Kernel.CADBounds
        private var progressiveRenderState: ProgressiveRenderState?
        private var drawingRevision = 0
        private var totalLayerCount = 0
        private var totalTextEntityCount = 0
        private var indexedTextEntityCount = 0
        private var openTraceDiagnosticRows: [String] = []
        private var featureOptions: CADCanvasFeatureOptions = .performanceDefault

        private var userZoom: Double = 1
        private var panOffsetPixels = SIMD2<Double>(0, 0)
        private var interactionPhase: Kernel.CADRenderInteractionPhase = .stable
        private var firstFrameStart = Date()
        private var didRenderFirstFrame = false
        private var visibleLayerIDs: Set<String>?
        private var selectedLayoutID: String?
        private var highlightedSearchEntityID: Kernel.CADEntity.ID?
        private var highlightedSearchBounds: Kernel.CADBounds?
        private var lastPublishedSnapPoints: [CADRendererSnapPointPayload] = []
        private let minimumUserZoom = 0.05
        private let maximumUserZoom = 4096.0
        private let pinchZoomAcceleration = 2.4
        private let doubleTapZoomFactor = 3.6
        private let maximumFilledHatchPointCount = 96
        private let progressiveVisibleEntityThreshold = 2_000
        private let progressiveEntityBatchSize = 1_000
        private let progressiveCommandCacheLimit = 80_000
        private let snapVisibleEntityLimit = 4_000
        var callbacks = CADRendererCallbacks()
        private var didApplyInitialViewState = false
        private var debugTextOverlays = false
        #if os(iOS)
        private var textOverlayMarkers: [String: UIView] = [:]
        private var textRasterCache = CADTextRasterCache()
        private var textAtlasTextureCache = CADTextAtlasTextureCache()
        private var currentTextAtlasTextCount = 0
        private var currentTextAtlasSkippedTextCount = 0
        private var textOverlayLabels: [String: UILabel] = [:]
        private var currentUIKitTextLabelCount = 0
        private var currentUIKitTextLabelSkippedCount = 0
        #endif

        private struct ProgressiveRenderKey: Equatable {
            var drawingRevision: Int
            var viewportMinX: Int64
            var viewportMinY: Int64
            var viewportMaxX: Int64
            var viewportMaxY: Int64
            var zoomBucket: Int64
            var visibleLayerKey: String
            var visibleEntityCount: Int
        }

        private struct ProgressiveRenderState {
            var key: ProgressiveRenderKey
            var commands: [Kernel.CADRenderCommand] = []
            var nextEntityOffset: Int = 0
            var completed = false
            var warnings: Set<String> = []
        }

        private struct FrameRenderPlan {
            var output: CADPoC.CADRenderPipeline.Output
            var needsContinuation: Bool
        }

        private struct TextViewportDiagnostics {
            var textWorldBounds: Kernel.CADBounds = .empty
            var visibleLayerTextWorldBounds: Kernel.CADBounds = .empty
            var nearestTextBounds: Kernel.CADBounds = .empty
            var nearestTextDistance: Double?
            var nearestTextPreview: String?
            var nearestTextLayerID: String?
            var detailRows: [String] = []
        }

        private struct TextOverlayFingerprint {
            var text: String
            var layerID: String
            var sourceHandle: String?
            var insertionPoint: Kernel.CADPoint
            var bounds: Kernel.CADBounds
            var rotationRadians: Double
        }

        private struct VisibleTextOverlayFrame {
            var text: String
            var rect: CGRect
            var rotationRadians: Double
        }

        override init() {
            let device = MTLCreateSystemDefaultDevice()
            self.device = device
            self.deviceName = device?.name
            self.commandQueue = device?.makeCommandQueue()
            self.allRenderableEntities = []
            self.entities = []
            self.layersByID = [:]
            self.spatialIndex = CADSpatialIndex()
            self.modelBounds = .empty
            self.renderPipelineState = Self.makeRenderPipelineState(
                device: device,
                colorPixelFormat: .bgra8Unorm
            )
            self.textRenderPipelineState = Self.makeTextRenderPipelineState(
                device: device,
                colorPixelFormat: .bgra8Unorm
            )
            super.init()
        }

        var isAvailable: Bool {
            device != nil && commandQueue != nil && renderPipelineState != nil && textRenderPipelineState != nil
        }

        func resetView() {
            userZoom = 1
            panOffsetPixels = SIMD2<Double>(0, 0)
            interactionPhase = .stable
            didApplyInitialViewState = false
            progressiveRenderState = nil
        }

        func fitToView() {
            userZoom = 1
            panOffsetPixels = SIMD2<Double>(0, 0)
            interactionPhase = .stable
            didApplyInitialViewState = true
            progressiveRenderState = nil
        }

        func updateEntities(_ importedEntities: [Kernel.CADEntity]) {
            updateDrawing(entities: importedEntities, layers: Array(layersByID.values))
        }

        func updateDrawing(entities importedEntities: [Kernel.CADEntity], layers: [Kernel.CADLayer]) {
            layersByID = Dictionary(uniqueKeysWithValues: layers.map { ($0.id, $0) })
            totalLayerCount = max(layersByID.count, 1)
            allRenderableEntities = importedEntities.filter { entity in
                switch entity.kind {
                case .line, .point, .polyline, .lwPolyline, .circle, .arc, .ellipse, .spline, .hatch, .dimension, .text, .mtext, .attrib, .image, .table:
                    return entity.isRenderable
                default:
                    return false
                }
            }
            rebuildDrawingForCurrentLayout(resetViewState: true)
        }

        private func rebuildDrawingForCurrentLayout(resetViewState: Bool) {
            entities = entitiesForSelectedLayout()
            spatialIndex = CADSpatialIndex(entities: entities)
            totalTextEntityCount = entities.filter(Self.isTextEntity).count
            indexedTextEntityCount = spatialIndex.query(.empty).filter(Self.isTextEntity).count
            modelBounds = fitModelBounds(for: entities)
            drawingRevision += 1
            progressiveRenderState = nil
            firstFrameStart = Date()
            didRenderFirstFrame = false
            lastFrameTrace = Kernel.CADPerformanceTrace(entityCount: entities.count)
            lastPublishedSnapPoints.removeAll()
            clearSearchHighlight()
            #if os(iOS)
            textRasterCache.removeAll()
            textAtlasTextureCache.removeAll()
            currentTextAtlasTextCount = 0
            currentTextAtlasSkippedTextCount = 0
            clearTextOverlayLabels()
            #endif
            if resetViewState {
                resetView()
            }
        }

        private func entitiesForSelectedLayout() -> [Kernel.CADEntity] {
            guard let selectedLayoutID else { return allRenderableEntities }
            return allRenderableEntities.filter { $0.layoutID == selectedLayoutID }
        }

        func applyInitialViewStateIfNeeded(_ state: CADRendererViewState?, contentScale: CGFloat) {
            guard !didApplyInitialViewState, let state else { return }
            userZoom = clampedZoom(Double(state.zoomScale))
            panOffsetPixels = SIMD2<Double>(
                Double(state.panOffset.width * contentScale),
                Double(state.panOffset.height * contentScale)
            )
            if state.usesSavedVisibleLayers {
                visibleLayerIDs = Set(state.visibleLayerNames)
            }
            didApplyInitialViewState = true
        }

        func applyPan(deltaPoints: CGPoint, contentScale: CGFloat) {
            panOffsetPixels.x += Double(deltaPoints.x * contentScale)
            panOffsetPixels.y += Double(deltaPoints.y * contentScale)
            progressiveRenderState = nil
        }

        func applyZoom(scale: CGFloat) {
            guard scale.isFinite, scale > 0 else { return }
            userZoom = clampedZoom(userZoom * acceleratedZoomDelta(for: Double(scale)))
            progressiveRenderState = nil
        }

        func applyZoom(
            scale: CGFloat,
            anchorPoint: CGPoint,
            contentScale: CGFloat,
            drawableSize: CGSize,
            viewSize: CGSize
        ) {
            guard scale.isFinite, scale > 0 else { return }
            zoom(
                to: clampedZoom(userZoom * acceleratedZoomDelta(for: Double(scale))),
                anchorPoint: anchorPoint,
                contentScale: contentScale,
                drawableSize: drawableSize,
                viewSize: viewSize
            )
            progressiveRenderState = nil
        }

        func applyDoubleTapZoom(
            anchorPoint: CGPoint,
            contentScale: CGFloat,
            drawableSize: CGSize,
            viewSize: CGSize
        ) {
            zoom(
                to: clampedZoom(userZoom * doubleTapZoomFactor),
                anchorPoint: anchorPoint,
                contentScale: contentScale,
                drawableSize: drawableSize,
                viewSize: viewSize
            )
            progressiveRenderState = nil
        }

        func applyZoomStep(
            factor: Double,
            anchorPoint: CGPoint,
            contentScale: CGFloat,
            drawableSize: CGSize,
            viewSize: CGSize
        ) {
            guard factor.isFinite, factor > 0 else { return }
            zoom(
                to: clampedZoom(userZoom * factor),
                anchorPoint: anchorPoint,
                contentScale: contentScale,
                drawableSize: drawableSize,
                viewSize: viewSize
            )
            progressiveRenderState = nil
        }

        private func zoom(
            to nextZoom: Double,
            anchorPoint: CGPoint,
            contentScale: CGFloat,
            drawableSize: CGSize,
            viewSize: CGSize
        ) {
            let previousZoom = userZoom
            guard abs(nextZoom - previousZoom) > 0.000001 else { return }
            guard !modelBounds.isEmpty,
                  drawableSize.width > 1,
                  drawableSize.height > 1,
                  viewSize.width > 1,
                  viewSize.height > 1
            else {
                userZoom = nextZoom
                return
            }

            let anchorScreenPoint = SIMD2<Double>(
                Double(anchorPoint.x * contentScale),
                Double(anchorPoint.y * contentScale)
            )
            let anchoredWorldPoint = worldPoint(
                forScreenPoint: anchorScreenPoint,
                drawableSize: drawableSize,
                viewSize: viewSize
            )
            userZoom = nextZoom
            keepWorldPoint(
                anchoredWorldPoint,
                atScreenPoint: anchorScreenPoint,
                drawableSize: drawableSize,
                viewSize: viewSize
            )
        }

        func setInteractionPhase(_ phase: Kernel.CADRenderInteractionPhase) {
            if interactionPhase != phase {
                progressiveRenderState = nil
            }
            interactionPhase = phase
        }

        func setVisibleLayerIDs(_ layerIDs: Set<String>?) {
            if visibleLayerIDs != layerIDs {
                progressiveRenderState = nil
            }
            visibleLayerIDs = layerIDs
        }

        func setSelectedLayoutID(_ layoutID: String?) {
            guard selectedLayoutID != layoutID else { return }
            selectedLayoutID = layoutID
            rebuildDrawingForCurrentLayout(resetViewState: true)
        }

        func setFeatureOptions(_ options: CADCanvasFeatureOptions) {
            guard featureOptions != options else { return }
            featureOptions = options
            progressiveRenderState = nil
            if !options.publishesSnapPoints {
                clearPublishedSnapPoints()
            }
            #if os(iOS)
            if !options.rendersTextOverlays {
                textRasterCache.removeAll()
                textAtlasTextureCache.removeAll()
                currentTextAtlasTextCount = 0
                currentTextAtlasSkippedTextCount = 0
                clearTextOverlayLabels()
            }
            #endif
        }

        func setOpenTrace(_ trace: CADOpenTrace?) {
            guard let trace else {
                openTraceDiagnosticRows = []
                return
            }

            var rows: [String] = []
            if trace.rawMLeaderCount > 0
                || trace.mleaderTextCandidateCount > 0
                || trace.exportedMLeaderTextCount > 0 {
                rows.append(
                    "mleader text raw \(trace.rawMLeaderCount) / candidate \(trace.mleaderTextCandidateCount) / exported \(trace.exportedMLeaderTextCount)"
                )
            }
            if trace.rawProxyEntityCount > 0
                || trace.rawTianzhengProxyCount > 0
                || trace.proxyTextCandidateCount > 0 {
                rows.append(
                    "custom text proxy \(trace.proxyTextCandidateCount)/\(trace.rawProxyEntityCount) / tch \(trace.tianzhengTextCandidateCount)/\(trace.rawTianzhengProxyCount)"
                )
            }
            openTraceDiagnosticRows = rows
        }

        func setDebugTextOverlays(_ enabled: Bool) {
            debugTextOverlays = enabled
        }

        func clearSearchHighlight() {
            highlightedSearchEntityID = nil
            highlightedSearchBounds = nil
        }

        func focusSearchResult(
            entityID: Kernel.CADEntity.ID,
            bounds: Kernel.CADBounds,
            fallbackPoint: Kernel.CADPoint,
            contentScale: CGFloat,
            drawableSize: CGSize,
            viewSize: CGSize
        ) {
            let focusBounds = searchFocusBounds(bounds: bounds, fallbackPoint: fallbackPoint)
            guard !focusBounds.isEmpty,
                  !modelBounds.isEmpty,
                  drawableSize.width > 1,
                  drawableSize.height > 1,
                  viewSize.width > 1,
                  viewSize.height > 1
            else {
                highlightedSearchEntityID = entityID
                highlightedSearchBounds = focusBounds.isEmpty ? bounds : focusBounds
                return
            }

            let baseScale = fitScale(drawableSize: drawableSize, viewSize: viewSize)
            let viewScale = Double(max(drawableSize.width / max(viewSize.width, 1), 1))
            let padding = max(24 * viewScale, fitContentInsetPoints(viewSize: viewSize) * viewScale * 2)
            let availableWidth = max(Double(drawableSize.width) - padding * 2, 1)
            let availableHeight = max(Double(drawableSize.height) - padding * 2, 1)
            let width = max(focusBounds.width, 0.0001)
            let height = max(focusBounds.height, 0.0001)
            let targetScreenScale = min(availableWidth / width, availableHeight / height)
            let nextZoom = clampedZoom(targetScreenScale / max(baseScale, 0.000001))

            userZoom = nextZoom
            keepWorldPoint(
                focusBounds.center,
                atScreenPoint: SIMD2<Double>(
                    Double(drawableSize.width) / 2,
                    Double(drawableSize.height) / 2
                ),
                drawableSize: drawableSize,
                viewSize: viewSize
            )
            interactionPhase = .stable
            didApplyInitialViewState = true
            progressiveRenderState = nil
            highlightedSearchEntityID = entityID
            highlightedSearchBounds = normalizedHighlightBounds(bounds: bounds, fallbackPoint: fallbackPoint)
        }

        private func clampedZoom(_ value: Double) -> Double {
            min(max(value, minimumUserZoom), maximumUserZoom)
        }

        private func acceleratedZoomDelta(for rawScale: Double) -> Double {
            guard rawScale.isFinite, rawScale > 0 else { return 1 }
            if rawScale >= 1 {
                return 1 + (rawScale - 1) * pinchZoomAcceleration
            }
            return 1 / (1 + ((1 / rawScale) - 1) * pinchZoomAcceleration)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            view.setNeedsDisplay()
        }

        func draw(in view: MTKView) {
            let frameStart = Date()
            guard
                isAvailable,
                let drawable = view.currentDrawable,
                let renderPassDescriptor = view.currentRenderPassDescriptor,
                let commandQueue,
                let renderPipelineState,
                view.drawableSize.width > 1,
                view.drawableSize.height > 1
            else {
                return
            }

            let viewportBounds = worldViewportBounds(
                drawableSize: view.drawableSize,
                viewSize: view.bounds.size
            )
            let viewportEntitiesBeforeLayerFilter = spatialIndex.query(viewportBounds, layerIDs: nil)
            let visibleEntities = spatialIndex.query(viewportBounds, layerIDs: visibleLayerIDs)
            let commandSourceEntities = entitiesAfterApplyingFeatureOptions(visibleEntities)
            let viewportTextEntityCountBeforeLayerFilter = viewportEntitiesBeforeLayerFilter.filter(Self.isTextEntity).count
            let visibleTextEntityCount = visibleEntities.filter(Self.isTextEntity).count
            let renderInputTextEntityCount = commandSourceEntities.filter(Self.isTextEntity).count
            var textViewportDiagnostics = makeTextViewportDiagnostics(viewportBounds: viewportBounds)
            if visibleTextEntityCount == 0 {
                textViewportDiagnostics.detailRows.insert(
                    contentsOf: Self.viewportEntityDiagnosticRows(visibleEntities),
                    at: 0
                )
            }
            let zoomScale = modelToScreenScale(
                drawableSize: view.drawableSize,
                viewSize: view.bounds.size
            )
            let renderPlan = renderOutputForFrame(
                visibleEntities: commandSourceEntities,
                viewportBounds: viewportBounds,
                zoomScale: zoomScale
            )
            var pipelineOutput = renderPlan.output
            pipelineOutput.commands = commandsAfterApplyingFeatureOptions(pipelineOutput.commands)
            pipelineOutput.performance.renderCommandCount = pipelineOutput.commands.count
            pipelineOutput.performance.drawCallCount = pipelineOutput.commands.reduce(0) { $0 + $1.drawCallCost }
            let textCommandCount = featureOptions.rendersTextOverlays ? pipelineOutput.commands.cadTextCommandCount : 0
            #if os(iOS)
            let textOverlaySourceEntities = textOverlaySourceEntities(
                renderInputEntities: commandSourceEntities,
                renderCommands: pipelineOutput.commands
            )
            self.syncDebugTextMarkers(
                commands: featureOptions.rendersTextOverlays ? pipelineOutput.commands : [],
                view: view,
                drawableSize: view.drawableSize,
                viewSize: view.bounds.size,
                contentScale: view.contentScaleFactor
            )
            let textAtlasPlan = usesMetalTextAtlasForLiveRendering && featureOptions.rendersTextOverlays
                ? makeTextAtlasRenderPlan(
                    commands: pipelineOutput.commands,
                    drawableSize: view.drawableSize,
                    viewSize: view.bounds.size,
                    contentScale: view.contentScaleFactor
                )
                : nil
            currentTextAtlasTextCount = textAtlasPlan?.textCount ?? 0
            currentTextAtlasSkippedTextCount = textAtlasPlan?.skippedTextCount ?? 0

            if let textAtlasPlan {
                clearTextOverlayLabels()
                textViewportDiagnostics.detailRows.append(
                    "metal text atlas \(textAtlasPlan.textCount) / command \(textCommandCount) / skipped \(textAtlasPlan.skippedTextCount)"
                )
                textViewportDiagnostics.detailRows.append(contentsOf: textAtlasPlan.diagnosticRows)
            } else {
                let uiTextOverlayStats = self.syncTextOverlayLabels(
                    entities: featureOptions.rendersTextOverlays ? textOverlaySourceEntities : [],
                    view: view,
                    drawableSize: view.drawableSize,
                    viewSize: view.bounds.size,
                    contentScale: view.contentScaleFactor
                )
                if featureOptions.rendersTextOverlays, uiTextOverlayStats.source > 0 {
                    textViewportDiagnostics.detailRows.append(
                        "ui text overlay \(uiTextOverlayStats.visible) / source \(uiTextOverlayStats.source) / skipped \(uiTextOverlayStats.skipped)"
                    )
                    if uiTextOverlayStats.overlapSkipped > 0 {
                        textViewportDiagnostics.detailRows.append(
                            "ui text overlap hidden \(uiTextOverlayStats.overlapSkipped)"
                        )
                    }
                    if uiTextOverlayStats.rawSource > uiTextOverlayStats.source {
                        textViewportDiagnostics.detailRows.append(
                            "ui text dedup \(uiTextOverlayStats.rawSource - uiTextOverlayStats.source) / raw \(uiTextOverlayStats.rawSource)"
                        )
                    }
                }
            }
            #else
            let textAtlasPlan: CADTextAtlasRenderPlan? = nil
            #endif
            if featureOptions.publishesSnapPoints {
                publishSnapPoints(from: visibleEntities)
            } else {
                clearPublishedSnapPoints()
            }
            var vertices = makeVertices(
                commands: pipelineOutput.commands,
                drawableSize: view.drawableSize,
                viewSize: view.bounds.size,
                contentScale: view.contentScaleFactor
            )
            vertices.append(contentsOf: makeSearchHighlightVertices(
                drawableSize: view.drawableSize,
                viewSize: view.bounds.size,
                contentScale: view.contentScaleFactor
            ))
            updateFrameTrace(
                pipelineTrace: pipelineOutput.performance,
                frameStart: frameStart,
                didProduceCommands: !pipelineOutput.commands.isEmpty,
                textCommandCount: textCommandCount,
                textOverlayCount: currentTextOverlayCount,
                textOverlaySkippedCount: currentTextOverlaySkippedCount,
                viewportBounds: viewportBounds,
                viewportEntityCountBeforeLayerFilter: viewportEntitiesBeforeLayerFilter.count,
                viewportTextEntityCountBeforeLayerFilter: viewportTextEntityCountBeforeLayerFilter,
                visibleTextEntityCount: visibleTextEntityCount,
                renderInputTextEntityCount: renderInputTextEntityCount,
                textViewportDiagnostics: textViewportDiagnostics,
                vertexCount: vertices.count + (textAtlasPlan?.vertices.count ?? 0)
            )
            publishCanvasState(
                view: view,
                viewportBounds: viewportBounds,
                visibleEntityCount: visibleEntities.count
            )
            let vertexBuffer = makeVertexBuffer(vertices)

            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
                red: 0.972,
                green: 0.976,
                blue: 0.984,
                alpha: 1
            )
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .store

            guard
                let commandBuffer = commandQueue.makeCommandBuffer(),
                let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
            else {
                return
            }

            encoder.setRenderPipelineState(renderPipelineState)
            if let vertexBuffer, !vertices.isEmpty {
                encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
            }
            if let textAtlasPlan,
               let textRenderPipelineState,
               let textVertexBuffer = makeTextVertexBuffer(textAtlasPlan.vertices) {
                encoder.setRenderPipelineState(textRenderPipelineState)
                encoder.setVertexBuffer(textVertexBuffer, offset: 0, index: 0)
                encoder.setFragmentTexture(textAtlasPlan.texture, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: textAtlasPlan.vertices.count)
            }
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
            if renderPlan.needsContinuation {
                DispatchQueue.main.async { [weak view] in
                    view?.setNeedsDisplay()
                }
            }
        }

        private func commandsAfterApplyingFeatureOptions(
            _ commands: [Kernel.CADRenderCommand]
        ) -> [Kernel.CADRenderCommand] {
            commands.flatMap { command -> [Kernel.CADRenderCommand] in
                if case let .hatch(path, style) = command,
                   !featureOptions.rendersHatches {
                    let points = path.points
                    return featureOptions.rendersHatchBoundaries && points.count >= 2
                        ? [.polyline(points, closed: path.isClosed, style: style)]
                        : []
                }
                return featureOptions.allows(command) ? [command] : []
            }
        }

        private func entitiesAfterApplyingFeatureOptions(
            _ visibleEntities: [Kernel.CADEntity]
        ) -> [Kernel.CADEntity] {
            visibleEntities.filter { featureOptions.allows($0) }
        }

        private func renderOutputForFrame(
            visibleEntities: [Kernel.CADEntity],
            viewportBounds: Kernel.CADBounds,
            zoomScale: Double
        ) -> FrameRenderPlan {
            let budget = renderBudget(for: interactionPhase, visibleEntityCount: visibleEntities.count)
            let pipeline = CADRenderPipeline(
                lodPolicy: lodPolicy(for: interactionPhase),
                featureOptions: featureOptions
            )
            guard interactionPhase == .stable,
                  visibleEntities.count > progressiveVisibleEntityThreshold
            else {
                progressiveRenderState = nil
                return FrameRenderPlan(
                    output: pipeline.renderOutput(
                        from: visibleEntities,
                        layersByID: layersByID,
                        totalEntityCount: entities.count,
                        visibleEntityCount: visibleEntities.count,
                        zoomScale: zoomScale,
                        interactionPhase: interactionPhase,
                        renderBudget: budget
                    ),
                    needsContinuation: false
                )
            }

            let key = progressiveKey(
                viewportBounds: viewportBounds,
                zoomScale: zoomScale,
                visibleEntityCount: visibleEntities.count
            )
            if progressiveRenderState?.key != key {
                progressiveRenderState = ProgressiveRenderState(key: key)
            }

            var state = progressiveRenderState ?? ProgressiveRenderState(key: key)
            let renderEntities = progressivePrioritizedEntities(visibleEntities)
            let renderStart = Date()
            if !state.completed, state.nextEntityOffset < renderEntities.count {
                let remainingCommandCapacity = max(progressiveCommandCacheLimit - state.commands.count, 0)
                if remainingCommandCapacity == 0 {
                    state.completed = true
                    state.warnings.insert("CAD_POC_PROGRESSIVE_COMMAND_CACHE_LIMIT")
                } else {
                    let batchEnd = min(
                        state.nextEntityOffset + progressiveEntityBatchSize,
                        renderEntities.count
                    )
                    let batch = Array(renderEntities[state.nextEntityOffset..<batchEnd])
                    let batchBudget = Kernel.CADRenderBudget(
                        maxRenderCommands: min(remainingCommandCapacity, budget.maxRenderCommands),
                        maxFrameTimeMilliseconds: min(budget.maxFrameTimeMilliseconds, 24)
                    )
                    let batchOutput = pipeline.renderOutput(
                        from: batch,
                        layersByID: layersByID,
                        totalEntityCount: entities.count,
                        visibleEntityCount: visibleEntities.count,
                        zoomScale: zoomScale,
                        interactionPhase: interactionPhase,
                        renderBudget: batchBudget
                    )
                    state.commands.append(contentsOf: batchOutput.commands.prefix(remainingCommandCapacity))
                    state.nextEntityOffset = batchEnd
                    state.warnings.formUnion(batchOutput.performance.warnings)
                    if batchOutput.commands.count >= remainingCommandCapacity {
                        state.completed = true
                        state.warnings.insert("CAD_POC_PROGRESSIVE_COMMAND_CACHE_LIMIT")
                    }
                }
            }

            if state.nextEntityOffset >= renderEntities.count {
                state.completed = true
            }

            let needsContinuation = !state.completed
            if needsContinuation {
                state.warnings.insert("CAD_POC_PROGRESSIVE_RENDERING")
            }
            progressiveRenderState = state

            let skippedEntityCount = max(renderEntities.count - min(state.nextEntityOffset, renderEntities.count), 0)
            let renderMs = Date().timeIntervalSince(renderStart) * 1000
            let commands = state.commands
            let trace = Kernel.CADPerformanceTrace(
                entityCount: entities.count,
                visibleEntityCount: visibleEntities.count,
                renderCommandCount: commands.count,
                drawCallCount: commands.reduce(0) { $0 + $1.drawCallCost },
                renderMs: renderMs,
                frameTimeMilliseconds: renderMs,
                peakMemoryMB: estimateProgressivePeakMemoryMB(
                    visibleEntityCount: visibleEntities.count,
                    commandCount: commands.count
                ),
                skippedEntityCount: skippedEntityCount,
                warnings: Array(state.warnings).sorted()
            )
            return FrameRenderPlan(
                output: CADPoC.CADRenderPipeline.Output(commands: commands, performance: trace),
                needsContinuation: needsContinuation
            )
        }

        private func progressivePrioritizedEntities(_ visibleEntities: [Kernel.CADEntity]) -> [Kernel.CADEntity] {
            guard featureOptions.rendersTextOverlays else { return visibleEntities }
            var textEntities: [Kernel.CADEntity] = []
            var otherEntities: [Kernel.CADEntity] = []
            textEntities.reserveCapacity(min(visibleEntities.count, 256))
            otherEntities.reserveCapacity(visibleEntities.count)
            for entity in visibleEntities {
                if shouldPrioritizeTextForProgressiveRender(entity) {
                    textEntities.append(entity)
                } else {
                    otherEntities.append(entity)
                }
            }
            return textEntities + otherEntities
        }

        private func shouldPrioritizeTextForProgressiveRender(_ entity: Kernel.CADEntity) -> Bool {
            Self.isTextEntity(entity)
        }

        private static func isTextEntity(_ entity: Kernel.CADEntity) -> Bool {
            switch entity.kind {
            case .text, .mtext, .attrib:
                return entity.text != nil
            case .dimension:
                return entity.text != nil
            default:
                return false
            }
        }

        private func progressiveKey(
            viewportBounds: Kernel.CADBounds,
            zoomScale: Double,
            visibleEntityCount: Int
        ) -> ProgressiveRenderKey {
            let span = max(max(modelBounds.width, modelBounds.height), 1)
            let bucketSize = max(span / 4096, 0.001)
            func bucket(_ value: Double) -> Int64 {
                Int64((value / bucketSize).rounded())
            }
            let layerKey = visibleLayerIDs?.sorted().joined(separator: ",") ?? "all"
            return ProgressiveRenderKey(
                drawingRevision: drawingRevision,
                viewportMinX: bucket(viewportBounds.minX),
                viewportMinY: bucket(viewportBounds.minY),
                viewportMaxX: bucket(viewportBounds.maxX),
                viewportMaxY: bucket(viewportBounds.maxY),
                zoomBucket: Int64((log2(max(zoomScale, 0.0001)) * 64).rounded()),
                visibleLayerKey: layerKey,
                visibleEntityCount: visibleEntityCount
            )
        }

        private func updateFrameTrace(
            pipelineTrace: Kernel.CADPerformanceTrace,
            frameStart: Date,
            didProduceCommands: Bool,
            textCommandCount: Int,
            textOverlayCount: Int,
            textOverlaySkippedCount: Int,
            viewportBounds: Kernel.CADBounds,
            viewportEntityCountBeforeLayerFilter: Int,
            viewportTextEntityCountBeforeLayerFilter: Int,
            visibleTextEntityCount: Int,
            renderInputTextEntityCount: Int,
            textViewportDiagnostics: TextViewportDiagnostics,
            vertexCount: Int
        ) {
            var trace = pipelineTrace
            let frameMs = Date().timeIntervalSince(frameStart) * 1000
            trace.frameTimeMilliseconds = frameMs
            trace.renderMs = frameMs
            if !didRenderFirstFrame, didProduceCommands {
                trace.firstFrameMs = Date().timeIntervalSince(firstFrameStart) * 1000
                didRenderFirstFrame = true
            } else {
                trace.firstFrameMs = lastFrameTrace.firstFrameMs
            }
            lastFrameTrace = trace
            logFrameTrace(trace)
            let modelBoundsValid = modelBounds.isFiniteForCADDisplay
            let viewportBoundsValid = viewportBounds.isFiniteForCADDisplay
            let viewportIntersectsModel = modelBoundsValid
                && viewportBoundsValid
                && modelBounds.intersects(viewportBounds)
            callbacks.onPerformanceSample(
                CADRendererPerformanceSnapshot(
                    entityCountInViewport: trace.visibleEntityCount,
                    drawCallCount: trace.drawCallCount,
                    frameTimeMilliseconds: trace.frameTimeMilliseconds,
                    skippedEntityCount: trace.skippedEntityCount,
                    visibleLayerCount: visibleLayerIDs?.count ?? totalLayerCount,
                    totalLayerCount: totalLayerCount,
                    simplifiedMode: interactionPhase != .stable,
                    renderCommandCount: trace.renderCommandCount,
                    textCommandCount: textCommandCount,
                    textOverlayCount: textOverlayCount,
                    textOverlaySkippedCount: textOverlaySkippedCount,
                    renderMs: trace.renderMs,
                    firstFrameMs: trace.firstFrameMs,
                    totalEntityCount: entities.count,
                    indexedEntityCount: spatialIndex.indexedEntityCount,
                    viewportEntityCountBeforeLayerFilter: viewportEntityCountBeforeLayerFilter,
                    layerFilterActive: visibleLayerIDs != nil,
                    modelBounds: CGRect(modelBounds),
                    viewportBounds: CGRect(viewportBounds),
                    modelBoundsValid: modelBoundsValid,
                    viewportBoundsValid: viewportBoundsValid,
                    viewportIntersectsModel: viewportIntersectsModel,
                    vertexCount: vertexCount,
                    totalTextEntityCount: totalTextEntityCount,
                    indexedTextEntityCount: indexedTextEntityCount,
                    viewportTextEntityCountBeforeLayerFilter: viewportTextEntityCountBeforeLayerFilter,
                    visibleTextEntityCount: visibleTextEntityCount,
                    renderInputTextEntityCount: renderInputTextEntityCount,
                    textWorldBounds: CGRect(textViewportDiagnostics.textWorldBounds),
                    visibleLayerTextWorldBounds: CGRect(textViewportDiagnostics.visibleLayerTextWorldBounds),
                    nearestTextBounds: CGRect(textViewportDiagnostics.nearestTextBounds),
                    nearestTextDistance: textViewportDiagnostics.nearestTextDistance,
                    nearestTextPreview: textViewportDiagnostics.nearestTextPreview,
                    nearestTextLayerID: textViewportDiagnostics.nearestTextLayerID,
                    textDiagnosticRows: textViewportDiagnostics.detailRows
                )
            )
        }

        private func makeTextViewportDiagnostics(viewportBounds: Kernel.CADBounds) -> TextViewportDiagnostics {
            var diagnostics = TextViewportDiagnostics()
            let proxyRows = Self.proxyTextCandidateDiagnosticRows(
                entities: entities,
                visibleLayerIDs: visibleLayerIDs,
                viewportBounds: viewportBounds
            )
            let sourceRows = openTraceDiagnosticRows
            let textEntities = entities.filter(Self.isTextEntity)
            guard !textEntities.isEmpty else {
                diagnostics.detailRows.append(contentsOf: sourceRows)
                diagnostics.detailRows.append(contentsOf: proxyRows)
                return diagnostics
            }

            let layerVisibleTextEntities = textEntities.filter { entity in
                visibleLayerIDs == nil || visibleLayerIDs?.contains(entity.layerID) == true
            }

            diagnostics.textWorldBounds = textEntities.reduce(Kernel.CADBounds.empty) { partial, entity in
                partial.union(CADSpatialIndex.effectiveBounds(for: entity))
            }
            diagnostics.visibleLayerTextWorldBounds = layerVisibleTextEntities.reduce(Kernel.CADBounds.empty) { partial, entity in
                partial.union(CADSpatialIndex.effectiveBounds(for: entity))
            }

            let nearestCandidates = layerVisibleTextEntities.isEmpty ? textEntities : layerVisibleTextEntities
            let nearest = nearestCandidates.compactMap { entity -> (entity: Kernel.CADEntity, bounds: Kernel.CADBounds, distance: Double)? in
                let bounds = CADSpatialIndex.effectiveBounds(for: entity)
                guard !bounds.isEmpty else { return nil }
                return (entity, bounds, Self.distanceBetween(bounds, viewportBounds))
            }.min { lhs, rhs in
                lhs.distance < rhs.distance
            }

            if let nearest {
                diagnostics.nearestTextBounds = nearest.bounds
                diagnostics.nearestTextDistance = nearest.distance
                diagnostics.nearestTextPreview = nearest.entity.text?.displayText
                diagnostics.nearestTextLayerID = nearest.entity.layerID
                diagnostics.detailRows.append(Self.nearestTextViewportOffsetRow(
                    nearestBounds: nearest.bounds,
                    viewportBounds: viewportBounds
                ))
            }
            diagnostics.detailRows.append(contentsOf: Self.textViewportDetailRows(
                textEntities: textEntities,
                layerVisibleTextEntities: layerVisibleTextEntities,
                viewportBounds: viewportBounds
            ))
            diagnostics.detailRows.append(contentsOf: sourceRows)
            diagnostics.detailRows.append(contentsOf: proxyRows)
            return diagnostics
        }

        private static func nearestTextViewportOffsetRow(
            nearestBounds: Kernel.CADBounds,
            viewportBounds: Kernel.CADBounds
        ) -> String {
            let nearestCenter = nearestBounds.center
            let viewportCenter = viewportBounds.center
            let dx = nearestCenter.x - viewportCenter.x
            let dy = nearestCenter.y - viewportCenter.y
            let horizontal: String
            if nearestBounds.maxX < viewportBounds.minX {
                horizontal = "left"
            } else if nearestBounds.minX > viewportBounds.maxX {
                horizontal = "right"
            } else {
                horizontal = "inside-x"
            }

            let vertical: String
            if nearestBounds.maxY < viewportBounds.minY {
                vertical = "below"
            } else if nearestBounds.minY > viewportBounds.maxY {
                vertical = "above"
            } else {
                vertical = "inside-y"
            }

            return "nearest text offset dx \(Self.formatDiagnosticNumber(dx)) / dy \(Self.formatDiagnosticNumber(dy)) / \(horizontal),\(vertical)"
        }

        private static func textViewportDetailRows(
            textEntities: [Kernel.CADEntity],
            layerVisibleTextEntities: [Kernel.CADEntity],
            viewportBounds: Kernel.CADBounds
        ) -> [String] {
            let viewportTextEntities = layerVisibleTextEntities.filter {
                CADSpatialIndex.effectiveBounds(for: $0).intersects(viewportBounds)
            }
            let orderedKinds = ["text", "mtext", "attrib", "dimension"]
            let allCounts = Self.textKindCounts(textEntities)
            let layerCounts = Self.textKindCounts(layerVisibleTextEntities)
            var rows: [String] = []
            if !viewportTextEntities.isEmpty {
                rows.append(Self.viewportTextPreviewRow(for: viewportTextEntities))
                rows.append(Self.textDecodeSummaryRow(for: viewportTextEntities))
                if let sample = viewportTextEntities.compactMap(\.text).first {
                    rows.append(Self.textDecodeSampleRow(for: sample))
                }
            }
            rows.append(contentsOf: [
                "text kind total \(Self.formatTextKindCounts(allCounts, orderedKinds: orderedKinds))",
                "text kind layer \(Self.formatTextKindCounts(layerCounts, orderedKinds: orderedKinds))"
            ])
            if viewportTextEntities.isEmpty,
               let annotationRow = Self.annotationLayerTextDiagnosticRow(
                candidates: layerVisibleTextEntities,
                viewportBounds: viewportBounds
               ) {
                rows.insert(annotationRow, at: 0)
            }

            for kind in orderedKinds {
                let candidates = layerVisibleTextEntities.filter {
                    Self.textDiagnosticKindLabel(for: $0) == kind
                }
                guard !candidates.isEmpty else { continue }

                let viewportHits = candidates.filter {
                    CADSpatialIndex.effectiveBounds(for: $0).intersects(viewportBounds)
                }.count
                let nearest = candidates.compactMap { entity -> (entity: Kernel.CADEntity, bounds: Kernel.CADBounds, distance: Double)? in
                    let bounds = CADSpatialIndex.effectiveBounds(for: entity)
                    guard !bounds.isEmpty else { return nil }
                    return (entity, bounds, Self.distanceBetween(bounds, viewportBounds))
                }.min { lhs, rhs in
                    lhs.distance < rhs.distance
                }

                if let nearest {
                    rows.append(
                        "near \(kind) total \(candidates.count) / viewport \(viewportHits) / d \(Self.formatDiagnosticNumber(nearest.distance)) / layer \(nearest.entity.layerID) \(Self.compactDiagnosticPreview(nearest.entity.text?.displayText))"
                    )
                    rows.append("near \(kind) bounds \(Self.formatDiagnosticBounds(nearest.bounds))")
                    if let text = nearest.entity.text {
                        rows.append(Self.textDecodeSampleRow(for: text, prefix: "near \(kind) decode"))
                    }
                } else {
                    rows.append("near \(kind) total \(candidates.count) / viewport \(viewportHits) / no finite bounds")
                }
            }

            return rows
        }

        private static func viewportTextPreviewRow(for entities: [Kernel.CADEntity]) -> String {
            let previews = entities
                .prefix(4)
                .map { entity -> String in
                    let handle = entity.sourceHandle.map { "#\($0)" } ?? ""
                    let preview = Self.compactDiagnosticPreview(entity.text?.displayText)
                    return "\(entity.layerID)\(handle):\(preview)"
                }
                .joined(separator: " | ")
            return "view text \(entities.count) \(previews)"
        }

        private static func annotationLayerTextDiagnosticRow(
            candidates: [Kernel.CADEntity],
            viewportBounds: Kernel.CADBounds
        ) -> String? {
            let annotationCandidates = candidates.filter { entity in
                let layer = entity.layerID.uppercased()
                return layer.contains("-BZ") || layer == "BZ" || layer.contains("标注")
            }
            guard !annotationCandidates.isEmpty else { return nil }

            let nearest = annotationCandidates.compactMap { entity -> (entity: Kernel.CADEntity, bounds: Kernel.CADBounds, distance: Double)? in
                let bounds = CADSpatialIndex.effectiveBounds(for: entity)
                guard !bounds.isEmpty else { return nil }
                return (entity, bounds, Self.distanceBetween(bounds, viewportBounds))
            }.min { lhs, rhs in
                lhs.distance < rhs.distance
            }
            guard let nearest else {
                return "-BZ text total \(annotationCandidates.count) / no finite bounds"
            }
            let preview = Self.compactDiagnosticPreview(nearest.entity.text?.displayText)
            return "-BZ text total \(annotationCandidates.count) / nearest d \(Self.formatDiagnosticNumber(nearest.distance)) / layer \(nearest.entity.layerID) \(preview)"
        }

        private static func proxyTextCandidateDiagnosticRows(
            entities: [Kernel.CADEntity],
            visibleLayerIDs: Set<String>?,
            viewportBounds: Kernel.CADBounds
        ) -> [String] {
            let candidates = entities.compactMap { entity -> (entity: Kernel.CADEntity, preview: String)? in
                guard entity.kind == .proxy,
                      let preview = proxyTextCandidatePreview(from: entity.unsupportedReason) else {
                    return nil
                }
                return (entity, preview)
            }
            guard !candidates.isEmpty else {
                return []
            }

            let layerVisibleCandidates = candidates.filter { candidate in
                visibleLayerIDs == nil || visibleLayerIDs?.contains(candidate.entity.layerID) == true
            }
            let boundedCandidates = layerVisibleCandidates.compactMap { candidate -> (entity: Kernel.CADEntity, preview: String, bounds: Kernel.CADBounds)? in
                let bounds = CADSpatialIndex.effectiveBounds(for: candidate.entity)
                guard !bounds.isEmpty else {
                    return nil
                }
                return (candidate.entity, candidate.preview, bounds)
            }
            let viewportHits = boundedCandidates.filter { $0.bounds.intersects(viewportBounds) }.count
            let nearest = boundedCandidates.min { lhs, rhs in
                Self.distanceBetween(lhs.bounds, viewportBounds) < Self.distanceBetween(rhs.bounds, viewportBounds)
            }
            let tianzhengCount = candidates.filter { candidate in
                candidate.entity.unsupportedReason?.localizedCaseInsensitiveContains("Tianzheng") == true
                    || candidate.entity.unsupportedReason?.localizedCaseInsensitiveContains("TCH") == true
            }.count

            var row = "proxy text total \(candidates.count) / layer \(layerVisibleCandidates.count) / inView \(viewportHits)"
            if let nearest {
                let distance = Self.distanceBetween(nearest.bounds, viewportBounds)
                row += " / nearest d \(Self.formatDiagnosticNumber(distance)) / layer \(nearest.entity.layerID) \(nearest.preview)"
            } else if let sample = layerVisibleCandidates.first ?? candidates.first {
                let handle = sample.entity.sourceHandle.map { "#\($0)" } ?? ""
                row += " / no finite bounds / sample \(sample.entity.layerID)\(handle):\(sample.preview)"
            } else {
                row += " / no finite bounds"
            }
            if tianzhengCount > 0 {
                row += " / tch \(tianzhengCount)"
            }
            return [row]
        }

        private static func proxyTextCandidatePreview(from reason: String?) -> String? {
            guard let reason,
                  let range = reason.range(of: "textCandidate=", options: [.caseInsensitive]) else {
                return nil
            }
            let suffix = reason[range.upperBound...]
            let value = suffix
                .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init) ?? String(suffix)
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }
            return compactDiagnosticPreview(trimmed)
        }

        private static func viewportEntityDiagnosticRows(_ entities: [Kernel.CADEntity]) -> [String] {
            guard !entities.isEmpty else { return [] }

            let kindCounts = entities.reduce(into: [Kernel.CADEntityKind: Int]()) { counts, entity in
                counts[entity.kind, default: 0] += 1
            }
            let leaderEntities = entities.filter { entity in
                entity.diagnostics.entries.contains { entry in
                    entry.code.localizedCaseInsensitiveContains("LEADER")
                        || entry.message.localizedCaseInsensitiveContains("LEADER")
                }
            }
            let orderedKinds: [Kernel.CADEntityKind] = [.line, .polyline, .lwPolyline, .dimension, .hatch, .proxy]
            let kindSummary = orderedKinds
                .map { "\($0.rawValue)=\(kindCounts[$0, default: 0])" }
                .joined(separator: " ")
            let layerSummary = Array(
                entities.reduce(into: [String: Int]()) { counts, entity in
                    counts[entity.layerID, default: 0] += 1
                }
                .sorted { lhs, rhs in
                    if lhs.value != rhs.value { return lhs.value > rhs.value }
                    return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
                }
                .prefix(3)
            )
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ",")
            let handleSummary = entities
                .compactMap(\.sourceHandle)
                .prefix(3)
                .joined(separator: ",")
            var row = "view kinds \(kindSummary) leader=\(leaderEntities.count)"
            if !layerSummary.isEmpty {
                row += " / layers \(layerSummary)"
            }
            if !handleSummary.isEmpty {
                row += " / handles \(handleSummary)"
            }
            var rows = [row]
            if let leader = leaderEntities.first {
                let handle = leader.sourceHandle.map { " / handle \($0)" } ?? ""
                rows.append("view leader layer \(leader.layerID)\(handle)")
            }
            return rows
        }

        private static func textDecodeSummaryRow(for entities: [Kernel.CADEntity]) -> String {
            let texts = entities.compactMap(\.text)
            let emptyDisplayCount = texts.filter {
                $0.displayText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.count
            let replacementCount = texts.reduce(0) { $0 + Self.replacementCharacterCount(in: $1.displayText) }
            let warningCount = texts.reduce(0) { $0 + $1.warnings.count }
            return "text decode viewport empty \(emptyDisplayCount)/\(texts.count) / replacement \(replacementCount) / warnings \(warningCount)"
        }

        private static func textDecodeSampleRow(
            for text: Kernel.CADTextRun,
            prefix: String = "text decode sample"
        ) -> String {
            let rawLength = text.rawText.count
            let decodedLength = text.decodedText.count
            let displayLength = text.displayText.count
            let rawPreview = compactDiagnosticPreview(text.rawText)
            let displayPreview = compactDiagnosticPreview(text.displayText)
            return "\(prefix) rawLen \(rawLength) / decodedLen \(decodedLength) / displayLen \(displayLength) / raw \(rawPreview) / display \(displayPreview)"
        }

        private static func replacementCharacterCount(in text: String) -> Int {
            text.unicodeScalars.filter { scalar in
                scalar.value == 0xFFFD || scalar.value == 0x25A1 || scalar.value == 0x25A0
            }.count
        }

        private static func textKindCounts(_ entities: [Kernel.CADEntity]) -> [String: Int] {
            entities.reduce(into: [:]) { counts, entity in
                counts[textDiagnosticKindLabel(for: entity), default: 0] += 1
            }
        }

        private static func formatTextKindCounts(_ counts: [String: Int], orderedKinds: [String]) -> String {
            orderedKinds.map { "\($0) \(counts[$0, default: 0])" }.joined(separator: " / ")
        }

        private static func textDiagnosticKindLabel(for entity: Kernel.CADEntity) -> String {
            switch entity.kind {
            case .text:
                return "text"
            case .mtext:
                return "mtext"
            case .attrib:
                return "attrib"
            case .dimension:
                return "dimension"
            default:
                return entity.kind.rawValue
            }
        }

        private static func formatDiagnosticNumber(_ value: Double) -> String {
            guard value.isFinite else { return "-" }
            if abs(value) >= 1000 {
                return String(format: "%.0f", value)
            }
            if abs(value) >= 10 {
                return String(format: "%.1f", value)
            }
            return String(format: "%.2f", value)
        }

        private static func compactDiagnosticPreview(_ value: String?) -> String {
            guard let value else { return "" }
            let singleLine = value.replacingOccurrences(of: "\n", with: " ")
            if singleLine.count <= 12 {
                return singleLine
            }
            return "\(singleLine.prefix(12))..."
        }

        private static func formatDiagnosticBounds(_ bounds: Kernel.CADBounds) -> String {
            guard !bounds.isEmpty else { return "-" }
            return "(\(formatDiagnosticNumber(bounds.minX)),\(formatDiagnosticNumber(bounds.minY))) \(formatDiagnosticNumber(bounds.width))x\(formatDiagnosticNumber(bounds.height))"
        }

        private static func formatDiagnosticPoint(_ point: Kernel.CADPoint) -> String {
            "(\(formatDiagnosticNumber(point.x)),\(formatDiagnosticNumber(point.y)))"
        }

        private static func distanceBetween(_ lhs: Kernel.CADBounds, _ rhs: Kernel.CADBounds) -> Double {
            guard !lhs.isEmpty, !rhs.isEmpty else { return .infinity }
            if lhs.intersects(rhs) {
                return 0
            }
            let dx: Double
            if lhs.maxX < rhs.minX {
                dx = rhs.minX - lhs.maxX
            } else if rhs.maxX < lhs.minX {
                dx = lhs.minX - rhs.maxX
            } else {
                dx = 0
            }
            let dy: Double
            if lhs.maxY < rhs.minY {
                dy = rhs.minY - lhs.maxY
            } else if rhs.maxY < lhs.minY {
                dy = lhs.minY - rhs.maxY
            } else {
                dy = 0
            }
            return hypot(dx, dy)
        }

        private static func distanceBetween(_ lhs: Kernel.CADPoint, _ rhs: Kernel.CADPoint) -> Double {
            hypot(lhs.x - rhs.x, lhs.y - rhs.y)
        }

        private func logFrameTrace(_ trace: Kernel.CADPerformanceTrace) {
            CADPoC.CADDiagnosticLog.recordEncoded(
                category: "cad.frameTrace",
                message: "CAD renderer frame trace captured.",
                payload: trace,
                coalescingKey: "cad.frameTrace.latest"
            )
        }

        private func publishCanvasState(
            view: MTKView,
            viewportBounds: Kernel.CADBounds,
            visibleEntityCount: Int
        ) {
            guard !modelBounds.isEmpty, view.bounds.width > 1, view.bounds.height > 1 else { return }
            callbacks.onCanvasTransformChange(
                CADRendererCanvasTransform(
                    bounds: CGRect(
                        x: modelBounds.minX,
                        y: modelBounds.minY,
                        width: modelBounds.width,
                        height: modelBounds.height
                    ),
                    size: view.bounds.size,
                    zoomScale: CGFloat(userZoom),
                    panOffset: CGSize(
                        width: panOffsetPixels.x / Double(max(view.contentScaleFactor, 1)),
                        height: panOffsetPixels.y / Double(max(view.contentScaleFactor, 1))
                    )
                )
            )
            callbacks.onViewStateChange(
                CADRendererViewState(
                    zoomScale: CGFloat(userZoom),
                    panOffset: CGSize(
                        width: panOffsetPixels.x / Double(max(view.contentScaleFactor, 1)),
                        height: panOffsetPixels.y / Double(max(view.contentScaleFactor, 1))
                    ),
                    viewportCenter: viewportBounds.center.cgPoint,
                    usesSavedVisibleLayers: visibleLayerIDs != nil,
                    visibleLayerNames: Array(visibleLayerIDs ?? []).sorted()
                )
            )
            if visibleEntityCount > 0 {
                callbacks.onOpenQualityChange(
                    CADOpenQualitySnapshot(
                        level: "ready",
                        title: "CAD Metal PoC",
                        summary: "当前图纸已由 Metal PoC 渲染。",
                        primaryAction: "",
                        detailLines: [],
                        allowsMarkup: true,
                        supportsSearch: false
                    )
                )
            }
        }

        static func makeSnapPointPayloads(
            for entities: [Kernel.CADEntity],
            maxSegmentCount: Int = 1_800,
            maxIntersectionCount: Int = 4_000
        ) -> [CADRendererSnapPointPayload] {
            CADSnapPrimitiveExtractor(
                entities: entities,
                maxSegmentCount: maxSegmentCount,
                maxIntersectionCount: maxIntersectionCount
            ).makePayloads()
        }

        private func publishSnapPoints(from visibleEntities: [Kernel.CADEntity]) {
            let snapEntities = visibleEntities.count > snapVisibleEntityLimit
                ? Array(visibleEntities.prefix(snapVisibleEntityLimit))
                : visibleEntities
            let payloads = Self.makeSnapPointPayloads(
                for: snapEntities,
                maxIntersectionCount: featureOptions.publishesSnapIntersections ? 4_000 : 0
            )
            guard payloads != lastPublishedSnapPoints else { return }
            lastPublishedSnapPoints = payloads
            callbacks.onSnapPointsChange(payloads)
        }

        private func clearPublishedSnapPoints() {
            guard !lastPublishedSnapPoints.isEmpty else { return }
            lastPublishedSnapPoints = []
            callbacks.onSnapPointsChange([])
        }
    }
}

private struct CADSnapPrimitiveExtractor {
    typealias Kernel = SiteKeeperCADKernel

    struct Segment {
        let start: Kernel.CADPoint
        let end: Kernel.CADPoint
        let layerID: String
        let primitiveKind: String
        let color: UInt32
        let lineWeight: Double
        let lineType: String

        var bounds: Kernel.CADBounds {
            Kernel.CADBounds.empty.including(start).including(end)
        }
    }

    let entities: [Kernel.CADEntity]
    let maxSegmentCount: Int
    let maxIntersectionCount: Int

    func makePayloads() -> [CADRendererSnapPointPayload] {
        var builder = CADSnapPointPayloadBuilder()
        var segments: [Segment] = []
        segments.reserveCapacity(min(entities.count * 2, maxSegmentCount))

        for entity in entities where entity.visibility == .visible {
            appendSnapPoints(for: entity, to: &builder)
            if segments.count < maxSegmentCount {
                segments.append(contentsOf: snapSegments(for: entity, remaining: maxSegmentCount - segments.count))
            }
        }

        appendIntersections(from: segments, to: &builder)
        return builder.payloads
    }

    private func appendSnapPoints(
        for entity: Kernel.CADEntity,
        to builder: inout CADSnapPointPayloadBuilder
    ) {
        let primitiveKind = snapPrimitiveKind(for: entity)
        switch entity.kind {
        case .line, .polyline, .lwPolyline, .spline, .dimension, .hatch:
            appendPathSnapPoints(
                entity.path,
                closed: entity.path?.isClosedForSnap == true,
                entity: entity,
                primitiveKind: primitiveKind,
                to: &builder
            )
        case .arc:
            builder.append(entity.bounds.center, kind: "center", entity: entity, primitiveKind: primitiveKind)
            appendPathSnapPoints(
                entity.path,
                closed: false,
                entity: entity,
                primitiveKind: primitiveKind,
                to: &builder
            )
        case .circle, .ellipse:
            builder.append(entity.bounds.center, kind: "center", entity: entity, primitiveKind: primitiveKind)
            appendCardinalBoundsPoints(for: entity, primitiveKind: primitiveKind, to: &builder)
        case .text, .mtext, .attrib:
            if let text = entity.text {
                builder.append(text.insertionPoint, kind: "center", entity: entity, primitiveKind: primitiveKind)
            } else {
                builder.append(entity.bounds.center, kind: "center", entity: entity, primitiveKind: primitiveKind)
            }
        case .point:
            builder.append(entity.bounds.center, kind: "endpoint", entity: entity, primitiveKind: primitiveKind)
        case .image, .table, .insert, .blockReference:
            appendBoundsSnapPoints(for: entity, primitiveKind: primitiveKind, to: &builder)
        case .xref, .proxy, .unsupported:
            return
        }
    }

    private func appendPathSnapPoints(
        _ path: Kernel.CADPath?,
        closed: Bool,
        entity: Kernel.CADEntity,
        primitiveKind: String,
        to builder: inout CADSnapPointPayloadBuilder
    ) {
        guard let path else { return }
        let points = path.pointsForSnap
        guard !points.isEmpty else { return }
        for point in points {
            builder.append(point, kind: "endpoint", entity: entity, primitiveKind: primitiveKind)
        }
        for segment in segments(from: points, closed: closed, entity: entity, primitiveKind: primitiveKind) {
            builder.append(segment.midpoint, kind: "midpoint", entity: entity, primitiveKind: primitiveKind)
        }
    }

    private func appendCardinalBoundsPoints(
        for entity: Kernel.CADEntity,
        primitiveKind: String,
        to builder: inout CADSnapPointPayloadBuilder
    ) {
        guard !entity.bounds.isEmpty else { return }
        let center = entity.bounds.center
        [
            Kernel.CADPoint(x: center.x, y: entity.bounds.maxY),
            Kernel.CADPoint(x: entity.bounds.maxX, y: center.y),
            Kernel.CADPoint(x: center.x, y: entity.bounds.minY),
            Kernel.CADPoint(x: entity.bounds.minX, y: center.y)
        ].forEach {
            builder.append($0, kind: "endpoint", entity: entity, primitiveKind: primitiveKind)
        }
    }

    private func appendBoundsSnapPoints(
        for entity: Kernel.CADEntity,
        primitiveKind: String,
        to builder: inout CADSnapPointPayloadBuilder
    ) {
        guard !entity.bounds.isEmpty else { return }
        let corners = [
            Kernel.CADPoint(x: entity.bounds.minX, y: entity.bounds.minY),
            Kernel.CADPoint(x: entity.bounds.maxX, y: entity.bounds.minY),
            Kernel.CADPoint(x: entity.bounds.maxX, y: entity.bounds.maxY),
            Kernel.CADPoint(x: entity.bounds.minX, y: entity.bounds.maxY)
        ]
        corners.forEach {
            builder.append($0, kind: "endpoint", entity: entity, primitiveKind: primitiveKind)
        }
        builder.append(entity.bounds.center, kind: "center", entity: entity, primitiveKind: primitiveKind)
    }

    private func snapSegments(
        for entity: Kernel.CADEntity,
        remaining: Int
    ) -> [Segment] {
        guard remaining > 0, let path = entity.path else { return [] }
        switch entity.kind {
        case .line, .polyline, .lwPolyline, .spline, .dimension, .hatch:
            return Array(segments(
                from: path.pointsForSnap,
                closed: path.isClosedForSnap,
                entity: entity,
                primitiveKind: snapPrimitiveKind(for: entity)
            ).prefix(remaining))
        default:
            return []
        }
    }

    private func appendIntersections(
        from segments: [Segment],
        to builder: inout CADSnapPointPayloadBuilder
    ) {
        guard segments.count > 1 else { return }
        var intersectionCount = 0
        for leftIndex in 0..<(segments.count - 1) {
            let left = segments[leftIndex]
            for rightIndex in (leftIndex + 1)..<segments.count {
                guard intersectionCount < maxIntersectionCount else { return }
                let right = segments[rightIndex]
                guard left.bounds.intersects(right.bounds.expanded(by: 0.000001)),
                      let point = intersection(of: left, and: right) else {
                    continue
                }
                builder.append(
                    point,
                    kind: "intersection",
                    layer: [left.layerID, right.layerID]
                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                        .uniquedForSnap()
                        .joined(separator: "/"),
                    primitiveKind: "line",
                    styleRGB: left.color,
                    styleWidth: CGFloat(max(left.lineWeight, right.lineWeight, 1)),
                    styleName: left.lineType
                )
                intersectionCount += 1
            }
        }
    }

    private func segments(
        from points: [Kernel.CADPoint],
        closed: Bool,
        entity: Kernel.CADEntity,
        primitiveKind: String
    ) -> [Segment] {
        guard points.count >= 2 else { return [] }
        var result: [Segment] = []
        result.reserveCapacity(points.count)
        for index in 0..<(points.count - 1) {
            result.append(segment(from: points[index], to: points[index + 1], entity: entity, primitiveKind: primitiveKind))
        }
        if closed, let first = points.first, let last = points.last, first != last {
            result.append(segment(from: last, to: first, entity: entity, primitiveKind: primitiveKind))
        }
        return result
    }

    private func segment(
        from start: Kernel.CADPoint,
        to end: Kernel.CADPoint,
        entity: Kernel.CADEntity,
        primitiveKind: String
    ) -> Segment {
        Segment(
            start: start,
            end: end,
            layerID: entity.layerID,
            primitiveKind: primitiveKind,
            color: entity.color,
            lineWeight: entity.lineWeight,
            lineType: entity.lineType
        )
    }

    private func intersection(of left: Segment, and right: Segment) -> Kernel.CADPoint? {
        let p = left.start
        let r = Kernel.CADPoint(x: left.end.x - left.start.x, y: left.end.y - left.start.y)
        let q = right.start
        let s = Kernel.CADPoint(x: right.end.x - right.start.x, y: right.end.y - right.start.y)
        let denominator = cross(r, s)
        guard abs(denominator) > 0.000000001 else { return nil }

        let qp = Kernel.CADPoint(x: q.x - p.x, y: q.y - p.y)
        let t = cross(qp, s) / denominator
        let u = cross(qp, r) / denominator
        guard t >= -0.000001, t <= 1.000001, u >= -0.000001, u <= 1.000001 else {
            return nil
        }

        return Kernel.CADPoint(x: p.x + r.x * t, y: p.y + r.y * t)
    }

    private func cross(_ left: Kernel.CADPoint, _ right: Kernel.CADPoint) -> Double {
        left.x * right.y - left.y * right.x
    }

    private func snapPrimitiveKind(for entity: Kernel.CADEntity) -> String {
        switch entity.kind {
        case .line:
            return "line"
        case .polyline, .lwPolyline, .spline:
            return "polyline"
        case .arc:
            return "arc"
        case .circle:
            return "circle"
        case .ellipse:
            return "ellipse"
        case .text:
            return "text"
        case .mtext, .attrib:
            return "mtext"
        case .dimension:
            return "dimension"
        case .hatch:
            return "hatch"
        case .image:
            return "image"
        case .insert, .blockReference:
            return "blockRef"
        case .point, .table:
            return "line"
        case .xref, .proxy, .unsupported:
            return "unknownProxy"
        }
    }
}

private struct CADSnapPointPayloadBuilder {
    typealias Kernel = SiteKeeperCADKernel

    private(set) var payloads: [CADRendererSnapPointPayload] = []
    private var seenKeys = Set<String>()

    mutating func append(
        _ point: Kernel.CADPoint,
        kind: String,
        entity: Kernel.CADEntity,
        primitiveKind: String
    ) {
        append(
            point,
            kind: kind,
            layer: entity.layerID,
            primitiveKind: primitiveKind,
            styleRGB: entity.color,
            styleWidth: CGFloat(max(entity.lineWeight, 1)),
            styleName: entity.lineType
        )
    }

    mutating func append(
        _ point: Kernel.CADPoint,
        kind: String,
        layer: String,
        primitiveKind: String,
        styleRGB: UInt32,
        styleWidth: CGFloat,
        styleName: String?
    ) {
        guard point.x.isFinite, point.y.isFinite else { return }
        let key = "\(kind)|\(quantized(point.x))|\(quantized(point.y))|\(layer)|\(primitiveKind)"
        guard seenKeys.insert(key).inserted else { return }
        payloads.append(
            CADRendererSnapPointPayload(
                point: point.cgPoint,
                snapKind: kind,
                layer: layer,
                primitiveKind: primitiveKind,
                styleRGB: styleRGB,
                styleWidth: styleWidth,
                styleName: styleName
            )
        )
    }

    private func quantized(_ value: Double) -> Int64 {
        Int64((value * 10_000).rounded())
    }
}

private extension SiteKeeperCADKernel.CADPoint {
    var isFiniteForSnap: Bool {
        x.isFinite && y.isFinite
    }

    static func midpoint(_ start: SiteKeeperCADKernel.CADPoint, _ end: SiteKeeperCADKernel.CADPoint) -> SiteKeeperCADKernel.CADPoint {
        SiteKeeperCADKernel.CADPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }
}

private extension CADSnapPrimitiveExtractor.Segment {
    var midpoint: SiteKeeperCADKernel.CADPoint {
        .midpoint(start, end)
    }
}

private extension SiteKeeperCADKernel.CADPath {
    var pointsForSnap: [SiteKeeperCADKernel.CADPoint] {
        points.filter(\.isFiniteForSnap)
    }

    var isClosedForSnap: Bool {
        elements.contains {
            if case .close = $0 {
                return true
            }
            return false
        }
    }
}

private extension Array where Element == String {
    func uniquedForSnap() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in self where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}

private extension CADPoC.CADMetalRenderer {
    struct CADMetalVertex {
        var position: SIMD2<Float>
        var color: SIMD4<Float>
    }

    struct CADTexturedVertex {
        var position: SIMD2<Float>
        var textureCoordinate: SIMD2<Float>
    }

    struct CADTextAtlasVertexBuildResult {
        var vertices: [CADTexturedVertex]
        var fallbackAnchorCount: Int
        var offscreenItemCount: Int
    }

    struct CADTextAtlasRenderPlan {
        var texture: MTLTexture
        var vertices: [CADTexturedVertex]
        var textCount: Int
        var skippedTextCount: Int
        var uniqueTextureCount: Int
        var atlasSize: CGSize
        var diagnosticRows: [String]

        init(
            texture: MTLTexture,
            vertices: [CADTexturedVertex],
            textCount: Int,
            skippedTextCount: Int,
            uniqueTextureCount: Int,
            atlasSize: CGSize,
            diagnosticRows: [String]
        ) {
            self.texture = texture
            self.vertices = vertices
            self.textCount = textCount
            self.skippedTextCount = skippedTextCount
            self.uniqueTextureCount = uniqueTextureCount
            self.atlasSize = atlasSize
            self.diagnosticRows = diagnosticRows
        }
    }

    static func makeRenderPipelineState(
        device: MTLDevice?,
        colorPixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineState? {
        guard let device else { return nil }
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "CAD Metal PoC Pipeline"
            descriptor.vertexFunction = library.makeFunction(name: "cad_vertex_main")
            descriptor.fragmentFunction = library.makeFunction(name: "cad_fragment_main")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            assertionFailure("CAD Metal pipeline failed: \(error)")
            return nil
        }
    }

    static func makeTextRenderPipelineState(
        device: MTLDevice?,
        colorPixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineState? {
        guard let device else { return nil }
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.label = "CAD Metal PoC Text Atlas Pipeline"
            descriptor.vertexFunction = library.makeFunction(name: "cad_text_vertex_main")
            descriptor.fragmentFunction = library.makeFunction(name: "cad_text_fragment_main")
            descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            assertionFailure("CAD Metal text atlas pipeline failed: \(error)")
            return nil
        }
    }

    static var shaderSource: String {
        """
        #include <metal_stdlib>
        using namespace metal;

        struct CADMetalVertex {
            float2 position;
            float4 color;
        };

        struct CADVertexOut {
            float4 position [[position]];
            float4 color;
        };

        struct CADTexturedVertex {
            float2 position;
            float2 textureCoordinate;
        };

        struct CADTexturedVertexOut {
            float4 position [[position]];
            float2 textureCoordinate;
        };

        vertex CADVertexOut cad_vertex_main(
            uint vertexID [[vertex_id]],
            const device CADMetalVertex *vertices [[buffer(0)]]
        ) {
            CADVertexOut out;
            out.position = float4(vertices[vertexID].position, 0.0, 1.0);
            out.color = vertices[vertexID].color;
            return out;
        }

        fragment half4 cad_fragment_main(CADVertexOut in [[stage_in]]) {
            return half4(in.color);
        }

        vertex CADTexturedVertexOut cad_text_vertex_main(
            uint vertexID [[vertex_id]],
            const device CADTexturedVertex *vertices [[buffer(0)]]
        ) {
            CADTexturedVertexOut out;
            out.position = float4(vertices[vertexID].position, 0.0, 1.0);
            out.textureCoordinate = vertices[vertexID].textureCoordinate;
            return out;
        }

        fragment half4 cad_text_fragment_main(
            CADTexturedVertexOut in [[stage_in]],
            texture2d<half> textAtlas [[texture(0)]]
        ) {
            constexpr sampler textSampler(
                mag_filter::linear,
                min_filter::linear,
                address::clamp_to_edge
            );
            return textAtlas.sample(textSampler, in.textureCoordinate);
        }
        """
    }

    func makeVertexBuffer(_ vertices: [CADMetalVertex]) -> MTLBuffer? {
        guard !vertices.isEmpty else { return nil }
        return vertices.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return nil as MTLBuffer? }
            return device?.makeBuffer(
                bytes: baseAddress,
                length: rawBuffer.count,
                options: [.storageModeShared]
            )
        }
    }

    func makeTextVertexBuffer(_ vertices: [CADTexturedVertex]) -> MTLBuffer? {
        guard !vertices.isEmpty else { return nil }
        return vertices.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return nil as MTLBuffer? }
            return device?.makeBuffer(
                bytes: baseAddress,
                length: rawBuffer.count,
                options: [.storageModeShared]
            )
        }
    }

    func renderBudget(
        for phase: Kernel.CADRenderInteractionPhase,
        visibleEntityCount: Int
    ) -> Kernel.CADRenderBudget {
        guard phase == .stable else { return .interactive }
        if visibleEntityCount > progressiveVisibleEntityThreshold {
            return Kernel.CADRenderBudget(maxRenderCommands: 12_000, maxFrameTimeMilliseconds: 24)
        }
        let commandBudget = min(max(visibleEntityCount * 2, Kernel.CADRenderBudget.standard.maxRenderCommands), 300_000)
        return Kernel.CADRenderBudget(maxRenderCommands: commandBudget, maxFrameTimeMilliseconds: 500)
    }

    func estimateProgressivePeakMemoryMB(
        visibleEntityCount: Int,
        commandCount: Int
    ) -> Double {
        Double(visibleEntityCount * 96 + commandCount * 112) / 1_048_576
    }

    var currentTextOverlayCount: Int {
        #if os(iOS)
        max(currentTextAtlasTextCount, currentUIKitTextLabelCount)
        #else
        0
        #endif
    }

    var currentTextOverlaySkippedCount: Int {
        #if os(iOS)
        max(currentTextAtlasSkippedTextCount, currentUIKitTextLabelSkippedCount)
        #else
        0
        #endif
    }

    func lodPolicy(for phase: Kernel.CADRenderInteractionPhase) -> Kernel.CADLODPolicy {
        guard phase == .stable else {
            return Kernel.CADLODPolicy(minTextHeightOnScreen: 2)
        }
        return Kernel.CADLODPolicy(minTextHeightOnScreen: 0)
    }

    func fitModelBounds(for entities: [Kernel.CADEntity]) -> Kernel.CADBounds {
        let finiteBounds = entities.compactMap { entity -> (Kernel.CADEntity, Kernel.CADBounds)? in
            let bounds = CADPoC.CADSpatialIndex.effectiveBounds(for: entity)
            guard bounds.isFiniteForCADDisplay else { return nil }
            return (entity, bounds)
        }
        let preferredBounds = finiteBounds.filter { entity, _ in
            !shouldExcludeFromInitialFit(entity)
        }
        let sourceBounds = preferredBounds.isEmpty ? finiteBounds.map { $0.1 } : preferredBounds.map { $0.1 }
        let bounds = sourceBounds.reduce(Kernel.CADBounds.empty) { $0.union($1) }
        return normalizedFitBounds(bounds)
    }

    func shouldExcludeFromInitialFit(_ entity: Kernel.CADEntity) -> Bool {
        if Kernel.CADDatabase.isPlaceholderEntity(entity) {
            return true
        }
        return entity.diagnostics.entries.contains { entry in
            entry.code == "CAD_POC_INFINITE_LINE_CLIPPED"
        }
    }

    func normalizedFitBounds(_ bounds: Kernel.CADBounds) -> Kernel.CADBounds {
        guard bounds.isFiniteForCADDisplay else { return .empty }
        var minX = bounds.minX
        var minY = bounds.minY
        var maxX = bounds.maxX
        var maxY = bounds.maxY
        let width = maxX - minX
        let height = maxY - minY
        let referenceSpan = max(width, height, 1)
        let pad = max(referenceSpan * 0.02, 1)

        if width <= 0 {
            minX -= pad
            maxX += pad
        }
        if height <= 0 {
            minY -= pad
            maxY += pad
        }

        return Kernel.CADBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    func makeVertices(
        commands: [Kernel.CADRenderCommand],
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> [CADMetalVertex] {
        commands.flatMap { command -> [CADMetalVertex] in
            switch command {
            case let .polyline(points, closed, style):
                return makePolylineVertices(
                    points: points,
                    closed: closed,
                    style: style,
                    drawableSize: drawableSize,
                    viewSize: viewSize,
                    contentScale: contentScale
                )
            case let .hatch(path, style):
                return makeHatchVertices(
                    path: path,
                    style: style,
                    drawableSize: drawableSize,
                    viewSize: viewSize,
                    contentScale: contentScale
                )
            case .text:
                return []
            case let .marker(point, _, style):
                return makeMarkerVertices(
                    point: point,
                    style: style,
                    drawableSize: drawableSize,
                    viewSize: viewSize,
                    contentScale: contentScale
                )
            case let .imagePlaceholder(_, bounds, _),
                 let .unsupportedPlaceholder(_, bounds, _):
                return makeBoundsPlaceholderVertices(
                    bounds: bounds,
                    style: Kernel.CADRenderStyle(layerID: "placeholder", colorARGB: 0xFF64748B, lineWidth: 1.5),
                    drawableSize: drawableSize,
                    viewSize: viewSize,
                    contentScale: contentScale
                )
            default:
                return []
            }
        }
    }

    func makeMarkerVertices(
        point: Kernel.CADPoint,
        style: Kernel.CADRenderStyle,
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> [CADMetalVertex] {
        let screen = screenPoint(
            for: point,
            drawableSize: drawableSize,
            viewSize: viewSize
        )
        let markerSize = 5.0 * Double(max(contentScale, 1))
        let color = rgbaVector(fromARGB: style.colorARGB)
        let width = screenLineWidth(for: style.lineWidth, contentScale: contentScale)
        let horizontalStart = SIMD2<Double>(screen.x - markerSize, screen.y)
        let horizontalEnd = SIMD2<Double>(screen.x + markerSize, screen.y)
        let verticalStart = SIMD2<Double>(screen.x, screen.y - markerSize)
        let verticalEnd = SIMD2<Double>(screen.x, screen.y + markerSize)
        return makeScreenSegmentVertices(
            from: horizontalStart,
            to: horizontalEnd,
            color: color,
            width: width,
            drawableSize: drawableSize
        ) + makeScreenSegmentVertices(
            from: verticalStart,
            to: verticalEnd,
            color: color,
            width: width,
            drawableSize: drawableSize
        )
    }

    func makeBoundsPlaceholderVertices(
        bounds: Kernel.CADBounds,
        style: Kernel.CADRenderStyle,
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> [CADMetalVertex] {
        guard !bounds.isEmpty else { return [] }
        let points = [
            Kernel.CADPoint(x: bounds.minX, y: bounds.minY),
            Kernel.CADPoint(x: bounds.maxX, y: bounds.minY),
            Kernel.CADPoint(x: bounds.maxX, y: bounds.maxY),
            Kernel.CADPoint(x: bounds.minX, y: bounds.maxY)
        ]
        return makePolylineVertices(
            points: points,
            closed: true,
            style: style,
            drawableSize: drawableSize,
            viewSize: viewSize,
            contentScale: contentScale
        ) + makePolylineVertices(
            points: [points[0], points[2]],
            closed: false,
            style: style,
            drawableSize: drawableSize,
            viewSize: viewSize,
            contentScale: contentScale
        ) + makePolylineVertices(
            points: [points[1], points[3]],
            closed: false,
            style: style,
            drawableSize: drawableSize,
            viewSize: viewSize,
            contentScale: contentScale
        )
    }

    func makeSearchHighlightVertices(
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> [CADMetalVertex] {
        guard let highlightedSearchBounds,
              !highlightedSearchBounds.isEmpty,
              !modelBounds.isEmpty else {
            return []
        }

        let modelScale = max(modelToScreenScale(drawableSize: drawableSize, viewSize: viewSize), 0.000001)
        let worldPadding = max(8 / modelScale, max(highlightedSearchBounds.width, highlightedSearchBounds.height) * 0.18)
        let outlineBounds = highlightedSearchBounds.expanded(by: worldPadding)
        let outlineStyle = Kernel.CADRenderStyle(
            layerID: "cad-search-highlight",
            colorARGB: 0xFFFFB000,
            lineWidth: 3.0,
            lineType: "Continuous"
        )
        let centerStyle = Kernel.CADRenderStyle(
            layerID: "cad-search-highlight",
            colorARGB: 0xFF2563EB,
            lineWidth: 2.0,
            lineType: "Continuous"
        )
        return makeBoundsPlaceholderVertices(
            bounds: outlineBounds,
            style: outlineStyle,
            drawableSize: drawableSize,
            viewSize: viewSize,
            contentScale: contentScale
        ) + makeMarkerVertices(
            point: highlightedSearchBounds.center,
            style: centerStyle,
            drawableSize: drawableSize,
            viewSize: viewSize,
            contentScale: contentScale
        )
    }

    func searchFocusBounds(
        bounds: Kernel.CADBounds,
        fallbackPoint: Kernel.CADPoint
    ) -> Kernel.CADBounds {
        let highlightBounds = normalizedHighlightBounds(bounds: bounds, fallbackPoint: fallbackPoint)
        guard !highlightBounds.isEmpty else { return .empty }
        let drawingSpan = max(max(modelBounds.width, modelBounds.height), 1)
        let localSpan = max(max(highlightBounds.width, highlightBounds.height), 1)
        let padding = max(localSpan * 1.35, min(max(drawingSpan * 0.004, 8), drawingSpan * 0.08))
        return highlightBounds.expanded(by: padding)
    }

    func normalizedHighlightBounds(
        bounds: Kernel.CADBounds,
        fallbackPoint: Kernel.CADPoint
    ) -> Kernel.CADBounds {
        let source = bounds.isFiniteForCADDisplay ? bounds : Kernel.CADBounds(
            minX: fallbackPoint.x,
            minY: fallbackPoint.y,
            maxX: fallbackPoint.x,
            maxY: fallbackPoint.y
        )
        guard source.isFiniteForCADDisplay else { return .empty }
        let drawingSpan = max(max(modelBounds.width, modelBounds.height), 1)
        let minimumSpan = max(drawingSpan * 0.0008, 0.5)
        var minX = source.minX
        var maxX = source.maxX
        var minY = source.minY
        var maxY = source.maxY
        if maxX - minX < minimumSpan {
            let center = (minX + maxX) / 2
            minX = center - minimumSpan / 2
            maxX = center + minimumSpan / 2
        }
        if maxY - minY < minimumSpan {
            let center = (minY + maxY) / 2
            minY = center - minimumSpan / 2
            maxY = center + minimumSpan / 2
        }
        return Kernel.CADBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    func makeHatchVertices(
        path: Kernel.CADPath,
        style: Kernel.CADRenderStyle,
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> [CADMetalVertex] {
        let points = path.points
        guard points.count >= 3 else {
            return makePolylineVertices(
                points: points,
                closed: path.isClosed,
                style: style,
                drawableSize: drawableSize,
                viewSize: viewSize,
                contentScale: contentScale
            )
        }
        guard path.isClosed, points.count <= maximumFilledHatchPointCount else {
            return makePolylineVertices(
                points: points,
                closed: path.isClosed,
                style: style,
                drawableSize: drawableSize,
                viewSize: viewSize,
                contentScale: contentScale
            )
        }

        var vertices: [CADMetalVertex] = []
        let fillColor = hatchFillColor(fromARGB: style.colorARGB)
        let screenPoints = points.map {
            screenPoint(for: $0, drawableSize: drawableSize, viewSize: viewSize)
        }
        let origin = screenPoints[0]
        for index in 1..<(screenPoints.count - 1) {
            vertices.append(CADMetalVertex(position: ndcPoint(fromScreen: origin, drawableSize: drawableSize), color: fillColor))
            vertices.append(CADMetalVertex(position: ndcPoint(fromScreen: screenPoints[index], drawableSize: drawableSize), color: fillColor))
            vertices.append(CADMetalVertex(position: ndcPoint(fromScreen: screenPoints[index + 1], drawableSize: drawableSize), color: fillColor))
        }

        let boundaryStyle = Kernel.CADRenderStyle(
            layerID: style.layerID,
            colorARGB: style.colorARGB,
            lineWidth: max(style.lineWidth, 1),
            lineType: style.lineType
        )
        vertices.append(contentsOf: makePolylineVertices(
            points: points,
            closed: path.isClosed,
            style: boundaryStyle,
            drawableSize: drawableSize,
            viewSize: viewSize,
            contentScale: contentScale
        ))
        return vertices
    }

    func makePolylineVertices(
        points: [Kernel.CADPoint],
        closed: Bool,
        style: Kernel.CADRenderStyle,
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> [CADMetalVertex] {
        guard points.count >= 2 else { return [] }
        var vertices: [CADMetalVertex] = []
        for index in 0..<(points.count - 1) {
            appendSegment(
                from: points[index],
                to: points[index + 1],
                style: style,
                drawableSize: drawableSize,
                viewSize: viewSize,
                contentScale: contentScale,
                to: &vertices
            )
        }
        if closed, let first = points.first, let last = points.last, first != last {
            appendSegment(
                from: last,
                to: first,
                style: style,
                drawableSize: drawableSize,
                viewSize: viewSize,
                contentScale: contentScale,
                to: &vertices
            )
        }
        return vertices
    }

    func appendSegment(
        from start: Kernel.CADPoint,
        to end: Kernel.CADPoint,
        style: Kernel.CADRenderStyle,
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat,
        to vertices: inout [CADMetalVertex]
    ) {
        let startScreen = screenPoint(
            for: start,
            drawableSize: drawableSize,
            viewSize: viewSize
        )
        let endScreen = screenPoint(
            for: end,
            drawableSize: drawableSize,
            viewSize: viewSize
        )
        let color = rgbaVector(fromARGB: style.colorARGB)
        let screenWidth = screenLineWidth(
            for: featureOptions.rendersLineWeights ? style.lineWidth : 0.25,
            contentScale: contentScale
        )
        let pattern = featureOptions.rendersLineTypes
            ? lineTypePattern(for: style.lineType, screenLineWidth: screenWidth)
            : []

        if pattern.isEmpty {
            vertices.append(contentsOf: makeScreenSegmentVertices(
                from: startScreen,
                to: endScreen,
                color: color,
                width: screenWidth,
                drawableSize: drawableSize
            ))
        } else {
            for dash in dashedScreenSegments(from: startScreen, to: endScreen, pattern: pattern) {
                vertices.append(contentsOf: makeScreenSegmentVertices(
                    from: dash.0,
                    to: dash.1,
                    color: color,
                    width: screenWidth,
                    drawableSize: drawableSize
                ))
            }
        }
    }

    func screenLineWidth(for lineWidth: Double, contentScale: CGFloat) -> Double {
        let scale = Double(max(contentScale, 1))
        let normalized = lineWidth.isFinite && lineWidth > 0 ? lineWidth : 0.25
        let points: Double
        if normalized >= 2 {
            points = min(max(1.0 + log2(normalized) * 0.22, 1.05), 3.0)
        } else {
            points = min(max(0.85 + normalized * 1.2, 0.9), 2.2)
        }
        return max(points * scale, 1.0)
    }

    func lineTypePattern(for lineType: String, screenLineWidth: Double) -> [Double] {
        let normalized = lineType
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        guard !normalized.isEmpty,
              normalized != "continuous",
              normalized != "bylayer",
              normalized != "byblock" else {
            return []
        }

        let unit = max(screenLineWidth, 1.5)
        if normalized.contains("center") {
            return [unit * 12, unit * 3, unit * 2, unit * 3]
        }
        if normalized.contains("phantom") {
            return [unit * 12, unit * 3, unit * 2, unit * 3, unit * 2, unit * 3]
        }
        if normalized.contains("dashdot") {
            return [unit * 8, unit * 3, unit * 2, unit * 3]
        }
        if normalized.contains("dot") {
            return [unit * 1.4, unit * 3]
        }
        if normalized.contains("hidden") || normalized.contains("dash") {
            return [unit * 8, unit * 4]
        }
        return []
    }

    func dashedScreenSegments(
        from start: SIMD2<Double>,
        to end: SIMD2<Double>,
        pattern: [Double]
    ) -> [(SIMD2<Double>, SIMD2<Double>)] {
        guard pattern.count >= 2 else { return [(start, end)] }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.01 else { return [] }

        let direction = SIMD2<Double>(dx / length, dy / length)
        var cursor = 0.0
        var patternIndex = 0
        var result: [(SIMD2<Double>, SIMD2<Double>)] = []
        while cursor < length, result.count < 4096 {
            let segmentLength = max(pattern[patternIndex % pattern.count], 0.5)
            let next = min(cursor + segmentLength, length)
            if patternIndex.isMultiple(of: 2), next > cursor {
                result.append((
                    start + direction * cursor,
                    start + direction * next
                ))
            }
            cursor = next
            patternIndex += 1
        }
        return result
    }

    func makeScreenSegmentVertices(
        from startScreen: SIMD2<Double>,
        to endScreen: SIMD2<Double>,
        color: SIMD4<Float>,
        width: Double,
        drawableSize: CGSize
    ) -> [CADMetalVertex] {
        let dx = endScreen.x - startScreen.x
        let dy = endScreen.y - startScreen.y
        let length = hypot(dx, dy)
        guard length > 0.01 else { return [] }

        let halfWidth = max(width, 1) / 2
        let normal = SIMD2<Double>(-dy / length * halfWidth, dx / length * halfWidth)

        let a = SIMD2<Double>(startScreen.x + normal.x, startScreen.y + normal.y)
        let b = SIMD2<Double>(startScreen.x - normal.x, startScreen.y - normal.y)
        let c = SIMD2<Double>(endScreen.x + normal.x, endScreen.y + normal.y)
        let d = SIMD2<Double>(endScreen.x - normal.x, endScreen.y - normal.y)

        return [
            CADMetalVertex(position: ndcPoint(fromScreen: a, drawableSize: drawableSize), color: color),
            CADMetalVertex(position: ndcPoint(fromScreen: b, drawableSize: drawableSize), color: color),
            CADMetalVertex(position: ndcPoint(fromScreen: c, drawableSize: drawableSize), color: color),
            CADMetalVertex(position: ndcPoint(fromScreen: c, drawableSize: drawableSize), color: color),
            CADMetalVertex(position: ndcPoint(fromScreen: b, drawableSize: drawableSize), color: color),
            CADMetalVertex(position: ndcPoint(fromScreen: d, drawableSize: drawableSize), color: color)
        ]
    }

    func screenPoint(
        for point: Kernel.CADPoint,
        drawableSize: CGSize,
        viewSize: CGSize
    ) -> SIMD2<Double> {
        let scale = fitScale(drawableSize: drawableSize, viewSize: viewSize) * userZoom
        let center = modelBounds.center
        let x = (point.x - center.x) * scale + Double(drawableSize.width) / 2 + panOffsetPixels.x
        let y = Double(drawableSize.height) / 2 - (point.y - center.y) * scale + panOffsetPixels.y
        return SIMD2<Double>(x, y)
    }

    func worldViewportBounds(
        drawableSize: CGSize,
        viewSize: CGSize
    ) -> Kernel.CADBounds {
        guard !modelBounds.isEmpty else { return .empty }
        let scale = fitScale(drawableSize: drawableSize, viewSize: viewSize) * userZoom
        guard scale.isFinite, scale > 0 else { return modelBounds }

        let corners = [
            SIMD2<Double>(0, 0),
            SIMD2<Double>(Double(drawableSize.width), 0),
            SIMD2<Double>(0, Double(drawableSize.height)),
            SIMD2<Double>(Double(drawableSize.width), Double(drawableSize.height))
        ]
        let bounds = corners.reduce(Kernel.CADBounds.empty) { partial, screenPoint in
            partial.including(
                worldPoint(
                    forScreenPoint: screenPoint,
                    drawableSize: drawableSize,
                    viewSize: viewSize
                )
            )
        }
        return bounds.expanded(by: max(4 / scale, 0.001))
    }

    func worldPoint(
        forScreenPoint screenPoint: SIMD2<Double>,
        drawableSize: CGSize,
        viewSize: CGSize
    ) -> Kernel.CADPoint {
        let scale = fitScale(drawableSize: drawableSize, viewSize: viewSize) * userZoom
        let center = modelBounds.center
        let x = (screenPoint.x - Double(drawableSize.width) / 2 - panOffsetPixels.x) / scale + center.x
        let y = (Double(drawableSize.height) / 2 + panOffsetPixels.y - screenPoint.y) / scale + center.y
        return Kernel.CADPoint(x: x, y: y)
    }

    func keepWorldPoint(
        _ worldPoint: Kernel.CADPoint,
        atScreenPoint screenPoint: SIMD2<Double>,
        drawableSize: CGSize,
        viewSize: CGSize
    ) {
        let scale = fitScale(drawableSize: drawableSize, viewSize: viewSize) * userZoom
        guard scale.isFinite, scale > 0 else { return }
        let center = modelBounds.center
        panOffsetPixels.x = screenPoint.x
            - Double(drawableSize.width) / 2
            - (worldPoint.x - center.x) * scale
        panOffsetPixels.y = screenPoint.y
            - Double(drawableSize.height) / 2
            + (worldPoint.y - center.y) * scale
    }

    func modelToScreenScale(drawableSize: CGSize, viewSize: CGSize) -> Double {
        fitScale(drawableSize: drawableSize, viewSize: viewSize) * userZoom
    }

    func fitScale(drawableSize: CGSize, viewSize: CGSize) -> Double {
        guard !modelBounds.isEmpty, modelBounds.width > 0, modelBounds.height > 0 else { return 1 }
        let viewScale = Double(max(drawableSize.width / max(viewSize.width, 1), 1))
        let padding = fitContentInsetPoints(viewSize: viewSize) * viewScale
        let availableWidth = max(Double(drawableSize.width) - padding * 2, 1)
        let availableHeight = max(Double(drawableSize.height) - padding * 2, 1)
        return max(min(availableWidth / modelBounds.width, availableHeight / modelBounds.height), 0.0001)
    }

    func fitContentInsetPoints(viewSize: CGSize) -> Double {
        min(max(Double(min(viewSize.width, viewSize.height)) * 0.018, 6), 14)
    }

    func ndcPoint(fromScreen point: SIMD2<Double>, drawableSize: CGSize) -> SIMD2<Float> {
        let x = point.x / Double(drawableSize.width) * 2 - 1
        let y = 1 - point.y / Double(drawableSize.height) * 2
        return SIMD2<Float>(Float(x), Float(y))
    }

    func rgbaVector(fromARGB argb: UInt32) -> SIMD4<Float> {
        let alpha = Float((argb >> 24) & 0xFF) / 255
        let red = Float((argb >> 16) & 0xFF) / 255
        let green = Float((argb >> 8) & 0xFF) / 255
        let blue = Float(argb & 0xFF) / 255
        return SIMD4<Float>(red, green, blue, max(alpha, 1))
    }

    func hatchFillColor(fromARGB argb: UInt32) -> SIMD4<Float> {
        let source = rgbaVector(fromARGB: argb)
        let paper = SIMD3<Float>(0.972, 0.976, 0.984)
        let amount: Float = 0.18
        return SIMD4<Float>(
            paper.x * (1 - amount) + source.x * amount,
            paper.y * (1 - amount) + source.y * amount,
            paper.z * (1 - amount) + source.z * amount,
            1
        )
    }

    private struct CADTextAtlasItem {
        var text: Kernel.CADTextRun
        var widthPoints: CGFloat
        var heightPoints: CGFloat
        var fontSizePoints: CGFloat
        var worldHeight: Double
        var alignmentOffset: CGPoint
        var glyphs: [CADTextAtlasGlyph]

        init(
            text: Kernel.CADTextRun,
            widthPoints: CGFloat,
            heightPoints: CGFloat,
            fontSizePoints: CGFloat,
            worldHeight: Double,
            alignmentOffset: CGPoint,
            glyphs: [CADTextAtlasGlyph]
        ) {
            self.text = text
            self.widthPoints = widthPoints
            self.heightPoints = heightPoints
            self.fontSizePoints = fontSizePoints
            self.worldHeight = worldHeight
            self.alignmentOffset = alignmentOffset
            self.glyphs = glyphs
        }
    }

    private struct CADTextAtlasGlyph {
        var cacheKey: CADTextRasterCache.Key
        var image: UIImage
        var offsetX: CGFloat
        var offsetY: CGFloat
        var widthPoints: CGFloat
        var heightPoints: CGFloat
        var advancePoints: CGFloat
    }

    struct CADPackedTextGlyph {
        var image: UIImage
        var rect: CGRect
    }

    private struct CADTextAtlasCommand {
        var text: Kernel.CADTextRun
        var style: Kernel.CADRenderStyle
        var priority: Double
        var ordinal: Int
    }

    private struct CADTextAtlasLayout {
        var items: [CADTextAtlasItem]
        var skippedTextCount: Int
    }

    func makeTextAtlasRenderPlan(
        commands: [Kernel.CADRenderCommand],
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> CADTextAtlasRenderPlan? {
        guard featureOptions.rendersTextOverlays,
              let device,
              drawableSize.width > 1,
              drawableSize.height > 1,
              viewSize.width > 1,
              viewSize.height > 1 else {
            return nil
        }

        let textLayout = textAtlasItems(
            from: commands,
            drawableSize: drawableSize,
            viewSize: viewSize,
            contentScale: contentScale
        )
        let textItems = textLayout.items
        guard !textItems.isEmpty else { return nil }

        let cacheKey = CADTextAtlasTextureCache.Key(
            glyphKeys: textItems.flatMap(\.glyphs).map(\.cacheKey).uniquedAndSortedByStableKey()
        )
        let atlas: CADTextAtlasTextureCache.Entry
        if let cached = textAtlasTextureCache.entry(for: cacheKey) {
            atlas = cached
        } else {
            guard let packedAtlas = makeTextAtlasTexture(
                from: textItems,
                device: device
            ) else {
                return nil
            }
            atlas = packedAtlas
            textAtlasTextureCache.insert(packedAtlas, for: cacheKey, limit: 16)
        }

        let vertexBuild = makeTextAtlasVertices(
            from: textItems,
            packedGlyphs: atlas.packedGlyphs,
            atlasSize: atlas.size,
            drawableSize: drawableSize,
            viewSize: viewSize,
            contentScale: contentScale
        )
        let vertices = vertexBuild.vertices
        guard !vertices.isEmpty else { return nil }

        return CADTextAtlasRenderPlan(
            texture: atlas.texture,
            vertices: vertices,
            textCount: textItems.count,
            skippedTextCount: textLayout.skippedTextCount,
            uniqueTextureCount: atlas.uniqueTextureCount,
            atlasSize: CGSize(width: atlas.size.width, height: atlas.size.height),
            diagnosticRows: textAtlasDiagnosticRows(
                items: textItems,
                vertices: vertices,
                atlasSize: atlas.size,
                fallbackAnchorCount: vertexBuild.fallbackAnchorCount,
                offscreenItemCount: vertexBuild.offscreenItemCount,
                drawableSize: drawableSize,
                viewSize: viewSize,
                contentScale: contentScale
            )
        )
    }

    private func textAtlasItems(
        from commands: [Kernel.CADRenderCommand],
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> CADTextAtlasLayout {
        let modelScale = modelToScreenScale(drawableSize: drawableSize, viewSize: viewSize)
        let viewScale = Self.drawableToViewScale(
            drawableSize: drawableSize,
            viewSize: viewSize,
            fallback: contentScale
        )
        let textCandidates = prioritizedTextAtlasCommands(from: commands, modelScale: modelScale)
        var items: [CADTextAtlasItem] = []
        items.reserveCapacity(min(textCandidates.count, maximumTextAtlasCommandCount))

        for candidate in textCandidates {
            guard items.count < maximumTextAtlasCommandCount else {
                continue
            }
            let text = candidate.text
            let style = candidate.style
            let worldHeight = Self.textOverlayWorldHeight(for: text)
            let fontSize = Self.textOverlayFontSize(
                textHeight: worldHeight,
                modelScale: modelScale,
                contentScale: viewScale.y
            )
            let displayText = text.displayText.isEmpty ? " " : text.displayText
            let font = uiFont(named: text.selectedFontName, supporting: displayText, size: CGFloat(fontSize))
            let textColor = readableTextColor(fromARGB: style.colorARGB)
            let widthFactor = CGFloat(max(text.widthFactor ?? 1, 0.1))
            let glyphs = makeTextAtlasGlyphs(
                displayText: displayText,
                font: font,
                textColor: textColor,
                widthFactor: widthFactor,
                contentScale: contentScale
            )
            guard !glyphs.isEmpty else { continue }
            let glyphBounds = glyphs.reduce(CGRect.null) { partial, glyph in
                partial.union(CGRect(
                    x: glyph.offsetX,
                    y: glyph.offsetY,
                    width: glyph.advancePoints,
                    height: glyph.heightPoints
                ))
            }
            let widthPoints = ceil(max(glyphBounds.width, 1))
            let heightPoints = ceil(max(glyphBounds.height, 1))
            guard widthPoints.isFinite,
                  heightPoints.isFinite,
                  widthPoints > 0,
                  heightPoints > 0 else {
                continue
            }
            let alignmentOffset = textOverlayAlignmentOffset(
                text: text,
                width: Double(widthPoints),
                height: Double(heightPoints),
                modelScale: modelScale,
                viewScale: viewScale
            )
            items.append(CADTextAtlasItem(
                text: text,
                widthPoints: widthPoints,
                heightPoints: heightPoints,
                fontSizePoints: fontSize,
                worldHeight: worldHeight,
                alignmentOffset: alignmentOffset,
                glyphs: glyphs
            ))
        }

        return CADTextAtlasLayout(
            items: items,
            skippedTextCount: max(textCandidates.count - items.count, 0)
        )
    }

    private func prioritizedTextAtlasCommands(
        from commands: [Kernel.CADRenderCommand],
        modelScale: Double
    ) -> [CADTextAtlasCommand] {
        commands.enumerated()
            .compactMap { offset, command -> CADTextAtlasCommand? in
                guard case let .text(text, style) = command else { return nil }
                return CADTextAtlasCommand(
                    text: text,
                    style: style,
                    priority: textAtlasPriority(text: text, modelScale: modelScale),
                    ordinal: offset
                )
            }
            .sorted {
                if abs($0.priority - $1.priority) > 0.0001 {
                    return $0.priority > $1.priority
                }
                return $0.ordinal < $1.ordinal
            }
    }

    private func textAtlasPriority(text: Kernel.CADTextRun, modelScale: Double) -> Double {
        let displayText = text.displayText.isEmpty ? " " : text.displayText
        let screenHeight = max(Self.textOverlayWorldHeight(for: text) * modelScale, 0)
        let lengthWeight = min(Double(displayText.count), 32) * 0.02
        let cjkWeight = displayText.cadContainsCJKScalars ? 1.15 : 1
        return (screenHeight + lengthWeight) * cjkWeight
    }

    private static func textOverlayWorldHeight(for text: Kernel.CADTextRun) -> Double {
        let declaredHeight = text.height.isFinite && text.height > 0 ? text.height : 2.5
        guard let boxHeight = text.boxHeight,
              boxHeight.isFinite,
              boxHeight > 0 else {
            return declaredHeight
        }

        let lineCount = max(text.displayText.cadRenderableLineCount, 1)
        let boxLineHeight = boxHeight / Double(lineCount)

        // LibreDWG can expose MTEXT content and extents while leaving text_height at
        // the CAD default. In that case the glyph atlas is technically produced but
        // too small to see in a deep-zoom construction drawing.
        if declaredHeight <= 2.6, boxLineHeight > declaredHeight * 8 {
            return boxLineHeight
        }

        return declaredHeight
    }

    private func makeTextAtlasGlyphs(
        displayText: String,
        font: UIFont,
        textColor: UIColor,
        widthFactor: CGFloat,
        contentScale: CGFloat
    ) -> [CADTextAtlasGlyph] {
        var glyphs: [CADTextAtlasGlyph] = []
        glyphs.reserveCapacity(displayText.count)

        var cursorX: CGFloat = 0
        var cursorY: CGFloat = 0
        var lineHeight = max(font.lineHeight + 4, 1)
        let colorKey = readableTextColorKey(textColor)
        let scaleBucket = Int((max(contentScale, 1) * 10).rounded())

        for character in displayText {
            if character.isNewline {
                cursorX = 0
                cursorY += lineHeight
                continue
            }

            let glyphText = String(character)
            let glyphFont = Self.rasterFont(for: glyphText, preferredFont: font)
            let pointSizeBucket = Int((glyphFont.pointSize * 2).rounded())
            let cacheKey = CADTextRasterCache.Key(
                displayText: glyphText,
                fontName: glyphFont.fontName,
                pointSizeBucket: pointSizeBucket,
                colorARGB: colorKey,
                scaleBucket: scaleBucket
            )
            guard let image = textRasterCache.image(for: cacheKey, limit: 2_048, makeImage: {
                Self.makeTextOverlayRasterImage(
                    displayText: glyphText,
                    font: glyphFont,
                    textColor: textColor,
                    scale: contentScale
                )
            }) else {
                continue
            }

            let imageWidth = ceil(max(image.size.width, glyphFont.pointSize * 0.35, 1))
            let imageHeight = ceil(max(image.size.height, lineHeight, 1))
            lineHeight = max(lineHeight, imageHeight)
            let measuredAdvance = Self.textAdvancePoints(for: glyphText, font: glyphFont)
            let glyphAdvance = ceil(max(measuredAdvance, glyphFont.pointSize * 0.25, 1)) * widthFactor
            let glyphWidth = imageWidth * widthFactor
            glyphs.append(CADTextAtlasGlyph(
                cacheKey: cacheKey,
                image: image,
                offsetX: cursorX,
                offsetY: cursorY,
                widthPoints: glyphWidth,
                heightPoints: imageHeight,
                advancePoints: glyphAdvance
            ))
            cursorX += glyphAdvance
        }

        return glyphs
    }

    private func makeTextAtlasTexture(
        from items: [CADTextAtlasItem],
        device: MTLDevice
    ) -> CADTextAtlasTextureCache.Entry? {
        let uniqueImages = items.flatMap(\.glyphs).reduce(into: [CADTextRasterCache.Key: UIImage]()) { partial, glyph in
            if partial[glyph.cacheKey] == nil {
                partial[glyph.cacheKey] = glyph.image
            }
        }
        guard !uniqueImages.isEmpty else { return nil }

        let padding = 2
        let maxAtlasSize = 4096
        let maxImageWidth = uniqueImages.values.compactMap(\.cgImage?.width).max() ?? 1
        let atlasWidth = min(max(maxImageWidth + padding * 2, 1024), maxAtlasSize)
        var cursorX = padding
        var cursorY = padding
        var rowHeight = 0
        var packed: [CADTextRasterCache.Key: CADPackedTextGlyph] = [:]

        for (key, image) in uniqueImages.sorted(by: { $0.key.stableSortKey < $1.key.stableSortKey }) {
            guard let cgImage = image.cgImage else { continue }
            let width = min(cgImage.width, maxAtlasSize - padding * 2)
            let height = min(cgImage.height, maxAtlasSize - padding * 2)
            guard width > 0, height > 0 else { continue }

            if cursorX + width + padding > atlasWidth {
                cursorX = padding
                cursorY += rowHeight + padding
                rowHeight = 0
            }
            guard cursorY + height + padding <= maxAtlasSize else { continue }

            packed[key] = CADPackedTextGlyph(
                image: image,
                rect: CGRect(x: cursorX, y: cursorY, width: width, height: height)
            )
            cursorX += width + padding
            rowHeight = max(rowHeight, height)
        }

        let atlasHeight = max(cursorY + rowHeight + padding, 1)
        guard atlasHeight <= maxAtlasSize, !packed.isEmpty else { return nil }

        var pixels = [UInt8](repeating: 0, count: atlasWidth * atlasHeight * 4)
        for glyph in packed.values {
            guard let glyphPixels = Self.rgbaPixels(from: glyph.image),
                  let cgImage = glyph.image.cgImage else {
                continue
            }
            let sourceWidth = min(cgImage.width, Int(glyph.rect.width))
            let sourceHeight = min(cgImage.height, Int(glyph.rect.height))
            let destinationX = Int(glyph.rect.minX)
            let destinationY = Int(glyph.rect.minY)
            for row in 0..<sourceHeight {
                let sourceOffset = row * cgImage.width * 4
                let destinationOffset = ((destinationY + row) * atlasWidth + destinationX) * 4
                let byteCount = sourceWidth * 4
                pixels.replaceSubrange(
                    destinationOffset..<(destinationOffset + byteCount),
                    with: glyphPixels[sourceOffset..<(sourceOffset + byteCount)]
                )
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: atlasWidth,
            height: atlasHeight,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.replace(
            region: MTLRegionMake2D(0, 0, atlasWidth, atlasHeight),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: atlasWidth * 4
        )

        return CADTextAtlasTextureCache.Entry(
            texture: texture,
            packedGlyphs: packed,
            size: (atlasWidth, atlasHeight),
            uniqueTextureCount: packed.count
        )
    }

    private func makeTextAtlasVertices(
        from items: [CADTextAtlasItem],
        packedGlyphs: [CADTextRasterCache.Key: CADPackedTextGlyph],
        atlasSize: (width: Int, height: Int),
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> CADTextAtlasVertexBuildResult {
        let viewScale = Self.drawableToViewScale(
            drawableSize: drawableSize,
            viewSize: viewSize,
            fallback: contentScale
        )
        var vertices: [CADTexturedVertex] = []
        vertices.reserveCapacity(items.reduce(0) { $0 + $1.glyphs.count * 6 })
        var fallbackAnchorCount = 0
        var offscreenItemCount = 0
        let fallbackMargin = max(96 * Double(max(contentScale, 1)), 96)

        for item in items {
            let screen = screenPoint(
                for: item.text.insertionPoint,
                drawableSize: drawableSize,
                viewSize: viewSize
            )
            guard screen.x.isFinite, screen.y.isFinite else { continue }

            let insertionViewPoint = Self.viewPoint(
                fromDrawablePoint: screen,
                drawableSize: drawableSize,
                viewSize: viewSize,
                fallbackScale: contentScale
            )
            let center = Self.textOverlayCenter(
                insertionScreen: insertionViewPoint,
                width: item.widthPoints,
                height: item.heightPoints,
                alignmentOffset: item.alignmentOffset,
                rotationRadians: item.text.rotationRadians
            )
            let itemVertices = makeTextAtlasVertices(
                for: item,
                center: center,
                packedGlyphs: packedGlyphs,
                atlasSize: atlasSize,
                drawableSize: drawableSize,
                viewScale: viewScale
            )
            if Self.texturedVerticesIntersectViewport(itemVertices)
                || !Self.drawablePointIsNearViewport(screen, drawableSize: drawableSize, margin: fallbackMargin) {
                if !Self.texturedVerticesIntersectViewport(itemVertices) {
                    offscreenItemCount += 1
                }
                vertices.append(contentsOf: itemVertices)
                continue
            }

            let fallbackCenter = Self.textOverlayCenter(
                insertionScreen: insertionViewPoint,
                width: item.widthPoints,
                height: item.heightPoints,
                alignmentOffset: .zero,
                rotationRadians: item.text.rotationRadians
            )
            let fallbackVertices = makeTextAtlasVertices(
                for: item,
                center: fallbackCenter,
                packedGlyphs: packedGlyphs,
                atlasSize: atlasSize,
                drawableSize: drawableSize,
                viewScale: viewScale
            )
            fallbackAnchorCount += 1
            if !Self.texturedVerticesIntersectViewport(fallbackVertices) {
                offscreenItemCount += 1
            }
            vertices.append(contentsOf: fallbackVertices)
        }

        return CADTextAtlasVertexBuildResult(
            vertices: vertices,
            fallbackAnchorCount: fallbackAnchorCount,
            offscreenItemCount: offscreenItemCount
        )
    }

    private func makeTextAtlasVertices(
        for item: CADTextAtlasItem,
        center: CGPoint,
        packedGlyphs: [CADTextRasterCache.Key: CADPackedTextGlyph],
        atlasSize: (width: Int, height: Int),
        drawableSize: CGSize,
        viewScale: CGPoint
    ) -> [CADTexturedVertex] {
        var vertices: [CADTexturedVertex] = []
        vertices.reserveCapacity(item.glyphs.count * 6)
        let screenAngle = -item.text.rotationRadians
        let cosine = cos(screenAngle)
        let sine = sin(screenAngle)

        for glyphItem in item.glyphs {
            guard let glyph = packedGlyphs[glyphItem.cacheKey] else { continue }
            let localCenterX = Double(glyphItem.offsetX + glyphItem.widthPoints / 2 - item.widthPoints / 2)
            let localCenterY = Double(glyphItem.offsetY + glyphItem.heightPoints / 2 - item.heightPoints / 2)
            let rotatedCenter = CGPoint(
                x: center.x + CGFloat(localCenterX * cosine - localCenterY * sine),
                y: center.y + CGFloat(localCenterX * sine + localCenterY * cosine)
            )
            vertices.append(contentsOf: makeTextAtlasQuadVertices(
                centerViewPoint: rotatedCenter,
                widthPoints: glyphItem.widthPoints,
                heightPoints: glyphItem.heightPoints,
                rotationRadians: item.text.rotationRadians,
                glyphRect: glyph.rect,
                atlasSize: atlasSize,
                drawableSize: drawableSize,
                viewScale: viewScale
            ))
        }

        return vertices
    }

    private func textAtlasDiagnosticRows(
        items: [CADTextAtlasItem],
        vertices: [CADTexturedVertex],
        atlasSize: (width: Int, height: Int),
        fallbackAnchorCount: Int,
        offscreenItemCount: Int,
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> [String] {
        var rows: [String] = [
            "text atlas item \(items.count) / vertex \(vertices.count) / texture \(atlasSize.width)x\(atlasSize.height)"
        ]
        if fallbackAnchorCount > 0 || offscreenItemCount > 0 {
            rows.append("text atlas anchorFallback \(fallbackAnchorCount) / offscreen \(offscreenItemCount)")
        }
        if !vertices.isEmpty {
            let minX = vertices.map(\.position.x).min() ?? 0
            let maxX = vertices.map(\.position.x).max() ?? 0
            let minY = vertices.map(\.position.y).min() ?? 0
            let maxY = vertices.map(\.position.y).max() ?? 0
            let vertexInsideCount = vertices.filter {
                $0.position.x >= -1 && $0.position.x <= 1
                    && $0.position.y >= -1 && $0.position.y <= 1
            }.count
            let quadIntersectsViewport = maxX >= -1 && minX <= 1 && maxY >= -1 && minY <= 1
            rows.append(
                "text atlas ndc x \(Self.formatDiagnosticNumber(Double(minX)))...\(Self.formatDiagnosticNumber(Double(maxX))) y \(Self.formatDiagnosticNumber(Double(minY)))...\(Self.formatDiagnosticNumber(Double(maxY))) / inside \(vertexInsideCount)/\(vertices.count) / intersects \(quadIntersectsViewport)"
            )
        }

        if let first = items.first {
            let drawablePoint = screenPoint(
                for: first.text.insertionPoint,
                drawableSize: drawableSize,
                viewSize: viewSize
            )
            let viewPoint = Self.viewPoint(
                fromDrawablePoint: drawablePoint,
                drawableSize: drawableSize,
                viewSize: viewSize,
                fallbackScale: contentScale
            )
            rows.append(
                "text atlas sample font \(Self.formatDiagnosticNumber(Double(first.fontSizePoints))) / worldH \(Self.formatDiagnosticNumber(first.worldHeight)) / view \(Self.formatDiagnosticNumber(Double(viewPoint.x))),\(Self.formatDiagnosticNumber(Double(viewPoint.y))) / size \(Self.formatDiagnosticNumber(Double(first.widthPoints)))x\(Self.formatDiagnosticNumber(Double(first.heightPoints)))"
            )
            rows.append(
                "text atlas sample \(Self.compactDiagnosticPreview(first.text.displayText))"
            )
        }

        return rows
    }

    private static func texturedVerticesIntersectViewport(_ vertices: [CADTexturedVertex]) -> Bool {
        guard !vertices.isEmpty else { return false }
        let minX = vertices.map(\.position.x).min() ?? 0
        let maxX = vertices.map(\.position.x).max() ?? 0
        let minY = vertices.map(\.position.y).min() ?? 0
        let maxY = vertices.map(\.position.y).max() ?? 0
        return maxX >= -1 && minX <= 1 && maxY >= -1 && minY <= 1
    }

    private static func drawablePointIsNearViewport(
        _ point: SIMD2<Double>,
        drawableSize: CGSize,
        margin: Double
    ) -> Bool {
        point.x >= -margin
            && point.x <= Double(drawableSize.width) + margin
            && point.y >= -margin
            && point.y <= Double(drawableSize.height) + margin
    }

    private func makeTextAtlasQuadVertices(
        centerViewPoint: CGPoint,
        widthPoints: CGFloat,
        heightPoints: CGFloat,
        rotationRadians: Double,
        glyphRect: CGRect,
        atlasSize: (width: Int, height: Int),
        drawableSize: CGSize,
        viewScale: CGPoint
    ) -> [CADTexturedVertex] {
        let halfWidth = Double(widthPoints) / 2
        let halfHeight = Double(heightPoints) / 2
        let screenAngle = -rotationRadians
        let cosine = cos(screenAngle)
        let sine = sin(screenAngle)

        func drawablePoint(localX: Double, localY: Double) -> SIMD2<Double> {
            let rotatedX = localX * cosine - localY * sine
            let rotatedY = localX * sine + localY * cosine
            return SIMD2<Double>(
                (Double(centerViewPoint.x) + rotatedX) * Double(viewScale.x),
                (Double(centerViewPoint.y) + rotatedY) * Double(viewScale.y)
            )
        }

        let topLeft = drawablePoint(localX: -halfWidth, localY: -halfHeight)
        let bottomLeft = drawablePoint(localX: -halfWidth, localY: halfHeight)
        let topRight = drawablePoint(localX: halfWidth, localY: -halfHeight)
        let bottomRight = drawablePoint(localX: halfWidth, localY: halfHeight)

        let u0 = Float(glyphRect.minX / CGFloat(max(atlasSize.width, 1)))
        let v0 = Float(glyphRect.minY / CGFloat(max(atlasSize.height, 1)))
        let u1 = Float(glyphRect.maxX / CGFloat(max(atlasSize.width, 1)))
        let v1 = Float(glyphRect.maxY / CGFloat(max(atlasSize.height, 1)))

        func vertex(_ point: SIMD2<Double>, _ uv: SIMD2<Float>) -> CADTexturedVertex {
            CADTexturedVertex(
                position: ndcPoint(fromScreen: point, drawableSize: drawableSize),
                textureCoordinate: uv
            )
        }

        return [
            vertex(topLeft, SIMD2<Float>(u0, v0)),
            vertex(bottomLeft, SIMD2<Float>(u0, v1)),
            vertex(topRight, SIMD2<Float>(u1, v0)),
            vertex(topRight, SIMD2<Float>(u1, v0)),
            vertex(bottomLeft, SIMD2<Float>(u0, v1)),
            vertex(bottomRight, SIMD2<Float>(u1, v1))
        ]
    }

    private static func rgbaPixels(from image: UIImage) -> [UInt8]? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        let ok = pixels.withUnsafeMutableBytes { rawPixels -> Bool in
            guard let context = CGContext(
                data: rawPixels.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? pixels : nil
    }

    private var maximumTextAtlasCommandCount: Int { 8_192 }
    private var maximumUIKitTextOverlayCount: Int { 2_048 }
    private var usesMetalTextAtlasForLiveRendering: Bool { false }

    private func syncDebugTextMarkers(
        commands: [Kernel.CADRenderCommand],
        view: MTKView,
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) {
        guard debugTextOverlays else {
            for marker in textOverlayMarkers.values {
                marker.removeFromSuperview()
            }
            textOverlayMarkers.removeAll()
            return
        }

        var activeKeys = Set<String>()
        let textCommands = commands.enumerated().compactMap { offset, command -> (String, Kernel.CADTextRun)? in
            guard case let .text(text, _) = command else { return nil }
            return ("text-\(offset)", text)
        }
        for (key, text) in textCommands {
            activeKeys.insert(key)
            let marker = textInsertionMarker(for: key, in: view)
            textOverlayMarkers[key] = marker
            configureTextInsertionMarker(
                marker,
                text: text,
                drawableSize: drawableSize,
                viewSize: viewSize,
                contentScale: contentScale
            )
            view.bringSubviewToFront(marker)
        }

        let staleKeys = textOverlayMarkers.keys.filter { !activeKeys.contains($0) }
        for key in staleKeys {
            textOverlayMarkers[key]?.removeFromSuperview()
            textOverlayMarkers.removeValue(forKey: key)
        }
    }

    private func syncTextOverlayLabels(
        entities: [Kernel.CADEntity],
        view: MTKView,
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> (visible: Int, source: Int, rawSource: Int, skipped: Int, overlapSkipped: Int) {
        guard featureOptions.rendersTextOverlays,
              drawableSize.width > 1,
              drawableSize.height > 1,
              viewSize.width > 1,
              viewSize.height > 1 else {
            clearTextOverlayLabels()
            return (0, 0, 0, entities.filter(Self.isTextEntity).count, 0)
        }

        let modelScale = modelToScreenScale(drawableSize: drawableSize, viewSize: viewSize)
        let viewScale = Self.drawableToViewScale(
            drawableSize: drawableSize,
            viewSize: viewSize,
            fallback: contentScale
        )
        let rawTextEntityCount = entities.filter(Self.isTextEntity).count
        let textEntities = prioritizedTextOverlayEntities(
            entities,
            modelScale: modelScale
        )
        let maxLabelCount = maximumUIKitTextOverlayCount
        var activeKeys = Set<String>()
        var visibleCount = 0
        var overlapSkippedCount = 0
        var visibleTextFrames: [VisibleTextOverlayFrame] = []
        visibleTextFrames.reserveCapacity(min(textEntities.count, maxLabelCount))
        var skippedCount = max(rawTextEntityCount - textEntities.count, 0)
            + max(textEntities.count - maxLabelCount, 0)

        for entity in textEntities.prefix(maxLabelCount) {
            guard let text = entity.text else {
                skippedCount += 1
                continue
            }
            let key = "label-\(entity.id.uuidString)"
            let style = rendererStyle(for: entity)
            activeKeys.insert(key)
            let label = textOverlayLabel(for: key, in: view)
            textOverlayLabels[key] = label
            let isVisible = configureTextOverlayLabel(
                label,
                text: text,
                style: style,
                modelScale: modelScale,
                viewScale: viewScale,
                view: view,
                drawableSize: drawableSize,
                viewSize: viewSize,
                contentScale: contentScale
            )
            if isVisible {
                let visibleFrame = VisibleTextOverlayFrame(
                    text: Self.normalizedTextOverlayFingerprint(text.displayText),
                    rect: label.frame,
                    rotationRadians: text.rotationRadians
                )
                if Self.shouldSuppressVisibleTextOverlay(visibleFrame, keptFrames: visibleTextFrames) {
                    label.isHidden = true
                    skippedCount += 1
                    overlapSkippedCount += 1
                    continue
                }
                visibleTextFrames.append(visibleFrame)
                visibleCount += 1
                view.bringSubviewToFront(label)
            } else {
                skippedCount += 1
            }
        }

        let staleKeys = textOverlayLabels.keys.filter { !activeKeys.contains($0) }
        for key in staleKeys {
            textOverlayLabels[key]?.removeFromSuperview()
            textOverlayLabels.removeValue(forKey: key)
        }

        currentUIKitTextLabelCount = visibleCount
        currentUIKitTextLabelSkippedCount = skippedCount
        return (visibleCount, textEntities.count, rawTextEntityCount, skippedCount, overlapSkippedCount)
    }

    private func textOverlaySourceEntities(
        renderInputEntities: [Kernel.CADEntity],
        renderCommands: [Kernel.CADRenderCommand]
    ) -> [Kernel.CADEntity] {
        guard featureOptions.rendersTextOverlays else { return [] }
        _ = renderCommands
        return renderInputEntities.filter(Self.isTextEntity)
    }

    private func prioritizedTextOverlayEntities(
        _ entities: [Kernel.CADEntity],
        modelScale: Double
    ) -> [Kernel.CADEntity] {
        let sorted = entities
            .filter(Self.isTextEntity)
            .sorted { lhs, rhs in
                let lhsPriority = textOverlayEntityPriority(lhs, modelScale: modelScale)
                let rhsPriority = textOverlayEntityPriority(rhs, modelScale: modelScale)
                if abs(lhsPriority - rhsPriority) > 0.0001 {
                    return lhsPriority > rhsPriority
                }
                let lhsHandle = lhs.sourceHandle ?? lhs.id.uuidString
                let rhsHandle = rhs.sourceHandle ?? rhs.id.uuidString
                return lhsHandle.localizedStandardCompare(rhsHandle) == .orderedAscending
            }
        return deduplicatedTextOverlayEntities(sorted, modelScale: modelScale)
    }

    private func deduplicatedTextOverlayEntities(
        _ entities: [Kernel.CADEntity],
        modelScale: Double
    ) -> [Kernel.CADEntity] {
        let worldTolerance = max(10.0 / max(modelScale, 0.000001), 0.01)
        var kept: [Kernel.CADEntity] = []
        var fingerprints: [TextOverlayFingerprint] = []

        for entity in entities {
            guard let text = entity.text else { continue }
            let displayText = Self.normalizedTextOverlayFingerprint(text.displayText)
            guard !displayText.isEmpty else { continue }
            let fingerprint = TextOverlayFingerprint(
                text: displayText,
                layerID: entity.layerID,
                sourceHandle: entity.sourceHandle?.trimmingCharacters(in: .whitespacesAndNewlines),
                insertionPoint: text.insertionPoint,
                bounds: entity.bounds,
                rotationRadians: text.rotationRadians
            )
            let isDuplicate = fingerprints.contains { existing in
                Self.textOverlayFingerprintsOverlap(
                    existing,
                    fingerprint,
                    tolerance: worldTolerance
                )
            }
            guard !isDuplicate else { continue }
            kept.append(entity)
            fingerprints.append(fingerprint)
        }

        return kept
    }

    private static func textOverlayFingerprintsOverlap(
        _ lhs: TextOverlayFingerprint,
        _ rhs: TextOverlayFingerprint,
        tolerance: Double
    ) -> Bool {
        guard lhs.text == rhs.text else { return false }
        guard lhs.layerID == rhs.layerID else { return false }
        guard textOverlayRotationMatches(lhs.rotationRadians, rhs.rotationRadians) else { return false }

        let sameSourceHandle = lhs.sourceHandle?.isEmpty == false
            && lhs.sourceHandle == rhs.sourceHandle
        if sameSourceHandle,
           distanceBetween(lhs.insertionPoint, rhs.insertionPoint) <= max(tolerance, 1.0) {
            return true
        }

        if distanceBetween(lhs.insertionPoint, rhs.insertionPoint) <= tolerance {
            return true
        }

        if textOverlayBoundsOverlap(lhs.bounds, rhs.bounds, tolerance: tolerance) {
            return true
        }

        return false
    }

    private static func textOverlayRotationMatches(_ lhs: Double, _ rhs: Double) -> Bool {
        let delta = abs(lhs - rhs).truncatingRemainder(dividingBy: .pi * 2)
        return min(delta, .pi * 2 - delta) <= 0.01
    }

    private static func textOverlayBoundsOverlap(
        _ lhs: Kernel.CADBounds,
        _ rhs: Kernel.CADBounds,
        tolerance: Double
    ) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        return lhs.expanded(by: max(tolerance, 0.01)).intersects(rhs)
    }

    private func textOverlayEntityPriority(
        _ entity: Kernel.CADEntity,
        modelScale: Double
    ) -> Double {
        guard let text = entity.text else { return 0 }
        let displayText = text.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayText.isEmpty else { return -1 }
        let kindWeight: Double
        switch entity.kind {
        case .mtext:
            kindWeight = 8
        case .text:
            kindWeight = 7
        case .attrib:
            kindWeight = 6
        case .dimension:
            kindWeight = 2
        default:
            kindWeight = 1
        }
        let cjkWeight = displayText.cadContainsCJKScalars ? 10.0 : 0.0
        let screenHeight = Self.textOverlayWorldHeight(for: text) * modelScale
        let lengthWeight = min(Double(displayText.count), 32.0) * 0.04
        return cjkWeight + kindWeight + max(screenHeight, 0) + lengthWeight
    }

    private static func normalizedTextOverlayFingerprint(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "\n")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func shouldSuppressVisibleTextOverlay(
        _ candidate: VisibleTextOverlayFrame,
        keptFrames: [VisibleTextOverlayFrame]
    ) -> Bool {
        guard !candidate.text.isEmpty, !candidate.rect.isNull, !candidate.rect.isEmpty else {
            return false
        }
        return keptFrames.contains { kept in
            guard kept.text == candidate.text else { return false }
            guard textOverlayRotationMatches(kept.rotationRadians, candidate.rotationRadians) else { return false }
            return textOverlayScreenRectsOverlap(kept.rect, candidate.rect)
        }
    }

    private static func textOverlayScreenRectsOverlap(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        guard !lhs.isNull, !rhs.isNull, !lhs.isEmpty, !rhs.isEmpty else { return false }
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return false }
        let smallerArea = min(lhs.width * lhs.height, rhs.width * rhs.height)
        guard smallerArea > 0 else { return false }
        return (intersection.width * intersection.height) / smallerArea >= 0.70
    }

    private func rendererStyle(for entity: Kernel.CADEntity) -> Kernel.CADRenderStyle {
        let layer = layersByID[entity.layerID] ?? .default
        let color = entity.color == 0x00000000 ? layer.colorARGB : entity.color
        let lineWidth = entity.lineWeight > 0 ? entity.lineWeight : layer.lineWeight
        let entityLineType = entity.lineType.trimmingCharacters(in: .whitespacesAndNewlines)
        let lineType: String
        if entityLineType.isEmpty ||
            entityLineType.caseInsensitiveCompare("ByLayer") == .orderedSame ||
            entityLineType.caseInsensitiveCompare("ByBlock") == .orderedSame {
            lineType = layer.lineType
        } else {
            lineType = entityLineType
        }
        return Kernel.CADRenderStyle(
            layerID: entity.layerID,
            colorARGB: color,
            lineWidth: max(lineWidth, 0.25),
            lineType: lineType
        )
    }

    private func textOverlayLabel(for key: String, in view: MTKView) -> UILabel {
        if let label = textOverlayLabels[key] {
            if label.superview !== view {
                label.removeFromSuperview()
                view.addSubview(label)
            }
            return label
        }

        let label = UILabel(frame: .zero)
        label.backgroundColor = .clear
        label.isOpaque = false
        label.isUserInteractionEnabled = false
        label.numberOfLines = 0
        label.lineBreakMode = .byClipping
        label.adjustsFontSizeToFitWidth = false
        label.layer.zPosition = 1_050
        label.layer.allowsEdgeAntialiasing = true
        view.addSubview(label)
        return label
    }

    @discardableResult
    private func configureTextOverlayLabel(
        _ label: UILabel,
        text: Kernel.CADTextRun,
        style: Kernel.CADRenderStyle,
        modelScale: Double,
        viewScale: CGPoint,
        view: MTKView,
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> Bool {
        let displayText = text.displayText.isEmpty ? " " : text.displayText
        let worldHeight = Self.textOverlayWorldHeight(for: text)
        let fontSize = Self.textOverlayFontSize(
            textHeight: worldHeight,
            modelScale: modelScale,
            contentScale: viewScale.y
        )
        guard fontSize.isFinite, fontSize > 0 else {
            label.isHidden = true
            return false
        }

        let font = uiFont(named: text.selectedFontName, supporting: displayText, size: CGFloat(fontSize))
        let textColor = readableTextColor(fromARGB: style.colorARGB)
        label.text = displayText
        label.font = font
        label.textColor = textColor

        let cadBoxTargetWidth = text.boxWidth.flatMap { boxWidth -> CGFloat? in
            guard boxWidth.isFinite, boxWidth > 0 else { return nil }
            let scaled = boxWidth * modelScale / Double(max(viewScale.x, 0.000001))
            return CGFloat(max(scaled, Double(fontSize)))
        }
        let unwrappedFittingSize = CGSize(
            width: max(viewSize.width * 32, 32_768),
            height: max(viewSize.height * 8, 8_192)
        )
        let unwrappedSize = label.sizeThatFits(unwrappedFittingSize)
        let fittingWidth = Self.textOverlayFittingWidth(
            cadBoxTargetWidth: cadBoxTargetWidth,
            unwrappedWidth: unwrappedSize.width,
            fontSize: fontSize
        )
        let fittingSize = CGSize(
            width: fittingWidth,
            height: max(viewSize.height * 4, 4096)
        )
        let measuredSize = label.sizeThatFits(fittingSize)
        let width = ceil(max(fittingWidth, measuredSize.width, 1))
        let height = ceil(max(measuredSize.height, font.lineHeight, 1))
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            label.isHidden = true
            return false
        }

        let screen = screenPoint(
            for: text.insertionPoint,
            drawableSize: drawableSize,
            viewSize: viewSize
        )
        guard screen.x.isFinite, screen.y.isFinite else {
            label.isHidden = true
            return false
        }

        let insertionViewPoint = Self.viewPoint(
            fromDrawablePoint: screen,
            drawableSize: drawableSize,
            viewSize: viewSize,
            fallbackScale: contentScale
        )
        let alignmentOffset = textOverlayAlignmentOffset(
            text: text,
            width: Double(width),
            height: Double(height),
            modelScale: modelScale,
            viewScale: viewScale
        )
        var center = Self.textOverlayCenter(
            insertionScreen: insertionViewPoint,
            width: width,
            height: height,
            alignmentOffset: alignmentOffset,
            rotationRadians: text.rotationRadians
        )
        if !Self.viewRect(center: center, size: CGSize(width: width, height: height))
            .intersects(view.bounds.insetBy(dx: -96, dy: -96)),
           Self.drawablePointIsNearViewport(
            screen,
            drawableSize: drawableSize,
            margin: max(96 * Double(max(contentScale, 1)), 96)
           ) {
            center = Self.textOverlayCenter(
                insertionScreen: insertionViewPoint,
                width: width,
                height: height,
                alignmentOffset: .zero,
                rotationRadians: text.rotationRadians
            )
        }

        label.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        label.center = center
        label.transform = CGAffineTransform(rotationAngle: CGFloat(-text.rotationRadians))
        label.isHidden = false
        return true
    }

    private static func textOverlayFittingWidth(
        cadBoxTargetWidth: CGFloat?,
        unwrappedWidth: CGFloat,
        fontSize: CGFloat
    ) -> CGFloat {
        let safeUnwrappedWidth = unwrappedWidth.isFinite && unwrappedWidth > 0
            ? unwrappedWidth
            : max(fontSize, 1)
        let safeBoxWidth = cadBoxTargetWidth.flatMap { width -> CGFloat? in
            guard width.isFinite, width > 0 else { return nil }
            return width
        }

        // LibreDWG often exposes MTEXT rect_width/extents_width values that are
        // much narrower than the actual single-line construction label. UIKit
        // would auto-wrap every label into columns. Keep explicit MTEXT newlines
        // from displayText, but do not introduce extra wrapping from a narrow box.
        return ceil(max(safeBoxWidth ?? 0, safeUnwrappedWidth, fontSize, 1))
    }

    private static func viewRect(center: CGPoint, size: CGSize) -> CGRect {
        CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func clearTextOverlayLabels() {
        for label in textOverlayLabels.values {
            label.removeFromSuperview()
        }
        textOverlayLabels.removeAll()
        currentUIKitTextLabelCount = 0
        currentUIKitTextLabelSkippedCount = 0
    }

    private func textInsertionMarker(for key: String, in view: MTKView) -> UIView {
        if let marker = textOverlayMarkers[key] {
            if marker.superview !== view {
                marker.removeFromSuperview()
                view.addSubview(marker)
            }
            return marker
        }
        return makeTextInsertionMarker(in: view)
    }

    private func makeTextInsertionMarker(in view: MTKView) -> UIView {
        let marker = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        marker.backgroundColor = .clear
        marker.isUserInteractionEnabled = false
        marker.layer.zPosition = 1_100

        let horizontal = CALayer()
        horizontal.name = "horizontal"
        horizontal.backgroundColor = UIColor.systemRed.cgColor
        marker.layer.addSublayer(horizontal)

        let vertical = CALayer()
        vertical.name = "vertical"
        vertical.backgroundColor = UIColor.systemRed.cgColor
        marker.layer.addSublayer(vertical)

        view.addSubview(marker)
        return marker
    }

    private func configureTextInsertionMarker(
        _ marker: UIView,
        text: Kernel.CADTextRun,
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) {
        let screen = screenPoint(
            for: text.insertionPoint,
            drawableSize: drawableSize,
            viewSize: viewSize
        )
        guard screen.x.isFinite, screen.y.isFinite else {
            marker.isHidden = true
            return
        }

        let markerSize: CGFloat = 10
        marker.bounds = CGRect(x: 0, y: 0, width: markerSize, height: markerSize)
        marker.center = Self.viewPoint(
            fromDrawablePoint: screen,
            drawableSize: drawableSize,
            viewSize: viewSize,
            fallbackScale: contentScale
        )
        marker.layer.sublayers?.first { $0.name == "horizontal" }?.frame = CGRect(
            x: 0,
            y: markerSize / 2 - 0.75,
            width: markerSize,
            height: 1.5
        )
        marker.layer.sublayers?.first { $0.name == "vertical" }?.frame = CGRect(
            x: markerSize / 2 - 0.75,
            y: 0,
            width: 1.5,
            height: markerSize
        )
        marker.isHidden = false
    }

    private func textOverlayAlignmentOffset(
        text: Kernel.CADTextRun,
        width: Double,
        height: Double,
        modelScale: Double,
        viewScale: CGPoint
    ) -> CGPoint {
        if let attachmentCode = Self.cadMTextAttachmentCode(for: text) {
            return Self.cadMTextAttachmentOverlayOffset(
                attachmentCode: attachmentCode,
                width: width,
                height: height
            )
        }

        let xScale = modelScale / Double(max(viewScale.x, 0.000001))
        let yScale = modelScale / Double(max(viewScale.y, 0.000001))
        let textWidth = text.boxWidth.flatMap { $0 > 0 ? $0 : nil }
            ?? width / max(xScale, 0.000001)
        let textHeight = text.boxHeight.flatMap { $0 > 0 ? $0 : nil }
            ?? max(text.height, height / max(yScale, 0.000001))
        let xWorldOffset = cadTextHorizontalOffset(width: textWidth, text: text)
        let yWorldOffset = cadTextVerticalOffset(height: textHeight, text: text)
        return CGPoint(x: xWorldOffset * xScale, y: yWorldOffset * yScale)
    }

    private static func cadMTextAttachmentCode(for text: Kernel.CADTextRun) -> Int? {
        guard let horizontal = text.horizontalAlignmentCode,
              let vertical = text.verticalAlignmentCode,
              horizontal == vertical,
              (1...9).contains(horizontal),
              text.boxWidth != nil || text.boxHeight != nil else {
            return nil
        }
        return horizontal
    }

    private static func cadMTextAttachmentOverlayOffset(
        attachmentCode: Int,
        width: Double,
        height: Double
    ) -> CGPoint {
        let safeWidth = max(width.isFinite ? width : 0, 0)
        let safeHeight = max(height.isFinite ? height : 0, 0)
        let xOffset: Double
        switch attachmentCode {
        case 2, 5, 8:
            xOffset = safeWidth / 2
        case 3, 6, 9:
            xOffset = safeWidth
        default:
            xOffset = 0
        }

        let yOffset: Double
        switch attachmentCode {
        case 1, 2, 3:
            yOffset = safeHeight
        case 4, 5, 6:
            yOffset = safeHeight / 2
        default:
            yOffset = 0
        }

        return CGPoint(x: xOffset, y: yOffset)
    }

    static func textOverlayFontSize(
        textHeight: Double,
        modelScale: Double,
        contentScale: CGFloat
    ) -> CGFloat {
        let scale = Double(max(contentScale, 1))
        let rawSize = textHeight * modelScale / scale
        return CGFloat(min(max(rawSize, 5), 256))
    }

    static func textOverlayCenter(
        insertionScreen: CGPoint,
        width: CGFloat,
        height: CGFloat,
        alignmentOffset: CGPoint,
        rotationRadians: Double
    ) -> CGPoint {
        let localCenter = CGPoint(
            x: width / 2 - alignmentOffset.x,
            y: alignmentOffset.y - height / 2
        )
        let screenAngle = -CGFloat(rotationRadians)
        let cosine = cos(screenAngle)
        let sine = sin(screenAngle)
        let rotated = CGPoint(
            x: localCenter.x * cosine - localCenter.y * sine,
            y: localCenter.x * sine + localCenter.y * cosine
        )
        return CGPoint(
            x: insertionScreen.x + rotated.x,
            y: insertionScreen.y + rotated.y
        )
    }

    static func viewPoint(
        fromDrawablePoint point: SIMD2<Double>,
        drawableSize: CGSize,
        viewSize: CGSize,
        fallbackScale: CGFloat
    ) -> CGPoint {
        let scale = drawableToViewScale(
            drawableSize: drawableSize,
            viewSize: viewSize,
            fallback: fallbackScale
        )
        return CGPoint(
            x: CGFloat(point.x) / max(scale.x, 0.000001),
            y: CGFloat(point.y) / max(scale.y, 0.000001)
        )
    }

    private static func drawableToViewScale(
        drawableSize: CGSize,
        viewSize: CGSize,
        fallback: CGFloat
    ) -> CGPoint {
        let fallback = max(fallback, 1)
        let x = viewSize.width > 0 ? drawableSize.width / viewSize.width : fallback
        let y = viewSize.height > 0 ? drawableSize.height / viewSize.height : fallback
        return CGPoint(
            x: max(x.isFinite && x > 0 ? x : fallback, 0.000001),
            y: max(y.isFinite && y > 0 ? y : fallback, 0.000001)
        )
    }

    private func cadTextHorizontalOffset(width: Double, text: Kernel.CADTextRun) -> Double {
        if text.boxWidth != nil, let alignmentCode = text.horizontalAlignmentCode {
            switch alignmentCode {
            case 2, 5, 8:
                return width / 2
            case 3, 6, 9:
                return width
            default:
                return 0
            }
        }

        switch text.horizontalAlignmentCode {
        case 1, 3, 4, 5:
            return width / 2
        case 2:
            return width
        default:
            return 0
        }
    }

    private func cadTextVerticalOffset(height: Double, text: Kernel.CADTextRun) -> Double {
        if text.boxHeight != nil, let alignmentCode = text.verticalAlignmentCode {
            switch alignmentCode {
            case 1, 2, 3:
                return height
            case 4, 5, 6:
                return height / 2
            default:
                return 0
            }
        }

        switch text.verticalAlignmentCode {
        case 2:
            return height / 2
        case 3:
            return height
        default:
            return 0
        }
    }

    private func uiFont(named name: String, supporting text: String, size: CGFloat) -> UIFont {
        if let font = UIFont(name: name, size: size), font.supportsCADText(text) {
            return font
        }
        if let family = UIFont.familyNames.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
           let fontName = UIFont.fontNames(forFamilyName: family).first,
           let font = UIFont(name: fontName, size: size),
           font.supportsCADText(text) {
            return font
        }
        for fallbackName in [
            "PingFang SC",
            "Hiragino Sans GB",
            "Heiti SC",
            "Songti SC",
            "FangSong",
            "STFangsong",
            "FangSong_GB2312",
            "SimFang"
        ] {
            if let font = UIFont(name: fallbackName, size: size), font.supportsCADText(text) {
                return font
            }
            if let family = UIFont.familyNames.first(where: { $0.caseInsensitiveCompare(fallbackName) == .orderedSame }),
               let fontName = UIFont.fontNames(forFamilyName: family).first,
               let font = UIFont(name: fontName, size: size),
               font.supportsCADText(text) {
                return font
            }
        }
        return Self.rasterFallbackFont(supporting: text, size: size)
    }

    private func uiColor(fromARGB argb: UInt32) -> UIColor {
        let alpha = CGFloat((argb >> 24) & 0xFF) / 255
        let red = CGFloat((argb >> 16) & 0xFF) / 255
        let green = CGFloat((argb >> 8) & 0xFF) / 255
        let blue = CGFloat(argb & 0xFF) / 255
        return UIColor(red: red, green: green, blue: blue, alpha: max(alpha, 1))
    }

    private func readableTextColor(fromARGB argb: UInt32) -> UIColor {
        let alpha = CGFloat((argb >> 24) & 0xFF) / 255
        let red = CGFloat((argb >> 16) & 0xFF) / 255
        let green = CGFloat((argb >> 8) & 0xFF) / 255
        let blue = CGFloat(argb & 0xFF) / 255
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        if luminance > 0.82 {
            return UIColor(red: 0.10, green: 0.12, blue: 0.14, alpha: max(alpha, 1))
        }
        return UIColor(red: red, green: green, blue: blue, alpha: max(alpha, 1))
    }

    private func readableTextColorKey(_ color: UIColor) -> UInt32 {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (UInt32((max(min(alpha, 1), 0) * 255).rounded()) << 24)
            | (UInt32((max(min(red, 1), 0) * 255).rounded()) << 16)
            | (UInt32((max(min(green, 1), 0) * 255).rounded()) << 8)
            | UInt32((max(min(blue, 1), 0) * 255).rounded())
    }

}

#if os(iOS)
private struct CADTextRasterCache {
    struct Key: Hashable {
        var displayText: String
        var fontName: String
        var pointSizeBucket: Int
        var colorARGB: UInt32
        var scaleBucket: Int
    }

    private var images: [Key: UIImage] = [:]
    private var order: [Key] = []

    mutating func image(for key: Key, limit: Int, makeImage: () -> UIImage?) -> UIImage? {
        if let cached = images[key] {
            return cached
        }
        guard let image = makeImage() else {
            return nil
        }
        images[key] = image
        order.append(key)
        trim(to: limit)
        return image
    }

    mutating func removeAll() {
        images.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }

    private mutating func trim(to limit: Int) {
        let safeLimit = max(limit, 32)
        while images.count > safeLimit, let oldest = order.first {
            order.removeFirst()
            images.removeValue(forKey: oldest)
        }
    }
}

private extension CADTextRasterCache.Key {
    var stableSortKey: String {
        "\(displayText)|\(fontName)|\(pointSizeBucket)|\(colorARGB)|\(scaleBucket)"
    }
}

private extension Array where Element == CADTextRasterCache.Key {
    func uniquedAndSortedByStableKey() -> [Element] {
        var seen = Set<Element>()
        var result: [Element] = []
        result.reserveCapacity(count)
        for key in self where !seen.contains(key) {
            seen.insert(key)
            result.append(key)
        }
        return result.sorted { $0.stableSortKey < $1.stableSortKey }
    }
}

private struct CADTextAtlasTextureCache {
    struct Key: Hashable {
        var glyphKeys: [CADTextRasterCache.Key]
    }

    struct Entry {
        var texture: MTLTexture
        var packedGlyphs: [CADTextRasterCache.Key: CADPoC.CADMetalRenderer.CADPackedTextGlyph]
        var size: (width: Int, height: Int)
        var uniqueTextureCount: Int
    }

    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    private(set) var hitCount = 0

    var entryCount: Int {
        entries.count
    }

    mutating func entry(for key: Key) -> Entry? {
        guard let entry = entries[key] else {
            return nil
        }
        hitCount += 1
        touch(key)
        return entry
    }

    mutating func insert(_ entry: Entry, for key: Key, limit: Int) {
        entries[key] = entry
        touch(key)
        trim(to: limit)
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
        hitCount = 0
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private mutating func trim(to limit: Int) {
        let safeLimit = max(limit, 1)
        while entries.count > safeLimit, let oldest = order.first {
            order.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }
}

extension CADPoC.CADMetalRenderer {
    struct CADTextAtlasSnapshot {
        var textCount: Int
        var skippedTextCount: Int
        var uniqueTextureCount: Int
        var vertexCount: Int
        var atlasSize: CGSize
        var diagnosticRows: [String]
        var cacheEntryCount: Int
        var cacheHitCount: Int
    }

    static func textOverlayFontSizeForTesting(
        textHeight: Double,
        modelScale: Double,
        contentScale: CGFloat
    ) -> CGFloat {
        textOverlayFontSize(
            textHeight: textHeight,
            modelScale: modelScale,
            contentScale: contentScale
        )
    }

    static func textOverlayWorldHeightForTesting(text: Kernel.CADTextRun) -> Double {
        textOverlayWorldHeight(for: text)
    }

    static func textOverlayCenterForTesting(
        insertionScreen: CGPoint,
        width: CGFloat,
        height: CGFloat,
        alignmentOffset: CGPoint,
        rotationRadians: Double
    ) -> CGPoint {
        textOverlayCenter(
            insertionScreen: insertionScreen,
            width: width,
            height: height,
            alignmentOffset: alignmentOffset,
            rotationRadians: rotationRadians
        )
    }

    static func textOverlayViewPointForTesting(
        drawablePoint: SIMD2<Double>,
        drawableSize: CGSize,
        viewSize: CGSize,
        fallbackScale: CGFloat
    ) -> CGPoint {
        viewPoint(
            fromDrawablePoint: drawablePoint,
            drawableSize: drawableSize,
            viewSize: viewSize,
            fallbackScale: fallbackScale
        )
    }

    func textOverlayAlignmentOffsetForTesting(
        text: Kernel.CADTextRun,
        width: Double,
        height: Double,
        modelScale: Double,
        viewScale: CGPoint
    ) -> CGPoint {
        textOverlayAlignmentOffset(
            text: text,
            width: width,
            height: height,
            modelScale: modelScale,
            viewScale: viewScale
        )
    }

    static func textOverlayFittingWidthForTesting(
        cadBoxTargetWidth: CGFloat?,
        unwrappedWidth: CGFloat,
        fontSize: CGFloat
    ) -> CGFloat {
        textOverlayFittingWidth(
            cadBoxTargetWidth: cadBoxTargetWidth,
            unwrappedWidth: unwrappedWidth,
            fontSize: fontSize
        )
    }

    func vertexCountForTesting(
        commands: [Kernel.CADRenderCommand],
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> Int {
        makeVertices(
            commands: commands,
            drawableSize: drawableSize,
            viewSize: viewSize,
            contentScale: contentScale
        ).count
    }

    func searchHighlightVertexCountForTesting(
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> Int {
        makeSearchHighlightVertices(
            drawableSize: drawableSize,
            viewSize: viewSize,
            contentScale: contentScale
        ).count
    }

    func textAtlasSnapshotForTesting(
        commands: [Kernel.CADRenderCommand],
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> CADTextAtlasSnapshot? {
        guard let plan = makeTextAtlasRenderPlan(
            commands: commands,
            drawableSize: drawableSize,
            viewSize: viewSize,
            contentScale: contentScale
        ) else {
            return nil
        }
        return CADTextAtlasSnapshot(
            textCount: plan.textCount,
            skippedTextCount: plan.skippedTextCount,
            uniqueTextureCount: plan.uniqueTextureCount,
            vertexCount: plan.vertices.count,
            atlasSize: plan.atlasSize,
            diagnosticRows: plan.diagnosticRows,
            cacheEntryCount: textAtlasTextureCache.entryCount,
            cacheHitCount: textAtlasTextureCache.hitCount
        )
    }

    func textAtlasLayoutWidthForTesting(
        displayText: String,
        font: UIFont,
        widthFactor: CGFloat,
        contentScale: CGFloat
    ) -> CGFloat {
        let glyphs = makeTextAtlasGlyphs(
            displayText: displayText,
            font: font,
            textColor: .black,
            widthFactor: widthFactor,
            contentScale: contentScale
        )
        let bounds = glyphs.reduce(CGRect.null) { partial, glyph in
            partial.union(CGRect(
                x: glyph.offsetX,
                y: glyph.offsetY,
                width: glyph.advancePoints,
                height: glyph.heightPoints
            ))
        }
        return bounds.isNull ? 0 : bounds.width
    }

    func textAtlasRenderedDisplayTextsForTesting(
        commands: [Kernel.CADRenderCommand],
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> [String] {
        textAtlasItems(
            from: commands,
            drawableSize: drawableSize,
            viewSize: viewSize,
            contentScale: contentScale
        ).items.map(\.text.displayText)
    }

    func textOverlaySourceDisplayTextsForTesting(
        renderInputEntities: [Kernel.CADEntity],
        renderCommands: [Kernel.CADRenderCommand]
    ) -> [String] {
        textOverlaySourceEntities(
            renderInputEntities: renderInputEntities,
            renderCommands: renderCommands
        ).compactMap(\.text?.displayText)
    }

    func deduplicatedTextOverlaySourceDisplayTextsForTesting(
        renderInputEntities: [Kernel.CADEntity],
        renderCommands: [Kernel.CADRenderCommand],
        modelScale: Double
    ) -> [String] {
        prioritizedTextOverlayEntities(
            textOverlaySourceEntities(
                renderInputEntities: renderInputEntities,
                renderCommands: renderCommands
            ),
            modelScale: modelScale
        ).compactMap(\.text?.displayText)
    }

    static func suppressesVisibleTextOverlayForTesting(
        candidateText: String,
        candidateRect: CGRect,
        kept: [(text: String, rect: CGRect)],
        rotationRadians: Double = 0
    ) -> Bool {
        shouldSuppressVisibleTextOverlay(
            VisibleTextOverlayFrame(
                text: normalizedTextOverlayFingerprint(candidateText),
                rect: candidateRect,
                rotationRadians: rotationRadians
            ),
            keptFrames: kept.map {
                VisibleTextOverlayFrame(
                    text: normalizedTextOverlayFingerprint($0.text),
                    rect: $0.rect,
                    rotationRadians: rotationRadians
                )
            }
        )
    }

    func textAtlasSkippedTextCountForTesting(
        commands: [Kernel.CADRenderCommand],
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) -> Int {
        textAtlasItems(
            from: commands,
            drawableSize: drawableSize,
            viewSize: viewSize,
            contentScale: contentScale
        ).skippedTextCount
    }

    static func textAdvanceWidthForTesting(text: String, font: UIFont) -> CGFloat {
        textAdvancePoints(for: text, font: font)
    }

    func renderableEntityCountForTesting() -> Int {
        entities.count
    }

    func modelBoundsForTesting() -> Kernel.CADBounds {
        modelBounds
    }

    func progressiveRenderOutputForTesting(
        visibleEntities: [Kernel.CADEntity],
        viewportBounds: Kernel.CADBounds,
        zoomScale: Double,
        phase: Kernel.CADRenderInteractionPhase
    ) -> CADPoC.CADRenderPipeline.Output {
        setInteractionPhase(phase)
        return renderOutputForFrame(
            visibleEntities: visibleEntities,
            viewportBounds: viewportBounds,
            zoomScale: zoomScale
        ).output
    }

    static func makeTextOverlayRasterImage(
        displayText: String,
        font: UIFont,
        textColor: UIColor,
        scale: CGFloat
    ) -> UIImage? {
        let text = displayText.isEmpty ? " " : displayText
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        paragraphStyle.lineBreakMode = .byClipping
        let attributedText = rasterAttributedString(
            text,
            preferredFont: font,
            textColor: textColor,
            paragraphStyle: paragraphStyle
        )
        let maxSize = CGSize(width: 4096, height: 4096)
        let measured = attributedText.boundingRect(
            with: maxSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let size = CGSize(
            width: ceil(max(measured.width, 1)) + 6,
            height: ceil(max(measured.height, font.lineHeight, 1)) + 4
        )
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = max(scale, 1)
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            attributedText.draw(
                with: CGRect(x: 3, y: 2, width: size.width - 6, height: size.height - 4),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
    }

    private static func rasterAttributedString(
        _ text: String,
        preferredFont: UIFont,
        textColor: UIColor,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let output = NSMutableAttributedString()
        for character in text {
            let chunk = String(character)
            let runFont = preferredFont.supportsCADGlyphs(in: chunk)
                ? preferredFont
                : rasterFallbackFont(supporting: chunk, size: preferredFont.pointSize)
            output.append(NSAttributedString(
                string: chunk,
                attributes: [
                    .font: runFont,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]
            ))
        }
        return output
    }

    private static func rasterFont(for text: String, preferredFont: UIFont) -> UIFont {
        preferredFont.supportsCADGlyphs(in: text)
            ? preferredFont
            : rasterFallbackFont(supporting: text, size: preferredFont.pointSize)
    }

    private static func textAdvancePoints(for text: String, font: UIFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let attributedText = NSAttributedString(string: text, attributes: [.font: font])
        let measured = attributedText.boundingRect(
            with: CGSize(width: 4096, height: 4096),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(max(measured.width, attributedText.size().width, 0))
    }

    fileprivate static func rasterFallbackFont(supporting text: String, size: CGFloat) -> UIFont {
        for fallbackName in rasterFallbackFontNames {
            if let font = UIFont(name: fallbackName, size: size), font.supportsCADText(text) {
                return font
            }
            if let family = UIFont.familyNames.first(where: { $0.caseInsensitiveCompare(fallbackName) == .orderedSame }),
               let fontName = UIFont.fontNames(forFamilyName: family).first,
               let font = UIFont(name: fontName, size: size),
               font.supportsCADText(text) {
                return font
            }
        }
        return .systemFont(ofSize: size)
    }

    private static let rasterFallbackFontNames = [
        "PingFangSC-Regular",
        "PingFang SC",
        "HiraginoSansGB-W3",
        "Hiragino Sans GB",
        "STHeitiSC-Light",
        "Heiti SC",
        "STSongti-SC-Regular",
        "Songti SC",
        "FangSong",
        "STFangsong",
        "FangSong_GB2312",
        "SimFang",
        "Noto Sans CJK SC",
        "Source Han Sans SC"
    ]
}
#endif

private extension Array where Element == SiteKeeperCADKernel.CADRenderCommand {
    var cadTextCommandCount: Int {
        reduce(0) { count, command in
            if case .text = command {
                return count + 1
            }
            return count
        }
    }
}

#if os(iOS)
private extension UIFont {
    func supportsCADText(_ text: String) -> Bool {
        let probe = text.cadCJKCoverageProbeText
        guard !probe.isEmpty else { return true }
        return supportsCADGlyphs(in: probe)
    }

    func supportsCADGlyphs(in text: String) -> Bool {
        let ctFont = CTFontCreateWithName(fontName as CFString, pointSize, nil)
        let characters = Array(text.utf16)
        guard !characters.isEmpty else { return true }
        var glyphs = Array(repeating: CGGlyph(), count: characters.count)
        return characters.withUnsafeBufferPointer { characterBuffer in
            glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                guard let characterBase = characterBuffer.baseAddress,
                      let glyphBase = glyphBuffer.baseAddress else {
                    return false
                }
                return CTFontGetGlyphsForCharacters(ctFont, characterBase, glyphBase, characters.count)
            }
        }
    }
}

private extension String {
    var cadRenderableLineCount: Int {
        let lines = split(whereSeparator: \.isNewline)
        let nonEmptyCount = lines.filter {
            !String($0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        return max(nonEmptyCount, 1)
    }

    var cadContainsCJKScalars: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF,
                 0x20000...0x2A6DF,
                 0x2A700...0x2B73F,
                 0x2B740...0x2B81F,
                 0x2B820...0x2CEAF:
                return true
            default:
                return false
            }
        }
    }

    var cadCJKCoverageProbeText: String {
        var scalars = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x3400...0x4DBF,
                 0x4E00...0x9FFF,
                 0xF900...0xFAFF:
                scalars.append(scalar)
            default:
                continue
            }
            if scalars.count >= 16 {
                break
            }
        }
        return String(scalars)
    }
}
#endif

private extension CGRect {
    init?(_ bounds: SiteKeeperCADKernel.CADBounds) {
        guard bounds.isFiniteForCADDisplay else { return nil }
        self.init(
            x: CGFloat(bounds.minX),
            y: CGFloat(bounds.minY),
            width: CGFloat(bounds.width),
            height: CGFloat(bounds.height)
        )
    }
}

fileprivate extension SiteKeeperCADKernel.CADBounds {
    var isFiniteForCADDisplay: Bool {
        !isEmpty
            && minX.isFinite
            && minY.isFinite
            && maxX.isFinite
            && maxY.isFinite
    }
}

private extension SiteKeeperCADKernel.CADPath {
    var isClosed: Bool {
        elements.contains {
            if case .close = $0 {
                return true
            }
            return false
        }
    }
}

#else
extension CADPoC {
    final class CADMetalRenderer {
        let deviceName: String? = nil
        var isAvailable: Bool { false }
    }
}
#endif
