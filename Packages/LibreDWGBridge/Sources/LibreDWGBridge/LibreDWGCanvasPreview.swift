import Foundation
import SwiftUI

private struct DXFStrokeBatchKey: Hashable {
    let rgb: UInt32
    let layer: String
    let widthBucket: Int

    init(style: DXFPreviewModel.StrokeStyle, layer: String) {
        self.rgb = style.rgb
        self.layer = layer
        self.widthBucket = Int((max(style.width, 0.45) * 100).rounded())
    }

    var lineWidth: CGFloat {
        CGFloat(widthBucket) / 100
    }

    var color: Color {
        DXFCanvasRenderer.color(from: rgb, layer: layer)
    }
}

struct DXFCanvasPreview: View {
    let model: DXFPreviewModel
    let sourceHint: String?
    let geometryIndex: DXFSpatialGeometryIndex
    let fileURL: URL
    let initialViewState: LibreDWGCanvasViewStateSnapshot?
    let onCanvasTransformChange: (LibreDWGCanvasTransformSnapshot) -> Void
    let onViewStateChange: (LibreDWGCanvasViewStateSnapshot) -> Void
    let onTextRepairPresetRequest: (Int32?, Int32?) -> Void
    let onSnapPointsChange: ([LibreDWGSnapPointPayload]) -> Void
    private let maxZoomScale: CGFloat = 800
    @State private var zoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var canvasSize: CGSize = .zero
    @State private var visibleLayers: Set<String> = []
    @State private var showLayerSheet = false
    @State private var showSearchResults = false
    @State private var showDiagnosticSheet = false
    @State private var searchText = ""
    @State private var layerSearchText = ""
    @State private var selectedSearchTextID: UUID?
    @State private var probeCanvasPoint: CGPoint?
    @State private var showCoordinateLegend = true
    @State private var showMinimap = false
    @State private var controlsCollapsed = true
    @State private var controlsAutoHideToken = UUID()
    @State private var didApplyInitialViewState = false
    @State private var lastPostedViewState: LibreDWGCanvasViewStateSnapshot?
    @State private var dismissedTextRepairHint = false
    @GestureState private var pinchScale: CGFloat = 1
    @GestureState private var dragOffset: CGSize = .zero

    init(
        model: DXFPreviewModel,
        sourceHint: String?,
        geometryIndex: DXFSpatialGeometryIndex,
        fileURL: URL,
        initialViewState: LibreDWGCanvasViewStateSnapshot? = nil,
        onCanvasTransformChange: @escaping (LibreDWGCanvasTransformSnapshot) -> Void = { _ in },
        onViewStateChange: @escaping (LibreDWGCanvasViewStateSnapshot) -> Void = { _ in },
        onTextRepairPresetRequest: @escaping (Int32?, Int32?) -> Void = { _, _ in },
        onSnapPointsChange: @escaping ([LibreDWGSnapPointPayload]) -> Void = { _ in }
    ) {
        self.model = model
        self.sourceHint = sourceHint
        self.geometryIndex = geometryIndex
        self.fileURL = fileURL
        self.initialViewState = initialViewState
        self.onCanvasTransformChange = onCanvasTransformChange
        self.onViewStateChange = onViewStateChange
        self.onTextRepairPresetRequest = onTextRepairPresetRequest
        self.onSnapPointsChange = onSnapPointsChange
    }

    private var canvasIndex: DXFCanvasIndex {
        DXFCanvasIndex(
            model: model,
            geometryIndex: geometryIndex,
            visibleLayers: visibleLayers,
            searchText: searchText,
            layerSearchText: layerSearchText
        )
    }

    private var effectiveScale: CGFloat {
        clampScale(zoomScale * pinchScale)
    }

    private var effectiveOffset: CGSize {
        let scaledOffset: CGSize
        if pinchScale != 1, canvasSize != .zero {
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            scaledOffset = panOffsetForZoom(
                effectiveScale,
                anchor: center,
                currentZoom: zoomScale,
                currentPanOffset: panOffset
            )
        } else {
            scaledOffset = panOffset
        }
        return clampedPanOffset(
            CGSize(
                width: scaledOffset.width + dragOffset.width,
                height: scaledOffset.height + dragOffset.height
            ),
            zoom: effectiveScale
        )
    }

    private var layerStats: [DXFLayerStat] {
        canvasIndex.layerStats
    }

    private var normalizedSearchText: String {
        canvasIndex.normalizedSearchText
    }

    private var primaryLayerStats: [DXFLayerStat] {
        canvasIndex.primaryLayerStats
    }

    private var matchedTexts: [DXFPreviewModel.TextEntity] {
        canvasIndex.matchedTexts
    }

    private var shouldShowMinimap: Bool {
        showMinimap && !controlsCollapsed && effectiveScale >= 2
    }

    private var shouldShowTextRepairHint: Bool {
        !dismissedTextRepairHint && (model.textIssueHint?.shouldSuggestTextRepair ?? false)
    }

    private var shouldShowLightweightDiagnosticCommand: Bool {
        if model.textIssueHint?.shouldSuggestTextRepair == true {
            return true
        }
        if let unsupported = model.unsupportedEntitySummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !unsupported.isEmpty {
            return true
        }
        if let diagnostic = model.dwgDiagnostic {
            if diagnostic.hasMissingXrefs {
                return true
            }
            if let failureReason = diagnostic.failureReason?.trimmingCharacters(in: .whitespacesAndNewlines),
               !failureReason.isEmpty {
                return true
            }
            if diagnostic.totalObjectCount > 0, diagnostic.drawableObjectCount == 0 {
                return true
            }
        }
        return false
    }

