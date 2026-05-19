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
        NativeCADViewerEntry(
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

struct NativeCADViewerEntry: View {
    let fileURL: URL
    let displayName: String
    let textImportOptions: CADCanvasTextImportOptions
    let showsToolbar: Bool
    let initialViewState: CADRendererViewState?
    let callbacks: CADRendererCallbacks
    let externalCurrentLayoutID: String?
    let externalVisibleLayerIDs: Set<String>?
    let onLayoutsChangedExternal: ([NativeCAD.CADLayout]) -> Void
    let onCurrentLayoutIDChangedExternal: (String?) -> Void
    let onLayersChangedExternal: ([NativeCAD.CADLayer]) -> Void
    let onVisibleLayerIDsChangedExternal: (Set<String>?) -> Void
    let onClose: () -> Void
    let onReportIssue: () -> Void
    @State private var layers: [NativeCAD.CADLayer] = []
    @State private var layouts: [NativeCAD.CADLayout] = []
    @State private var currentLayoutID: String?
    @State private var visibleLayerIDs: Set<String>?
    @State private var canvasControlCommand: CADCanvasControlCommand?
    @State private var rendererViewState: CADRendererViewState?
    @State private var canvasTransform: CADRendererCanvasTransform?
    @State private var textSearchIndex: SiteKeeperCADKernel.CADTextSearchIndex?
    @State private var searchText = ""
    @State private var searchResults: [SiteKeeperCADKernel.CADTextSearchResult] = []
    @State private var selectedSearchResultIndex: Int?
    @State private var showsSearchPanel = false
    @State private var rendererPerformance: CADRendererPerformanceSnapshot?
    @State private var importState = CADCanvasImportState.idle
    @State private var importCancelCommand: CADCanvasImportCancelCommand?
    @AppStorage("cad.native.showsOverviewMap") private var showsOverviewMap = false
    @AppStorage("cad.native.rendersTextOverlays") private var rendersTextOverlays = true
    @AppStorage("cad.native.rendersLineTypes") private var rendersLineTypes = false
    @AppStorage("cad.native.rendersLineWeights") private var rendersLineWeights = false
    @AppStorage("cad.native.rendersDimensionDetails") private var rendersDimensionDetails = false
    @AppStorage("cad.native.buildsTextSearchIndex") private var buildsTextSearchIndex = false
    @AppStorage("cad.native.publishesSnapPoints") private var publishesSnapPoints = false
    @AppStorage("cad.native.publishesSnapIntersections") private var publishesSnapIntersections = false
    @AppStorage("cad.native.rendersHatchBoundaries") private var rendersHatchBoundaries = false
    @AppStorage("cad.native.rendersHatches") private var rendersHatches = false
    @AppStorage("cad.native.rendersPlaceholders") private var rendersPlaceholders = false
    @AppStorage("cad.native.showsRendererDiagnostics") private var showsRendererDiagnostics = false
    @AppStorage("cad.native.featureDefaultsVersion") private var featureDefaultsVersion = 0
    @AppStorage("cad.native.textDisplayFont") private var textDisplayFontRaw = CADDrawingTextDisplayFont.auto.rawValue
    @AppStorage("cad.native.importedTextFontName") private var importedTextFontName = ""
    @AppStorage("cad.native.importedTextFontPath") private var importedTextFontPath = ""

    init(
        fileURL: URL,
        displayName: String,
        textImportOptions: CADCanvasTextImportOptions = .automatic,
        showsToolbar: Bool = true,
        initialViewState: CADRendererViewState? = nil,
        callbacks: CADRendererCallbacks = CADRendererCallbacks(),
        externalCurrentLayoutID: String? = nil,
        externalVisibleLayerIDs: Set<String>? = nil,
        onLayoutsChangedExternal: @escaping ([NativeCAD.CADLayout]) -> Void = { _ in },
        onCurrentLayoutIDChangedExternal: @escaping (String?) -> Void = { _ in },
        onLayersChangedExternal: @escaping ([NativeCAD.CADLayer]) -> Void = { _ in },
        onVisibleLayerIDsChangedExternal: @escaping (Set<String>?) -> Void = { _ in },
        onClose: @escaping () -> Void,
        onReportIssue: @escaping () -> Void
    ) {
        self.fileURL = fileURL
        self.displayName = displayName
        self.textImportOptions = textImportOptions
        self.showsToolbar = showsToolbar
        self.initialViewState = initialViewState
        self.callbacks = callbacks
        self.externalCurrentLayoutID = externalCurrentLayoutID
        self.externalVisibleLayerIDs = externalVisibleLayerIDs
        self.onLayoutsChangedExternal = onLayoutsChangedExternal
        self.onCurrentLayoutIDChangedExternal = onCurrentLayoutIDChangedExternal
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
                    layouts: layouts,
                    currentLayoutID: effectiveCurrentLayoutID,
                    layers: layers,
                    visibleLayerIDs: effectiveVisibleLayerIDs,
                    supportsTextSearch: buildsTextSearchIndex,
                    searchResultCount: searchResults.count,
                    rendersTextOverlays: rendersTextOverlays,
                    rendersLineTypes: rendersLineTypes,
                    rendersLineWeights: rendersLineWeights,
                    rendersDimensionDetails: rendersDimensionDetails,
                    buildsTextSearchIndex: buildsTextSearchIndex,
                    publishesSnapPoints: publishesSnapPoints,
                    publishesSnapIntersections: publishesSnapIntersections,
                    rendersHatchBoundaries: rendersHatchBoundaries,
                    rendersHatches: rendersHatches,
                    rendersPlaceholders: rendersPlaceholders,
                    showsOverviewMap: showsOverviewMap,
                    showsRendererDiagnostics: showsRendererDiagnostics,
                    onSelectLayout: selectLayout,
                    onToggleLayer: toggleLayer,
                    onShowAllLayers: showAllLayers,
                    onSearchTapped: toggleSearchPanel,
                    onToggleTextOverlays: { rendersTextOverlays.toggle() },
                    onToggleLineTypes: { rendersLineTypes.toggle() },
                    onToggleLineWeights: { rendersLineWeights.toggle() },
                    onToggleDimensionDetails: { rendersDimensionDetails.toggle() },
                    onToggleTextSearchIndex: { buildsTextSearchIndex.toggle() },
                    onToggleSnapPoints: { publishesSnapPoints.toggle() },
                    onToggleSnapIntersections: { publishesSnapIntersections.toggle() },
                    onToggleHatchBoundaries: { rendersHatchBoundaries.toggle() },
                    onToggleHatches: { rendersHatches.toggle() },
                    onTogglePlaceholders: { rendersPlaceholders.toggle() },
                    onToggleOverviewMap: { showsOverviewMap.toggle() },
                    onToggleRendererDiagnostics: { showsRendererDiagnostics.toggle() },
                    onClose: onClose,
                    onReportIssue: onReportIssue
                )
            }

            canvasLayer
        }
        .background(Color(.systemBackground))
        .onAppear {
            migrateNativeCADFeatureDefaultsIfNeeded()
        }
    }

    private var canvasLayer: some View {
        CADCanvasView(
            fileURL: fileURL,
            selectedLayoutID: effectiveCurrentLayoutID,
            visibleLayerIDs: effectiveVisibleLayerIDs,
            initialViewState: initialViewState,
            controlCommand: canvasControlCommand,
            cancelImportCommand: importCancelCommand,
            featureOptions: featureOptions,
            textImportOptions: effectiveTextImportOptions,
            buildsTextSearchIndex: buildsTextSearchIndex,
            debugTextOverlays: showsRendererDiagnostics && rendersTextOverlays,
            callbacks: bridgedRendererCallbacks,
            onLayoutsChanged: handleLayoutsChanged,
            onLayersChanged: handleLayersChanged,
            onSearchIndexChanged: handleSearchIndexChanged,
            onImportStateChanged: handleImportStateChanged
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if showsSearchPanel {
                searchPanel
                    .padding(12)
            }
        }
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
        .overlay(alignment: .bottomLeading) {
            if Self.shouldShowRendererDiagnostics(
                enabled: showsRendererDiagnostics,
                sample: rendererPerformance
            ),
               let rendererPerformance {
                rendererDiagnosticBadge(rendererPerformance)
                    .padding(12)
            }
        }
        .overlay {
            if importState.phase == .importing || importState.phase == .failed {
                cadImportStateOverlay(importState)
            }
        }
    }

    private func handleImportStateChanged(_ state: CADCanvasImportState) {
        DispatchQueue.main.async {
            importState = state
        }
    }

    @ViewBuilder
    private func cadImportStateOverlay(_ state: CADCanvasImportState) -> some View {
        VStack(spacing: 10) {
            switch state.phase {
            case .importing:
                ProgressView()
                    .controlSize(.large)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(.orange)
            case .idle, .completed, .cancelled:
                EmptyView()
            }
            VStack(spacing: 3) {
                Text(state.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                if !state.fileName.isEmpty {
                    Text(state.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }
            }
            if state.isCancellable {
                Button(role: .destructive) {
                    importCancelCommand = CADCanvasImportCancelCommand()
                } label: {
                    Label(String(localized: "取消导入"), systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
            if state.phase == .failed {
                HStack(spacing: 8) {
                    Button {
                        onReportIssue()
                    } label: {
                        Label(String(localized: "导出诊断"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        importState = .idle
                    } label: {
                        Label(String(localized: "关闭"), systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }
                .font(.caption)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        }
    }

    static func shouldShowRendererDiagnostics(
        enabled: Bool,
        sample: CADRendererPerformanceSnapshot?
    ) -> Bool {
        enabled && sample != nil
    }

    private var featureOptions: CADCanvasFeatureOptions {
        CADCanvasFeatureOptions(
            rendersTextOverlays: rendersTextOverlays,
            rendersLineTypes: rendersLineTypes,
            rendersLineWeights: rendersLineWeights,
            rendersDimensionDetails: rendersDimensionDetails,
            publishesSnapPoints: publishesSnapPoints,
            publishesSnapIntersections: publishesSnapIntersections,
            rendersHatchBoundaries: rendersHatchBoundaries,
            rendersHatches: rendersHatches,
            rendersPlaceholders: rendersPlaceholders
        )
    }

    private var effectiveTextImportOptions: CADCanvasTextImportOptions {
        var options = textImportOptions
        let choice = CADDrawingTextDisplayFont(rawValue: textDisplayFontRaw) ?? .auto
        options.preferredDisplayFontName = CADImportedFontRegistry.resolvedDisplayFontName(
            for: choice,
            importedFontName: importedTextFontName,
            importedFontPath: importedTextFontPath
        )
        return options
    }

    private var bridgedRendererCallbacks: CADRendererCallbacks {
        var next = callbacks
        next.onOpenTraceChange = { trace in
            callbacks.onOpenTraceChange(trace)
        }
        next.onPerformanceSample = { sample in
            callbacks.onPerformanceSample(sample)
            DispatchQueue.main.async {
                if rendererPerformance != sample {
                    rendererPerformance = sample
                }
            }
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

    private func rendererDiagnosticBadge(_ sample: CADRendererPerformanceSnapshot) -> some View {
        let isFailure = sample.hasActionableRendererFailure
        let tint: Color = isFailure ? .orange : .green

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(tint)
                Text("渲染诊断：\(sample.rendererDiagnosticSummary)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            if isFailure {
                Text(sample.rendererFailureReason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            ForEach(Self.rendererDiagnosticRows(for: sample), id: \.self) { row in
                Text(row)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: 420, maxHeight: 156, alignment: .topLeading)
        .clipped()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(isFailure ? 0.4 : 0.3), lineWidth: 1)
        }
    }

    static func rendererDiagnosticRows(for sample: CADRendererPerformanceSnapshot) -> [String] {
        var rows = [
            "entity \(sample.totalEntityCount) / viewport \(sample.visibleEntityCount) / command \(sample.renderCommandCount) / draw \(sample.drawCallCount)",
            "layer \(sample.visibleLayerCount)/\(sample.totalLayerCount) / text \(sample.textOverlayCount)/\(sample.visibleTextEntityCount) / ms \(Self.formatMilliseconds(sample.frameTimeMilliseconds))"
        ]
        if let overlayRow = sample.textDiagnosticRows.first(where: { row in
            row.localizedCaseInsensitiveContains("ui text overlay")
        }) {
            rows.append(overlayRow)
        }
        if let textPreviewRow = sample.textDiagnosticRows.first(where: { row in
            row.localizedCaseInsensitiveContains("view text")
        }) {
            rows.append(textPreviewRow)
        }
        if let mleaderTextRow = sample.textDiagnosticRows.first(where: { row in
            row.localizedCaseInsensitiveContains("mleader text")
        }) {
            rows.append(mleaderTextRow)
        }
        if let customTextRow = sample.textDiagnosticRows.first(where: { row in
            row.localizedCaseInsensitiveContains("custom text")
        }) {
            rows.append(customTextRow)
        }
        if let proxyTextRow = sample.textDiagnosticRows.first(where: { row in
            row.localizedCaseInsensitiveContains("proxy text")
        }) {
            rows.append(proxyTextRow)
        }
        if sample.totalTextEntityCount > 0, sample.visibleTextEntityCount == 0 {
            rows.append(
                "text import \(sample.totalTextEntityCount) / index \(sample.indexedTextEntityCount) / inView \(sample.viewportTextEntityCountBeforeLayerFilter)/0"
            )
            if let distance = sample.nearestTextDistance {
                let preview = Self.compactTextPreview(sample.nearestTextPreview)
                let layer = sample.nearestTextLayerID.map { " / layer \($0)" } ?? ""
                rows.append("nearest text d \(Self.formatCADNumber(distance))\(layer) \(preview)")
            }
            let annotationRow = sample.textDiagnosticRows.first { row in
                row.localizedCaseInsensitiveContains("-BZ")
            }
            let geometryRow = sample.textDiagnosticRows.first { row in
                row.localizedCaseInsensitiveContains("view kinds")
                    || row.localizedCaseInsensitiveContains("view leader")
            }
            if let annotationRow {
                rows.append(annotationRow)
            }
            if let geometryRow, geometryRow != annotationRow {
                rows.append(geometryRow)
            }
            return Array(rows.prefix(7))
        }

        guard sample.hasActionableRendererFailure else {
            return Array(rows.prefix(5))
        }

        if let distance = sample.nearestTextDistance, sample.visibleTextEntityCount > 0 {
            let preview = Self.compactTextPreview(sample.nearestTextPreview)
            let layer = sample.nearestTextLayerID.map { " / layer \($0)" } ?? ""
            rows.append("nearest text d \(Self.formatCADNumber(distance))\(layer) \(preview)")
        }
        rows.append(contentsOf: sample.textDiagnosticRows.prefix(2))
        return Array(rows.prefix(5))
    }

    private static func formatMilliseconds(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        if value >= 100 {
            return "\(Int(value.rounded()))"
        }
        return String(format: "%.1f", value)
    }

    private static func formatCADRect(_ rect: CGRect) -> String {
        "x \(formatCADNumber(rect.minX))...\(formatCADNumber(rect.maxX)) y \(formatCADNumber(rect.minY))...\(formatCADNumber(rect.maxY))"
    }

    private static func formatCADNumber(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        let magnitude = abs(value)
        if magnitude >= 10_000 || (magnitude > 0 && magnitude < 0.01) {
            return String(format: "%.2e", value)
        }
        if magnitude >= 100 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    private static func compactTextPreview(_ preview: String?) -> String {
        guard let preview, !preview.isEmpty else { return "" }
        let collapsed = preview
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return "" }
        return String(collapsed.prefix(12))
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

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("搜索图纸文字", text: $searchText)
                    .textFieldStyle(.plain)
                    .submitLabel(.search)
                    .onSubmit {
                        executeTextSearch()
                    }
                    .onChange(of: searchText) { _, _ in
                        refreshSearchResults()
                    }

                Button {
                    executeTextSearch()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    clearTextSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("清除搜索")
            }

            searchStatusRow

            if !searchResults.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(searchResults.prefix(8).enumerated()), id: \.element.id) { index, result in
                            Button {
                                focusSearchResult(at: index)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: selectedSearchResultIndex == index ? "scope" : "text.magnifyingglass")
                                        .foregroundStyle(selectedSearchResultIndex == index ? Color.appPrimaryAction : .secondary)
                                    Text(result.previewText)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 168)
            }
        }
        .padding(10)
        .frame(width: 320)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }

    @ViewBuilder
    private var searchStatusRow: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if textSearchIndex == nil {
            Text("正在读取文字索引")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if trimmed.isEmpty {
            Text("输入文字后按回车定位")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if searchResults.isEmpty {
            Text("未找到匹配文字")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                Text(searchResultPositionLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    focusAdjacentSearchResult(step: -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .disabled(searchResults.count <= 1)
                Button {
                    focusAdjacentSearchResult(step: 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .disabled(searchResults.count <= 1)
            }
        }
    }

    private var searchResultPositionLabel: String {
        let current = (selectedSearchResultIndex ?? 0) + 1
        return "\(current)/\(searchResults.count)"
    }

    private var effectiveVisibleLayerIDs: Set<String>? {
        Self.reconciledVisibleLayerIDs(
            requested: externalVisibleLayerIDs ?? visibleLayerIDs,
            importedLayers: layers
        )
    }

    private var effectiveCurrentLayoutID: String? {
        guard !layouts.isEmpty else { return currentLayoutID }
        if let externalCurrentLayoutID, layouts.contains(where: { $0.id == externalCurrentLayoutID }) {
            return externalCurrentLayoutID
        }
        if let currentLayoutID, layouts.contains(where: { $0.id == currentLayoutID }) {
            return currentLayoutID
        }
        return Self.defaultLayoutID(layouts)
    }

    private func handleLayoutsChanged(_ importedLayouts: [NativeCAD.CADLayout]) {
        layouts = importedLayouts
        onLayoutsChangedExternal(importedLayouts)
        let requestedLayoutID = externalCurrentLayoutID ?? currentLayoutID
        let nextLayoutID: String?
        if let requestedLayoutID, importedLayouts.contains(where: { $0.id == requestedLayoutID }) {
            nextLayoutID = requestedLayoutID
        } else {
            nextLayoutID = Self.defaultLayoutID(importedLayouts)
        }
        if currentLayoutID != nextLayoutID {
            currentLayoutID = nextLayoutID
        }
        if externalCurrentLayoutID != nextLayoutID {
            onCurrentLayoutIDChangedExternal(nextLayoutID)
        }
        refreshSearchResults()
    }

    private func handleLayersChanged(_ importedLayers: [NativeCAD.CADLayer]) {
        layers = importedLayers
        onLayersChangedExternal(importedLayers)
        let requested = externalVisibleLayerIDs ?? visibleLayerIDs
        let nextVisible = requested.map {
            Self.reconciledVisibleLayerIDs(requested: $0, importedLayers: importedLayers) ?? $0
        } ?? Self.defaultVisibleLayerIDs(importedLayers)
        if nextVisible != externalVisibleLayerIDs || nextVisible != visibleLayerIDs {
            visibleLayerIDs = nextVisible
            onVisibleLayerIDsChangedExternal(nextVisible)
        }
    }

    private func handleSearchIndexChanged(_ index: SiteKeeperCADKernel.CADTextSearchIndex?) {
        textSearchIndex = index
        refreshSearchResults()
    }

    private func toggleSearchPanel() {
        withAnimation(.easeInOut(duration: 0.16)) {
            showsSearchPanel.toggle()
        }
        if showsSearchPanel, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            executeTextSearch()
        }
    }

    private func refreshSearchResults() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let textSearchIndex else {
            searchResults = []
            selectedSearchResultIndex = nil
            return
        }

        let layoutID = effectiveCurrentLayoutID
        searchResults = textSearchIndex.search(trimmed).filter {
            layoutID == nil || $0.layoutId == layoutID
        }
        if searchResults.isEmpty {
            selectedSearchResultIndex = nil
        } else if let selectedSearchResultIndex {
            self.selectedSearchResultIndex = min(selectedSearchResultIndex, searchResults.count - 1)
        } else {
            selectedSearchResultIndex = 0
        }
    }

    private func executeTextSearch() {
        refreshSearchResults()
        focusSearchResult(at: selectedSearchResultIndex ?? 0)
    }

    private func focusAdjacentSearchResult(step: Int) {
        guard !searchResults.isEmpty else { return }
        let current = selectedSearchResultIndex ?? 0
        let next = (current + step + searchResults.count) % searchResults.count
        focusSearchResult(at: next)
    }

    private func focusSearchResult(at index: Int) {
        guard searchResults.indices.contains(index) else { return }
        selectedSearchResultIndex = index
        let result = searchResults[index]
        sendCanvasCommand(
            .focusSearchResult(
                entityID: result.entityId,
                bounds: result.bounds,
                fallbackPoint: result.worldPoint
            )
        )
    }

    private func clearTextSearch() {
        searchText = ""
        searchResults = []
        selectedSearchResultIndex = nil
        sendCanvasCommand(.clearSearchHighlight)
    }

    static func reconciledVisibleLayerIDs(
        requested: Set<String>?,
        importedLayers: [NativeCAD.CADLayer]
    ) -> Set<String>? {
        guard let requested else { return nil }
        guard !importedLayers.isEmpty else { return requested }
        guard !requested.isEmpty else { return requested }

        let importedIDs = Set(importedLayers.map(\.id))
        let validRequestedIDs = requested.intersection(importedIDs)
        if !validRequestedIDs.isEmpty {
            return validRequestedIDs
        }

        let visibleImportedIDs = Set(importedLayers.filter(\.isVisible).map(\.id))
        return visibleImportedIDs.isEmpty ? importedIDs : visibleImportedIDs
    }

    static func defaultVisibleLayerIDs(_ importedLayers: [NativeCAD.CADLayer]) -> Set<String>? {
        guard !importedLayers.isEmpty else { return nil }
        let visibleImportedIDs = Set(importedLayers.filter(\.isVisible).map(\.id))
        return visibleImportedIDs.isEmpty ? Set(importedLayers.map(\.id)) : visibleImportedIDs
    }

    static func defaultLayoutID(_ importedLayouts: [NativeCAD.CADLayout]) -> String? {
        importedLayouts.first(where: \.isModelSpace)?.id ?? importedLayouts.first?.id
    }

    private func selectLayout(_ layoutID: String) {
        guard effectiveCurrentLayoutID != layoutID else { return }
        currentLayoutID = layoutID
        onCurrentLayoutIDChangedExternal(layoutID)
        selectedSearchResultIndex = nil
        sendCanvasCommand(.clearSearchHighlight)
        refreshSearchResults()
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

    private func migrateNativeCADFeatureDefaultsIfNeeded() {
        guard featureDefaultsVersion < 2 else { return }
        if featureDefaultsVersion < 1 {
            rendersTextOverlays = true
        }
        rendersHatchBoundaries = false
        publishesSnapIntersections = publishesSnapPoints && publishesSnapIntersections
        featureDefaultsVersion = 2
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
