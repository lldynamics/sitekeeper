import Foundation
import SwiftUI

struct DXFCanvasPreview: View {
    let model: DXFPreviewModel
    let sourceHint: String?
    let fileURL: URL
    let onCanvasTransformChange: (LibreDWGCanvasTransformSnapshot) -> Void
    let onSnapPointsChange: ([LibreDWGSnapPointPayload]) -> Void
    private let geometryIndex: DXFSpatialGeometryIndex
    private let maxZoomScale: CGFloat = 800
    @State private var zoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var canvasSize: CGSize = .zero
    @State private var visibleLayers: Set<String> = []
    @State private var lockedLayers: Set<String> = []
    @State private var showLayerSheet = false
    @State private var showSearchResults = false
    @State private var showDiagnosticSheet = false
    @State private var searchText = ""
    @State private var layerSearchText = ""
    @State private var selectedSearchTextID: UUID?
    @State private var probeCanvasPoint: CGPoint?
    @State private var showCoordinateLegend = true
    @State private var controlsCollapsed = true
    @State private var controlsAutoHideToken = UUID()
    @GestureState private var pinchScale: CGFloat = 1
    @GestureState private var dragOffset: CGSize = .zero

    init(
        model: DXFPreviewModel,
        sourceHint: String?,
        fileURL: URL,
        onCanvasTransformChange: @escaping (LibreDWGCanvasTransformSnapshot) -> Void = { _ in },
        onSnapPointsChange: @escaping ([LibreDWGSnapPointPayload]) -> Void = { _ in }
    ) {
        self.model = model
        self.sourceHint = sourceHint
        self.fileURL = fileURL
        self.onCanvasTransformChange = onCanvasTransformChange
        self.onSnapPointsChange = onSnapPointsChange
        self.geometryIndex = DXFSpatialGeometryIndex(model: model)
    }

    private var canvasIndex: DXFCanvasIndex {
        DXFCanvasIndex(
            model: model,
            geometryIndex: geometryIndex,
            visibleLayers: visibleLayers,
            lockedLayers: lockedLayers,
            searchText: searchText,
            layerSearchText: layerSearchText
        )
    }

    private var effectiveScale: CGFloat {
        clampScale(zoomScale * pinchScale)
    }

