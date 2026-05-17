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
        private var allRenderableEntities: [Kernel.CADEntity]
        private var entities: [Kernel.CADEntity]
        private var layersByID: [String: Kernel.CADLayer]
        private var spatialIndex: CADSpatialIndex
        private var modelBounds: Kernel.CADBounds
        private var progressiveRenderState: ProgressiveRenderState?
        private var drawingRevision = 0
        private var totalLayerCount = 0
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
        private var textOverlayImages: [String: UIImageView] = [:]
        private var textOverlayMarkers: [String: UIView] = [:]
        private var textRasterCache = CADTextRasterCache()
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
            super.init()
        }

        var isAvailable: Bool {
            device != nil && commandQueue != nil && renderPipelineState != nil
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
            }
            #endif
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
            if featureOptions.publishesSnapPoints {
                publishSnapPoints(from: visibleEntities)
            } else {
                clearPublishedSnapPoints()
            }
            syncTextOverlays(
                commands: featureOptions.rendersTextOverlays ? pipelineOutput.commands : [],
                view: view,
                drawableSize: view.drawableSize,
                viewSize: view.bounds.size,
                contentScale: view.contentScaleFactor
            )
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
                viewportBounds: viewportBounds,
                viewportEntityCountBeforeLayerFilter: viewportEntitiesBeforeLayerFilter.count,
                vertexCount: vertices.count
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
                    return points.count >= 2
                        ? [.polyline(points, closed: path.isClosed, style: style)]
                        : []
                }
                return featureOptions.allows(command) ? [command] : []
            }
        }

        private func entitiesAfterApplyingFeatureOptions(
            _ visibleEntities: [Kernel.CADEntity]
        ) -> [Kernel.CADEntity] {
            guard !featureOptions.rendersTextOverlays else { return visibleEntities }
            return visibleEntities.filter { entity in
                switch entity.kind {
                case .text, .mtext, .attrib:
                    return false
                default:
                    return true
                }
            }
        }

        private func renderOutputForFrame(
            visibleEntities: [Kernel.CADEntity],
            viewportBounds: Kernel.CADBounds,
            zoomScale: Double
        ) -> FrameRenderPlan {
            let budget = renderBudget(for: interactionPhase, visibleEntityCount: visibleEntities.count)
            let pipeline = CADRenderPipeline(lodPolicy: lodPolicy(for: interactionPhase))
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
            let renderStart = Date()
            if !state.completed, state.nextEntityOffset < visibleEntities.count {
                let remainingCommandCapacity = max(progressiveCommandCacheLimit - state.commands.count, 0)
                if remainingCommandCapacity == 0 {
                    state.completed = true
                    state.warnings.insert("CAD_POC_PROGRESSIVE_COMMAND_CACHE_LIMIT")
                } else {
                    let batchEnd = min(
                        state.nextEntityOffset + progressiveEntityBatchSize,
                        visibleEntities.count
                    )
                    let batch = Array(visibleEntities[state.nextEntityOffset..<batchEnd])
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

            if state.nextEntityOffset >= visibleEntities.count {
                state.completed = true
            }

            let needsContinuation = !state.completed
            if needsContinuation {
                state.warnings.insert("CAD_POC_PROGRESSIVE_RENDERING")
            }
            progressiveRenderState = state

            let skippedEntityCount = max(visibleEntities.count - min(state.nextEntityOffset, visibleEntities.count), 0)
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
            viewportBounds: Kernel.CADBounds,
            viewportEntityCountBeforeLayerFilter: Int,
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
                    vertexCount: vertexCount
                )
            )
        }

        private func logFrameTrace(_ trace: Kernel.CADPerformanceTrace) {
            #if DEBUG
            guard let data = try? JSONEncoder().encode(trace),
                  let json = String(data: data, encoding: .utf8) else { return }
            print("CADFrameTrace \(json)")
            #endif
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
            let payloads = Self.makeSnapPointPayloads(for: snapEntities)
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
        textOverlayImages.values.filter { !$0.isHidden && $0.image != nil }.count
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
        let screenWidth = screenLineWidth(for: style.lineWidth, contentScale: contentScale)
        let pattern = lineTypePattern(for: style.lineType, screenLineWidth: screenWidth)

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
            points = min(normalized, 12)
        } else {
            points = min(max(1 + normalized * 2.5, 1), 7)
        }
        return max(points * scale, 1.5)
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

    func syncTextOverlays(
        commands: [Kernel.CADRenderCommand],
        view: MTKView,
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) {
        #if os(iOS)
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                self.syncTextOverlays(
                    commands: commands,
                    view: view,
                    drawableSize: drawableSize,
                    viewSize: viewSize,
                    contentScale: contentScale
                )
            }
            return
        }

        var activeKeys = Set<String>()
        let textCommands = commands.enumerated().compactMap { offset, command -> (String, Kernel.CADTextRun, Kernel.CADRenderStyle)? in
            guard case let .text(text, style) = command else { return nil }
            return ("text-\(offset)", text, style)
        }

        for (key, text, style) in textCommands {
            activeKeys.insert(key)
            let imageView = textOverlayImages[key] ?? makeTextOverlayImageView(in: view)
            textOverlayImages[key] = imageView
            configureTextOverlay(
                imageView,
                text: text,
                style: style,
                drawableSize: drawableSize,
                viewSize: viewSize,
                contentScale: contentScale
            )
            view.bringSubviewToFront(imageView)

            if debugTextOverlays {
                let marker = textOverlayMarkers[key] ?? makeTextInsertionMarker(in: view)
                textOverlayMarkers[key] = marker
                configureTextInsertionMarker(
                    marker,
                    text: text,
                    drawableSize: drawableSize,
                    viewSize: viewSize,
                    contentScale: contentScale
                )
                view.bringSubviewToFront(marker)
            } else if let marker = textOverlayMarkers[key] {
                marker.removeFromSuperview()
                textOverlayMarkers.removeValue(forKey: key)
            }
        }

        let staleKeys = textOverlayImages.keys.filter { !activeKeys.contains($0) }
        for key in staleKeys {
            guard let imageView = textOverlayImages[key] else { continue }
            imageView.removeFromSuperview()
            textOverlayImages.removeValue(forKey: key)
            if let marker = textOverlayMarkers[key] {
                marker.removeFromSuperview()
                textOverlayMarkers.removeValue(forKey: key)
            }
        }

        if !debugTextOverlays {
            for marker in textOverlayMarkers.values {
                marker.removeFromSuperview()
            }
            textOverlayMarkers.removeAll()
        }
        #endif
    }

    #if os(iOS)
    private func makeTextOverlayImageView(in view: MTKView) -> UIImageView {
        let imageView = UIImageView()
        imageView.backgroundColor = .clear
        imageView.isUserInteractionEnabled = false
        imageView.contentMode = .scaleToFill
        imageView.alpha = 1
        imageView.layer.zPosition = 1_000
        imageView.layer.contentsScale = view.contentScaleFactor
        view.addSubview(imageView)
        return imageView
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

    private func configureTextOverlay(
        _ imageView: UIImageView,
        text: Kernel.CADTextRun,
        style: Kernel.CADRenderStyle,
        drawableSize: CGSize,
        viewSize: CGSize,
        contentScale: CGFloat
    ) {
        let screen = screenPoint(
            for: text.insertionPoint,
            drawableSize: drawableSize,
            viewSize: viewSize
        )
        let modelScale = modelToScreenScale(drawableSize: drawableSize, viewSize: viewSize)
        let fontSize = Self.textOverlayFontSize(
            textHeight: text.height,
            modelScale: modelScale,
            contentScale: contentScale
        )
        let displayText = text.displayText.isEmpty ? " " : text.displayText
        let font = uiFont(named: text.selectedFontName, supporting: displayText, size: CGFloat(fontSize))
        let textColor = readableTextColor(fromARGB: style.colorARGB)
        let cacheKey = CADTextRasterCache.Key(
            displayText: displayText,
            fontName: font.fontName,
            pointSizeBucket: Int((font.pointSize * 2).rounded()),
            colorARGB: readableTextColorKey(textColor),
            scaleBucket: Int((max(contentScale, 1) * 10).rounded())
        )
        guard let image = textRasterCache.image(for: cacheKey, limit: 640, makeImage: {
            Self.makeTextOverlayRasterImage(
                displayText: displayText,
                font: font,
                textColor: textColor,
                scale: contentScale
            )
        }) else {
            imageView.isHidden = true
            return
        }
        let measuredSize = image.size
        let widthFactor = CGFloat(max(text.widthFactor ?? 1, 0.1))
        let width = ceil(measuredSize.width * widthFactor)
        let height = ceil(measuredSize.height)

        guard screen.x.isFinite, screen.y.isFinite, width.isFinite, height.isFinite else {
            imageView.isHidden = true
            return
        }

        let alignmentOffset = textOverlayAlignmentOffset(
            text: text,
            width: Double(width),
            height: Double(height),
            modelScale: modelScale,
            contentScale: contentScale
        )
        imageView.image = image
        imageView.alpha = 1
        imageView.transform = .identity
        let insertionScreen = CGPoint(
            x: CGFloat(screen.x) / max(contentScale, 1),
            y: CGFloat(screen.y) / max(contentScale, 1)
        )
        imageView.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        imageView.center = Self.textOverlayCenter(
            insertionScreen: insertionScreen,
            width: width,
            height: height,
            alignmentOffset: alignmentOffset,
            rotationRadians: text.rotationRadians
        )
        imageView.transform = CGAffineTransform(rotationAngle: CGFloat(-text.rotationRadians))
        imageView.layer.zPosition = 1_000
        imageView.layer.shadowColor = readableShadowColor(for: textColor).cgColor
        imageView.layer.shadowOpacity = 0.75
        imageView.layer.shadowRadius = 1.2
        imageView.layer.shadowOffset = .zero
        imageView.layer.borderColor = debugTextOverlays ? UIColor.systemRed.withAlphaComponent(0.85).cgColor : nil
        imageView.layer.borderWidth = debugTextOverlays ? 1 : 0
        imageView.layer.cornerRadius = debugTextOverlays ? 2 : 0
        imageView.isHidden = false
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
        marker.center = CGPoint(
            x: CGFloat(screen.x) / max(contentScale, 1),
            y: CGFloat(screen.y) / max(contentScale, 1)
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
        contentScale: CGFloat
    ) -> CGPoint {
        let textWidth = text.boxWidth.flatMap { $0 > 0 ? $0 : nil }
            ?? width / max(modelScale / Double(max(contentScale, 1)), 0.000001)
        let textHeight = text.boxHeight.flatMap { $0 > 0 ? $0 : nil }
            ?? max(text.height, height / max(modelScale / Double(max(contentScale, 1)), 0.000001))
        let xWorldOffset = cadTextHorizontalOffset(width: textWidth, text: text)
        let yWorldOffset = cadTextVerticalOffset(height: textHeight, text: text)
        let scale = modelScale / Double(max(contentScale, 1))
        return CGPoint(x: xWorldOffset * scale, y: yWorldOffset * scale)
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
        for fallbackName in ["PingFang SC", "Hiragino Sans GB", "Heiti SC", "Songti SC"] {
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

    private func readableShadowColor(for color: UIColor) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 1
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.5 ? UIColor.black.withAlphaComponent(0.65) : UIColor.white.withAlphaComponent(0.9)
    }
    #endif
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

extension CADPoC.CADMetalRenderer {
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
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
        let maxSize = CGSize(width: 4096, height: 4096)
        let measured = (text as NSString).boundingRect(
            with: maxSize,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
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
            (text as NSString).draw(
                with: CGRect(x: 3, y: 2, width: size.width - 6, height: size.height - 4),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes,
                context: nil
            )
        }
    }
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
        let ctFont = CTFontCreateWithName(fontName as CFString, pointSize, nil)
        let characters = Array(probe.utf16)
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
