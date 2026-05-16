import SwiftUI

struct CADKernelPreviewHost: View {
    let fileURL: URL
    let initialViewState: CADRendererViewState?
    let callbacks: CADRendererCallbacks

    @State private var loadState: CADKernelPreviewLoadState = .loading

    var body: some View {
        Group {
            switch loadState {
            case .loading:
                CADKernelLoadingView(fileName: fileURL.lastPathComponent)
            case let .loaded(document, diagnostics):
                if document.hasRenderableGeometry {
                    CADKernelVectorCanvas(
                        document: document,
                        initialViewState: initialViewState,
                        callbacks: callbacks
                    )
                } else {
                    CADKernelDiagnosticPreview(
                        fileURL: fileURL,
                        document: document,
                        diagnostics: diagnostics
                    )
                }
            }
        }
        .task(id: fileURL.path) {
            await loadDocument()
        }
    }

    @MainActor
    private func loadDocument() async {
        loadState = .loading
        let result = await CADKernelImportRegistry.importDocument(
            CADKernelImportRequest(fileURL: fileURL)
        )
        callbacks.onOpenQualityChange(result.openQualitySnapshot)
        callbacks.onPerformanceSample(
            CADRendererPerformanceSnapshot(
                entityCountInViewport: result.document.entities.count,
                drawCallCount: result.document.entities.count,
                frameTimeMilliseconds: 0,
                skippedEntityCount: result.document.entities.filter { $0.kind == .unsupported }.count,
                visibleLayerCount: result.document.visibleLayers.count,
                simplifiedMode: !result.document.hasRenderableGeometry
            )
        )
        loadState = .loaded(result.document, result.diagnostics)
    }
}

private enum CADKernelPreviewLoadState {
    case loading
    case loaded(CADKernelDocument, [CADKernelDiagnostic])
}

private struct CADKernelLoadingView: View {
    let fileName: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("正在读取 CAD 图纸")
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

private struct CADKernelDiagnosticPreview: View {
    let fileURL: URL
    let document: CADKernelDocument
    let diagnostics: [CADKernelDiagnostic]

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Color.appWarning)

