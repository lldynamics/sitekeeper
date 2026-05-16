import SwiftUI

private actor SiteKeeperCADKernelEngineSession {
    private let engine: SiteKeeperCADKernel.SiteKeeperCADViewerEngine

    init(engine: SiteKeeperCADKernel.SiteKeeperCADViewerEngine = SiteKeeperCADKernel.SiteKeeperCADViewerEngine()) {
        self.engine = engine
    }

    func open(file: SiteKeeperCADKernel.CADFile) async throws -> SiteKeeperCADKernel.CADOpenResult {
        try await engine.open(file: file)
    }

    func render(
        viewport: SiteKeeperCADKernel.CADViewport,
        options: SiteKeeperCADKernel.CADRenderOptions
    ) async throws -> SiteKeeperCADKernel.CADRenderFrame {
        try await engine.render(viewport: viewport, options: options)
    }

    func setLayerVisible(_ layerId: String, visible: Bool) async throws {
        try await engine.setLayerVisible(layerId, visible: visible)
    }

    func layers() async throws -> [SiteKeeperCADKernel.CADLayer] {
        try await engine.getLayers()
    }

    func search(keyword: String) async throws -> [SiteKeeperCADKernel.CADTextSearchResult] {
        try await engine.searchText(keyword)
    }
}

struct SiteKeeperCADKernelRendererHost: View {
    let fileURL: URL
    let initialViewState: CADRendererViewState?
    let callbacks: CADRendererCallbacks

    @State private var session = SiteKeeperCADKernelEngineSession()
    @State private var loadState: SiteKeeperCADKernelRendererLoadState = .loading
    @State private var database: SiteKeeperCADKernel.CADDatabase?
    @State private var layerStates: [SiteKeeperCADKernel.CADLayer] = []
    @State private var visibleLayerIDs: Set<String> = []
    @State private var currentLayoutID = SiteKeeperCADKernel.CADLayout.modelSpace.id
    @State private var renderFrame: SiteKeeperCADKernel.CADRenderFrame?
    @State private var drawingBounds = SiteKeeperCADKernel.CADBounds(minX: -50, minY: -50, maxX: 50, maxY: 50)
    @State private var canvasSize: CGSize = .zero
    @State private var zoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var pendingInitialViewportCenter: SiteKeeperCADKernel.CADPoint?
    @State private var gestureStartPan: CGSize?
    @State private var gestureStartZoom: CGFloat?
    @State private var renderTask: Task<Void, Never>?
    @State private var searchTask: Task<Void, Never>?
    @State private var renderGeneration: Int = 0
    @State private var layerSheetPresented = false
    @State private var searchSheetPresented = false
    @State private var searchKeyword = ""
    @State private var searchResults: [SiteKeeperCADKernel.CADTextSearchResult] = []
    @State private var focusedBounds: SiteKeeperCADKernel.CADBounds?