    var body: some View {
        GeometryReader { proxy in
            let transform = CADCanvasTransform(
                bounds: model.bounds,
                size: canvasSize == .zero ? proxy.size : canvasSize,
                zoomScale: effectiveScale,
                panOffset: effectiveOffset
            )
            let visibleGeometry = canvasIndex.visibleGeometry(in: transform.viewportRectInSource())
            ZStack(alignment: .bottomTrailing) {
                drawingCanvas(visibleGeometry: visibleGeometry)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .contentShape(Rectangle())
                    .gesture(canvasGesture)
                    .simultaneousGesture(
                        SpatialTapGesture().onEnded { value in
                            probeCanvasPoint = value.location
                            showControlsTemporarily()
                        }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture(count: 2).onEnded { value in
                            probeCanvasPoint = value.location
                            doubleTapZoom(at: value.location)
                        }
                    )

                if controlsCollapsed {
                    compactControlsButton
                        .padding(.top, 10)
                        .padding(.trailing, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                } else {
                    VStack(spacing: 8) {
                        DXFCanvasToolbar(
                            searchText: $searchText,
                            showCoordinateLegend: $showCoordinateLegend,
                            showMinimap: $showMinimap,
                            effectiveScale: effectiveScale,
                            layerStats: layerStats,
                            primaryLayerStats: primaryLayerStats,
                            visibleLayers: visibleLayers,
                            matchedTexts: matchedTexts,
                            selectedSearchTextID: selectedSearchTextID,
                            probeSourcePoint: probeSourcePoint(transform: transform),
                            onFitAll: fitToAll,
                            onShowLayers: {
                                showControlsTemporarily(scheduleAutoHide: false)
                                showLayerSheet = true
                            },
                            onCoordinateToggle: {
                                showControlsTemporarily()
                            },
                            onZoomOut: {
                                zoom(by: 1 / 1.6)
                            },
                            onZoomIn: {
                                zoom(by: 1.6)
                            },
                            onMinimapToggle: {
                                showControlsTemporarily(scheduleAutoHide: false)
                            },
                            onCollapse: collapseControls,
                            onShowSearchResults: {
                                showControlsTemporarily(scheduleAutoHide: false)
                                showSearchResults = true
                            },
                            onCenterSelectedText: {
                                centerOnSelectedText()
                                showControlsTemporarily(scheduleAutoHide: false)
                            },
                            onMoveSearchSelection: moveSearchSelection,
                            onToggleLayer: toggleLayer,
                            onIsolateLayer: isolateLayer,
                            onFocusLayer: focusLayer,
                            onSelectText: selectSearchResult
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .frame(maxHeight: .infinity, alignment: .top)
                }

                if !controlsCollapsed {
                    footerStrip(visibleGeometry: visibleGeometry)
                        .padding(.leading, 10)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .allowsHitTesting(false)

                    if shouldShowMinimap {
                        minimap(transform: transform)
                    }
                }

                if shouldShowTextRepairHint {
                    textRepairHintView
                        .padding(.horizontal, 12)
                        .padding(.bottom, controlsCollapsed ? 12 : 54)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .zIndex(4)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .sheet(isPresented: $showLayerSheet) {
                DXFLayerSheet(
                    layerSearchText: $layerSearchText,
                    visibleLayers: $visibleLayers,
                    layerStats: layerStats,
                    filteredLayerStats: canvasIndex.filteredLayerStats,
                    onIsolate: { layerName in
                        showLayerSheet = false
                        isolateLayer(layerName)
                    },
                    onFocus: { layerName in
                        showLayerSheet = false
                        focusLayer(layerName)
                    },
                    onDone: {
                        showLayerSheet = false
                    }
                )
            }
            .sheet(isPresented: $showSearchResults) {
                DXFSearchResultsSheet(
                    matchedTexts: matchedTexts,
                    onSelect: selectSearchResult,
                    onDone: {
                        showSearchResults = false
                    }
                )
            }
            .sheet(isPresented: $showDiagnosticSheet) {
                DWGLightweightDiagnosticSheet(
                    diagnostic: model.dwgDiagnostic,
                    onDone: {
                        showDiagnosticSheet = false
                    }
                )
            }
            .onAppear {
                restoreInitialViewStateIfNeeded(canvasSize: proxy.size)
                postCanvasTransform(transform)
                postViewState(transform)
                postSnapPoints(in: transform.viewportRectInSource())
            }
            .onChange(of: canvasSize) { _, _ in
                panOffset = clampedPanOffset(panOffset, zoom: zoomScale)
                postCanvasTransform(transform)
                postViewState(transform)
                postSnapPoints(in: transform.viewportRectInSource())
            }
            .onChange(of: zoomScale) { _, _ in
                postCanvasTransform(transform)
                postViewState(transform)
                postSnapPoints(in: transform.viewportRectInSource())
            }
            .onChange(of: panOffset) { _, _ in
                postCanvasTransform(transform)
                postViewState(transform)
                postSnapPoints(in: transform.viewportRectInSource())
            }
            .onChange(of: searchText) { _, _ in
                syncSearchSelection()
                showControlsTemporarily(scheduleAutoHide: normalizedSearchText.isEmpty)
            }
            .onChange(of: visibleLayers) { _, _ in
                syncSearchSelection()
                postViewState(transform)
                postSnapPoints(in: transform.viewportRectInSource())
                showControlsTemporarily()
            }
            .onChange(of: showLayerSheet) { _, isPresented in
                if !isPresented {
                    scheduleControlsAutoHide()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LibreDWGBridgeShowLayerSheet"))) { notification in
                guard let filePath = notification.userInfo?["filePath"] as? String,
                      filePath == fileURL.path else { return }
                showControlsTemporarily(scheduleAutoHide: false)
                showLayerSheet = true
            }
            .task(id: controlsAutoHideToken) {
                await autoHideControlsIfNeeded(for: controlsAutoHideToken)
            }
            .task(id: fileURL.path) {
                await observeFocusRequests()
            }
        }
    }

    private var compactControlsButton: some View {
        Button {
            showControlsTemporarily()
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.headline)
                .frame(width: 42, height: 42)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(.regularMaterial, in: Circle())
        .overlay(Circle().stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
        .accessibilityLabel("显示看图工具")
    }

    private var textRepairHintView: some View {
        HStack(spacing: 10) {
            Image(systemName: "character.book.closed")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.orange)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text("当前可能缺字体或编码不匹配")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let summary = model.textIssueHint?.summary {
                    Text(summary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Button {
                dismissedTextRepairHint = true
                onTextRepairPresetRequest(936, 1)
            } label: {
                Text("GBK/大字体")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)

            Button {
                dismissedTextRepairHint = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("关闭文字提示")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: min(canvasSize.width - 24, 430), alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
    }

    private func restoreInitialViewStateIfNeeded(canvasSize size: CGSize) {
        guard !didApplyInitialViewState else { return }
        didApplyInitialViewState = true

        let allLayers = Set(layerStats.map(\.name))
        guard let initialViewState else {
            if visibleLayers.isEmpty {
                visibleLayers = allLayers
            }
            return
        }

        if initialViewState.usesSavedVisibleLayers {
            visibleLayers = Set(initialViewState.visibleLayerNames).intersection(allLayers)
        } else {
            visibleLayers = allLayers
        }

        let restoredZoom = clampScale(initialViewState.zoomScale)
        zoomScale = restoredZoom

        let restoreSize = size.width > 0 && size.height > 0 ? size : canvasSize
        if let viewportCenter = initialViewState.viewportCenter,
           restoreSize.width > 0,
           restoreSize.height > 0 {
            panOffset = panOffsetToCenter(
                sourcePoint: viewportCenter,
                zoom: restoredZoom,
                canvasSize: restoreSize
            )
        } else if restoreSize.width > 0, restoreSize.height > 0 {
            panOffset = clampedPanOffset(
                initialViewState.panOffset,
                zoom: restoredZoom,
                canvasSize: restoreSize
            )
        } else {
            panOffset = initialViewState.panOffset
        }
    }

    @ViewBuilder
    private func drawingCanvas(visibleGeometry: DXFVisibleGeometry) -> some View {
        if shouldAnimateSearchHighlight {
            TimelineView(.animation(minimumInterval: 0.25)) { timeline in
                drawingCanvasBody(visibleGeometry: visibleGeometry, pulseDate: timeline.date)
            }
        } else {
            drawingCanvasBody(visibleGeometry: visibleGeometry, pulseDate: nil)
        }
    }

    private var shouldAnimateSearchHighlight: Bool {
        selectedSearchTextID != nil && !normalizedSearchText.isEmpty
    }

    private func drawingCanvasBody(visibleGeometry: DXFVisibleGeometry, pulseDate: Date?) -> some View {
        let searchPulse = pulseDate.map {
            DXFCanvasRenderer.searchHighlightPulse(
                hasSelection: selectedSearchTextID != nil,
                hasSearchText: !normalizedSearchText.isEmpty,
                at: $0
            )
        } ?? 0
        return Canvas { context, size in
            let activeTransform = CADCanvasTransform(
                bounds: model.bounds,
                size: size,
                zoomScale: effectiveScale,
                panOffset: effectiveOffset
            )
            let visiblePrimitiveCount = visibleGeometry.segments.count
                + visibleGeometry.polylines.count
                + visibleGeometry.circles.count
                + visibleGeometry.texts.count
            let isDenseOverview = effectiveScale < 3.5 && visiblePrimitiveCount > 12_000
            let minimumPolylineStep = isDenseOverview ? CGFloat(0.85) : CGFloat(0.2)
            let allowsHatchPattern = !isDenseOverview && (effectiveScale > 4 || visiblePrimitiveCount < 4_000)

            var segmentBatches: [DXFStrokeBatchKey: Path] = [:]
            segmentBatches.reserveCapacity(min(visibleGeometry.segments.count, 128))
            for segment in visibleGeometry.segments {
                let key = DXFStrokeBatchKey(style: segment.style, layer: segment.layer)
                var path = segmentBatches[key] ?? Path()
                path.move(to: activeTransform.point(segment.from))
                path.addLine(to: activeTransform.point(segment.to))
                segmentBatches[key] = path
            }
            for (key, path) in segmentBatches {
                context.stroke(path, with: .color(key.color), lineWidth: key.lineWidth)
            }

            var regularPolylineBatches: [DXFStrokeBatchKey: Path] = [:]
            regularPolylineBatches.reserveCapacity(min(visibleGeometry.polylines.count, 128))
            for polyline in visibleGeometry.polylines where polyline.points.count > 1 {
                let path = polylinePath(
                    for: polyline.points,
                    transform: activeTransform,
                    minimumScreenDistance: minimumPolylineStep
                )
                if canBatch(polyline) {
                    let key = DXFStrokeBatchKey(style: polyline.style, layer: polyline.layer)
                    var batchedPath = regularPolylineBatches[key] ?? Path()
                    batchedPath.addPath(path)
                    regularPolylineBatches[key] = batchedPath
                    continue
                }
                DXFCanvasRenderer.drawPolyline(
                    polyline,
                    path: path,
                    in: &context,
                    allowsHatchPattern: allowsHatchPattern
                )
                if polyline.renderKind == .dimension {
                    DXFCanvasRenderer.drawDimensionTicks(for: polyline, in: &context, transform: activeTransform)
                }
            }
            for (key, path) in regularPolylineBatches {
                context.stroke(
                    path,
                    with: .color(key.color),
                    style: StrokeStyle(lineWidth: key.lineWidth, lineCap: .round, lineJoin: .round)
                )
            }

            var circleBatches: [DXFStrokeBatchKey: Path] = [:]
            circleBatches.reserveCapacity(min(visibleGeometry.circles.count, 128))
            for circle in visibleGeometry.circles {
                let center = activeTransform.point(circle.center)
                let radius = activeTransform.radius(circle.radius)
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                let key = DXFStrokeBatchKey(style: circle.style, layer: circle.layer)
                var path = circleBatches[key] ?? Path()
                path.addEllipse(in: rect)
                circleBatches[key] = path
            }
            for (key, path) in circleBatches {
                context.stroke(path, with: .color(key.color), lineWidth: key.lineWidth)
            }

            let selectedID = selectedSearchTextID
            let rawSearchText = normalizedSearchText
            let foldedQuery = rawSearchText.isEmpty
                ? ""
                : rawSearchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            for text in visibleGeometry.texts {
                let isMatch: Bool
                if foldedQuery.isEmpty {
                    isMatch = false
                } else {
                    let value = text.value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                    isMatch = value.contains(foldedQuery)
                }
                let isSelected = selectedID == text.id
                let renderColor = DXFCanvasRenderer.textColor(for: text, isMatch: isMatch, isSelected: isSelected, pulse: searchPulse)
                let fontSize = DXFCanvasRenderer.textFontSize(for: text, transform: activeTransform, isSelected: isSelected)
                guard shouldDrawText(text, fontSize: fontSize, isMatch: isMatch, isSelected: isSelected, isDenseOverview: isDenseOverview) else {
                    continue
                }
                let point = activeTransform.point(text.point)
                var textContext = context
                textContext.translateBy(x: point.x, y: point.y)
                textContext.rotate(by: .radians(-text.rotation))
                if isSelected || text.renderKind == .dimension || text.renderKind == .hatch {
                    DXFCanvasRenderer.drawTextBackdrop(
                        for: text,
                        fontSize: fontSize,
                        isSelected: isSelected,
                        pulse: searchPulse,
                        in: &textContext
                    )
                }
                DXFCanvasRenderer.drawText(
                    text.value,
                    entity: text,
                    fontSize: fontSize,
                    color: renderColor,
                    in: &textContext
                )
            }

            if showCoordinateLegend {
                DXFCanvasRenderer.drawAxes(in: &context, transform: activeTransform, bounds: model.bounds)
            }

            if let probeCanvasPoint {
                var marker = Path()
                marker.move(to: CGPoint(x: probeCanvasPoint.x - 8, y: probeCanvasPoint.y))
                marker.addLine(to: CGPoint(x: probeCanvasPoint.x + 8, y: probeCanvasPoint.y))
                marker.move(to: CGPoint(x: probeCanvasPoint.x, y: probeCanvasPoint.y - 8))
                marker.addLine(to: CGPoint(x: probeCanvasPoint.x, y: probeCanvasPoint.y + 8))
                context.stroke(marker, with: .color(.orange), lineWidth: 1.4)
            }
            }
        .overlay {
            GeometryReader { canvasProxy in
                Color.clear
                    .onAppear { canvasSize = canvasProxy.size }
                    .onChange(of: canvasProxy.size) { _, newSize in
                        canvasSize = newSize
                    }
            }
        }
    }

    private func canBatch(_ polyline: DXFPreviewModel.Polyline) -> Bool {
        polyline.renderKind == .regular &&
            polyline.kind != .blockRef &&
            polyline.kind != .unknownProxy
    }

    private func polylinePath(
        for points: [CGPoint],
        transform: CADCanvasTransform,
        minimumScreenDistance: CGFloat
    ) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        var lastRendered = transform.point(first)
        path.move(to: lastRendered)
        guard points.count > 1 else { return path }

        let minimumDistanceSquared = minimumScreenDistance * minimumScreenDistance
        for point in points.dropFirst().dropLast() {
            let rendered = transform.point(point)
            let dx = rendered.x - lastRendered.x
            let dy = rendered.y - lastRendered.y
            guard dx * dx + dy * dy >= minimumDistanceSquared else { continue }
            path.addLine(to: rendered)
            lastRendered = rendered
        }
        path.addLine(to: transform.point(points[points.count - 1]))
        return path
    }

    private func shouldDrawText(
        _ text: DXFPreviewModel.TextEntity,
        fontSize: CGFloat,
        isMatch: Bool,
        isSelected: Bool,
        isDenseOverview: Bool
    ) -> Bool {
        if isSelected || isMatch {
            return true
        }
        if isDenseOverview {
            switch text.renderKind {
            case .dimension:
                return fontSize >= 5.5
            case .hatch:
                return fontSize >= 6
            case .leader, .attribute:
                return fontSize >= 7
            case .regular:
                return fontSize >= 8
            }
        }
        return fontSize >= 3.5 || text.renderKind == .dimension
    }

    private func footerStrip(visibleGeometry: DXFVisibleGeometry) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Label("\(visibleGeometry.segments.count) 条直线", systemImage: "line.diagonal")
                Label("\(visibleGeometry.polylines.count) 条多段线", systemImage: "scribble.variable")
                Label("\(model.arcCount) 条圆弧", systemImage: "rotate.left")
                Label("\(visibleGeometry.circles.count) 个圆", systemImage: "circle")
                Label("\(visibleGeometry.texts.count) 段文字", systemImage: "textformat")
                Label(String(format: "缩放 %.1fx", effectiveScale), systemImage: "magnifyingglass")
                if model.sourceObjectCount > 0 {
                    Label("对象 \(model.sourceObjectCount)", systemImage: "cube.transparent")
                }
                if let textDecodingHint = model.textDecodingHint, !textDecodingHint.isEmpty {
                    Label(textDecodingHint, systemImage: "character.book.closed")
                }
                if let unsupportedEntitySummary = model.unsupportedEntitySummary, !unsupportedEntitySummary.isEmpty {
                    Label("未渲染 \(unsupportedEntitySummary)", systemImage: "exclamationmark.triangle")
                }
                if shouldShowLightweightDiagnosticCommand, let diagnostic = model.dwgDiagnostic {
                    Button {
                        showDiagnosticSheet = true
                    } label: {
                        Label("诊断", systemImage: "stethoscope")
                    }
                    .buttonStyle(.plain)
                    let blockSummary = diagnostic.blockReferenceSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !blockSummary.isEmpty, blockSummary != "无" {
                        Label("图块 \(blockSummary)", systemImage: "square.stack.3d.up")
                    }
                    let xrefSummary = diagnostic.xrefSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !xrefSummary.isEmpty, xrefSummary != "无" {
                        Label("外参 \(xrefSummary)", systemImage: diagnostic.hasMissingXrefs ? "exclamationmark.triangle" : "link")
                    }
                    Label("\(diagnostic.parseDurationMilliseconds) ms", systemImage: "timer")
                    Label(String(format: "%.2f MB", diagnostic.estimatedMemoryMB), systemImage: "memorychip")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func minimap(transform: CADCanvasTransform) -> some View {
        let viewport = transform.viewportRectInSource().intersection(model.bounds)
        return Canvas { context, size in
            let inset: CGFloat = 6
            let frame = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
            context.stroke(Path(roundedRect: frame, cornerRadius: 6), with: .color(.secondary), lineWidth: 0.8)

            func mapPoint(_ point: CGPoint) -> CGPoint {
                let xRatio = (point.x - model.bounds.minX) / max(model.bounds.width, 1)
                let yRatio = (point.y - model.bounds.minY) / max(model.bounds.height, 1)
                return CGPoint(
                    x: frame.minX + xRatio * frame.width,
                    y: frame.maxY - yRatio * frame.height
                )
            }

            if viewport.width > 0, viewport.height > 0 {
                let minPoint = mapPoint(CGPoint(x: viewport.minX, y: viewport.minY))
                let maxPoint = mapPoint(CGPoint(x: viewport.maxX, y: viewport.maxY))
                let rect = CGRect(
                    x: min(minPoint.x, maxPoint.x),
                    y: min(minPoint.y, maxPoint.y),
                    width: abs(maxPoint.x - minPoint.x),
                    height: abs(maxPoint.y - minPoint.y)
                )
                context.fill(Path(rect), with: .color(.orange.opacity(0.18)))
                context.stroke(Path(rect), with: .color(.orange), lineWidth: 1.2)
            }
        }
        .frame(width: 120, height: 120)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
                centerFromMinimapTap(value.location)
            }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    centerFromMinimapTap(value.location, animated: false)
                }
                .onEnded { value in
                    centerFromMinimapTap(value.location, animated: true)
                }
        )
        .padding(12)
    }

    private func moveSearchSelection(step: Int) {
        guard !matchedTexts.isEmpty else {
            selectedSearchTextID = nil
            return
        }
        let ids = matchedTexts.map(\.id)
        let nextID: UUID
        if let selectedSearchTextID,
           let index = ids.firstIndex(of: selectedSearchTextID) {
            let nextIndex = (index + step + ids.count) % ids.count
            nextID = ids[nextIndex]
        } else {
            nextID = ids[0]
        }
        selectedSearchTextID = nextID
        centerOnSelectedText()
    }

    private func selectSearchResult(_ text: DXFPreviewModel.TextEntity) {
        selectedSearchTextID = text.id
        showSearchResults = false
        showControlsTemporarily(scheduleAutoHide: false)
        centerOnSelectedText()
    }

    private func centerOnSelectedText() {
        guard let selectedID = selectedSearchTextID,
              let target = matchedTexts.first(where: { $0.id == selectedID }),
              canvasSize != .zero else { return }
        let targetZoom = max(zoomScale, min(maxZoomScale, 24))
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = targetZoom
            panOffset = panOffsetToCenter(sourcePoint: target.point, zoom: targetZoom)
        }
    }

    private func fitToAll() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = 1
            panOffset = .zero
        }
        showControlsTemporarily()
    }

    private func setLayer(_ layerName: String, visible: Bool) {
        if visible {
            visibleLayers.insert(layerName)
        } else {
            visibleLayers.remove(layerName)
        }
    }

    private func toggleLayer(_ layerName: String) {
        setLayer(layerName, visible: !visibleLayers.contains(layerName))
        showControlsTemporarily(scheduleAutoHide: false)
    }

    private func isolateLayer(_ layerName: String) {
        visibleLayers = [layerName]
        focusLayer(layerName)
    }

    private func focusLayer(_ layerName: String) {
        guard let bounds = canvasIndex.layerBounds(for: layerName),
              canvasSize != .zero else {
            showControlsTemporarily(scheduleAutoHide: false)
            return
        }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let targetZoom = fitZoom(for: bounds)
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = targetZoom
            panOffset = panOffsetToCenter(sourcePoint: center, zoom: targetZoom)
        }
        showControlsTemporarily(scheduleAutoHide: false)
    }

    private func fitZoom(for rect: CGRect) -> CGFloat {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return max(zoomScale, 3) }
        let contentInset = min(max(min(canvasSize.width, canvasSize.height) * 0.018, 6), 14)
        let availableWidth = max(canvasSize.width - contentInset * 2, 1)
        let availableHeight = max(canvasSize.height - contentInset * 2, 1)
        let baseScale = min(
            availableWidth / max(model.bounds.width, 1),
            availableHeight / max(model.bounds.height, 1)
        )
        let paddedWidth = max(rect.width * 1.28, model.bounds.width * 0.015, 1)
        let paddedHeight = max(rect.height * 1.28, model.bounds.height * 0.015, 1)
        let targetScale = min(
            availableWidth / paddedWidth,
            availableHeight / paddedHeight
        )
        return clampScale(max(1, targetScale / max(baseScale, 0.0001)))
    }

    private func zoom(by factor: CGFloat) {
        guard factor.isFinite, factor > 0 else { return }
        let center = canvasSize == .zero
            ? nil
            : CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        applyZoom(clampScale(zoomScale * factor), anchor: center)
        showControlsTemporarily()
    }

    private func doubleTapZoom(at location: CGPoint) {
        guard canvasSize != .zero else { return }
        let currentTransform = CADCanvasTransform(
            bounds: model.bounds,
            size: canvasSize,
            zoomScale: effectiveScale,
            panOffset: effectiveOffset
        )
        let sourcePoint = currentTransform.sourcePoint(location)
        let targetZoom = clampScale(max(zoomScale * 2.2, zoomScale + 1))
        withAnimation(.easeInOut(duration: 0.18)) {
            zoomScale = targetZoom
            panOffset = panOffsetToCenter(sourcePoint: sourcePoint, zoom: targetZoom)
        }
        probeCanvasPoint = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        showControlsTemporarily()
    }

    private func centerFromMinimapTap(_ location: CGPoint, animated: Bool = true) {
        guard canvasSize != .zero else { return }
        let sourcePoint = minimapSourcePoint(for: location)
        let update = {
            panOffset = panOffsetToCenter(sourcePoint: sourcePoint, zoom: zoomScale)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.18), update)
        } else {
            update()
        }
        showControlsTemporarily()
    }

