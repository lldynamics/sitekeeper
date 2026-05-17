import SwiftUI

struct CADViewerToolbar: View {
    let fileURL: URL
    let displayName: String
    let layouts: [CADPoC.CADLayout]
    let currentLayoutID: String?
    let layers: [CADPoC.CADLayer]
    let visibleLayerIDs: Set<String>?
    let supportsTextSearch: Bool
    let searchResultCount: Int
    let rendersTextOverlays: Bool
    let rendersLineTypes: Bool
    let rendersLineWeights: Bool
    let rendersDimensionDetails: Bool
    let buildsTextSearchIndex: Bool
    let publishesSnapPoints: Bool
    let publishesSnapIntersections: Bool
    let rendersHatchBoundaries: Bool
    let rendersHatches: Bool
    let rendersPlaceholders: Bool
    let showsOverviewMap: Bool
    let showsRendererDiagnostics: Bool
    let onSelectLayout: (String) -> Void
    let onToggleLayer: (String) -> Void
    let onShowAllLayers: () -> Void
    let onSearchTapped: () -> Void
    let onToggleTextOverlays: () -> Void
    let onToggleLineTypes: () -> Void
    let onToggleLineWeights: () -> Void
    let onToggleDimensionDetails: () -> Void
    let onToggleTextSearchIndex: () -> Void
    let onToggleSnapPoints: () -> Void
    let onToggleSnapIntersections: () -> Void
    let onToggleHatchBoundaries: () -> Void
    let onToggleHatches: () -> Void
    let onTogglePlaceholders: () -> Void
    let onToggleOverviewMap: () -> Void
    let onToggleRendererDiagnostics: () -> Void
    let onClose: () -> Void
    let onReportIssue: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            regularLayout
            compactLayout
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private var regularLayout: some View {
        HStack(spacing: 10) {
            title

            Spacer(minLength: 8)

            layoutMenu
            layerMenu
            performanceMenu
            searchButton
            downloadButton
            reportButton
            closeButton
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                title
                Spacer(minLength: 8)
                closeButton
            }

            HStack(spacing: 8) {
                layoutMenu
                layerMenu
                performanceMenu
                searchButton
                downloadButton
                reportButton
            }
        }
    }

    private var title: some View {
        Text(displayName)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    @ViewBuilder
    private var layoutMenu: some View {
        if !layouts.isEmpty {
            Menu {
                ForEach(layouts) { layout in
                    Button {
                        onSelectLayout(layout.id)
                    } label: {
                        Label(
                            layoutDisplayName(layout),
                            systemImage: layout.id == currentLayoutID ? "checkmark.circle.fill" : layoutIcon(layout)
                        )
                    }
                }
            } label: {
                Label(currentLayoutLabel, systemImage: currentLayoutIcon)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityLabel("选择模型或布局")
        }
    }

    @ViewBuilder
    private var layerMenu: some View {
        if !layers.isEmpty {
            Menu {
                Button(action: onShowAllLayers) {
                    Label("显示全部图层", systemImage: "eye")
                }

                Divider()

                ForEach(layers) { layer in
                    Button {
                        onToggleLayer(layer.id)
                    } label: {
                        Label(layer.name, systemImage: isLayerVisible(layer) ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                Label("图层", systemImage: "square.3.layers.3d")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    @ViewBuilder
    private var performanceMenu: some View {
        Menu {
            Button(action: onToggleTextOverlays) {
                Label("文字显示", systemImage: rendersTextOverlays ? "checkmark.circle.fill" : "circle")
            }
            Button(action: onToggleTextSearchIndex) {
                Label("文字搜索索引", systemImage: buildsTextSearchIndex ? "checkmark.circle.fill" : "circle")
            }
            Button(action: onToggleLineTypes) {
                Label("虚线/点划线", systemImage: rendersLineTypes ? "checkmark.circle.fill" : "circle")
            }
            Button(action: onToggleLineWeights) {
                Label("线宽", systemImage: rendersLineWeights ? "checkmark.circle.fill" : "circle")
            }
            Button(action: onToggleDimensionDetails) {
                Label("标注箭头", systemImage: rendersDimensionDetails ? "checkmark.circle.fill" : "circle")
            }
            Button(action: onToggleSnapPoints) {
                Label("吸附点", systemImage: publishesSnapPoints ? "checkmark.circle.fill" : "circle")
            }
            Button(action: onToggleSnapIntersections) {
                Label("交点吸附", systemImage: publishesSnapIntersections ? "checkmark.circle.fill" : "circle")
            }
            .disabled(!publishesSnapPoints)
            Button(action: onToggleHatchBoundaries) {
                Label("填充细节", systemImage: rendersHatchBoundaries ? "checkmark.circle.fill" : "circle")
            }
            Button(action: onToggleHatches) {
                Label("填充实体", systemImage: rendersHatches ? "checkmark.circle.fill" : "circle")
            }
            Button(action: onTogglePlaceholders) {
                Label("占位对象", systemImage: rendersPlaceholders ? "checkmark.circle.fill" : "circle")
            }
            Button(action: onToggleOverviewMap) {
                Label("全局小窗", systemImage: showsOverviewMap ? "checkmark.circle.fill" : "circle")
            }
            Divider()
            Button(action: onToggleRendererDiagnostics) {
                Label("渲染诊断", systemImage: showsRendererDiagnostics ? "checkmark.circle.fill" : "circle")
            }
        } label: {
            Label(performanceMenuLabel, systemImage: "speedometer")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(performanceOptionEnabledCount > 0 ? .appPrimaryAction : .secondary)
        .accessibilityLabel("CAD 性能和显示开关")
    }

    private var performanceOptionEnabledCount: Int {
        [
            rendersTextOverlays,
            rendersLineTypes,
            rendersLineWeights,
            rendersDimensionDetails,
            buildsTextSearchIndex,
            publishesSnapPoints,
            publishesSnapIntersections,
            rendersHatchBoundaries,
            rendersHatches,
            rendersPlaceholders,
            showsOverviewMap,
            showsRendererDiagnostics
        ].filter { $0 }.count
    }

    private var performanceMenuLabel: String {
        performanceOptionEnabledCount == 0 ? "性能优先" : "细节 \(performanceOptionEnabledCount)"
    }

    @ViewBuilder
    private var searchButton: some View {
        if supportsTextSearch {
            Button(action: onSearchTapped) {
                if searchResultCount > 0 {
                    Label("搜索 \(searchResultCount)", systemImage: "magnifyingglass")
                } else {
                    Label("搜索", systemImage: "magnifyingglass")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .accessibilityLabel("搜索图纸文字")
        }
    }

    private var downloadButton: some View {
        ShareLink(item: fileURL) {
            Label("下载原图", systemImage: "square.and.arrow.down")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
    }

    private var reportButton: some View {
        Button(action: onReportIssue) {
            Label("反馈问题", systemImage: "exclamationmark.bubble")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Label("关闭", systemImage: "xmark")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityLabel("关闭")
    }

    private func isLayerVisible(_ layer: CADPoC.CADLayer) -> Bool {
        visibleLayerIDs?.contains(layer.id) ?? layer.isVisible
    }

    private var currentLayout: CADPoC.CADLayout? {
        layouts.first { $0.id == currentLayoutID } ?? layouts.first(where: \.isModelSpace) ?? layouts.first
    }

    private var currentLayoutLabel: String {
        guard let layout = currentLayout else { return "模型/布局" }
        return layout.isModelSpace ? "模型" : layoutDisplayName(layout)
    }

    private var currentLayoutIcon: String {
        currentLayout.map(layoutIcon) ?? "rectangle.3.group"
    }

    private func layoutIcon(_ layout: CADPoC.CADLayout) -> String {
        layout.isModelSpace ? "cube.transparent" : "rectangle.on.rectangle"
    }

    private func layoutDisplayName(_ layout: CADPoC.CADLayout) -> String {
        let trimmed = layout.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if layout.isModelSpace {
            return "模型"
        }
        return trimmed.isEmpty ? layout.id : trimmed
    }
}