            VStack(spacing: 6) {
                Text("CAD 内核已接管")
                    .font(.title3.weight(.semibold))
                Text("当前阶段旧 CAD 桥接链路已停用。诊断 ImportEngine 已接管入口；真实几何解析接入前，这里只显示文件诊断，不静默白屏或乱码。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                diagnosticRow("文件", value: document.metadata.sourceFileName)
                diagnosticRow("类型", value: document.metadata.sourceFormat.displayName)
                diagnosticRow("导入引擎", value: document.metadata.importerID)
                if let dwgVersion = document.metadata.dwgVersion {
                    diagnosticRow("DWG 版本", value: dwgVersion)
                }
            }
            .font(.caption)
            .padding(14)
            .frame(maxWidth: 520, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(diagnostics.prefix(4)) { diagnostic in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(diagnostic.message)
                                .font(.caption.weight(.semibold))
                            if !diagnostic.detail.isEmpty {
                                Text(diagnostic.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } icon: {
                        Image(systemName: icon(for: diagnostic.severity))
                            .foregroundStyle(color(for: diagnostic.severity))
                    }
                }
            }
            .frame(maxWidth: 520, alignment: .leading)

            ShareLink(item: fileURL) {
                Label("导出给其他 CAD 工具核对", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appProminent(tint: .appDoc))
            .controlSize(.large)
            .frame(maxWidth: 520)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func diagnosticRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }

    private func icon(for severity: CADKernelDiagnosticSeverity) -> String {
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

    private func color(for severity: CADKernelDiagnosticSeverity) -> Color {
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

private struct CADKernelVectorCanvas: View {
    let document: CADKernelDocument
    let initialViewState: CADRendererViewState?
    let callbacks: CADRendererCallbacks

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                render(document: document, context: &context, size: size)
            }
            .background(Color(uiColor: .systemBackground))
            .onAppear {
                let bounds = document.drawingBounds.isNull ? CGRect(origin: .zero, size: proxy.size) : document.drawingBounds
                callbacks.onCanvasTransformChange(
                    CADRendererCanvasTransform(
                        bounds: bounds,
                        size: proxy.size,
                        zoomScale: initialViewState?.zoomScale ?? 1,
                        panOffset: initialViewState?.panOffset ?? .zero
                    )
                )
            }
        }
    }

    private func render(document: CADKernelDocument, context: inout GraphicsContext, size: CGSize) {
        let visibleLayerIDs = Set(document.visibleLayers.map(\.id))
        let bounds = document.drawingBounds
        guard !bounds.isNull, !bounds.isEmpty else { return }

        let scale = min(size.width / max(bounds.width, 1), size.height / max(bounds.height, 1)) * 0.92
        let offset = CGSize(
            width: (size.width - bounds.width * scale) / 2 - bounds.minX * scale,
            height: (size.height - bounds.height * scale) / 2 + bounds.maxY * scale
        )

        for entity in document.entities where visibleLayerIDs.contains(entity.layerID) {
            let color = Color(rgb: entity.colorRGB ?? 0x2F80ED)
            var path = Path()
            switch entity.kind {
            case .line, .polyline:
                guard let first = entity.points.first else { continue }
                path.move(to: transform(first, scale: scale, offset: offset))
                for point in entity.points.dropFirst() {
                    path.addLine(to: transform(point, scale: scale, offset: offset))
                }
                context.stroke(path, with: .color(color), lineWidth: CGFloat(max(entity.lineWeight ?? 1, 1)))
            case .circle:
                guard let radius = entity.radius, let center = entity.points.first else { continue }
                let cgRadius = CGFloat(radius)
                let rect = CGRect(
                    x: center.x - cgRadius,
                    y: center.y - cgRadius,
                    width: cgRadius * 2,
                    height: cgRadius * 2
                )
                path.addEllipse(in: transform(rect, scale: scale, offset: offset))
                context.stroke(path, with: .color(color), lineWidth: CGFloat(max(entity.lineWeight ?? 1, 1)))
            case .text:
                guard let text = entity.text, let point = entity.points.first else { continue }
                var resolvedText = context.resolve(Text(text).font(.caption))
                resolvedText.shading = .color(color)
                context.draw(resolvedText, at: transform(point, scale: scale, offset: offset), anchor: .bottomLeading)
            case .arc, .hatch, .imageReference, .blockReference, .unsupported:
                continue
            }
        }
    }

    private func transform(_ point: CGPoint, scale: CGFloat, offset: CGSize) -> CGPoint {
        CGPoint(x: point.x * scale + offset.width, y: offset.height - point.y * scale)
    }

    private func transform(_ rect: CGRect, scale: CGFloat, offset: CGSize) -> CGRect {
        let origin = transform(CGPoint(x: rect.minX, y: rect.maxY), scale: scale, offset: offset)
        return CGRect(x: origin.x, y: origin.y, width: rect.width * scale, height: rect.height * scale)
    }
}

private extension CADKernelImportResult {
    var openQualitySnapshot: CADOpenQualitySnapshot {
        let severities = diagnostics.map(\.severity)
        let hasBlocker = severities.contains(.blocker)
        let hasError = severities.contains(.error)
        let hasGeometry = document.hasRenderableGeometry
        let level: String
        let title: String
        let summary: String

        if hasGeometry && !hasError && !hasBlocker {
            level = "ready"
            title = "新 CAD 内核可显示"
            summary = "Renderer 正在使用统一 CADKernelDocument。"
        } else {
            level = "kernelBootstrap"
            title = "诊断导入已接管"
            summary = "新 CAD 内核已接管入口，当前文件尚未转换为真实可渲染图元。"
        }

        return CADOpenQualitySnapshot(
            level: level,
            title: title,
            summary: summary,
            primaryAction: hasGeometry ? "查看图纸" : "查看诊断",
            detailLines: diagnostics.map { "\($0.code)：\($0.message)" },
            allowsMarkup: hasGeometry,
            supportsSearch: hasGeometry && document.entities.contains { $0.kind == .text }
        )
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}