    private func minimapSourcePoint(for location: CGPoint) -> CGPoint {
        let frame = CGRect(x: 6, y: 6, width: 108, height: 108)
        let clampedX = min(max(location.x, frame.minX), frame.maxX)
        let clampedY = min(max(location.y, frame.minY), frame.maxY)
        let xRatio = (clampedX - frame.minX) / max(frame.width, 1)
        let yRatio = 1 - (clampedY - frame.minY) / max(frame.height, 1)
        return CGPoint(
            x: model.bounds.minX + model.bounds.width * xRatio,
            y: model.bounds.minY + model.bounds.height * yRatio
        )
    }

    private func applyZoom(_ newZoom: CGFloat, anchor: CGPoint?, animated: Bool = true) {
        let clampedZoom = clampScale(newZoom)
        let nextOffset = panOffsetForZoom(
            clampedZoom,
            anchor: anchor,
            currentZoom: zoomScale,
            currentPanOffset: panOffset
        )
        let update = {
            zoomScale = clampedZoom
            panOffset = nextOffset
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.16), update)
        } else {
            update()
        }
    }

    private func panOffsetToCenter(sourcePoint: CGPoint, zoom: CGFloat) -> CGSize {
        panOffsetToCenter(sourcePoint: sourcePoint, zoom: zoom, canvasSize: canvasSize)
    }

    private func panOffsetToCenter(sourcePoint: CGPoint, zoom: CGFloat, canvasSize size: CGSize) -> CGSize {
        guard size != .zero else { return .zero }
        let baseTransform = CADCanvasTransform(
            bounds: model.bounds,
            size: size,
            zoomScale: zoom,
            panOffset: .zero
        )
        let renderedPoint = baseTransform.point(sourcePoint)
        let offset = CGSize(
            width: size.width / 2 - renderedPoint.x,
            height: size.height / 2 - renderedPoint.y
        )
        return clampedPanOffset(offset, zoom: zoom, canvasSize: size)
    }

    private func panOffsetForZoom(
        _ newZoom: CGFloat,
        anchor: CGPoint?,
        currentZoom: CGFloat,
        currentPanOffset: CGSize
    ) -> CGSize {
        let clampedZoom = clampScale(newZoom)
        guard clampedZoom > 1.001, canvasSize != .zero else { return .zero }
        guard let anchor, anchor.x.isFinite, anchor.y.isFinite else {
            return clampedPanOffset(currentPanOffset, zoom: clampedZoom)
        }
        let currentTransform = CADCanvasTransform(
            bounds: model.bounds,
            size: canvasSize,
            zoomScale: currentZoom,
            panOffset: currentPanOffset
        )
        let sourceAnchor = currentTransform.sourcePoint(anchor)
        let baseTransform = CADCanvasTransform(
            bounds: model.bounds,
            size: canvasSize,
            zoomScale: clampedZoom,
            panOffset: .zero
        )
        let renderedPoint = baseTransform.point(sourceAnchor)
        let offset = CGSize(
            width: anchor.x - renderedPoint.x,
            height: anchor.y - renderedPoint.y
        )
        return clampedPanOffset(offset, zoom: clampedZoom)
    }

    private func clampedPanOffset(_ proposed: CGSize, zoom: CGFloat) -> CGSize {
        clampedPanOffset(proposed, zoom: zoom, canvasSize: canvasSize)
    }

    private func clampedPanOffset(_ proposed: CGSize, zoom: CGFloat, canvasSize size: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0, zoom > 1.001 else { return .zero }
        let rect = contentRect(zoom: zoom, panOffset: proposed, canvasSize: size)
        guard rect.width.isFinite, rect.height.isFinite else { return proposed }

        var offset = proposed
        let horizontalPadding = min(max(size.width * 0.08, 18), 64)
        let verticalPadding = min(max(size.height * 0.08, 18), 64)

        if rect.width <= size.width - horizontalPadding * 2 {
            offset.width += size.width / 2 - rect.midX
        } else {
            if rect.minX > horizontalPadding {
                offset.width -= rect.minX - horizontalPadding
            }
            if rect.maxX < size.width - horizontalPadding {
                offset.width += size.width - horizontalPadding - rect.maxX
            }
        }

        if rect.height <= size.height - verticalPadding * 2 {
            offset.height += size.height / 2 - rect.midY
        } else {
            if rect.minY > verticalPadding {
                offset.height -= rect.minY - verticalPadding
            }
            if rect.maxY < size.height - verticalPadding {
                offset.height += size.height - verticalPadding - rect.maxY
            }
        }
        return offset
    }

    private func contentRect(zoom: CGFloat, panOffset: CGSize) -> CGRect {
        contentRect(zoom: zoom, panOffset: panOffset, canvasSize: canvasSize)
    }

    private func contentRect(zoom: CGFloat, panOffset: CGSize, canvasSize size: CGSize) -> CGRect {
        let transform = CADCanvasTransform(
            bounds: model.bounds,
            size: size,
            zoomScale: zoom,
            panOffset: panOffset
        )
        let points = [
            transform.point(CGPoint(x: model.bounds.minX, y: model.bounds.minY)),
            transform.point(CGPoint(x: model.bounds.minX, y: model.bounds.maxY)),
            transform.point(CGPoint(x: model.bounds.maxX, y: model.bounds.minY)),
            transform.point(CGPoint(x: model.bounds.maxX, y: model.bounds.maxY))
        ]
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else {
            return .zero
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private func showControlsTemporarily(scheduleAutoHide: Bool = true) {
        withAnimation(.easeInOut(duration: 0.18)) {
            controlsCollapsed = false
        }
        if scheduleAutoHide {
            scheduleControlsAutoHide()
        }
    }

    private func collapseControls() {
        withAnimation(.easeInOut(duration: 0.18)) {
            controlsCollapsed = true
        }
        controlsAutoHideToken = UUID()
    }

    private func scheduleControlsAutoHide() {
        controlsAutoHideToken = UUID()
    }

    @MainActor
    private func autoHideControlsIfNeeded(for token: UUID) async {
        guard !controlsCollapsed, normalizedSearchText.isEmpty, !showLayerSheet else { return }
        try? await Task.sleep(for: .seconds(4))
        guard token == controlsAutoHideToken,
              !controlsCollapsed,
              normalizedSearchText.isEmpty,
              !showLayerSheet else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            controlsCollapsed = true
        }
    }

    private func syncSearchSelection() {
        guard !matchedTexts.isEmpty else {
            selectedSearchTextID = nil
            return
        }
        if let selectedSearchTextID,
           matchedTexts.contains(where: { $0.id == selectedSearchTextID }) {
            return
        }
        selectedSearchTextID = matchedTexts.first?.id
    }

    private func probeSourcePoint(transform: CADCanvasTransform) -> CGPoint? {
        guard let probeCanvasPoint else { return nil }
        return transform.sourcePoint(probeCanvasPoint)
    }

    private var canvasGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .updating($pinchScale) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    let center = canvasSize == .zero
                        ? nil
                        : CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
                    applyZoom(clampScale(zoomScale * value), anchor: center, animated: false)
                },
            DragGesture(minimumDistance: 2, coordinateSpace: .local)
                .updating($dragOffset) { value, state, _ in
                    guard effectiveScale > 1 else {
                        state = .zero
                        return
                    }
                    state = value.translation
                }
                .onEnded { value in
                    guard zoomScale > 1 else {
                        panOffset = .zero
                        return
                    }
                    panOffset = clampedPanOffset(
                        CGSize(
                            width: panOffset.width + value.translation.width,
                            height: panOffset.height + value.translation.height
                        ),
                        zoom: zoomScale
                    )
                }
        )
    }

    private func clampScale(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), maxZoomScale)
    }

    @MainActor
    private func observeFocusRequests() async {
        for await notification in NotificationCenter.default.notifications(named: .libreDWGFocusSourcePoint) {
            guard !Task.isCancelled,
                  let userInfo = notification.userInfo,
                  let filePath = userInfo["filePath"] as? String,
                  filePath == fileURL.path,
                  let pointValue = userInfo["point"] as? NSValue else { continue }
            if let boundsValue = userInfo["bounds"] as? NSValue {
                focusOnSourceBounds(boundsValue.cgRectValue, fallbackPoint: pointValue.cgPointValue)
            } else {
                focusOnSourcePoint(pointValue.cgPointValue)
            }
        }
    }

    private func focusOnSourceBounds(_ bounds: CGRect, fallbackPoint: CGPoint) {
        guard canvasSize != .zero, bounds.width.isFinite, bounds.height.isFinite else {
            focusOnSourcePoint(fallbackPoint)
            return
        }
        let normalizedBounds = bounds.width > 0 && bounds.height > 0 ? bounds : CGRect(
            x: fallbackPoint.x - model.bounds.width * 0.006,
            y: fallbackPoint.y - model.bounds.height * 0.006,
            width: model.bounds.width * 0.012,
            height: model.bounds.height * 0.012
        )
        let targetZoom = max(zoomScale, fitZoom(for: normalizedBounds))
        let center = CGPoint(x: normalizedBounds.midX, y: normalizedBounds.midY)
        withAnimation(.easeInOut(duration: 0.22)) {
            zoomScale = targetZoom
            panOffset = panOffsetToCenter(sourcePoint: center, zoom: targetZoom)
        }
        probeCanvasPoint = CADCanvasTransform(
            bounds: model.bounds,
            size: canvasSize,
            zoomScale: targetZoom,
            panOffset: panOffsetToCenter(sourcePoint: center, zoom: targetZoom)
        ).point(center)
        showControlsTemporarily(scheduleAutoHide: false)
    }

    private func focusOnSourcePoint(_ sourcePoint: CGPoint) {
        guard canvasSize != .zero else { return }
        let targetZoom = max(zoomScale, min(maxZoomScale, 18))
        withAnimation(.easeInOut(duration: 0.22)) {
            zoomScale = targetZoom
            panOffset = panOffsetToCenter(sourcePoint: sourcePoint, zoom: targetZoom)
        }
        probeCanvasPoint = CADCanvasTransform(
            bounds: model.bounds,
            size: canvasSize,
            zoomScale: targetZoom,
            panOffset: panOffsetToCenter(sourcePoint: sourcePoint, zoom: targetZoom)
        ).point(sourcePoint)
        showControlsTemporarily(scheduleAutoHide: false)
    }

    private func postCanvasTransform(_ transform: CADCanvasTransform) {
        onCanvasTransformChange(
            LibreDWGCanvasTransformSnapshot(
                bounds: transform.bounds,
                size: transform.size,
                zoomScale: transform.zoomScale,
                panOffset: transform.panOffset
            )
        )
    }

    private func postViewState(_ transform: CADCanvasTransform) {
        let viewportCenter: CGPoint?
        if transform.size.width > 0, transform.size.height > 0 {
            viewportCenter = transform.sourcePoint(
                CGPoint(x: transform.size.width / 2, y: transform.size.height / 2)
            )
        } else {
            viewportCenter = nil
        }
        let snapshot = LibreDWGCanvasViewStateSnapshot(
            zoomScale: transform.zoomScale,
            panOffset: transform.panOffset,
            viewportCenter: viewportCenter,
            usesSavedVisibleLayers: true,
            visibleLayerNames: visibleLayers.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }
        )
        guard snapshot != lastPostedViewState else { return }
        lastPostedViewState = snapshot
        onViewStateChange(snapshot)
    }

    private func postSnapPoints(in viewport: CGRect) {
        let sourcePoints = canvasIndex.visibleSnapSourcePoints(in: viewport)
        onSnapPointsChange(
            sourcePoints.points.map { point in
                LibreDWGSnapPointPayload(
                    point: point.point,
                    snapKind: point.kind.rawValue,
                    layer: point.layer,
                    primitiveKind: point.primitiveKind.rawValue,
                    styleRGB: point.styleRGB,
                    styleWidth: point.styleWidth,
                    styleName: point.styleName
                )
            }
        )
    }

}
