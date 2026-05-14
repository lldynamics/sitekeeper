import CoreGraphics
import Foundation
import SwiftUI

struct DXFCanvasToolbar: View {
    @Binding var searchText: String
    @Binding var showCoordinateLegend: Bool

    let effectiveScale: CGFloat
    let layerStats: [DXFLayerStat]
    let primaryLayerStats: [DXFLayerStat]
    let visibleLayers: Set<String>
    let lockedLayers: Set<String>
    let matchedTexts: [DXFPreviewModel.TextEntity]
    let selectedSearchTextID: UUID?
    let probeSourcePoint: CGPoint?

    let onFitAll: () -> Void
    let onShowLayers: () -> Void
    let onCoordinateToggle: () -> Void
    let onZoomOut: () -> Void
    let onZoomIn: () -> Void
    let onCollapse: () -> Void
    let onShowSearchResults: () -> Void
    let onCenterSelectedText: () -> Void
    let onMoveSearchSelection: (Int) -> Void
    let onToggleLayer: (String) -> Void
    let onToggleLayerLock: (String) -> Void
    let onIsolateLayer: (String) -> Void
    let onFocusLayer: (String) -> Void
    let onSelectText: (DXFPreviewModel.TextEntity) -> Void

    var body: some View {
        VStack(spacing: 8) {
            primaryActions

            if layerStats.count > 1 {
                layerQuickStrip
            }

            searchBar

            if !matchedTexts.isEmpty {
                searchPreviewStrip
            }

            statusLine
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var primaryActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    onFitAll()
                } label: {
                    Label("适应全图", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onShowLayers()
                } label: {
                    Label("图层开关", systemImage: "square.3.layers.3d")
                }
                .buttonStyle(.bordered)

                Button {
                    showCoordinateLegend.toggle()
                    onCoordinateToggle()
                } label: {
                    Label(showCoordinateLegend ? "隐藏坐标" : "显示坐标", systemImage: "scope")
                }
                .buttonStyle(.bordered)

                Button {
                    onZoomOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.bordered)

                Button {
                    onZoomIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)

                Text(String(format: "缩放 %.1fx", effectiveScale))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                Button {
                    onCollapse()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("收起看图工具")
            }
        }
    }

    private var layerQuickStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(primaryLayerStats) { layer in
                    layerQuickMenu(for: layer)
                }

                if layerStats.count > primaryLayerStats.count {
                    Button {
                        onShowLayers()
                    } label: {
                        Label("+\(layerStats.count - primaryLayerStats.count)", systemImage: "ellipsis")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func layerQuickMenu(for layer: DXFLayerStat) -> some View {
        let isVisible = visibleLayers.contains(layer.name)
        let isLocked = lockedLayers.contains(layer.name)
        return Menu {
            Button(isVisible ? "隐藏该层" : "显示该层") {
                onToggleLayer(layer.name)
            }
            .disabled(isLocked)
            Button("只看该层") {
                onIsolateLayer(layer.name)
            }
            .disabled(isLocked)
            Button("定位该层") {
                onFocusLayer(layer.name)
            }
            Button(isLocked ? "解锁该层" : "锁定该层") {
                onToggleLayerLock(layer.name)
            }
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(DXFCanvasRenderer.color(from: 0, layer: layer.name))
                    .frame(width: 7, height: 7)
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(layer.name)
                    .lineLimit(1)
                Text("\(layer.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(isVisible ? .primary : .secondary)
        }
        .buttonStyle(.bordered)
        .tint(isVisible ? Color.accentColor : .secondary)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索图纸文字", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            if !matchedTexts.isEmpty {
                Button {
                    onShowSearchResults()
                } label: {
                    Label("结果", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.bordered)

                Button {
                    onCenterSelectedText()
                } label: {
                    Label("定位", systemImage: "scope")
                }
                .buttonStyle(.borderedProminent)

                Button { onMoveSearchSelection(-1) } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.bordered)

                Button { onMoveSearchSelection(1) } label: {
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
    }

    private var searchPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(matchedTexts.prefix(8))) { text in
                    searchPreviewChip(for: text)
                }
                if matchedTexts.count > 8 {
                    Button {
                        onShowSearchResults()
                    } label: {
                        Label("+\(matchedTexts.count - 8)", systemImage: "list.bullet.rectangle")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func searchPreviewChip(for text: DXFPreviewModel.TextEntity) -> some View {
        let isSelected = selectedSearchTextID == text.id
        return Button {
            onSelectText(text)
        } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(text.value)
                        .lineLimit(1)
                        .font(.caption.weight(.semibold))
                    Text("\(text.layer) · \(text.kind.rawValue)")
                        .lineLimit(1)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
                }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color(uiColor: .tertiarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            if let probeSourcePoint {
                Text("点位 X:\(DXFCanvasRenderer.formatCoordinate(probeSourcePoint.x)) Y:\(DXFCanvasRenderer.formatCoordinate(probeSourcePoint.y))")
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

    private var searchProgressText: String {
        guard !matchedTexts.isEmpty else { return "0/0" }
        let ids = matchedTexts.map(\.id)
        guard let selectedSearchTextID,
              let index = ids.firstIndex(of: selectedSearchTextID) else {
            return "1/\(ids.count)"
        }
        return "\(index + 1)/\(ids.count)"
    }
}
