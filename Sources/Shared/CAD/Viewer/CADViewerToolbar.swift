import SwiftUI

struct CADViewerToolbar: View {
    let fileURL: URL
    let displayName: String
    let layers: [CADPoC.CADLayer]
    let visibleLayerIDs: Set<String>?
    let onToggleLayer: (String) -> Void
    let onShowAllLayers: () -> Void
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

            layerMenu
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
                layerMenu
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
}
