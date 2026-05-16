import SwiftUI

struct CADViewerContainer: View {
    let fileURL: URL
    let displayName: String
    let onClose: () -> Void
    let onReportIssue: () -> Void

    init(
        fileURL: URL,
        displayName: String,
        onClose: @escaping () -> Void = {},
        onReportIssue: @escaping () -> Void
    ) {
        self.fileURL = fileURL
        self.displayName = displayName
        self.onClose = onClose
        self.onReportIssue = onReportIssue
    }

    var body: some View {
        CADMetalLibreDWGPoCEntry(
            fileURL: fileURL,
            displayName: displayName,
            showsToolbar: true,
            initialViewState: nil,
            callbacks: CADRendererCallbacks(),
            onClose: onClose,
            onReportIssue: onReportIssue
        )
    }
}

struct CADMetalLibreDWGPoCEntry: View {
    let fileURL: URL
    let displayName: String
    let showsToolbar: Bool
    let initialViewState: CADRendererViewState?
    let callbacks: CADRendererCallbacks
    let externalVisibleLayerIDs: Set<String>?
    let onLayersChangedExternal: ([CADPoC.CADLayer]) -> Void
    let onVisibleLayerIDsChangedExternal: (Set<String>?) -> Void
    let onClose: () -> Void
    let onReportIssue: () -> Void
    @State private var layers: [CADPoC.CADLayer] = []
    @State private var visibleLayerIDs: Set<String>?
    @State private var canvasControlCommand: CADCanvasControlCommand?
    @State private var rendererViewState: CADRendererViewState?
    @State private var canvasTransform: CADRendererCanvasTransform?
    @AppStorage("cad.metal.poc.showsOverviewMap") private var showsOverviewMap = true

    init(
        fileURL: URL,
        displayName: String,
        showsToolbar: Bool = true,
        initialViewState: CADRendererViewState? = nil,
        callbacks: CADRendererCallbacks = CADRendererCallbacks(),
        externalVisibleLayerIDs: Set<String>? = nil,
        onLayersChangedExternal: @escaping ([CADPoC.CADLayer]) -> Void = { _ in },
        onVisibleLayerIDsChangedExternal: @escaping (Set<String>?) -> Void = { _ in },
        onClose: @escaping () -> Void,
        onReportIssue: @escaping () -> Void
    ) {
        self.fileURL = fileURL
        self.displayName = displayName
        self.showsToolbar = showsToolbar
        self.initialViewState = initialViewState
        self.callbacks = callbacks
        self.externalVisibleLayerIDs = externalVisibleLayerIDs
        self.onLayersChangedExternal = onLayersChangedExternal
        self.onVisibleLayerIDsChangedExternal = onVisibleLayerIDsChangedExternal
        self.onClose = onClose
        self.onReportIssue = onReportIssue
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsToolbar {
                CADViewerToolbar(
                    fileURL: fileURL,
                    displayName: displayName,
                    layers: layers,
                    visibleLayerIDs: effectiveVisibleLayerIDs,
                    onToggleLayer: toggleLayer,
                    onShowAllLayers: showAllLayers,
                    onClose: onClose,
                    onReportIssue: onReportIssue
                )
            }

            canvasLayer
        }
        .background(Color(.systemBackground))
    }

    private var canvasLayer: some View {
        CADCanvasView(
            fileURL: fileURL,
            visibleLayerIDs: effectiveVisibleLayerIDs,
            initialViewState: initialViewState,
            controlCommand: canvasControlCommand,
            debugTextOverlays: false,
            callbacks: bridgedRendererCallbacks,
            onLayersChanged: handleLayersChanged
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            zoomControls
                .padding(12)
        }
        .overlay(alignment: .bottomTrailing) {
            if showsOverviewMap, let canvasTransform {
                CADOverviewMiniMap(transform: canvasTransform)
                    .frame(width: 150, height: 112)
                    .padding(12)
            }
        }
    }

    private var bridgedRendererCallbacks: CADRendererCallbacks {
        var next = callbacks
        next.onOpenTraceChange = { trace in
            callbacks.onOpenTraceChange(trace)
        }
        next.onPerformanceSample = { sample in
            callbacks.onPerformanceSample(sample)
        }
        next.onOpenQualityChange = { quality in
            callbacks.onOpenQualityChange(quality)
        }
        next.onCanvasTransformChange = { transform in
            callbacks.onCanvasTransformChange(transform)
            DispatchQueue.main.async {
                if canvasTransform != transform {
                    canvasTransform = transform
                }
            }
        }
        next.onViewStateChange = { state in
            callbacks.onViewStateChange(state)
            DispatchQueue.main.async {
                if rendererViewState != state {
                    rendererViewState = state
                }
            }
        }
        return next
    }

    private var zoomControls: some View {
        HStack(spacing: 6) {
            zoomButton(systemImage: "minus.magnifyingglass", label: "缩小") {
                sendCanvasCommand(.zoomOut)
            }

            Text(zoomLabel)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .frame(minWidth: 54)

            zoomButton(systemImage: "plus.magnifyingglass", label: "放大") {
                sendCanvasCommand(.zoomIn)
            }

            Divider()
                .frame(height: 24)

            zoomButton(systemImage: "arrow.up.left.and.down.right.magnifyingglass", label: "适配全图") {
                sendCanvasCommand(.fitToView)
            }

            zoomButton(
                systemImage: showsOverviewMap ? "map.fill" : "map",
                label: showsOverviewMap ? "关闭全局小窗" : "打开全局小窗",
                isActive: showsOverviewMap
            ) {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showsOverviewMap.toggle()
                }
            }
        }
        .padding(6)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }

    private var zoomLabel: String {
        let zoom = Double(rendererViewState?.zoomScale ?? initialViewState?.zoomScale ?? 1)
        if zoom >= 10 {
            return "\(Int(zoom.rounded()))x"
        }
        return "\(Int((zoom * 100).rounded()))%"
    }

    private func zoomButton(
        systemImage: String,
        label: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isActive ? Color.white : Color.appPrimaryAction)
        .background {
            Circle().fill(isActive ? Color.appPrimaryAction : Color.clear)
        }
        .accessibilityLabel(label)
    }

    private func sendCanvasCommand(_ kind: CADCanvasControlCommand.Kind) {
        canvasControlCommand = CADCanvasControlCommand(kind: kind)
    }

    private var effectiveVisibleLayerIDs: Set<String>? {
        externalVisibleLayerIDs ?? visibleLayerIDs
    }

    private func handleLayersChanged(_ importedLayers: [CADPoC.CADLayer]) {
        layers = importedLayers
        onLayersChangedExternal(importedLayers)
        let importedVisibleIDs = Set(importedLayers.filter(\.isVisible).map(\.id))
        if effectiveVisibleLayerIDs == nil {
            let nextVisible = importedVisibleIDs.isEmpty ? Set(importedLayers.map(\.id)) : importedVisibleIDs
            visibleLayerIDs = nextVisible
            onVisibleLayerIDsChangedExternal(nextVisible)
        }
    }

    private func toggleLayer(_ layerID: String) {
        var nextVisible = effectiveVisibleLayerIDs ?? Set(layers.filter(\.isVisible).map(\.id))
        if nextVisible.contains(layerID) {
            nextVisible.remove(layerID)
        } else {
            nextVisible.insert(layerID)
        }
        visibleLayerIDs = nextVisible
        onVisibleLayerIDsChangedExternal(nextVisible)
    }

    private func showAllLayers() {
        let nextVisible = Set(layers.map(\.id))
        visibleLayerIDs = nextVisible
        onVisibleLayerIDsChangedExternal(nextVisible)
    }
}