    private let minZoomScale: CGFloat = 0.6
    private let maxZoomScale: CGFloat = 24

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                SiteKeeperCADKernelLoadingView(fileName: fileURL.lastPathComponent)
            case .ready:
                interactiveCanvas
            case let .unsupported(message, diagnostics):
                SiteKeeperCADKernelStatusView(
                    fileURL: fileURL,
                    title: "当前图纸暂不支持在线预览",
                    message: message,
                    diagnostics: diagnostics,
                    onReportIssue: {
                        StorageIssueLog.record("CAD feedback requested: \(fileURL.lastPathComponent)")
                    }
                )
            case let .failed(message, diagnostics):
                SiteKeeperCADKernelStatusView(
                    fileURL: fileURL,
                    title: "CAD 导入失败",
                    message: message,
                    diagnostics: diagnostics,
                    onReportIssue: {
                        StorageIssueLog.record("CAD feedback requested: \(fileURL.lastPathComponent)")
                    }
                )
            }
        }
        .task(id: fileURL.path) {
            await load()
        }
        .onDisappear {
            renderTask?.cancel()
            searchTask?.cancel()
        }
    }

    private var interactiveCanvas: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    if let frame = renderFrame {
                        draw(frame: frame, context: &context)
                    }
                }
                .background(Color(uiColor: .systemBackground))
                .onAppear {
                    updateCanvasSize(geo.size)
                }
                .onChange(of: geo.size) { _, newSize in
                    updateCanvasSize(newSize)
                }

                if let focusedBounds {
                    focusedBoundsOverlay(focusedBounds)
                        .allowsHitTesting(false)
                }

                interactiveControls
            }
            .contentShape(Rectangle())
            .gesture(
                panGesture.simultaneously(with: zoomGesture)
            )
            .simultaneousGesture(doubleTapGesture)
            .onReceive(NotificationCenter.default.publisher(for: .cadFocusSourcePoint)) { notice in
                handleFocusNotice(notice)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cadOpenDrawingLayerPanel)) { notice in
                guard noticeFilePath(notice) == fileURL.path else { return }
                layerSheetPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .cadOpenTextSearchPanel)) { notice in
                guard noticeFilePath(notice) == fileURL.path else { return }
                searchSheetPresented = true
            }
        }
        .sheet(isPresented: $layerSheetPresented) {
            layerSheet
        }
        .sheet(isPresented: $searchSheetPresented) {
            searchSheet
        }
    }

    @MainActor
    private func load() async {
        renderTask?.cancel()
        searchTask?.cancel()

        loadState = .loading
        database = nil
        layerStates = []
        visibleLayerIDs = []
        renderFrame = nil
        drawingBounds = SiteKeeperCADKernel.CADBounds(minX: -50, minY: -50, maxX: 50, maxY: 50)
        zoomScale = min(max(initialViewState?.zoomScale ?? 1, minZoomScale), maxZoomScale)
        panOffset = initialViewState?.panOffset ?? .zero
        pendingInitialViewportCenter = initialViewState?.viewportCenter.map(SiteKeeperCADKernel.CADPoint.init)
        focusedBounds = nil
        searchKeyword = ""
        searchResults = []
        renderGeneration = 0

        session = SiteKeeperCADKernelEngineSession()
        let file = SiteKeeperCADKernel.CADFile(url: fileURL)

        do {
            let openResult = try await session.open(file: file)
            switch openResult.status {
            case .rendered:
                guard let openDatabase = openResult.database else {
                    let diagnostics = openResult.diagnostics
                    callbacks.onOpenQualityChange(openQuality(for: diagnostics))
                    loadState = .failed(
                        diagnostics.summary(defaultMessage: CADViewerMessages.onlinePreviewUnavailableMessage),
                        diagnostics
                    )
                    return
                }
                if !openDatabase.hasRenderableContent {
                    callbacks.onOpenQualityChange(openQuality(for: openResult, frame: nil))
                    loadState = .unsupported(
                        CADViewerMessages.importEnginePendingMessage(for: fileURL.pathExtension),
                        openResult.diagnostics
                    )
                    return
                }

                database = openDatabase
                drawingBounds = displayBounds(for: openDatabase)
                currentLayoutID = openDatabase.layouts.first(where: \.isModelSpace)?.id
                    ?? openDatabase.layouts.first?.id
                    ?? SiteKeeperCADKernel.CADLayout.modelSpace.id

                var preparedLayers = sortedLayers(openDatabase.layers)
                let visible = initialVisibleLayerIDs(layers: preparedLayers)
                if !visible.isEmpty {
                    for index in preparedLayers.indices {
                        preparedLayers[index].isVisible = visible.contains(preparedLayers[index].id)
                    }
                }
                layerStates = preparedLayers
                visibleLayerIDs = Set(preparedLayers.filter(\.isVisible).map(\.id))

                try await synchronizeLayerVisibility(with: preparedLayers)
                callbacks.onOpenQualityChange(openQuality(for: openResult, frame: nil))
                loadState = .ready
                publishTransformAndViewState()
                scheduleRender(interactionPhase: .stable, immediate: true)
            case .diagnosticOnly:
                callbacks.onOpenQualityChange(openQuality(for: openResult, frame: nil))
                loadState = .unsupported(
                    CADViewerMessages.onlinePreviewUnavailableMessage,
                    openResult.diagnostics
                )
            case .unsupported:
                callbacks.onOpenQualityChange(openQuality(for: openResult, frame: nil))
                loadState = .unsupported(
                    CADViewerMessages.onlinePreviewUnavailableMessage,
                    openResult.diagnostics
                )
            case .failed:
                callbacks.onOpenQualityChange(openQuality(for: openResult, frame: nil))
                loadState = .failed(
                    openResult.diagnostics.summary(defaultMessage: "CAD 导入失败。"),
                    openResult.diagnostics
                )
            }
        } catch {
            let diagnostics = SiteKeeperCADKernel.CADDrawingDiagnostics(entries: [
                SiteKeeperCADKernel.CADDrawingDiagnostics.Entry(
                    severity: .error,
                    code: "CAD_APP_KERNEL_OPEN_FAILED",
                    message: error.localizedDescription,
                    detail: fileURL.lastPathComponent
                )
            ])
            callbacks.onOpenQualityChange(openQuality(for: diagnostics))
            loadState = .failed(error.localizedDescription, diagnostics)
        }
    }

    @MainActor
    private func synchronizeLayerVisibility(with layers: [SiteKeeperCADKernel.CADLayer]) async throws {
        for layer in layers {
            try await session.setLayerVisible(layer.id, visible: layer.isVisible)
        }
    }

    private func sortedLayers(_ layers: [SiteKeeperCADKernel.CADLayer]) -> [SiteKeeperCADKernel.CADLayer] {
        layers.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func initialVisibleLayerIDs(layers: [SiteKeeperCADKernel.CADLayer]) -> Set<String> {
        guard let initialViewState,
              initialViewState.usesSavedVisibleLayers,
              !initialViewState.visibleLayerNames.isEmpty else {
            return Set(layers.filter(\.isVisible).map(\.id))
        }
        let map = Dictionary(uniqueKeysWithValues: layers.map { ($0.name, $0.id) })
        let ids = Set(initialViewState.visibleLayerNames.compactMap { map[$0] })
        return ids.isEmpty ? Set(layers.filter(\.isVisible).map(\.id)) : ids
    }

    @MainActor
    private func scheduleRender(
        interactionPhase: SiteKeeperCADKernel.CADRenderInteractionPhase,
        immediate: Bool = false
    ) {
        guard case .ready = loadState,
              canvasSize.width > 1,
              canvasSize.height > 1 else { return }

        renderGeneration += 1
        let generation = renderGeneration
        let viewport = currentViewport()
        let options = currentRenderOptions(for: interactionPhase, viewport: viewport)
        renderTask?.cancel()

        renderTask = Task {
            if !immediate && interactionPhase == .zooming {
                try? await Task.sleep(nanoseconds: 22_000_000)
            }
            guard !Task.isCancelled else { return }
            do {
                let frame = try await session.render(viewport: viewport, options: options)
                await MainActor.run {
                    guard generation == renderGeneration else { return }
                    applyRenderedFrame(frame)
                }
            } catch {
                await MainActor.run {
                    callbacks.onFallbackRecommendation("CAD 渲染失败：\(error.localizedDescription)")
                }
            }
        }
    }

    @MainActor
    private func applyRenderedFrame(_ frame: SiteKeeperCADKernel.CADRenderFrame) {
        renderFrame = frame
        callbacks.onPerformanceSample(performanceSnapshot(for: frame))
        callbacks.onOpenQualityChange(
            CADOpenQualitySnapshot(
                level: "ready",
                title: "自有 CAD 内核已启用",
                summary: "已启用实时 viewport 渲染、图层过滤和交互式 LOD。",
                primaryAction: "查看图纸",
                detailLines: frame.performance.warnings,
                allowsMarkup: true,
                supportsSearch: true
            )
        )
        callbacks.onSnapPointsChange(makeSnapPoints(for: frame))
        recordPerformanceTrace(frame.performance)
    }

    @MainActor
    private func updateCanvasSize(_ newSize: CGSize) {
        guard newSize.width > 1, newSize.height > 1 else { return }
        canvasSize = newSize
        applyPendingInitialViewportCenterIfNeeded()
        publishTransformAndViewState()
        scheduleRender(interactionPhase: .stable, immediate: true)
    }

    @MainActor
    private func applyPendingInitialViewportCenterIfNeeded() {
        guard let target = pendingInitialViewportCenter,
              canvasSize.width > 1,
              canvasSize.height > 1 else { return }
        let noPan = makeCanvasTransform(size: canvasSize, zoom: zoomScale, pan: .zero)
        let point = noPan.screenPoint(target)
        panOffset = CGSize(
            width: canvasSize.width / 2 - point.x,
            height: canvasSize.height / 2 - point.y
        )
        pendingInitialViewportCenter = nil
    }

    @MainActor
    private func publishTransformAndViewState() {
        guard canvasSize.width > 1, canvasSize.height > 1 else { return }
        let transform = makeCanvasTransform()
        callbacks.onCanvasTransformChange(
            CADRendererCanvasTransform(
                bounds: transform.baseBoundsRect,
                size: transform.size,
                zoomScale: zoomScale,
                panOffset: panOffset
            )
        )
        let center = transform.worldPoint(
            CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        ).cgPoint
        callbacks.onViewStateChange(
            CADRendererViewState(
                zoomScale: zoomScale,
                panOffset: panOffset,
                viewportCenter: center,
                usesSavedVisibleLayers: layerStates.contains(where: { !$0.isVisible }),
                visibleLayerNames: layerStates.filter(\.isVisible).map(\.name)
            )
        )
    }

    @MainActor
    private func makeCanvasTransform(
        size: CGSize? = nil,
        zoom: CGFloat? = nil,
        pan: CGSize? = nil
    ) -> SiteKeeperCADKernelCanvasTransform {
        SiteKeeperCADKernelCanvasTransform(
            bounds: drawingBounds,
            size: size ?? canvasSize,
            zoomScale: min(max(zoom ?? zoomScale, minZoomScale), maxZoomScale),
            panOffset: pan ?? panOffset
        )
    }

    @MainActor
    private func currentViewport() -> SiteKeeperCADKernel.CADViewport {
        let transform = makeCanvasTransform()
        let visibleBounds = transform.visibleBounds
        return SiteKeeperCADKernel.CADViewport(
            id: "sitekeeper-live-viewport",
            layoutID: currentLayoutID,
            viewCenter: visibleBounds.center,
            viewHeight: max(visibleBounds.height, 1),
            clipBounds: visibleBounds
        )
    }

    @MainActor
    private func currentRenderOptions(
        for interactionPhase: SiteKeeperCADKernel.CADRenderInteractionPhase,
        viewport: SiteKeeperCADKernel.CADViewport
    ) -> SiteKeeperCADKernel.CADRenderOptions {
        let transform = makeCanvasTransform()
        return SiteKeeperCADKernel.CADRenderOptions(
            layoutID: currentLayoutID,
            visibleLayerIDs: visibleLayerIDs,
            viewportBounds: viewport.clipBounds,
            deviceScale: Double(transform.pixelsPerWorldUnit),
            lodPolicy: .standard,
            interactionPhase: interactionPhase,
            renderBudget: interactionPhase == .zooming ? .interactive : .standard,
            enableCache: true
        )
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                if gestureStartPan == nil {
                    gestureStartPan = panOffset
                }
                let start = gestureStartPan ?? .zero
                panOffset = CGSize(
                    width: start.width + value.translation.width,
                    height: start.height + value.translation.height
                )
                focusedBounds = nil
                publishTransformAndViewState()
                scheduleRender(interactionPhase: .zooming)
            }
            .onEnded { _ in
                gestureStartPan = nil
                publishTransformAndViewState()
                scheduleRender(interactionPhase: .stable, immediate: true)
            }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if gestureStartZoom == nil {
                    gestureStartZoom = zoomScale
                }
                let start = gestureStartZoom ?? zoomScale
                zoomScale = min(max(start * value, minZoomScale), maxZoomScale)
                focusedBounds = nil
                publishTransformAndViewState()
                scheduleRender(interactionPhase: .zooming)
            }
            .onEnded { _ in
                gestureStartZoom = nil
                publishTransformAndViewState()
                scheduleRender(interactionPhase: .stable, immediate: true)
            }
    }

    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.easeInOut(duration: 0.18)) {
                    zoomScale = 1
                    panOffset = .zero
                }
                focusedBounds = nil
                publishTransformAndViewState()
                scheduleRender(interactionPhase: .stable, immediate: true)
            }
    }

    private var interactiveControls: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        searchSheetPresented = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.headline)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .background(.regularMaterial, in: Circle())
                    .accessibilityLabel("文字搜索")

                    Button {
                        layerSheetPresented = true
                    } label: {
                        Image(systemName: "rectangle.3.group")
                            .font(.headline)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .background(.regularMaterial, in: Circle())
                    .accessibilityLabel("图层显示")
                    .disabled(layerStates.isEmpty)
                    .opacity(layerStates.isEmpty ? 0.45 : 1)
                }
            }
            .padding(.top, 12)
            .padding(.trailing, 12)

            Spacer()

            if let frame = renderFrame {
                HStack {
                    Label(
                        "可见 \(frame.performance.visibleEntityCount) · 命令 \(frame.performance.renderCommandCount) · \(Int(frame.performance.renderMs))ms",
                        systemImage: "speedometer"
                    )
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12)
                .padding(.bottom, 12)
            }
        }
    }

    private var layerSheet: some View {
        NavigationStack {
            List {
                if layerStates.isEmpty {
                    Text("当前图纸未返回图层索引。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(layerStates, id: \.id) { layer in
                        Toggle(isOn: layerVisibilityBinding(for: layer.id)) {
                            HStack {
                                Text(layer.name)
                                Spacer(minLength: 8)
                                Text(layer.id)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("图纸图层")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        layerSheetPresented = false
                    }
                }
            }
        }
    }

    private func layerVisibilityBinding(for layerID: String) -> Binding<Bool> {
        Binding(
            get: {
                layerStates.first(where: { $0.id == layerID })?.isVisible ?? false
            },
            set: { visible in
                Task { @MainActor in
                    await setLayerVisible(layerID: layerID, visible: visible)
                }
            }
        )
    }

    @MainActor
    private func setLayerVisible(layerID: String, visible: Bool) async {
        guard let index = layerStates.firstIndex(where: { $0.id == layerID }) else { return }
        guard layerStates[index].isVisible != visible else { return }

        let rollback = layerStates
        layerStates[index].isVisible = visible
        visibleLayerIDs = Set(layerStates.filter(\.isVisible).map(\.id))
        publishTransformAndViewState()
        scheduleRender(interactionPhase: .stable)

        do {
            try await session.setLayerVisible(layerID, visible: visible)
            let refreshed = sortedLayers(try await session.layers())
            layerStates = refreshed
            visibleLayerIDs = Set(refreshed.filter(\.isVisible).map(\.id))
            publishTransformAndViewState()
            scheduleRender(interactionPhase: .stable, immediate: true)
        } catch {
            layerStates = rollback
            visibleLayerIDs = Set(rollback.filter(\.isVisible).map(\.id))
            callbacks.onFallbackRecommendation("图层切换失败：\(error.localizedDescription)")
            publishTransformAndViewState()
            scheduleRender(interactionPhase: .stable, immediate: true)
        }
    }

    private var searchSheet: some View {
        NavigationStack {
            List {
                Section {
                    TextField("搜索文字", text: $searchKeyword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section {
                        Text("输入关键字后可定位到图纸实体范围。")
                            .foregroundStyle(.secondary)
                    }
                } else if searchResults.isEmpty {
                    Section {
                        Text("未命中。")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("搜索结果 \(searchResults.count)") {
                        ForEach(searchResults, id: \.id) { result in
                            Button {
                                focus(on: result.bounds)
                                searchSheetPresented = false
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.previewText)
                                        .font(.body)
                                        .lineLimit(2)
                                    Text("实体 \(result.entityId.uuidString.prefix(8)) · 布局 \(result.layoutId)")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("文字搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        searchSheetPresented = false
                    }
                }
            }
        }
        .onAppear {
            refreshSearch()
        }
        .onChange(of: searchKeyword) { _, _ in
            refreshSearch()
        }
    }

    @MainActor
    private func refreshSearch() {
        searchTask?.cancel()
        let keyword = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            searchResults = []
            return
        }
        searchTask = Task {
            do {
                let results = try await session.search(keyword: keyword)
                await MainActor.run {
                    searchResults = results
                }
            } catch {
                await MainActor.run {
                    searchResults = []
                }
            }
        }
    }

    @MainActor
    private func focus(on bounds: SiteKeeperCADKernel.CADBounds) {
        guard canvasSize.width > 1, canvasSize.height > 1 else { return }

        let safeBounds: SiteKeeperCADKernel.CADBounds
        if bounds.isEmpty {
            safeBounds = SiteKeeperCADKernel.CADBounds(
                minX: drawingBounds.center.x - 1,
                minY: drawingBounds.center.y - 1,
                maxX: drawingBounds.center.x + 1,
                maxY: drawingBounds.center.y + 1
            )
        } else {
            let pad = max(max(bounds.width, bounds.height) * 0.6, 8)
            safeBounds = bounds.expanded(by: pad)
        }

        let unitTransform = makeCanvasTransform(size: canvasSize, zoom: 1, pan: .zero)
        let widthZoom = unitTransform.visibleBounds.width / max(safeBounds.width, 0.0001)
        let heightZoom = unitTransform.visibleBounds.height / max(safeBounds.height, 0.0001)
        let targetZoom = min(max(min(widthZoom, heightZoom) * 0.88, minZoomScale), maxZoomScale)
        let centeredTransform = makeCanvasTransform(size: canvasSize, zoom: targetZoom, pan: .zero)
        let screenPoint = centeredTransform.screenPoint(safeBounds.center)
        let targetPan = CGSize(
            width: canvasSize.width / 2 - screenPoint.x,
            height: canvasSize.height / 2 - screenPoint.y
        )

        withAnimation(.easeInOut(duration: 0.22)) {
            zoomScale = targetZoom
            panOffset = targetPan
        }
        focusedBounds = safeBounds
        publishTransformAndViewState()
        scheduleRender(interactionPhase: .stable, immediate: true)
    }

    @MainActor
    private func handleFocusNotice(_ notice: Notification) {
        guard noticeFilePath(notice) == fileURL.path else { return }
        if let boundsValue = notice.userInfo?["bounds"] as? NSValue {
            focus(on: SiteKeeperCADKernel.CADBounds(boundsValue.cgRectValue))
            return
        }
        guard let pointValue = notice.userInfo?["point"] as? NSValue else { return }
        let point = SiteKeeperCADKernel.CADPoint(pointValue.cgPointValue)
        focus(
            on: SiteKeeperCADKernel.CADBounds(
                minX: point.x - 6,
                minY: point.y - 6,
                maxX: point.x + 6,
                maxY: point.y + 6
            )
        )
    }

    private func noticeFilePath(_ notice: Notification) -> String? {
        notice.userInfo?["filePath"] as? String
    }

    private func focusedBoundsOverlay(_ bounds: SiteKeeperCADKernel.CADBounds) -> some View {
        Canvas { context, _ in
            let transform = makeCanvasTransform()
            let rect = transform.screenRect(bounds)
            guard rect.width > 0, rect.height > 0 else { return }
            var path = Path(roundedRect: rect, cornerRadius: 4)
            context.stroke(path, with: .color(Color.appWarning), lineWidth: 2)
            path = Path(rect.insetBy(dx: -4, dy: -4))
            context.stroke(
                path,
                with: .color(Color.appWarning.opacity(0.35)),
                style: StrokeStyle(lineWidth: 1, dash: [4, 3])
            )
        }
    }

    private func draw(
        frame: SiteKeeperCADKernel.CADRenderFrame,
        context: inout GraphicsContext
    ) {
        let transform = makeCanvasTransform()
        var currentPoint: CGPoint?

        for command in frame.commands {
            switch command {
            case let .moveTo(point, _):
                currentPoint = transform.screenPoint(point)
            case let .lineTo(point, style):
                guard let start = currentPoint else {
                    currentPoint = transform.screenPoint(point)
                    continue
                }
                let end = transform.screenPoint(point)
                var path = Path()
                path.move(to: start)
                path.addLine(to: end)
                context.stroke(path, with: .color(color(from: style.colorARGB)), lineWidth: lineWidth(style))
                currentPoint = end
            case let .polyline(points, closed, style):
                drawPolyline(points, closed: closed, style: style, context: &context, transform: transform)
            case let .circle(center, radius, style):
                let screenCenter = transform.screenPoint(center)
                let screenRadius = CGFloat(radius) * transform.pixelsPerWorldUnit
                let rect = CGRect(
                    x: screenCenter.x - screenRadius,
                    y: screenCenter.y - screenRadius,
                    width: screenRadius * 2,
                    height: screenRadius * 2
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(color(from: style.colorARGB)),
                    lineWidth: lineWidth(style)
                )
            case let .arc(center, radius, startAngle, endAngle, style):
                var path = Path()
                path.addArc(
                    center: transform.screenPoint(center),
                    radius: CGFloat(radius) * transform.pixelsPerWorldUnit,
                    startAngle: .radians(-endAngle),
                    endAngle: .radians(-startAngle),
                    clockwise: false
                )
                context.stroke(path, with: .color(color(from: style.colorARGB)), lineWidth: lineWidth(style))
            case let .ellipse(center, radiusX, radiusY, _, style):
                let screenCenter = transform.screenPoint(center)
                let rect = CGRect(
                    x: screenCenter.x - CGFloat(radiusX) * transform.pixelsPerWorldUnit,
                    y: screenCenter.y - CGFloat(radiusY) * transform.pixelsPerWorldUnit,
                    width: CGFloat(radiusX) * transform.pixelsPerWorldUnit * 2,
                    height: CGFloat(radiusY) * transform.pixelsPerWorldUnit * 2
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(color(from: style.colorARGB)),
                    lineWidth: lineWidth(style)
                )
            case let .text(run, style):
                let baseFont = max(min(CGFloat(run.height) * transform.pixelsPerWorldUnit * 0.42, 22), 9)
                var resolved = context.resolve(Text(run.displayText).font(.system(size: baseFont)))
                resolved.shading = .color(color(from: style.colorARGB))
                context.draw(resolved, at: transform.screenPoint(run.insertionPoint), anchor: .bottomLeading)
            case let .hatch(path, style):
                drawPath(path, style: style, context: &context, transform: transform)
            case let .imagePlaceholder(_, bounds, _),
                 let .unsupportedPlaceholder(_, bounds, _):
                drawPlaceholder(bounds, context: &context, transform: transform)
            case let .marker(point, label, style):
                drawMarker(point, label: label, style: style, context: &context, transform: transform)
            }
        }
    }

    private func drawPolyline(
        _ points: [SiteKeeperCADKernel.CADPoint],
        closed: Bool,
        style: SiteKeeperCADKernel.CADRenderStyle,
        context: inout GraphicsContext,
        transform: SiteKeeperCADKernelCanvasTransform
    ) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: transform.screenPoint(first))
        for point in points.dropFirst() {
            path.addLine(to: transform.screenPoint(point))
        }
        if closed {
            path.closeSubpath()
        }
        context.stroke(path, with: .color(color(from: style.colorARGB)), lineWidth: lineWidth(style))
    }

    private func drawPath(
        _ cadPath: SiteKeeperCADKernel.CADPath,
        style: SiteKeeperCADKernel.CADRenderStyle,
        context: inout GraphicsContext,
        transform: SiteKeeperCADKernelCanvasTransform
    ) {
        var path = Path()
        for element in cadPath.elements {
            switch element {
            case let .move(point):
                path.move(to: transform.screenPoint(point))
            case let .line(point):
                path.addLine(to: transform.screenPoint(point))
            case let .curve(point, control1, control2):
                path.addCurve(
                    to: transform.screenPoint(point),
                    control1: transform.screenPoint(control1),
                    control2: transform.screenPoint(control2)
                )
            case .close:
                path.closeSubpath()
            }
        }
        context.stroke(path, with: .color(color(from: style.colorARGB)), lineWidth: lineWidth(style))
    }

    private func drawPlaceholder(
        _ bounds: SiteKeeperCADKernel.CADBounds,
        context: inout GraphicsContext,
        transform: SiteKeeperCADKernelCanvasTransform
    ) {
        guard !bounds.isEmpty else { return }
        let rect = transform.screenRect(bounds)
        guard rect.width > 0, rect.height > 0 else { return }
        var path = Path(rect)
        context.stroke(
            path,
            with: .color(Color.appWarning.opacity(0.75)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
        )
        path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        context.stroke(path, with: .color(Color.appWarning.opacity(0.45)), lineWidth: 1)
    }

    private func drawMarker(
        _ point: SiteKeeperCADKernel.CADPoint,
        label: String?,
        style: SiteKeeperCADKernel.CADRenderStyle,
        context: inout GraphicsContext,
        transform: SiteKeeperCADKernelCanvasTransform
    ) {
        let center = transform.screenPoint(point)
        let rect = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
        context.fill(Path(ellipseIn: rect), with: .color(color(from: style.colorARGB)))
        if let label, !label.isEmpty {
            var resolved = context.resolve(Text(label).font(.caption2))
            resolved.shading = .color(color(from: style.colorARGB))
            context.draw(resolved, at: CGPoint(x: center.x + 8, y: center.y), anchor: .leading)
        }
    }

    private func lineWidth(_ style: SiteKeeperCADKernel.CADRenderStyle) -> CGFloat {
        max(CGFloat(style.lineWidth), 0.75)
    }

    private func color(from argb: UInt32) -> Color {
        let alpha = Double((argb >> 24) & 0xFF) / 255
        let red = Double((argb >> 16) & 0xFF) / 255
        let green = Double((argb >> 8) & 0xFF) / 255
        let blue = Double(argb & 0xFF) / 255
        return Color(
            red: red,
            green: green,
            blue: blue,
            opacity: alpha == 0 ? 1 : alpha
        )
    }

    private func makeSnapPoints(for frame: SiteKeeperCADKernel.CADRenderFrame) -> [CADRendererSnapPointPayload] {
        let layerNames = Dictionary(uniqueKeysWithValues: layerStates.map { ($0.id, $0.name) })
        var payloads: [CADRendererSnapPointPayload] = []
        payloads.reserveCapacity(frame.commands.count * 2)
        var seen: Set<String> = []
        var currentPoint: SiteKeeperCADKernel.CADPoint?

        func append(
            point: SiteKeeperCADKernel.CADPoint,
            kind: String,
            primitive: String,
            style: SiteKeeperCADKernel.CADRenderStyle
        ) {
            let key = "\(kind)|\(primitive)|\(style.layerID)|\(point.x.rounded(toPlaces: 5))|\(point.y.rounded(toPlaces: 5))"
            guard !seen.contains(key) else { return }
            seen.insert(key)
            payloads.append(
                CADRendererSnapPointPayload(
                    point: point.cgPoint,
                    snapKind: kind,
                    layer: layerNames[style.layerID] ?? style.layerID,
                    primitiveKind: primitive,
                    styleRGB: style.colorARGB,
                    styleWidth: CGFloat(style.lineWidth),
                    styleName: nil
                )
            )
        }

        for command in frame.commands {
            switch command {
            case let .moveTo(point, _):
                currentPoint = point
            case let .lineTo(point, style):
                if let start = currentPoint {
                    append(point: start, kind: "endpoint", primitive: "line", style: style)
                    append(point: point, kind: "endpoint", primitive: "line", style: style)
                    append(point: midpoint(start, point), kind: "midpoint", primitive: "line", style: style)
                }
                currentPoint = point
            case let .polyline(points, _, style):
                guard points.count > 1 else { continue }
                append(point: points.first ?? .zero, kind: "endpoint", primitive: "polyline", style: style)
                append(point: points.last ?? .zero, kind: "endpoint", primitive: "polyline", style: style)
                for pair in zip(points, points.dropFirst()) {
                    append(point: midpoint(pair.0, pair.1), kind: "midpoint", primitive: "polyline", style: style)
                }
            case let .circle(center, _, style):
                append(point: center, kind: "center", primitive: "circle", style: style)
            case let .arc(center, radius, startAngle, endAngle, style):
                append(point: center, kind: "center", primitive: "arc", style: style)
                let start = SiteKeeperCADKernel.CADPoint(
                    x: center.x + cos(startAngle) * radius,
                    y: center.y + sin(startAngle) * radius
                )
                let end = SiteKeeperCADKernel.CADPoint(
                    x: center.x + cos(endAngle) * radius,
                    y: center.y + sin(endAngle) * radius
                )
                append(point: start, kind: "endpoint", primitive: "arc", style: style)
                append(point: end, kind: "endpoint", primitive: "arc", style: style)
            case let .ellipse(center, _, _, _, style):
                append(point: center, kind: "center", primitive: "ellipse", style: style)
            case let .text(run, style):
                append(point: run.insertionPoint, kind: "endpoint", primitive: "text", style: style)
            case let .hatch(path, style):
                let hatchPoints = path.points
                guard hatchPoints.count > 1 else { continue }
                append(point: hatchPoints.first ?? .zero, kind: "endpoint", primitive: "hatch", style: style)
                append(point: hatchPoints.last ?? .zero, kind: "endpoint", primitive: "hatch", style: style)
            case let .marker(point, _, style):
                append(point: point, kind: "center", primitive: "circle", style: style)
            case .imagePlaceholder, .unsupportedPlaceholder:
                continue
            }
        }

        return payloads
    }

    private func midpoint(
        _ lhs: SiteKeeperCADKernel.CADPoint,
        _ rhs: SiteKeeperCADKernel.CADPoint
    ) -> SiteKeeperCADKernel.CADPoint {
        SiteKeeperCADKernel.CADPoint(
            x: (lhs.x + rhs.x) / 2,
            y: (lhs.y + rhs.y) / 2
        )
    }

    private func displayBounds(for database: SiteKeeperCADKernel.CADDatabase) -> SiteKeeperCADKernel.CADBounds {
        let contentBounds = database.entities.reduce(database.extents) { partial, entity in
            partial.union(entity.bounds)
        }
        guard !contentBounds.isEmpty else {
            return SiteKeeperCADKernel.CADBounds(minX: -50, minY: -50, maxX: 50, maxY: 50)
        }
        let padding = max(max(contentBounds.width, contentBounds.height) * 0.05, 1)
        return contentBounds.expanded(by: padding)
    }

    private func openQuality(
        for result: SiteKeeperCADKernel.CADOpenResult,
        frame: SiteKeeperCADKernel.CADRenderFrame?
    ) -> CADOpenQualitySnapshot {
        switch result.status {
        case .rendered:
            if result.database?.hasRenderableContent != true {
                return CADOpenQualitySnapshot(
                    level: "kernelBootstrap",
                    title: "在线预览不可用",
                    summary: CADViewerMessages.onlinePreviewUnavailableMessage,
                    primaryAction: "下载原图",
                    detailLines: result.diagnostics.detailLines,
                    allowsMarkup: false,
                    supportsSearch: false
                )
            }
            return CADOpenQualitySnapshot(
                level: "ready",
                title: "在线预览可用",
                summary: "图纸已进入可交互预览。",
                primaryAction: "查看图纸",
                detailLines: frame?.performance.warnings ?? result.diagnostics.detailLines,
                allowsMarkup: true,
                supportsSearch: true
            )
        case .diagnosticOnly:
            return CADOpenQualitySnapshot(
                level: "diagnosticOnly",
                title: "在线预览不可用",
                summary: CADViewerMessages.onlinePreviewUnavailableMessage,
                primaryAction: "下载原图",
                detailLines: result.diagnostics.detailLines,
                allowsMarkup: false,
                supportsSearch: false
            )
        case .unsupported:
            return CADOpenQualitySnapshot(
                level: "kernelBootstrap",
                title: "在线预览不可用",
                summary: CADViewerMessages.onlinePreviewUnavailableMessage,
                primaryAction: "下载原图",
                detailLines: result.diagnostics.detailLines,
                allowsMarkup: false,
                supportsSearch: false
            )
        case .failed:
            return openQuality(for: result.diagnostics)
        }
    }

    private func openQuality(for diagnostics: SiteKeeperCADKernel.CADDrawingDiagnostics) -> CADOpenQualitySnapshot {
        CADOpenQualitySnapshot(
            level: "failed",
            title: "CAD 导入失败",
            summary: diagnostics.summary(defaultMessage: "CAD 导入失败。"),
            primaryAction: "查看诊断",
            detailLines: diagnostics.detailLines,
            allowsMarkup: false,
            supportsSearch: false
        )
    }

    private func performanceSnapshot(for frame: SiteKeeperCADKernel.CADRenderFrame) -> CADRendererPerformanceSnapshot {
        CADRendererPerformanceSnapshot(
            entityCountInViewport: frame.performance.visibleEntityCount,
            drawCallCount: frame.performance.drawCallCount,
            frameTimeMilliseconds: frame.performance.frameTimeMilliseconds,
            skippedEntityCount: frame.performance.skippedEntityCount,
            visibleLayerCount: visibleLayerIDs.count,
            simplifiedMode: frame.performance.skippedEntityCount > 0,
            renderCommandCount: frame.performance.renderCommandCount,
            renderMs: frame.performance.renderMs,
            firstFrameMs: frame.performance.firstFrameMs
        )
    }

    private func recordPerformanceTrace(_ performance: SiteKeeperCADKernel.CADPerformanceTrace) {
        let payload: [String: Any] = [
            "visibleEntityCount": performance.visibleEntityCount,
            "renderCommandCount": performance.renderCommandCount,
            "renderMs": performance.renderMs,
            "firstFrameMs": performance.firstFrameMs,
            "skippedEntityCount": performance.skippedEntityCount
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else {
            return
        }
        StorageIssueLog.record("CAD performance_trace: \(text)")
    }
}

private enum SiteKeeperCADKernelRendererLoadState {
    case loading
    case ready
    case unsupported(String, SiteKeeperCADKernel.CADDrawingDiagnostics)
    case failed(String, SiteKeeperCADKernel.CADDrawingDiagnostics)
}

private struct SiteKeeperCADKernelCanvasTransform {
    let bounds: SiteKeeperCADKernel.CADBounds
    let size: CGSize
    let zoomScale: CGFloat
    let panOffset: CGSize

    var contentInset: CGFloat {
        min(max(min(size.width, size.height) * 0.018, 6), 14)
    }

    var baseScale: CGFloat {
        let availableWidth = max(size.width - contentInset * 2, 1)
        let availableHeight = max(size.height - contentInset * 2, 1)
        let sx = availableWidth / max(CGFloat(bounds.width), 1)
        let sy = availableHeight / max(CGFloat(bounds.height), 1)
        return min(sx, sy)
    }

    var pixelsPerWorldUnit: CGFloat {
        max(baseScale * zoomScale, 0.0001)
    }

    var horizontalPad: CGFloat {
        (size.width - CGFloat(bounds.width) * baseScale) / 2
    }

    var verticalPad: CGFloat {
        (size.height - CGFloat(bounds.height) * baseScale) / 2
    }

    var baseBoundsRect: CGRect {
        guard !bounds.isEmpty else { return .zero }
        return CGRect(
            x: CGFloat(bounds.minX),
            y: CGFloat(bounds.minY),
            width: CGFloat(bounds.width),
            height: CGFloat(bounds.height)
        )
    }

    func screenPoint(_ point: SiteKeeperCADKernel.CADPoint) -> CGPoint {
        let x = CGFloat(point.x - bounds.minX) * baseScale
        let y = CGFloat(point.y - bounds.minY) * baseScale
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

    func worldPoint(_ point: CGPoint) -> SiteKeeperCADKernel.CADPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let unscaledX = ((point.x - panOffset.width) - center.x) / max(zoomScale, 0.0001) + center.x
        let unscaledY = ((point.y - panOffset.height) - center.y) / max(zoomScale, 0.0001) + center.y
        let sourceX = bounds.minX + Double((unscaledX - horizontalPad) / max(baseScale, 0.0001))
        let sourceY = bounds.minY + Double(((size.height - unscaledY) - verticalPad) / max(baseScale, 0.0001))
        return SiteKeeperCADKernel.CADPoint(x: sourceX, y: sourceY)
    }

    var visibleBounds: SiteKeeperCADKernel.CADBounds {
        let tl = worldPoint(.zero)
        let tr = worldPoint(CGPoint(x: size.width, y: 0))
        let bl = worldPoint(CGPoint(x: 0, y: size.height))
        let br = worldPoint(CGPoint(x: size.width, y: size.height))
        return [tl, tr, bl, br].reduce(SiteKeeperCADKernel.CADBounds.empty) { partial, point in
            partial.including(point)
        }
    }

    func screenRect(_ bounds: SiteKeeperCADKernel.CADBounds) -> CGRect {
        let topLeft = screenPoint(SiteKeeperCADKernel.CADPoint(x: bounds.minX, y: bounds.maxY))
        let bottomRight = screenPoint(SiteKeeperCADKernel.CADPoint(x: bounds.maxX, y: bounds.minY))
        return CGRect(
            x: topLeft.x,
            y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
    }
}

private struct SiteKeeperCADKernelLoadingView: View {
    let fileName: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("正在启动 CAD 看图内核")
                .font(.headline)
            Text(fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}

private struct SiteKeeperCADKernelStatusView: View {
    let fileURL: URL
    let title: String
    let message: String
    let diagnostics: SiteKeeperCADKernel.CADDrawingDiagnostics
    let onReportIssue: (() -> Void)?

    private var shouldShowTechnicalDetails: Bool {
        CADTechnicalDiagnosticsVisibility.isEnabled && !diagnostics.entries.isEmpty
    }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.appWarning)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title3.weight(.semibold))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ShareLink(item: fileURL) {
                Label("下载原图", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appProminent(tint: .appDoc))
            .controlSize(.large)
            .frame(maxWidth: 520)

            Button {
                onReportIssue?()
            } label: {
                Label("反馈问题", systemImage: "exclamationmark.bubble")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: 520)

            if shouldShowTechnicalDetails {
                DisclosureGroup("技术信息") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(diagnostics.entries.prefix(8).enumerated()), id: \.offset) { _, entry in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(entry.code)：\(entry.message)")
                                        .font(.caption.weight(.semibold))
                                    let detail = entry.detail ?? ""
                                    if !detail.isEmpty {
                                        Text(detail)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } icon: {
                                Image(systemName: icon(for: entry.severity))
                                    .foregroundStyle(color(for: entry.severity))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: 560, alignment: .leading)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func icon(for severity: SiteKeeperCADKernel.CADDrawingDiagnostics.Severity) -> String {
        switch severity {
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .error:
            return "xmark.octagon"
        case .blocker:
            return "hand.raised"
        }
    }

    private func color(for severity: SiteKeeperCADKernel.CADDrawingDiagnostics.Severity) -> Color {
        switch severity {
        case .info:
            return .appDoc
        case .warning:
            return .appWarning
        case .error, .blocker:
            return .appRisk
        }
    }
}

enum SiteKeeperCADKernelDiagnosticReporter {
    static func makeReport(for fileURL: URL) async -> String {
        let engine = SiteKeeperCADKernel.SiteKeeperCADViewerEngine()
        let result: SiteKeeperCADKernel.CADOpenResult
        do {
            result = try await engine.open(file: SiteKeeperCADKernel.CADFile(url: fileURL))
        } catch {
            let diagnostics = SiteKeeperCADKernel.CADDrawingDiagnostics(entries: [
                SiteKeeperCADKernel.CADDrawingDiagnostics.Entry(
                    severity: .error,
                    code: "CAD_APP_KERNEL_DIAGNOSTIC_FAILED",
                    message: error.localizedDescription,
                    detail: fileURL.lastPathComponent
                )
            ])
            return report(fileURL: fileURL, status: "failed", diagnostics: diagnostics)
        }
        return report(
            fileURL: fileURL,
            status: result.status.rawValue,
            diagnostics: result.diagnostics
        )
    }

    private static func report(
        fileURL: URL,
        status: String,
        diagnostics: SiteKeeperCADKernel.CADDrawingDiagnostics
    ) -> String {
        var lines: [String] = []
        lines.append("# CAD Diagnostics")
        lines.append("")
        lines.append("- Kernel: SiteKeeperCADKernel")
        lines.append("- Renderer input: CADDatabase / CADRenderCommand")
        lines.append("- File: \(fileURL.lastPathComponent)")
        lines.append("- Status: \(status)")
        lines.append("")
        lines.append("## Diagnostics")
        if diagnostics.entries.isEmpty {
            lines.append("- none")
        } else {
            diagnostics.entries.forEach { entry in
                let detail = (entry.detail ?? "").isEmpty ? "" : " - \(entry.detail ?? "")"
                lines.append("- [\(entry.severity.rawValue)] \(entry.code): \(entry.message)\(detail)")
            }
        }
        return lines.joined(separator: "\n")
    }
}

private extension SiteKeeperCADKernel.CADDrawingDiagnostics {
    var detailLines: [String] {
        entries.map { entry in
            (entry.detail ?? "").isEmpty
                ? "\(entry.code)：\(entry.message)"
                : "\(entry.code)：\(entry.message)（\(entry.detail ?? "")）"
        }
    }

    func summary(defaultMessage: String) -> String {
        if entries.contains(where: { $0.code == "CAD_DWG_DIAGNOSTIC_ONLY" || $0.code == "CAD_DWG_IMPORT_ENGINE_CONNECTED" }) {
            return defaultMessage
        }
        guard let first = entries.first else { return defaultMessage }
        if first.message == "CAD engine is not installed" {
            return defaultMessage
        }
        let detail = first.detail ?? ""
        if detail.isEmpty {
            return first.message
        }
        return "\(first.message)：\(detail)"
    }
}

private extension SiteKeeperCADKernel.CADBounds {
    init(_ rect: CGRect) {
        self.init(
            minX: Double(rect.minX),
            minY: Double(rect.minY),
            maxX: Double(rect.maxX),
            maxY: Double(rect.maxY)
        )
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        guard places > 0 else { return rounded() }
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
