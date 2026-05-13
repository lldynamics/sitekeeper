import Foundation
import SwiftUI

public struct LibreDWGBridgePreview: View {
    public let fileURL: URL
    public let preferredCodePage: Int32?
    public let preferredBigFont: Int32?

    @State private var state: PreviewState = .loading

    public init(fileURL: URL, preferredCodePage: Int32? = nil, preferredBigFont: Int32? = nil) {
        self.fileURL = fileURL
        self.preferredCodePage = preferredCodePage
        self.preferredBigFont = preferredBigFont
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
        "\(fileURL.path)#\(preferredCodePage.map(String.init) ?? "auto")#\(preferredBigFont.map(String.init) ?? "auto")"
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("正在加载图纸…")
                .controlSize(.large)
        case .dxf(let model, let sourceHint):
            DXFCanvasPreview(model: model, sourceHint: sourceHint, fileURL: fileURL)
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
                    try DXFPreviewParser.parse(
                        fileURL: fileURL,
                        preferredCodePage: preferredCodePage,
                        preferredBigFont: preferredBigFont
                    )
                }.value
                state = .dxf(model, nil)
            case "dwg":
                do {
                    let model = try await Task.detached(priority: .userInitiated) {
                        try LibreDWGNativeParser.parse(
                            fileURL: fileURL,
                            preferredCodePage: preferredCodePage,
                            preferredBigFont: preferredBigFont
                        )
                    }.value
                    state = .dxf(model, "LibreDWG 已解析 DWG：\(fileURL.lastPathComponent)")
                    return
                } catch {
                    let codePageHint = preferredCodePage.map { "（编码 \(Int($0))）" } ?? ""
                    let bigFontHint = preferredBigFont.map { " / 字体 \(Int($0))" } ?? ""
                    let nativeParseHint = "LibreDWG C 解析未生成可显示几何\(codePageHint)\(bigFontHint)：\(error.localizedDescription)"
                    let sidecar = await Task.detached(priority: .utility) {
                        DWGSidecarResolver.resolve(for: fileURL)
                    }.value

                    if let dxfURL = sidecar.dxfURL {
                        do {
                            let model = try await Task.detached(priority: .userInitiated) {
                                try DXFPreviewParser.parse(
                                    fileURL: dxfURL,
                                    preferredCodePage: preferredCodePage,
                                    preferredBigFont: preferredBigFont
                                )
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

private struct DXFCanvasPreview: View {
    let model: DXFPreviewModel
    let sourceHint: String?
    let fileURL: URL
    private let maxZoomScale: CGFloat = 240
    @State private var zoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var canvasSize: CGSize = .zero
    @State private var visibleLayers: Set<String> = []
    @State private var showLayerSheet = false
    @State private var showSearchResults = false
    @State private var searchText = ""
    @State private var layerSearchText = ""
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

    private var normalizedLayerSearchText: String {
        layerSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredLayerStats: [LayerStat] {
        guard !normalizedLayerSearchText.isEmpty else { return layerStats }
        let query = normalizedLayerSearchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return layerStats.filter { layer in
            layer.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).contains(query)
        }
    }

    private var matchedTexts: [DXFPreviewModel.TextEntity] {
        guard !normalizedSearchText.isEmpty else { return [] }
        let query = normalizedSearchText.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return model.texts.filter { text in
            guard visibleLayers.isEmpty || visibleLayers.contains(text.layer) else { return false }
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
            .sheet(isPresented: $showSearchResults) {
                searchResultsSheet
            }
            .onAppear {
                if visibleLayers.isEmpty {
                    visibleLayers = Set(layerStats.map(\.name))
                }
                postCanvasTransform(transform)
                scheduleControlsAutoHide()
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
        TimelineView(.animation(minimumInterval: 0.25)) { timeline in
            let searchPulse = searchHighlightPulse(at: timeline.date)
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
                switch polyline.renderKind {
                case .hatch:
                    context.fill(path, with: .color(Color.orange.opacity(0.08)))
                    context.stroke(
                        path,
                        with: .color(color(from: polyline.style.rgb, layer: polyline.layer).opacity(0.82)),
                        style: StrokeStyle(lineWidth: max(polyline.style.width, 0.55), dash: [4, 3])
                    )
                case .dimension:
                    context.stroke(
                        path,
                        with: .color(Color.cyan.opacity(0.95)),
                        style: StrokeStyle(lineWidth: max(polyline.style.width, 0.75), dash: [7, 3])
                    )
                    drawDimensionTicks(for: polyline, in: &context, transform: activeTransform)
                case .regular:
                    context.stroke(path, with: .color(color(from: polyline.style.rgb, layer: polyline.layer)), lineWidth: max(polyline.style.width, 0.45))
                }
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
                let renderColor = textColor(for: text, isMatch: isMatch, isSelected: isSelected, pulse: searchPulse)
                let fontSize = textFontSize(for: text, transform: activeTransform, isSelected: isSelected)
                var textContext = context
                textContext.translateBy(x: point.x, y: point.y)
                textContext.rotate(by: .radians(-text.rotation))
                if isSelected || text.renderKind == .dimension || text.renderKind == .hatch {
                    drawTextBackdrop(
                        for: text,
                        fontSize: fontSize,
                        isSelected: isSelected,
                        pulse: searchPulse,
                        in: &textContext
                    )
                }
                textContext.draw(
                    Text(text.value)
                        .font(.system(size: fontSize, weight: textWeight(for: text), design: .default))
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
                if let textDecodingHint = model.textDecodingHint, !textDecodingHint.isEmpty {
                    Label(textDecodingHint, systemImage: "character.book.closed")
                }
                if let unsupportedEntitySummary = model.unsupportedEntitySummary, !unsupportedEntitySummary.isEmpty {
                    Label("未渲染 \(unsupportedEntitySummary)", systemImage: "exclamationmark.triangle")
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
                    Button {
                        showControlsTemporarily(scheduleAutoHide: false)
                        showSearchResults = true
                    } label: {
                        Label("结果", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        centerOnSelectedText()
                        showControlsTemporarily(scheduleAutoHide: false)
                    } label: {
                        Label("定位", systemImage: "scope")
                    }
                    .buttonStyle(.borderedProminent)

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
                Section {
                    TextField("搜索图层名称", text: $layerSearchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                Section("图层开关") {
                    Button("显示全部") {
                        visibleLayers = Set(layerStats.map(\.name))
                    }
                    Button("全部隐藏", role: .destructive) {
                        visibleLayers.removeAll()
                    }

                    if filteredLayerStats.isEmpty {
                        ContentUnavailableView(
                            "没有匹配图层",
                            systemImage: "square.3.layers.3d.down.right.slash",
                            description: Text("换个关键词继续搜索")
                        )
                    }

                    ForEach(filteredLayerStats) { layer in
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

    private var searchResultsSheet: some View {
        NavigationStack {
            List {
                if matchedTexts.isEmpty {
                    ContentUnavailableView(
                        "没有匹配文字",
                        systemImage: "text.magnifyingglass",
                        description: Text("输入图纸文字后再查看结果")
                    )
                } else {
                    Section("文字搜索结果") {
                        ForEach(matchedTexts) { text in
                            Button {
                                selectSearchResult(text)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(text.value)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    if let rawValue = text.rawValue, rawValue != text.value {
                                        Text("原始文本：\(rawValue)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    HStack(spacing: 8) {
                                        Text(text.layer)
                                        Text("X:\(formatCoordinate(text.point.x)) Y:\(formatCoordinate(text.point.y))")
                                    }
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("解码：\(text.chosenCodepage.map(codePageDisplayName) ?? "自动/未知")")
                                        if let styleName = text.styleName {
                                            Text("样式：\(styleName)")
                                        }
                                        if let fontFile = text.fontFile {
                                            Text("字体：\(fontFile)")
                                        }
                                        if let bigFontFile = text.bigFontFile {
                                            Text("大字体：\(bigFontFile)")
                                        }
                                        if let rawTextBytesHex = text.rawTextBytesHex {
                                            Text("原始字节：\(rawTextBytesHex)")
                                                .textSelection(.enabled)
                                        }
                                    }
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("搜索结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        showSearchResults = false
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
        withAnimation(.easeInOut(duration: 0.2)) {
            panOffset = panOffsetToCenter(sourcePoint: target.point, zoom: zoomScale)
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
        let center = canvasSize == .zero
            ? nil
            : CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        applyZoom(clampScale(zoomScale * factor), anchor: center)
        showControlsTemporarily()
    }

    private func doubleTapZoom(at location: CGPoint) {
        if effectiveScale >= 7.5 {
            fitToAll()
        } else {
            applyZoom(clampScale(zoomScale * 1.8), anchor: location)
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

    private func searchHighlightPulse(at date: Date) -> CGFloat {
        guard selectedSearchTextID != nil, !normalizedSearchText.isEmpty else { return 0 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.95) / 0.95
        return 0.5 + 0.5 * CGFloat(sin(phase * .pi * 2))
    }

    private func textFontSize(
        for text: DXFPreviewModel.TextEntity,
        transform: CADCanvasTransform,
        isSelected: Bool
    ) -> CGFloat {
        let base = activeTextHeight(text, transform: transform)
        switch text.renderKind {
        case .dimension:
            return min(max(base * 1.08, 9), isSelected ? 34 : 28)
        case .hatch:
            return min(max(base * 0.92, 8), isSelected ? 30 : 22)
        case .leader, .attribute:
            return min(max(base, 8), isSelected ? 32 : 25)
        case .regular:
            return min(max(base, 7), isSelected ? 30 : 26)
        }
    }

    private func activeTextHeight(_ text: DXFPreviewModel.TextEntity, transform: CADCanvasTransform) -> CGFloat {
        transform.radius(max(text.height, 1))
    }

    private func textWeight(for text: DXFPreviewModel.TextEntity) -> Font.Weight {
        switch text.renderKind {
        case .dimension:
            return .semibold
        case .hatch:
            return .medium
        case .leader, .attribute:
            return .regular
        case .regular:
            return .regular
        }
    }

    private func textColor(
        for text: DXFPreviewModel.TextEntity,
        isMatch: Bool,
        isSelected: Bool,
        pulse: CGFloat
    ) -> Color {
        if isSelected {
            return Color.red.opacity(0.78 + 0.22 * Double(pulse))
        }
        if isMatch {
            return .orange
        }
        switch text.renderKind {
        case .dimension:
            return .cyan
        case .hatch:
            return .orange
        case .leader:
            return .purple
        case .attribute:
            return .teal
        case .regular:
            return color(from: text.style.rgb, layer: text.layer)
        }
    }

    private func drawTextBackdrop(
        for text: DXFPreviewModel.TextEntity,
        fontSize: CGFloat,
        isSelected: Bool,
        pulse: CGFloat,
        in context: inout GraphicsContext
    ) {
        let textWidth = max(CGFloat(text.value.count) * fontSize * 0.58, fontSize * 1.5)
        let textHeight = fontSize * 1.35
        let paddingX = max(fontSize * 0.36, 4)
        let paddingY = max(fontSize * 0.18, 2)
        let rect = CGRect(
            x: -paddingX,
            y: -textHeight / 2 - paddingY,
            width: textWidth + paddingX * 2,
            height: textHeight + paddingY * 2
        )
        let path = Path(roundedRect: rect, cornerRadius: min(8, textHeight / 2))

        if isSelected {
            let halo = rect.insetBy(dx: -5 - pulse * 5, dy: -4 - pulse * 4)
            context.fill(
                Path(roundedRect: halo, cornerRadius: min(12, halo.height / 2)),
                with: .color(Color.red.opacity(0.12 + 0.24 * Double(pulse)))
            )
            context.stroke(
                Path(roundedRect: halo, cornerRadius: min(12, halo.height / 2)),
                with: .color(Color.red.opacity(0.55 + 0.35 * Double(pulse))),
                lineWidth: 1.1 + pulse * 1.2
            )
        }

        switch text.renderKind {
        case .dimension:
            context.fill(path, with: .color(Color.cyan.opacity(0.12)))
            context.stroke(path, with: .color(Color.cyan.opacity(0.72)), lineWidth: 0.8)
        case .hatch:
            context.fill(path, with: .color(Color.orange.opacity(0.12)))
            context.stroke(path, with: .color(Color.orange.opacity(0.58)), lineWidth: 0.7)
        case .regular, .leader, .attribute:
            if isSelected {
                context.fill(path, with: .color(Color(uiColor: .systemBackground).opacity(0.82)))
            }
        }
    }

    private func drawDimensionTicks(
        for polyline: DXFPreviewModel.Polyline,
        in context: inout GraphicsContext,
        transform: CADCanvasTransform
    ) {
        guard polyline.points.count >= 2 else { return }
        let start = transform.point(polyline.points[0])
        let end = transform.point(polyline.points[polyline.points.count - 1])
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux
        let tickLength = min(max(length * 0.035, 7), 14)

        func addTick(at point: CGPoint, direction: CGFloat) {
            var path = Path()
            path.move(to: CGPoint(
                x: point.x - px * tickLength * 0.5 - ux * tickLength * direction * 0.35,
                y: point.y - py * tickLength * 0.5 - uy * tickLength * direction * 0.35
            ))
            path.addLine(to: CGPoint(
                x: point.x + px * tickLength * 0.5 + ux * tickLength * direction * 0.35,
                y: point.y + py * tickLength * 0.5 + uy * tickLength * direction * 0.35
            ))
            context.stroke(path, with: .color(Color.cyan.opacity(0.95)), lineWidth: 1.2)
        }

        addTick(at: start, direction: 1)
        addTick(at: end, direction: -1)
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

    private func postCanvasTransform(_ transform: CADCanvasTransform) {
        NotificationCenter.default.post(
            name: .libreDWGCanvasTransformDidChange,
            object: nil,
            userInfo: [
                "filePath": fileURL.path,
                "bounds": NSValue(cgRect: transform.bounds),
                "size": NSValue(cgSize: transform.size),
                "zoomScale": transform.zoomScale,
                "panOffset": NSValue(cgSize: transform.panOffset),
            ]
        )
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

    private func codePageDisplayName(_ codePage: Int) -> String {
        switch codePage {
        case 936:
            return "GBK 936"
        case 54936:
            return "GB18030 54936"
        case 950:
            return "Big5 950"
        case 932:
            return "Shift-JIS 932"
        case 949:
            return "Korean 949"
        case 65001:
            return "UTF-8"
        default:
            return "CP\(codePage)"
        }
    }
}

private enum DXFPreviewParser {
    private struct DecodedTextPayload {
        let text: String
        let resolvedCodePage: Int32?
        let usedPreferredCodePage: Bool
    }

    static func parse(
        fileURL: URL,
        preferredCodePage: Int32? = nil,
        preferredBigFont: Int32? = nil
    ) throws -> DXFPreviewModel {
        let raw = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        let decodedPayload = decodeText(raw, preferredCodePage: preferredCodePage)
        let text = decodedPayload.text
        let bigFontProfile = preferredBigFont
            .flatMap(CADTextBigFontProfile.init(rawValue:)) ?? .auto
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
                        style: DXFPreviewModel.StrokeStyle(rgb: 0x008EA8, width: 0.9),
                        layer: layer,
                        renderKind: .dimension
                    ))
                }
                if let x = fields.firstDouble(11),
                   let y = fields.firstDouble(21),
                   let rawValue = fields.firstString(1) {
                    let normalized = normalizeDXFText(rawValue, bigFontProfile: bigFontProfile)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            rawValue: rawValue,
                            rawTextBytesHex: nil,
                            chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(53) ?? 0) * .pi / 180),
                            style: DXFPreviewModel.StrokeStyle(rgb: 0x008EA8, width: 0.9),
                            layer: layer,
                            renderKind: .dimension
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
                    let normalized = normalizeDXFText(rawValue, bigFontProfile: bigFontProfile)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            rawValue: rawValue,
                            rawTextBytesHex: nil,
                            chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(50) ?? 0) * .pi / 180),
                            style: DXFPreviewModel.StrokeStyle(rgb: 0x7A3DB8, width: 0.8),
                            layer: layer,
                            renderKind: .leader
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
                    polylines.append(.init(
                        points: points,
                        style: DXFPreviewModel.StrokeStyle(rgb: 0xCC7A00, width: 0.7),
                        layer: layer,
                        renderKind: .hatch
                    ))
                    if let labelPoint = centroid(of: points),
                       let rawPattern = fields.firstString(2) {
                        let pattern = normalizeDXFText(rawPattern, bigFontProfile: bigFontProfile)
                        let label = hatchLabel(for: pattern, solidFlag: fields.firstInt(70))
                        if !label.isEmpty {
                            texts.append(.init(
                                point: labelPoint,
                                value: label,
                                rawValue: rawPattern,
                                rawTextBytesHex: nil,
                                chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
                                height: max(fields.firstDouble(41) ?? 2, 1.4),
                                rotation: 0,
                                style: DXFPreviewModel.StrokeStyle(rgb: 0xCC7A00, width: 0.7),
                                layer: layer,
                                renderKind: .hatch
                            ))
                        }
                    }
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
                    let normalized = normalizeDXFText(rawValue, bigFontProfile: bigFontProfile)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            rawValue: rawValue,
                            rawTextBytesHex: nil,
                            chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
                            height: fields.firstDouble(40) ?? 2,
                            rotation: ((fields.firstDouble(50) ?? 0) * .pi / 180),
                            style: .default,
                            layer: layer,
                            renderKind: type == "ATTRIB" ? .attribute : .regular
                        ))
                    }
                }
            case "MTEXT":
                if let x = fields.firstDouble(10),
                   let y = fields.firstDouble(20) {
                    let chunks = fields.allStrings(3)
                    let tail = fields.firstString(1).map { [$0] } ?? []
                    let merged = (chunks + tail).joined()
                    let normalized = normalizeDXFText(merged, bigFontProfile: bigFontProfile)
                    if !normalized.isEmpty {
                        texts.append(.init(
                            point: CGPoint(x: x, y: y),
                            value: normalized,
                            rawValue: merged,
                            rawTextBytesHex: nil,
                            chosenCodepage: decodedPayload.resolvedCodePage.map(Int.init),
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
            textDecodingHint: decodingHint(
                preferredCodePage: preferredCodePage,
                resolvedCodePage: decodedPayload.resolvedCodePage,
                preferredBigFont: preferredBigFont,
                usedPreferredCodePage: decodedPayload.usedPreferredCodePage
            ),
            bounds: bounds
        )
    }

    private static func decodeText(_ data: Data, preferredCodePage: Int32?) -> DecodedTextPayload {
        let candidates: [(Int32?, String.Encoding)] = {
            var values: [(Int32?, String.Encoding)] = []
            if let preferredCodePage, let encoding = stringEncoding(for: preferredCodePage) {
                values.append((preferredCodePage, encoding))
            }
            values.append(contentsOf: [
                (65001, .utf8),
                (936, stringEncoding(for: 936)),
                (54936, stringEncoding(for: 54936)),
                (950, stringEncoding(for: 950)),
                (932, .shiftJIS),
                (949, stringEncoding(for: 949)),
                (20127, .ascii),
            ].compactMap { codePage, encoding in
                encoding.map { (codePage, $0) }
            })
            return values
        }()

        var seen: Set<UInt> = []
        var best: (text: String, score: Int, codePage: Int32?)?
        for (codePage, encoding) in candidates where seen.insert(encoding.rawValue).inserted {
            guard let decoded = String(data: data, encoding: encoding) else { continue }
            let score = decodedQualityScore(decoded)
            if let preferredCodePage, codePage == preferredCodePage {
                return DecodedTextPayload(
                    text: decoded,
                    resolvedCodePage: preferredCodePage,
                    usedPreferredCodePage: true
                )
            }
            if best == nil || score > best!.score {
                best = (decoded, score, codePage)
            }
        }
        if let best {
            return DecodedTextPayload(
                text: best.text,
                resolvedCodePage: best.codePage,
                usedPreferredCodePage: false
            )
        }
        return DecodedTextPayload(
            text: String(decoding: data, as: UTF8.self),
            resolvedCodePage: 65001,
            usedPreferredCodePage: false
        )
    }

    private static func stringEncoding(for codePage: Int32) -> String.Encoding? {
        let cfEncoding = CFStringConvertWindowsCodepageToEncoding(UInt32(codePage))
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        guard nsEncoding != UInt(kCFStringEncodingInvalidId) else { return nil }
        return String.Encoding(rawValue: nsEncoding)
    }

    private static func decodedQualityScore(_ text: String) -> Int {
        var score = 0
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if (0x3400...0x4DBF).contains(value) ||
                (0x4E00...0x9FFF).contains(value) ||
                (0xF900...0xFAFF).contains(value) ||
                (0x3000...0x303F).contains(value) ||
                (0xFF00...0xFFEF).contains(value) {
                score += 12
            } else if value == 0xFFFD {
                score -= 40
            } else if (0x00A0...0x00FF).contains(value) {
                score -= 6
            } else if value == 0x3F {
                score -= 4
            } else if value < 0x20 && scalar != "\n" && scalar != "\r" && scalar != "\t" {
                score -= 12
            } else if value < 0x7F {
                score += 1
            }
        }
        score += cadVocabularyScore(text)
        return score
    }

    private static func cadVocabularyScore(_ text: String) -> Int {
        let commonTerms = [
            "平面", "立面", "剖面", "详图", "节点", "标高", "轴线", "尺寸",
            "配电", "回路", "照明", "插座", "桥架", "线管", "接地", "负荷", "施工",
            "建筑", "结构", "电气", "给排水", "消防", "弱电", "系统图", "配线",
            "平面圖", "立面圖", "剖面圖", "詳圖", "節點", "標高", "軸線", "尺寸",
            "配電", "迴路", "照明", "插座", "橋架", "線管", "接地", "負荷", "施工",
            "建築", "結構", "電氣", "給排水", "消防", "弱電", "系統圖", "配線",
        ]
        let suspiciousGlyphs = ["Ê", "Ð", "Ä", "Ã", "Â", "Ó", "Æ", "Ë", "·", "µ", "Ç"]
        var score = 0
        for term in commonTerms where text.contains(term) {
            score += 18
        }
        for glyph in suspiciousGlyphs where text.contains(glyph) {
            score -= 18
        }
        return score
    }

    private static func decodingHint(
        preferredCodePage: Int32?,
        resolvedCodePage: Int32?,
        preferredBigFont: Int32?,
        usedPreferredCodePage: Bool
    ) -> String? {
        let bodyText: String
        if usedPreferredCodePage, let preferredCodePage {
            bodyText = "正文 \(codePageName(for: preferredCodePage))"
        } else if let resolvedCodePage {
            bodyText = "正文自动命中 \(codePageName(for: resolvedCodePage))"
        } else {
            bodyText = "正文自动编码"
        }
        let shxText = preferredBigFont
            .flatMap(CADTextBigFontProfile.init(rawValue:))
            .map(bigFontName(for:)) ?? "自动 SHX"
        return "\(bodyText) / \(shxText)"
    }

    private static func codePageName(for codePage: Int32) -> String {
        switch codePage {
        case 936:
            return "GBK 936"
        case 950:
            return "Big5 950"
        case 54936:
            return "GB18030 54936"
        case 932:
            return "Shift-JIS 932"
        case 949:
            return "Korean 949"
        case 65001:
            return "UTF-8"
        case 20127:
            return "ASCII"
        default:
            return "代码页 \(Int(codePage))"
        }
    }

    private static func bigFontName(for profile: CADTextBigFontProfile) -> String {
        switch profile {
        case .auto:
            return "自动 SHX"
        case .gbcbig:
            return "GBCBIG"
        case .hztxt:
            return "HZTXT"
        case .hzfs:
            return "HZFS"
        case .big5:
            return "Big5 字体"
        case .disabled:
            return "关闭 SHX 映射"
        }
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

    private static func centroid(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let uniquePoints: [CGPoint]
        if points.count > 1, points.first == points.last {
            uniquePoints = Array(points.dropLast())
        } else {
            uniquePoints = points
        }
        guard !uniquePoints.isEmpty else { return nil }

        let sum = uniquePoints.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(
            x: sum.x / CGFloat(uniquePoints.count),
            y: sum.y / CGFloat(uniquePoints.count)
        )
    }

    private static func hatchLabel(for pattern: String, solidFlag: Int?) -> String {
        let normalized = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty {
            return ""
        }
        if normalized.caseInsensitiveCompare("SOLID") == .orderedSame || solidFlag == 1 {
            return "实填充"
        }
        return normalized
    }

    private static func normalizeDXFText(_ raw: String, bigFontProfile: CADTextBigFontProfile) -> String {
        CADTextNormalizer.normalize(raw, bigFontProfile: bigFontProfile)
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