private struct CADOverviewMiniMap: View {
    let transform: CADRendererCanvasTransform

    var body: some View {
        GeometryReader { geometry in
            let viewport = viewportRect(in: geometry.size)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(.systemBackground).opacity(0.72))
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.18), lineWidth: 1)

                Text("全局")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)

                Rectangle()
                    .stroke(Color.primary.opacity(0.24), lineWidth: 1)
                    .padding(8)

                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.appPrimaryAction, lineWidth: 2)
                    .background {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.appPrimaryAction.opacity(0.12))
                    }
                    .frame(width: viewport.width, height: viewport.height)
                    .offset(x: viewport.minX, y: viewport.minY)
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("全局小窗")
    }

    private func viewportRect(in size: CGSize) -> CGRect {
        let drawing = transform.bounds
        guard size.width > 1,
              size.height > 1,
              drawing.width > 0,
              drawing.height > 0 else {
            return CGRect(x: 8, y: 8, width: max(size.width - 16, 1), height: max(size.height - 16, 1))
        }

        let viewport = visibleDrawingRect()
        let x = (viewport.minX - drawing.minX) / drawing.width * size.width
        let y = (drawing.maxY - viewport.maxY) / drawing.height * size.height
        let width = viewport.width / drawing.width * size.width
        let height = viewport.height / drawing.height * size.height
        let raw = CGRect(x: x, y: y, width: width, height: height).standardized
        let bounds = CGRect(origin: .zero, size: size)
        let clipped = raw.intersection(bounds)
        guard !clipped.isNull, !clipped.isEmpty else {
            return CGRect(
                x: clamp(raw.midX, lower: 0, upper: max(size.width - 6, 0)),
                y: clamp(raw.midY, lower: 0, upper: max(size.height - 6, 0)),
                width: 6,
                height: 6
            )
        }
        return CGRect(
            x: clipped.minX,
            y: clipped.minY,
            width: max(clipped.width, 6),
            height: max(clipped.height, 6)
        )
    }

    private func visibleDrawingRect() -> CGRect {
        let drawing = transform.bounds
        let canvasSize = transform.size
        let scale = max(baseFitScale() * transform.zoomScale, 0.000001)
        let center = CGPoint(x: drawing.midX, y: drawing.midY)

        func drawingPoint(from canvasPoint: CGPoint) -> CGPoint {
            CGPoint(
                x: (canvasPoint.x - canvasSize.width / 2 - transform.panOffset.width) / scale + center.x,
                y: (canvasSize.height / 2 + transform.panOffset.height - canvasPoint.y) / scale + center.y
            )
        }

        let topLeft = drawingPoint(from: .zero)
        let bottomRight = drawingPoint(from: CGPoint(x: canvasSize.width, y: canvasSize.height))
        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }

    private func baseFitScale() -> CGFloat {
        let drawing = transform.bounds
        let size = transform.size
        guard drawing.width > 0, drawing.height > 0 else { return 1 }
        let padding = min(max(min(size.width, size.height) * 0.018, 6), 14)
        let availableWidth = max(size.width - padding * 2, 1)
        let availableHeight = max(size.height - padding * 2, 1)
        return max(min(availableWidth / drawing.width, availableHeight / drawing.height), 0.0001)
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