    private var effectiveOffset: CGSize {
        CGSize(
            width: panOffset.width + dragOffset.width,
            height: panOffset.height + dragOffset.height
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

    private var visibleSnapSourcePoints: DXFSnapPointSet {
        canvasIndex.visibleSnapSourcePoints()
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
                        if let sourceHint, !sourceHint.isEmpty {
                            Label(sourceHint, systemImage: "arrow.triangle.swap")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                        DXFCanvasToolbar(
                            searchText: $searchText,
                            showCoordinateLegend: $showCoordinateLegend,
                            effectiveScale: effectiveScale,
                            layerStats: layerStats,
                            primaryLayerStats: primaryLayerStats,
                            visibleLayers: visibleLayers,
                            lockedLayers: lockedLayers,
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
                            onToggleLayerLock: toggleLayerLock,
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

                    minimap(transform: transform)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .sheet(isPresented: $showLayerSheet) {
                DXFLayerSheet(
                    layerSearchText: $layerSearchText,
                    visibleLayers: $visibleLayers,
                    lockedLayers: $lockedLayers,
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
                if visibleLayers.isEmpty {
                    visibleLayers = Set(layerStats.map(\.name))
                }
                postCanvasTransform(transform)
                postSnapPoints()
            }
            .onChange(of: canvasSize) { _, _ in
                postCanvasTransform(transform)
            }
            .onChange(of: zoomScale) { _, _ in
                postCanvasTransform(transform)
            }
            .onChange(of: panOffset) { _, _ in
                postCanvasTransform(transform)
            }
            .onChange(of: searchText) { _, _ in
                syncSearchSelection()
                showControlsTemporarily(scheduleAutoHide: normalizedSearchText.isEmpty)
            }
            .onChange(of: visibleLayers) { _, _ in
                syncSearchSelection()
                postSnapPoints()
                showControlsTemporarily()
            }
            .onChange(of: lockedLayers) { _, _ in
                syncSearchSelection()
                postSnapPoints()
                showControlsTemporarily()
            }
            .onChange(of: showLayerSheet) { _, isPresented in
                if !isPresented {
                    scheduleControlsAutoHide()
                }
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

    private func drawingCanvas(visibleGeometry: DXFVisibleGeometry) -> some View {
        TimelineView(.animation(minimumInterval: 0.25)) { timeline in
            let searchPulse = DXFCanvasRenderer.searchHighlightPulse(hasSelection: selectedSearchTextID != nil, hasSearchText: !normalizedSearchText.isEmpty, at: timeline.date)
            Canvas { context, size in
            let activeTransform = CADCanvasTransform(
                bounds: model.bounds,
                size: size,
                zoomScale: effectiveScale,
                panOffset: effectiveOffset
            )

            for segment in visibleGeometry.segments {
                var path = Path()
                path.move(to: activeTransform.point(segment.from))
                path.addLine(to: activeTransform.point(segment.to))
                context.stroke(path, with: .color(DXFCanvasRenderer.color(from: segment.style.rgb, layer: segment.layer)), lineWidth: max(segment.style.width, 0.45))
            }

            for polyline in visibleGeometry.polylines where polyline.points.count > 1 {
                var path = Path()
                path.move(to: activeTransform.point(polyline.points[0]))
                for point in polyline.points.dropFirst() {
                    path.addLine(to: activeTransform.point(point))
                }
                DXFCanvasRenderer.drawPolyline(polyline, path: path, in: &context)
                if polyline.renderKind == .dimension {
                    DXFCanvasRenderer.drawDimensionTicks(for: polyline, in: &context, transform: activeTransform)
                }
            }

            for circle in visibleGeometry.circles {
                let center = activeTransform.point(circle.center)
                let radius = activeTransform.radius(circle.radius)
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(DXFCanvasRenderer.color(from: circle.style.rgb, layer: circle.layer)), lineWidth: max(circle.style.width, 0.45))
            }

            let selectedID = selectedSearchTextID
            let foldedQuery = normalizedSearchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            for text in visibleGeometry.texts {
                let point = activeTransform.point(text.point)
                let value = text.value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                let isMatch = !foldedQuery.isEmpty && value.contains(foldedQuery)
                let isSelected = selectedID == text.id
                let renderColor = DXFCanvasRenderer.textColor(for: text, isMatch: isMatch, isSelected: isSelected, pulse: searchPulse)
                let fontSize = DXFCanvasRenderer.textFontSize(for: text, transform: activeTransform, isSelected: isSelected)
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
                if let diagnostic = model.dwgDiagnostic {
                    Button {
                        showDiagnosticSheet = true
                    } label: {
                        Label("诊断 \(diagnostic.dwgVersion)", systemImage: "stethoscope")
                    }
                    .buttonStyle(.plain)
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
        guard !lockedLayers.contains(layerName) else { return }
        if visible {
            visibleLayers.insert(layerName)
        } else {
            visibleLayers.remove(layerName)
        }
    }

    private func setLayer(_ layerName: String, locked: Bool) {
        if locked {
            lockedLayers.insert(layerName)
        } else {
            lockedLayers.remove(layerName)
        }
    }

    private func toggleLayer(_ layerName: String) {
        guard !lockedLayers.contains(layerName) else {
            showControlsTemporarily(scheduleAutoHide: false)
            return
        }
        setLayer(layerName, visible: !visibleLayers.contains(layerName))
        showControlsTemporarily(scheduleAutoHide: false)
    }

    private func toggleLayerLock(_ layerName: String) {
        let locked = lockedLayers.contains(layerName)
        setLayer(layerName, locked: !locked)
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
        if effectiveScale >= 18 {
            fitToAll()
        } else {
            applyZoom(clampScale(zoomScale * 2.2), anchor: location)
            showControlsTemporarily()
        }
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

    private func applyZoom(_ newZoom: CGFloat, anchor: CGPoint?) {
        let clampedZoom = clampScale(newZoom)
        let nextOffset: CGSize
        if clampedZoom <= 1.001 || canvasSize == .zero {
            nextOffset = .zero
        } else if let anchor, anchor.x.isFinite, anchor.y.isFinite {
            let currentTransform = CADCanvasTransform(
                bounds: model.bounds,
                size: canvasSize,
                zoomScale: zoomScale,
                panOffset: panOffset
            )
            let sourceAnchor = currentTransform.sourcePoint(anchor)
            let baseTransform = CADCanvasTransform(
                bounds: model.bounds,
                size: canvasSize,
                zoomScale: clampedZoom,
                panOffset: .zero
            )
            let renderedPoint = baseTransform.point(sourceAnchor)
            nextOffset = CGSize(
                width: anchor.x - renderedPoint.x,
                height: anchor.y - renderedPoint.y
            )
        } else {
            nextOffset = panOffset
        }

        withAnimation(.easeInOut(duration: 0.16)) {
            zoomScale = clampedZoom
            panOffset = nextOffset
        }
    }

    private func panOffsetToCenter(sourcePoint: CGPoint, zoom: CGFloat) -> CGSize {
        guard canvasSize != .zero else { return .zero }
        let baseTransform = CADCanvasTransform(
            bounds: model.bounds,
            size: canvasSize,
            zoomScale: zoom,
            panOffset: .zero
        )
        let renderedPoint = baseTransform.point(sourcePoint)
        return CGSize(
            width: canvasSize.width / 2 - renderedPoint.x,
            height: canvasSize.height / 2 - renderedPoint.y
        )
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
                    zoomScale = clampScale(zoomScale * value)
                    if zoomScale <= 1.001 {
                        panOffset = .zero
                    }
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
                    panOffset.width += value.translation.width
                    panOffset.height += value.translation.height
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

    private func postSnapPoints() {
        onSnapPointsChange(
            visibleSnapSourcePoints.points.map { point in
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
