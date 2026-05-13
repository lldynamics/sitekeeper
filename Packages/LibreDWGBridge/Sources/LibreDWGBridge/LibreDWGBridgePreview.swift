import Foundation
import SwiftUI

public struct LibreDWGBridgePreview: View {
    public let fileURL: URL
    public let preferredCodePage: Int32?

    @State private var state: PreviewState = .loading

    public init(fileURL: URL, preferredCodePage: Int32? = nil) {
        self.fileURL = fileURL
        self.preferredCodePage = preferredCodePage
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .systemBackground))
            .task(id: taskIdentity) {
                await loadPreview()
            }
    }

    private var taskIdentity: String {
        "\(fileURL.path)#\(preferredCodePage.map(String.init) ?? "auto")"
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("正在加载图纸…")
                .controlSize(.large)
        case .dxf(let model, let sourceHint):
            DXFCanvasPreview(model: model, sourceHint: sourceHint)
        case .pdf(let url, let sourceHint):
            PDFSidecarPreview(fileURL: url, sourceHint: sourceHint)
        case .dwgMetadata(let info):
            DWGMetadataPreview(fileURL: fileURL, info: info)
        case .failed(let reason):
            ContentUnavailableView(
                "图纸预览失败",
                systemImage: "exclamationmark.triangle.fill",
                description: Text(reason)
            )
        }
    }

    private func loadPreview() async {
        let ext = fileURL.pathExtension.lowercased()
        do {
            switch ext {
            case "dxf":
                let model = try await Task.detached(priority: .userInitiated) {
                    try DXFPreviewParser.parse(fileURL: fileURL)
                }.value
                state = .dxf(model, nil)
            case "dwg":
                do {
                    let model = try await Task.detached(priority: .userInitiated) {
                        try LibreDWGNativeParser.parse(
                            fileURL: fileURL,
                            preferredCodePage: preferredCodePage
                        )
                    }.value
                    state = .dxf(model, "LibreDWG 已解析 DWG：\(fileURL.lastPathComponent)")
                    return
                } catch {
                    let codePageHint = preferredCodePage.map { "（编码 \(Int($0))）" } ?? ""
                    let nativeParseHint = "LibreDWG C 解析未生成可显示几何\(codePageHint)：\(error.localizedDescription)"
                    let sidecar = await Task.detached(priority: .utility) {
                        DWGSidecarResolver.resolve(for: fileURL)
                    }.value

                    if let dxfURL = sidecar.dxfURL {
                        do {
                            let model = try await Task.detached(priority: .userInitiated) {
                                try DXFPreviewParser.parse(fileURL: dxfURL)
                            }.value
                            state = .dxf(model, "\(nativeParseHint)，已改用同名 DXF：\(dxfURL.lastPathComponent)")
                            return
                        } catch {
                            if let pdfURL = sidecar.pdfURL {
                                state = .pdf(pdfURL, "DWG/DXF 解析失败，已改用同名 PDF：\(pdfURL.lastPathComponent)")
                                return
                            }
                            let info = try await Task.detached(priority: .utility) {
                                try DWGMetadata.from(
                                    fileURL: fileURL,
                                    hints: [
                                        nativeParseHint,
                                        "检测到同名 DXF：\(dxfURL.lastPathComponent)，但解析失败：\(error.localizedDescription)",
                                    ] + sidecar.hints
                                )
                            }.value
                            state = .dwgMetadata(info)
                            return
                        }
                    }

                    if let pdfURL = sidecar.pdfURL {
                        state = .pdf(pdfURL, "\(nativeParseHint)，已改用同名 PDF：\(pdfURL.lastPathComponent)")
                        return
                    }

                    let info = try await Task.detached(priority: .utility) {
                        try DWGMetadata.from(fileURL: fileURL, hints: [nativeParseHint] + sidecar.hints)
                    }.value
                    state = .dwgMetadata(info)
                    return
                }
            default:
                state = .failed("不支持的图纸格式：\(ext.uppercased())")
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

struct DXFPreviewModel {
    struct StrokeStyle {
        let rgb: UInt32
        let width: CGFloat

        static let `default` = StrokeStyle(rgb: 0x2A2A2A, width: 1)
    }

    struct Segment {
        let from: CGPoint
        let to: CGPoint
        let style: StrokeStyle
        let layer: String
    }

    struct Polyline {
        let points: [CGPoint]
        let style: StrokeStyle
        let layer: String
    }

    struct Circle {
        let center: CGPoint
        let radius: CGFloat
        let style: StrokeStyle
        let layer: String
    }

    struct TextEntity: Identifiable {
        let id = UUID()
        let point: CGPoint
        let value: String
        let height: CGFloat
        let rotation: CGFloat
        let style: StrokeStyle
        let layer: String
    }

    var segments: [Segment]
    var polylines: [Polyline]
    var circles: [Circle]
    var texts: [TextEntity] = []
    var arcCount: Int
    var polylineEntityCount: Int
    var sourceObjectCount: Int = 0
    var unsupportedEntityCount: Int = 0
    var bounds: CGRect
}

private struct DXFCanvasPreview: View {
    let model: DXFPreviewModel
    let sourceHint: String?
    private let maxZoomScale: CGFloat = 240
    @State private var zoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var canvasSize: CGSize = .zero
    @State private var visibleLayers: Set<String> = []
    @State private var showLayerSheet = false
    @State private var searchText = ""
    @State private var selectedSearchTextID: UUID?
    @State private var probeCanvasPoint: CGPoint?
    @State private var showCoordinateLegend = true
    @State private var controlsCollapsed = false
    @State private var controlsAutoHideToken = UUID()
    @GestureState private var pinchScale: CGFloat = 1
    @GestureState private var dragOffset: CGSize = .zero

    private struct LayerStat: Identifiable {
        let name: String
        let count: Int
        var id: String { name }
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

    private var layerStats: [LayerStat] {
        var counter: [String: Int] = [:]
        for item in model.segments { counter[item.layer, default: 0] += 1 }
        for item in model.polylines { counter[item.layer, default: 0] += 1 }
        for item in model.circles { counter[item.layer, default: 0] += 1 }
        for item in model.texts { counter[item.layer, default: 0] += 1 }
        return counter
            .map { LayerStat(name: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count { return $0.name < $1.name }
                return $0.count > $1.count
            }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchedTexts: [DXFPreviewModel.TextEntity] {
        guard !normalizedSearchText.isEmpty else { return [] }
        let query = normalizedSearchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return model.texts.filter { text in
            let value = text.value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return value.contains(query)
        }
    }

    private var visibleSegments: [DXFPreviewModel.Segment] {
        model.segments.filter { visibleLayers.contains($0.layer) }
    }

    private var visiblePolylines: [DXFPreviewModel.Polyline] {
        model.polylines.filter { visibleLayers.contains($0.layer) }
    }

    private var visibleCircles: [DXFPreviewModel.Circle] {
        model.circles.filter { visibleLayers.contains($0.layer) }
    }

    private var visibleTexts: [DXFPreviewModel.TextEntity] {
        model.texts.filter { visibleLayers.contains($0.layer) }
    }

    var body: some View {
        GeometryReader { proxy in
            let transform = CADCanvasTransform(
                bounds: model.bounds,
                size: canvasSize == .zero ? proxy.size : canvasSize,
                zoomScale: effectiveScale,
                panOffset: effectiveOffset
            )
            ZStack(alignment: .bottomTrailing) {
                drawingCanvas
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
                    .onTapGesture(count: 2) {
                        fitToAll()
                    }

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
                        toolbarStrip(transform: transform)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .frame(maxHeight: .infinity, alignment: .top)
                }

                if !controlsCollapsed {
                    footerStrip
                        .padding(.leading, 10)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .allowsHitTesting(false)

                    minimap(transform: transform)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .sheet(isPresented: $showLayerSheet) {
                layerSheet
            }
            .onAppear {
                if visibleLayers.isEmpty {
                    visibleLayers = Set(layerStats.map(\.name))
                }
                scheduleControlsAutoHide()
            }
            .onChange(of: searchText) { _, _ in
                syncSearchSelection()
                showControlsTemporarily(scheduleAutoHide: normalizedSearchText.isEmpty)
            }
            .onChange(of: visibleLayers) { _, _ in
                syncSearchSelection()
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

    private var drawingCanvas: some View {
        Canvas { context, size in
            let activeTransform = CADCanvasTransform(
                bounds: model.bounds,
                size: size,
                zoomScale: effectiveScale,
                panOffset: effectiveOffset
            )

            for segment in visibleSegments {
                var path = Path()
                path.move(to: activeTransform.point(segment.from))
                path.addLine(to: activeTransform.point(segment.to))
                context.stroke(path, with: .color(color(from: segment.style.rgb, layer: segment.layer)), lineWidth: max(segment.style.width, 0.45))
            }

            for polyline in visiblePolylines where polyline.points.count > 1 {
                var path = Path()
                path.move(to: activeTransform.point(polyline.points[0]))
                for point in polyline.points.dropFirst() {
                    path.addLine(to: activeTransform.point(point))
                }
                context.stroke(path, with: .color(color(from: polyline.style.rgb, layer: polyline.layer)), lineWidth: max(polyline.style.width, 0.45))
            }

            for circle in visibleCircles {
                let center = activeTransform.point(circle.center)
                let radius = activeTransform.radius(circle.radius)
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(color(from: circle.style.rgb, layer: circle.layer)), lineWidth: max(circle.style.width, 0.45))
            }

            let selectedID = selectedSearchTextID
            let foldedQuery = normalizedSearchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            for text in visibleTexts {
                let point = activeTransform.point(text.point)
                let value = text.value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                let isMatch = !foldedQuery.isEmpty && value.contains(foldedQuery)
                let isSelected = selectedID == text.id
                let renderColor: Color = isSelected ? .red : (isMatch ? .orange : color(from: text.style.rgb, layer: text.layer))
                let fontSize = min(max(activeTransform.radius(text.height), 7), isSelected ? 30 : 26)
                var textContext = context
                textContext.translateBy(x: point.x, y: point.y)
                textContext.rotate(by: .radians(-text.rotation))
                textContext.draw(
                    Text(text.value)
                        .font(.system(size: fontSize))
                        .foregroundStyle(renderColor),
                    at: .zero,
                    anchor: .leading
                )
            }

            if showCoordinateLegend {
                drawAxes(in: &context, transform: activeTransform)
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

    private var footerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Label("\(visibleSegments.count) 条直线", systemImage: "line.diagonal")
                Label("\(visiblePolylines.count) 条多段线", systemImage: "scribble.variable")
                Label("\(model.arcCount) 条圆弧", systemImage: "rotate.left")
                Label("\(visibleCircles.count) 个圆", systemImage: "circle")
                Label("\(visibleTexts.count) 段文字", systemImage: "textformat")
                Label(String(format: "缩放 %.1fx", effectiveScale), systemImage: "magnifyingglass")
                if model.sourceObjectCount > 0 {
                    Label("对象 \(model.sourceObjectCount)", systemImage: "cube.transparent")
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

    private func toolbarStrip(transform: CADCanvasTransform) -> some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        fitToAll()
                    } label: {
                        Label("适应全图", systemImage: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        showControlsTemporarily(scheduleAutoHide: false)
                        showLayerSheet = true
                    } label: {
                        Label("图层开关", systemImage: "square.3.layers.3d")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showCoordinateLegend.toggle()
                        showControlsTemporarily()
                    } label: {
                        Label(showCoordinateLegend ? "隐藏坐标" : "显示坐标", systemImage: "scope")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        zoom(by: 1 / 1.35)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        zoom(by: 1.35)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)

                    Text(String(format: "缩放 %.1fx", effectiveScale))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    Button {
                        collapseControls()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("收起看图工具")
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索图纸文字", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                if !matchedTexts.isEmpty {
                    Button { moveSearchSelection(step: -1) } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.bordered)

                    Button { moveSearchSelection(step: 1) } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.bordered)

                    Text(searchProgressText)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack(spacing: 8) {
                if let sourcePoint = probeSourcePoint(transform: transform) {
                    Text("点位 X:\(formatCoordinate(sourcePoint.x)) Y:\(formatCoordinate(sourcePoint.y))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Text("双击适应全图；单击查看坐标")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("图层 \(visibleLayers.count)/\(max(layerStats.count, 1))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var layerSheet: some View {
        NavigationStack {
            List {
                Section("图层开关") {
                    Button("显示全部") {
                        visibleLayers = Set(layerStats.map(\.name))
                    }
                    Button("全部隐藏", role: .destructive) {
                        visibleLayers.removeAll()
                    }

                    ForEach(layerStats) { layer in
                        Toggle(isOn: Binding(
                            get: { visibleLayers.contains(layer.name) },
                            set: { newValue in
                                if newValue {
                                    visibleLayers.insert(layer.name)
                                } else {
                                    visibleLayers.remove(layer.name)
                                }
                            }
                        )) {
                            HStack {
                                Text(layer.name)
                                Spacer(minLength: 0)
                                Text("\(layer.count)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("图层")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        showLayerSheet = false
                    }
                }
            }
        }
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
        .padding(12)
    }

    private var searchProgressText: String {
        guard !matchedTexts.isEmpty else { return "0/0" }
        let ids = matchedTexts.map(\.id)
        guard let selectedSearchTextID,
              let index = ids.firstIndex(of: selectedSearchTextID) else {
            return "1/\(ids.count)"
        }
        return "\(index + 1)/\(ids.count)"
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

    private func centerOnSelectedText() {
        guard let selectedID = selectedSearchTextID,
              let target = matchedTexts.first(where: { $0.id == selectedID }),
              canvasSize != .zero else { return }
        let transform = CADCanvasTransform(
            bounds: model.bounds,
            size: canvasSize,
            zoomScale: zoomScale,
            panOffset: panOffset
        )
        let currentPoint = transform.point(target.point)
        let centerPoint = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        withAnimation(.easeInOut(duration: 0.2)) {
            panOffset.width += centerPoint.x - currentPoint.x
            panOffset.height += centerPoint.y - currentPoint.y
        }
    }

    private func fitToAll() {
        withAnimation(.easeInOut(duration: 0.2)) {
            zoomScale = 1
            panOffset = .zero
        }
        showControlsTemporarily()
    }

    private func zoom(by factor: CGFloat) {
        guard factor.isFinite, factor > 0 else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            zoomScale = clampScale(zoomScale * factor)
            if zoomScale <= 1.001 {
                panOffset = .zero
            }
        }
        showControlsTemporarily()
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

    private func drawAxes(in context: inout GraphicsContext, transform: CADCanvasTransform) {
        guard model.bounds.contains(CGPoint.zero) else { return }
        var xAxis = Path()
        xAxis.move(to: transform.point(CGPoint(x: model.bounds.minX, y: 0)))
        xAxis.addLine(to: transform.point(CGPoint(x: model.bounds.maxX, y: 0)))
        context.stroke(xAxis, with: .color(.green.opacity(0.75)), lineWidth: 1)

        var yAxis = Path()
        yAxis.move(to: transform.point(CGPoint(x: 0, y: model.bounds.minY)))
        yAxis.addLine(to: transform.point(CGPoint(x: 0, y: model.bounds.maxY)))
        context.stroke(yAxis, with: .color(.blue.opacity(0.75)), lineWidth: 1)
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

    private func color(from rgb: UInt32, layer: String) -> Color {
        if rgb == 0 {
            return layerFallbackColor(layer)
        }
        let red = Double((rgb >> 16) & 0xFF) / 255
        let green = Double((rgb >> 8) & 0xFF) / 255
        let blue = Double(rgb & 0xFF) / 255
        return Color(red: red, green: green, blue: blue)
    }

    private func layerFallbackColor(_ layer: String) -> Color {
        let palette: [Color] = [
            .blue, .green, .orange, .purple, .pink, .teal, .indigo, .mint, .cyan, .brown,
        ]
        let hash = abs(layer.lowercased().hashValue)
        return palette[hash % palette.count]
    }

    private func formatCoordinate(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }
}

private struct CADCanvasTransform {
    let bounds: CGRect
    let size: CGSize
    let zoomScale: CGFloat
    let panOffset: CGSize

    private var contentInset: CGFloat { 16 }

    private var baseScale: CGFloat {
        let availableWidth = max(size.width - contentInset * 2, 1)
        let availableHeight = max(size.height - contentInset * 2, 1)
        let sx = availableWidth / max(bounds.width, 1)
        let sy = availableHeight / max(bounds.height, 1)
        return min(sx, sy)
    }

    private var horizontalPad: CGFloat {
        (size.width - bounds.width * baseScale) / 2
    }

    private var verticalPad: CGFloat {
        (size.height - bounds.height * baseScale) / 2
    }

    func point(_ source: CGPoint) -> CGPoint {
        let x = (source.x - bounds.minX) * baseScale
        let y = (source.y - bounds.minY) * baseScale
        let base = CGPoint(
            x: horizontalPad + x,
            y: size.height - (verticalPad + y)
        )
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(
            x: center.x + (base.x - center.x) * zoomScale + panOffset.width,
            y: center.y + (base.y - center.y) * zoomScale + panOffset.height
        )
    }

    func sourcePoint(_ rendered: CGPoint) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let unscaledX = ((rendered.x - panOffset.width) - center.x) / max(zoomScale, 0.0001) + center.x
        let unscaledY = ((rendered.y - panOffset.height) - center.y) / max(zoomScale, 0.0001) + center.y
        let sourceX = bounds.minX + (unscaledX - horizontalPad) / max(baseScale, 0.0001)
        let sourceY = bounds.minY + ((size.height - unscaledY) - verticalPad) / max(baseScale, 0.0001)
        return CGPoint(x: sourceX, y: sourceY)
    }

    func viewportRectInSource() -> CGRect {
        let topLeft = sourcePoint(CGPoint(x: 0, y: 0))
        let bottomRight = sourcePoint(CGPoint(x: size.width, y: size.height))
        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }

    func radius(_ source: CGFloat) -> CGFloat {
        source * baseScale * zoomScale
    }
}

private enum LibreDWGNativeParser {
    static func parse(fileURL: URL, preferredCodePage: Int32?) throws -> DXFPreviewModel {
        var result = SKCADParseResult()
        let overrideCodePage = preferredCodePage ?? 0
        let success = fileURL.path.withCString { path in
            sk_libredwg_parse_file_with_codepage(path, Int32(overrideCodePage), &result)
        }
        defer {
            sk_libredwg_free_parse_result(&result)
        }

        guard success != 0 else {
            let message = errorMessage(from: &result)
            throw NSError(domain: "LibreDWGBridge", code: 2001, userInfo: [
                NSLocalizedDescriptionKey: message.isEmpty ? "LibreDWG 未能解析 DWG 几何。" : message,
            ])
        }
        guard let primitives = result.primitives, result.primitiveCount > 0 else {
            throw NSError(domain: "LibreDWGBridge", code: 2002, userInfo: [
                NSLocalizedDescriptionKey: "LibreDWG 没有返回可绘制实体。",
            ])
        }

        let buffer = UnsafeBufferPointer(start: primitives, count: Int(result.primitiveCount))
        var segments: [DXFPreviewModel.Segment] = []
        var polylines: [DXFPreviewModel.Polyline] = []
        var circles: [DXFPreviewModel.Circle] = []
        var texts: [DXFPreviewModel.TextEntity] = []
        var arcCount = 0

        for primitive in buffer {
            let style = strokeStyle(from: primitive)
            let layerName: String = {
                guard let raw = primitive.layerName else { return "0" }
                let trimmed = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? "0" : trimmed
            }()
            switch primitive.kind {
            case SKCADPrimitiveLine:
                segments.append(.init(
                    from: CGPoint(x: primitive.start.x, y: primitive.start.y),
                    to: CGPoint(x: primitive.end.x, y: primitive.end.y),
                    style: style,
                    layer: layerName
                ))
            case SKCADPrimitiveArc:
                let points = sampleArcPoints(
                    center: CGPoint(x: primitive.center.x, y: primitive.center.y),
                    radius: primitive.radius,
                    startRadians: primitive.startAngle,
                    endRadians: primitive.endAngle
                )
                if points.count > 1 {
                    polylines.append(.init(points: points, style: style, layer: layerName))
                    arcCount += 1
                }
            case SKCADPrimitiveCircle:
                circles.append(.init(
                    center: CGPoint(x: primitive.center.x, y: primitive.center.y),
                    radius: primitive.radius,
                    style: style,
                    layer: layerName
                ))
            case SKCADPrimitiveText:
                let value: String
                if let text = primitive.text {
                    value = normalizeCADText(String(cString: text))
                } else {
                    value = ""
                }
                if !value.isEmpty {
                    texts.append(.init(
                        point: CGPoint(x: primitive.start.x, y: primitive.start.y),
                        value: value,
                        height: primitive.textHeight > 0 ? primitive.textHeight : 2,
                        rotation: primitive.textRotation,
                        style: style,
                        layer: layerName
                    ))
                }
            default:
                break
            }
        }

        guard let bounds = computeBounds(segments: segments, polylines: polylines, circles: circles, texts: texts) else {
            throw NSError(domain: "LibreDWGBridge", code: 2003, userInfo: [
                NSLocalizedDescriptionKey: "LibreDWG 已读取实体，但无法计算图纸范围。",
            ])
        }

        return DXFPreviewModel(
            segments: segments,
            polylines: polylines,
            circles: circles,
            texts: texts,
            arcCount: arcCount,
            polylineEntityCount: 0,
            sourceObjectCount: Int(result.totalObjectCount),
            unsupportedEntityCount: Int(result.unsupportedEntityCount),
            bounds: bounds
        )
    }

    private static func strokeStyle(from primitive: SKCADPrimitive) -> DXFPreviewModel.StrokeStyle {
        let rgb = UInt32(primitive.strokeRGB & 0x00FF_FFFF)
        let width = CGFloat(max(primitive.strokeWidth, 0.45))
        return .init(rgb: rgb, width: width)
    }

    private static func normalizeCADText(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .replacingOccurrences(of: "\\P", with: "\n")
            .replacingOccurrences(of: "\\p", with: "\n")
            .replacingOccurrences(of: "\\~", with: " ")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
    }

    private static func sampleArcPoints(
        center: CGPoint,
        radius: CGFloat,
        startRadians: CGFloat,
        endRadians: CGFloat
    ) -> [CGPoint] {
        let twoPi = CGFloat.pi * 2
        var end = endRadians
        while end < startRadians {
            end += twoPi
        }
        let span = max(end - startRadians, 0)
        let segments = max(Int(ceil(span / (.pi / 18))), 8)
        return (0...segments).map { index in
            let t = CGFloat(index) / CGFloat(segments)
            let angle = startRadians + span * t
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private static func computeBounds(
        segments: [DXFPreviewModel.Segment],
        polylines: [DXFPreviewModel.Polyline],
        circles: [DXFPreviewModel.Circle],
        texts: [DXFPreviewModel.TextEntity]
    ) -> CGRect? {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        func include(_ point: CGPoint) {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        for segment in segments {
            include(segment.from)
            include(segment.to)
        }
        for polyline in polylines {
            for point in polyline.points {
                include(point)
            }
        }
        for circle in circles {
            include(CGPoint(x: circle.center.x - circle.radius, y: circle.center.y - circle.radius))
            include(CGPoint(x: circle.center.x + circle.radius, y: circle.center.y + circle.radius))
        }
        for text in texts {
            include(text.point)
        }

        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else {
            return nil
        }
        return CGRect(
            x: minX,
            y: minY,
            width: max(maxX - minX, 1),
            height: max(maxY - minY, 1)
        )
    }

    private static func errorMessage(from result: inout SKCADParseResult) -> String {
        withUnsafeBytes(of: &result.errorMessage) { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: CChar.self).baseAddress else {
                return ""
            }
            return String(cString: baseAddress)
        }
    }
}

private enum DXFPreviewParser {
    static func parse(fileURL: URL) throws -> DXFPreviewModel {
        let raw = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let text = decodeText(raw)
        let pairs = dxfPairs(from: text)

        var segments: [DXFPreviewModel.Segment] = []
        var polylines: [DXFPreviewModel.Polyline] = []
        var circles: [DXFPreviewModel.Circle] = []
        var texts: [DXFPreviewModel.TextEntity] = []
        var arcCount = 0
        var polylineEntityCount = 0

        var type: String?
        var fields: [Int: [String]] = [:]
        var isCollectingPolyline = false
        var polylineClosed = false
        var polylineVertices: [CGPoint] = []
        var activePolylineLayer = "0"

        func flushEntity() {
            guard let type else { return }
            let layer = fields.firstString(8).flatMap { raw in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            } ?? "0"
            switch type {
            case "LINE":
                if let x1 = fields.firstDouble(10),
                   let y1 = fields.firstDouble(20),
                   let x2 = fields.firstDouble(11),
                   let y2 = fields.firstDouble(21) {
                    segments.append(.init(
                        from: CGPoint(x: x1, y: y1),
                        to: CGPoint(x: x2, y: y2),
                        style: .default,
                        layer: layer
                    ))
                }
            case "LWPOLYLINE":
                let xs = fields.allDoubles(10)
                let ys = fields.allDoubles(20)
                let count = min(xs.count, ys.count)
                if count > 1 {
                    var points: [CGPoint] = (0..<count).map { CGPoint(x: xs[$0], y: ys[$0]) }
                    let flag = fields.firstInt(70) ?? 0
                    if (flag & 0x01) == 0x01, let first = points.first {
                        points.append(first)
                    }
                    polylines.append(.init(points: points, style: .default, layer: layer))
                    polylineEntityCount += 1
                }
            case "POLYLINE":
                isCollectingPolyline = true
                polylineClosed = ((fields.firstInt(70) ?? 0) & 0x01) == 0x01
                polylineVertices = []
                activePolylineLayer = layer
            case "VERTEX":
                guard isCollectingPolyline,
                      let x = fields.firstDouble(10),
                      let y = fields.firstDouble(20) else { break }
                polylineVertices.append(CGPoint(x: x, y: y))
            case "SEQEND":
                guard isCollectingPolyline else { break }
                var points = polylineVertices
                if polylineClosed, let first = points.first, points.count > 1 {
                    points.append(first)
                }
                if points.count > 1 {
                    polylines.append(.init(points: points, style: .default, layer: activePolylineLayer))
                    polylineEntityCount += 1
                }
                isCollectingPolyline = false
                polylineVertices = []
                activePolylineLayer = "0"
            case "CIRCLE":
                if let x = fields.firstDouble(10),
                   let y = fields.firstDouble(20),
                   let radius = fields.firstDouble(40),
                   radius > 0 {
                    circles.append(.init(
                        center: CGPoint(x: x, y: y),
                        radius: radius,
                        style: .default,
                        layer: layer
                    ))
                }
            case "ARC":
                if let centerX = fields.firstDouble(10),
                   let centerY = fields.firstDouble(20),
                   let radius = fields.firstDouble(40),
                   let start = fields.firstDouble(50),
                   let end = fields.firstDouble(51),
                   radius > 0 {
                    let arcPoints = sampleArcPoints(
                        center: CGPoint(x: centerX, y: centerY),
                        radius: radius,
                        startDegrees: start,
                        endDegrees: end
                    )
                    if arcPoints.count > 1 {
                        polylines.append(.init(points: arcPoints, style: .default, layer: layer))
                        arcCount += 1
                    }
                }
            case "SOLID", "TRACE", "3DFACE":
                if let x1 = fields.firstDouble(10),
                   let y1 = fields.firstDouble(20),
                   let x2 = fields.firstDouble(11),
                   let y2 = fields.firstDouble(21),
                   let x3 = fields.firstDouble(12),
                   let y3 = fields.firstDouble(22) {
                    var points = [
                        CGPoint(x: x1, y: y1),
                        CGPoint(x: x2, y: y2),
                        CGPoint(x: x3, y: y3),
                    ]
                    if let x4 = fields.firstDouble(13),
                       let y4 = fields.firstDouble(23) {
                        points.append(CGPoint(x: x4, y: y4))
                    }
                    if let first = points.first {
                        points.append(first)
                    }
                    if points.count > 2 {
                        polylines.append(.init(points: points, style: .default, layer: layer))
                    }
                }
            case "DIMENSION":
                if let x1 = fields.firstDouble(13),
                   let y1 = fields.firstDouble(23),
                   let x2 = fields.firstDouble(14),
                   let y2 = fields.firstDouble(24) {
                    polylines.append(.init(
                        points: [CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2)],
                        style: .default,
                        layer: layer
                    ))
                }
                if let x = fields.firstDouble(11),
                   let y = fields.firstDouble(21),
                   let rawValue = fields.firstString(1) {
                    let normalized = normalizeDXFText(rawValue)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(53) ?? 0) * .pi / 180),
                            style: .default,
                            layer: layer
                        ))
                    }
                }
            case "LEADER", "MULTILEADER":
                let xs = fields.allDoubles(10)
                let ys = fields.allDoubles(20)
                let count = min(xs.count, ys.count)
                if count > 1 {
                    let points = (0..<count).map { CGPoint(x: xs[$0], y: ys[$0]) }
                    polylines.append(.init(points: points, style: .default, layer: layer))
                }
                if let x = fields.firstDouble(11),
                   let y = fields.firstDouble(21),
                   let rawValue = fields.firstString(304) ?? fields.firstString(1) {
                    let normalized = normalizeDXFText(rawValue)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(50) ?? 0) * .pi / 180),
                            style: .default,
                            layer: layer
                        ))
                    }
                }
            case "HATCH":
                let xs = fields.allDoubles(10)
                let ys = fields.allDoubles(20)
                let count = min(xs.count, ys.count)
                if count > 1 {
                    var points = (0..<count).map { CGPoint(x: xs[$0], y: ys[$0]) }
                    if let first = points.first, let last = points.last,
                       (abs(first.x - last.x) > 0.0001 || abs(first.y - last.y) > 0.0001) {
                        points.append(first)
                    }
                    polylines.append(.init(points: points, style: .default, layer: layer))
                }
            case "IMAGE", "WIPEOUT":
                if let x = fields.firstDouble(10),
                   let y = fields.firstDouble(20),
                   let ux = fields.firstDouble(11),
                   let uy = fields.firstDouble(21),
                   let vx = fields.firstDouble(12),
                   let vy = fields.firstDouble(22),
                   let width = fields.firstDouble(13),
                   let height = fields.firstDouble(23) {
                    let a = CGPoint(x: x, y: y)
                    let b = CGPoint(x: x + ux * width, y: y + uy * width)
                    let d = CGPoint(x: x + vx * height, y: y + vy * height)
                    let c = CGPoint(x: b.x + (d.x - a.x), y: b.y + (d.y - a.y))
                    let points = [a, b, c, d, a]
                    polylines.append(.init(points: points, style: .default, layer: layer))
                }
            case "TEXT", "ATTRIB":
                if let x = fields.firstDouble(10),
                   let y = fields.firstDouble(20),
                   let rawValue = fields.firstString(1) {
                    let normalized = normalizeDXFText(rawValue)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(50) ?? 0) * .pi / 180),
                            style: .default,
                            layer: layer
                        ))
                    }
                }
            case "MTEXT":
                if let x = fields.firstDouble(10),
                   let y = fields.firstDouble(20) {
                    let chunks = fields.allStrings(3)
                    let tail = fields.firstString(1).map { [$0] } ?? []
                    let merged = (chunks + tail).joined()
                    let normalized = normalizeDXFText(merged)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(50) ?? 0) * .pi / 180),
                            style: .default,
                            layer: layer
                        ))
                    }
                }
            default:
                break
            }
        }

        for pair in pairs {
            if pair.code == 0 {
                flushEntity()
                type = pair.value.uppercased()
                fields = [:]
            } else if type != nil {
                fields[pair.code, default: []].append(pair.value)
            }
        }
        flushEntity()

        let bounds = computeBounds(
            segments: segments,
            polylines: polylines,
            circles: circles,
            texts: texts
        )
        guard let bounds else {
            throw NSError(domain: "LibreDWGBridge", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "未识别到可绘制的 DXF 几何元素（当前支持 LINE / ARC / LWPOLYLINE / POLYLINE / CIRCLE / SOLID / 3DFACE / DIMENSION / TEXT / MTEXT / ATTRIB）。",
            ])
        }

        return DXFPreviewModel(
            segments: segments,
            polylines: polylines,
            circles: circles,
            texts: texts,
            arcCount: arcCount,
            polylineEntityCount: polylineEntityCount,
            bounds: bounds
        )
    }

    private static func decodeText(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let ascii = String(data: data, encoding: .ascii) {
            return ascii
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func dxfPairs(from text: String) -> [(code: Int, value: String)] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
        var result: [(code: Int, value: String)] = []
        var index = 0
        while index + 1 < lines.count {
            let codeText = lines[index].trimmingCharacters(in: .whitespaces)
            let valueText = lines[index + 1].trimmingCharacters(in: .whitespaces)
            if let code = Int(codeText) {
                result.append((code: code, value: valueText))
            }
            index += 2
        }
        return result
    }

    private static func computeBounds(
        segments: [DXFPreviewModel.Segment],
        polylines: [DXFPreviewModel.Polyline],
        circles: [DXFPreviewModel.Circle],
        texts: [DXFPreviewModel.TextEntity]
    ) -> CGRect? {
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        func include(_ point: CGPoint) {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }

        for segment in segments {
            include(segment.from)
            include(segment.to)
        }
        for polyline in polylines {
            for point in polyline.points {
                include(point)
            }
        }
        for circle in circles {
            include(CGPoint(x: circle.center.x - circle.radius, y: circle.center.y - circle.radius))
            include(CGPoint(x: circle.center.x + circle.radius, y: circle.center.y + circle.radius))
        }
        for text in texts {
            include(text.point)
        }

        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else {
            return nil
        }
        let width = max(maxX - minX, 1)
        let height = max(maxY - minY, 1)
        return CGRect(x: minX, y: minY, width: width, height: height)
    }

    private static func sampleArcPoints(
        center: CGPoint,
        radius: CGFloat,
        startDegrees: CGFloat,
        endDegrees: CGFloat
    ) -> [CGPoint] {
        let twoPi = CGFloat.pi * 2
        let start = startDegrees * .pi / 180
        var end = endDegrees * .pi / 180
        while end < start {
            end += twoPi
        }
        let span = max(end - start, 0)
        let segments = max(Int(ceil(span / (.pi / 18))), 8)
        guard segments > 0 else { return [] }

        return (0...segments).map { index in
            let t = CGFloat(index) / CGFloat(segments)
            let angle = start + span * t
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    private static func normalizeDXFText(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\\P", with: "\n")
            .replacingOccurrences(of: "\\p", with: "\n")
            .replacingOccurrences(of: "\\~", with: " ")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Dictionary where Key == Int, Value == [String] {
    func firstDouble(_ code: Int) -> CGFloat? {
        self[code]?.first.flatMap { Double($0) }.map { CGFloat($0) }
    }

    func allDoubles(_ code: Int) -> [CGFloat] {
        (self[code] ?? []).compactMap { Double($0) }.map { CGFloat($0) }
    }

    func firstInt(_ code: Int) -> Int? {
        self[code]?.first.flatMap(Int.init)
    }

    func firstString(_ code: Int) -> String? {
        self[code]?.first
    }

    func allStrings(_ code: Int) -> [String] {
        self[code] ?? []
    }
}
