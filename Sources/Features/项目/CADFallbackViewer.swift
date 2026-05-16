import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import PDFKit
import UIKit
import WebKit
#endif

enum CADViewerMode: String, CaseIterable, Identifiable {
    case auto
    case vector
    case fallback

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return String(localized: "自动")
        case .vector: return String(localized: "图元")
        case .fallback: return String(localized: "兼容预览")
        }
    }

    var icon: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .vector: return "point.3.connected.trianglepath.dotted"
        case .fallback: return "photo.on.rectangle"
        }
    }
}

struct CADFallbackViewportTransform: Codable, Equatable {
    var zoomScale: Double
    var panOffsetX: Double
    var panOffsetY: Double
    var boundsX: Double
    var boundsY: Double
    var boundsWidth: Double
    var boundsHeight: Double
    var viewportCenterX: Double?
    var viewportCenterY: Double?

    init(
        zoomScale: Double,
        panOffsetX: Double,
        panOffsetY: Double,
        boundsX: Double,
        boundsY: Double,
        boundsWidth: Double,
        boundsHeight: Double,
        viewportCenterX: Double?,
        viewportCenterY: Double?
    ) {
        self.zoomScale = zoomScale
        self.panOffsetX = panOffsetX
        self.panOffsetY = panOffsetY
        self.boundsX = boundsX
        self.boundsY = boundsY
        self.boundsWidth = boundsWidth
        self.boundsHeight = boundsHeight
        self.viewportCenterX = viewportCenterX
        self.viewportCenterY = viewportCenterY
    }

    init(transform: CADNativeCanvasTransform, viewState: CADDrawingViewState) {
        self.init(
            zoomScale: viewState.zoomScale,
            panOffsetX: viewState.panOffsetX,
            panOffsetY: viewState.panOffsetY,
            boundsX: Double(transform.bounds.minX),
            boundsY: Double(transform.bounds.minY),
            boundsWidth: Double(transform.bounds.width),
            boundsHeight: Double(transform.bounds.height),
            viewportCenterX: viewState.viewportCenterX,
            viewportCenterY: viewState.viewportCenterY
        )
    }
}

struct CADArrowAnnotation: Identifiable, Codable, Equatable {
    var id = UUID()
    var start: CADPoint
    var end: CADPoint
    var lineWidth: Double
    var colorHex: String?
    var layerName: String?
    var createdAt: String
}

struct CADFallbackIssueMarker: Identifiable, Codable, Equatable {
    var id = UUID()
    var point: CADPoint
    var normalizedPoint: CADPoint
    var drawingId: UUID?
    var layoutId: String?
    var worldPoint: CADPoint?
    var viewportTransform: CADFallbackViewportTransform?
    var title: String
    var note: String
    var photoFileName: String?
    var colorHex: String?
    var createdAt: String
}

struct CADFallbackPreviewOutputs: Equatable {
    var thumbnailURL: URL?
    var previewSVGURL: URL?
    var previewPDFURL: URL?
    var previewImageURL: URL?
    var previewPageURLs: [URL]
    var previewTileURLs: [URL]
    var searchedDirectories: [URL]

    static let empty = CADFallbackPreviewOutputs(
        thumbnailURL: nil,
        previewSVGURL: nil,
        previewPDFURL: nil,
        previewImageURL: nil,
        previewPageURLs: [],
        previewTileURLs: [],
        searchedDirectories: []
    )

    var hasRenderablePreview: Bool {
        previewSVGURL != nil ||
            previewPDFURL != nil ||
            previewImageURL != nil ||
            thumbnailURL != nil ||
            !previewPageURLs.isEmpty ||
            !previewTileURLs.isEmpty
    }

    var firstImageURL: URL? {
        previewImageURL ?? previewPageURLs.first ?? previewTileURLs.first ?? thumbnailURL
    }

    var summary: String {
        var parts: [String] = []
        if thumbnailURL != nil { parts.append("thumbnail.png") }
        if previewSVGURL != nil { parts.append("preview.svg") }
        if previewPDFURL != nil { parts.append("preview.pdf") }
        if previewImageURL != nil { parts.append("preview image") }
        if !previewPageURLs.isEmpty { parts.append("preview_pages \(previewPageURLs.count)") }
        if !previewTileURLs.isEmpty { parts.append("preview_tiles \(previewTileURLs.count)") }
        return parts.isEmpty ? String(localized: "未找到兼容预览输出") : parts.joined(separator: " · ")
    }
}

enum CADFallbackOutputResolver {
    static func resolve(fileURL: URL) -> CADFallbackPreviewOutputs {
        let directories = candidateDirectories(for: fileURL)
        let previewPDFURL: URL?
        if fileURL.pathExtension.lowercased() == "pdf" {
            previewPDFURL = fileURL
        } else {
            previewPDFURL = firstExistingFile(named: ["preview.pdf"], in: directories)
        }

        return CADFallbackPreviewOutputs(
            thumbnailURL: firstExistingFile(named: ["thumbnail.png"], in: directories),
            previewSVGURL: firstExistingFile(named: ["preview.svg"], in: directories),
            previewPDFURL: previewPDFURL,
            previewImageURL: firstExistingFile(named: ["preview.png", "preview.jpg", "preview.jpeg"], in: directories),
            previewPageURLs: imageFiles(in: firstExistingDirectory(named: "preview_pages", in: directories)),
            previewTileURLs: imageFiles(in: firstExistingDirectory(named: "preview_tiles", in: directories)),
            searchedDirectories: directories
        )
    }

    private static func candidateDirectories(for fileURL: URL) -> [URL] {
        let parent = fileURL.deletingLastPathComponent()
        let stem = fileURL.deletingPathExtension().lastPathComponent
        return [
            parent.appendingPathComponent("Fallback").appendingPathComponent(stem, isDirectory: true),
            parent.appendingPathComponent("\(stem).fallback", isDirectory: true),
            parent.appendingPathComponent(stem, isDirectory: true),
            parent
        ]
    }

    private static func firstExistingFile(named names: [String], in directories: [URL]) -> URL? {
        for directory in directories {
            for name in names {
                let candidate = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func firstExistingDirectory(named name: String, in directories: [URL]) -> URL? {
        for directory in directories {
            let candidate = directory.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return candidate
            }
        }
        return nil
    }

    private static func imageFiles(in directory: URL?) -> [URL] {
        guard let directory else { return [] }
        do {
            return try FileManager.default
                .contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
                .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch {
            StorageIssueLog.record("CAD 兼容预览目录读取失败：\(directory.lastPathComponent)，\(error.localizedDescription)")
            return []
        }
    }
}

private enum CADFallbackGeometry {
    static let contentInsetLimits: ClosedRange<CGFloat> = 6...14

    static func drawingBounds(forAspect aspect: CGFloat) -> CGRect {
        CGRect(x: 0, y: 0, width: max(aspect, 0.1), height: 1)
    }

    static func transform(size: CGSize, aspect: CGFloat, zoomScale: CGFloat, panOffset: CGSize) -> CADRendererCanvasTransform {
        CADRendererCanvasTransform(
            bounds: drawingBounds(forAspect: aspect),
            size: size,
            zoomScale: zoomScale,
            panOffset: panOffset
        )
    }

    static func contentFrame(size: CGSize, aspect: CGFloat, zoomScale: CGFloat, panOffset: CGSize) -> CGRect {
        let bounds = drawingBounds(forAspect: aspect)
        let inset = min(max(min(size.width, size.height) * 0.018, contentInsetLimits.lowerBound), contentInsetLimits.upperBound)
        let scale = min(
            max(size.width - inset * 2, 1) / max(bounds.width, 0.1),
            max(size.height - inset * 2, 1) / max(bounds.height, 0.1)
        )
        let baseWidth = bounds.width * scale
        let baseHeight = bounds.height * scale
        let width = baseWidth * zoomScale
        let height = baseHeight * zoomScale
        return CGRect(
            x: (size.width - width) / 2 + panOffset.width,
            y: (size.height - height) / 2 + panOffset.height,
            width: width,
            height: height
        )
    }
}

struct CADFallbackViewer: View {
    let fileURL: URL
    let displayName: String
    let initialViewState: CADRendererViewState?
    let overlaySnapshot: CADOverlaySnapshot
    let onCanvasTransformChange: (CADRendererCanvasTransform) -> Void
    let onViewStateChange: (CADRendererViewState) -> Void
    let onScreenshotFeedback: (Data) -> Void

    @State private var outputs: CADFallbackPreviewOutputs = .empty
    @State private var previewImage: UIImage?
    @State private var previewMessage = ""
    @State private var aspectRatio: CGFloat = 1.414
    @State private var zoomScale: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var gestureStartZoom: CGFloat?
    @State private var gestureStartPan: CGSize?
    @State private var lastPublishedTransform: CADRendererCanvasTransform?

    private let minimumZoomScale: CGFloat = 0.6
    private let maximumZoomScale: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(uiColor: .secondarySystemBackground)

                fallbackContent(size: geo.size)

                fallbackStatusCard
                    .padding(12)

                HStack(spacing: 8) {
                    Button {
                        fitToScreen(size: geo.size)
                    } label: {
                        Label(String(localized: "适配"), systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        exportScreenshotFeedback(size: geo.size)
                    } label: {
                        Label(String(localized: "截图反馈"), systemImage: "camera.viewfinder")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(12)
            }
            .contentShape(Rectangle())
            .gesture(panGesture(size: geo.size).simultaneously(with: zoomGesture(size: geo.size)))
            .simultaneousGesture(doubleTapGesture(size: geo.size))
            .onAppear {
                applyInitialViewStateIfNeeded()
                loadFallbackOutputs(size: geo.size)
                publishTransform(size: geo.size, force: true)
            }
            .onChange(of: geo.size) { _, newSize in
                publishTransform(size: newSize, force: true)
            }
            .onChange(of: aspectRatio) { _, _ in
                publishTransform(size: geo.size, force: true)
            }
            .onChange(of: zoomScale) { _, _ in
                publishTransform(size: geo.size)
            }
            .onChange(of: panOffset) { _, _ in
                publishTransform(size: geo.size)
            }
        }
        .accessibilityLabel(String(localized: "CAD 兼容预览"))
        .accessibilityHint(String(localized: "双指缩放，拖动平移，双击适配屏幕。"))
    }

    private func fallbackContent(size: CGSize) -> some View {
        let frame = CADFallbackGeometry.contentFrame(
            size: size,
            aspect: aspectRatio,
            zoomScale: zoomScale,
            panOffset: panOffset
        )
        return ZStack {
            if let svgURL = outputs.previewSVGURL, previewImage == nil {
                CADFallbackSVGPreview(url: svgURL)
                    .background(Color.white)
            } else if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFill()
                    .background(Color.white)
            } else {
                CADFallbackEmptyPreview(
                    displayName: displayName,
                    message: previewMessage,
                    outputs: outputs
                )
                .background(Color.white)
            }
        }
        .clipShape(Rectangle())
        .overlay(Rectangle().stroke(Color(uiColor: .separator).opacity(0.35), lineWidth: 0.8))
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    private var fallbackStatusCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(String(localized: "兼容预览"), systemImage: "photo.on.rectangle")
                .font(.caption.weight(.semibold))
            Text(outputs.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.28), lineWidth: 0.8)
        )
    }

    private func loadFallbackOutputs(size: CGSize) {
        let resolved = CADFallbackOutputResolver.resolve(fileURL: fileURL)
        outputs = resolved
        previewMessage = resolved.hasRenderablePreview
            ? String(localized: "正在读取兼容预览")
            : String(localized: "未找到 thumbnail.png、preview.svg、preview.pdf、preview_pages 或 preview_tiles。")

        Task.detached(priority: .userInitiated) {
            let loaded = loadPreviewImage(from: resolved)
            await MainActor.run {
                if let loaded {
                    previewImage = loaded.image
                    aspectRatio = loaded.aspectRatio
                    previewMessage = ""
                } else if resolved.previewSVGURL != nil {
                    previewImage = nil
                    aspectRatio = svgAspectRatio(from: resolved.previewSVGURL) ?? 1.414
                    previewMessage = ""
                } else {
                    previewImage = nil
                    aspectRatio = 1.414
                }
                publishTransform(size: size, force: true)
            }
        }
    }

    private func applyInitialViewStateIfNeeded() {
        guard let initialViewState else { return }
        zoomScale = min(max(initialViewState.zoomScale, minimumZoomScale), maximumZoomScale)
        panOffset = initialViewState.panOffset
    }

    private func panGesture(size: CGSize) -> some Gesture {
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
            }
            .onEnded { _ in
                gestureStartPan = nil
                publishTransform(size: size, force: true)
            }
    }

    private func zoomGesture(size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if gestureStartZoom == nil {
                    gestureStartZoom = zoomScale
                }
                let start = gestureStartZoom ?? zoomScale
                zoomScale = min(max(start * value, minimumZoomScale), maximumZoomScale)
            }
            .onEnded { _ in
                gestureStartZoom = nil
                publishTransform(size: size, force: true)
            }
    }

    private func doubleTapGesture(size: CGSize) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                fitToScreen(size: size)
            }
    }

    private func fitToScreen(size: CGSize) {
        withAnimation(.easeInOut(duration: 0.18)) {
            zoomScale = 1
            panOffset = .zero
        }
        publishTransform(size: size, force: true)
    }

    private func publishTransform(size: CGSize, force: Bool = false) {
        guard size.width > 1, size.height > 1 else { return }
        let transform = CADFallbackGeometry.transform(
            size: size,
            aspect: aspectRatio,
            zoomScale: zoomScale,
            panOffset: panOffset
        )
        if force || lastPublishedTransform != transform {
            lastPublishedTransform = transform
            onCanvasTransformChange(transform)
        }
        let nativeTransform = CADNativeCanvasTransform(transform)
        let center = nativeTransform.drawingPoint(fromCanvas: CGPoint(x: size.width / 2, y: size.height / 2))
        onViewStateChange(
            CADRendererViewState(
                zoomScale: zoomScale,
                panOffset: panOffset,
                viewportCenter: center,
                usesSavedVisibleLayers: false,
                visibleLayerNames: []
            )
        )
    }

    private func exportScreenshotFeedback(size: CGSize) {
        guard let data = CADFallbackScreenshotComposer.makePNG(
            image: previewImage,
            displayName: displayName,
            overlaySnapshot: overlaySnapshot,
            size: size,
            aspectRatio: aspectRatio,
            zoomScale: zoomScale,
            panOffset: panOffset
        ) else {
            return
        }
        onScreenshotFeedback(data)
    }
}

private struct CADFallbackEmptyPreview: View {
    let displayName: String
    let message: String
    let outputs: CADFallbackPreviewOutputs

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Color.appWarning)
            Text(displayName)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !outputs.searchedDirectories.isEmpty {
                Text(outputs.searchedDirectories.prefix(2).map(\.lastPathComponent).joined(separator: " / "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(24)
    }
}

#if os(iOS)
private struct CADFallbackSVGPreview: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .white
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }
}
#endif

private struct CADFallbackLoadedImage {
    let image: UIImage
    let aspectRatio: CGFloat
}

private func loadPreviewImage(from outputs: CADFallbackPreviewOutputs) -> CADFallbackLoadedImage? {
    if let imageURL = outputs.firstImageURL,
       let data = try? Data(contentsOf: imageURL),
       let image = UIImage(data: data) {
        return CADFallbackLoadedImage(
            image: image,
            aspectRatio: max(image.size.width / max(image.size.height, 1), 0.1)
        )
    }

    if let pdfURL = outputs.previewPDFURL,
       let document = PDFDocument(url: pdfURL),
       let page = document.page(at: 0) {
        let box = page.bounds(for: .cropBox)
        let targetWidth: CGFloat = 1800
        let scale = targetWidth / max(box.width, 1)
        let targetSize = CGSize(width: max(box.width * scale, 1), height: max(box.height * scale, 1))
        let image = page.thumbnail(of: targetSize, for: .cropBox)
        return CADFallbackLoadedImage(
            image: image,
            aspectRatio: max(box.width / max(box.height, 1), 0.1)
        )
    }

    return nil
}

private func svgAspectRatio(from url: URL?) -> CGFloat? {
    guard let url,
          let data = try? Data(contentsOf: url),
          let text = String(data: Data(data.prefix(4096)), encoding: .utf8) else {
        return nil
    }
    if let viewBoxRange = text.range(of: #"viewBox\s*=\s*["'][^"']+["']"#, options: .regularExpression) {
        let raw = String(text[viewBoxRange])
            .replacingOccurrences(of: #"viewBox\s*=\s*["']"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"["']"#, with: "", options: .regularExpression)
        let numbers = raw
            .split { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" }
            .compactMap { Double($0) }
        if numbers.count >= 4, numbers[3] > 0 {
            return CGFloat(max(numbers[2] / numbers[3], 0.1))
        }
    }
    return nil
}

private enum CADFallbackScreenshotComposer {
    static func makePNG(
        image: UIImage?,
        displayName: String,
        overlaySnapshot: CADOverlaySnapshot,
        size: CGSize,
        aspectRatio: CGFloat,
        zoomScale: CGFloat,
        panOffset: CGSize
    ) -> Data? {
        guard size.width > 1, size.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let transform = CADNativeCanvasTransform(
            CADFallbackGeometry.transform(
                size: size,
                aspect: aspectRatio,
                zoomScale: zoomScale,
                panOffset: panOffset
            )
        )
        return renderer.pngData { context in
            UIColor.systemBackground.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let frame = CADFallbackGeometry.contentFrame(
                size: size,
                aspect: aspectRatio,
                zoomScale: zoomScale,
                panOffset: panOffset
            )
            UIColor.white.setFill()
            context.fill(frame)
            image?.draw(in: frame)

            drawOverlay(overlaySnapshot, transform: transform)

            let title = displayName as NSString
            title.draw(
                at: CGPoint(x: 14, y: 12),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: UIColor.secondaryLabel
                ]
            )
        }
    }

    private static func drawOverlay(_ snapshot: CADOverlaySnapshot, transform: CADNativeCanvasTransform) {
        for stroke in snapshot.strokes {
            drawPolyline(
                stroke.points.map { transform.canvasPoint(fromDrawing: $0.cgPoint) },
                color: UIColor(hex: stroke.colorHex ?? "2F80ED") ?? .systemBlue,
                lineWidth: max(stroke.lineWidth, 1.5),
                dashed: stroke.kind == .cloud
            )
        }

        for arrow in snapshot.arrowAnnotations {
            drawArrow(
                from: transform.canvasPoint(fromDrawing: arrow.start.cgPoint),
                to: transform.canvasPoint(fromDrawing: arrow.end.cgPoint),
                color: UIColor(hex: arrow.colorHex ?? "2F80ED") ?? .systemBlue,
                lineWidth: max(arrow.lineWidth, 1.5)
            )
        }

        for note in snapshot.notes {
            let point = transform.canvasPoint(fromDrawing: note.point.cgPoint)
            drawMarkerText(note.text, at: point, color: UIColor(hex: note.colorHex ?? "F2994A") ?? .systemOrange)
        }

        for marker in snapshot.issueMarkers {
            let point = transform.canvasPoint(fromDrawing: marker.point.cgPoint)
            drawIssueMarker(marker, at: point)
        }
    }

    private static func drawPolyline(_ points: [CGPoint], color: UIColor, lineWidth: CGFloat, dashed: Bool) {
        guard points.count > 1 else { return }
        let path = UIBezierPath()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        color.setStroke()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if dashed {
            var pattern: [CGFloat] = [8, 5]
            path.setLineDash(&pattern, count: pattern.count, phase: 0)
        }
        path.stroke()
    }

    private static func drawArrow(from start: CGPoint, to end: CGPoint, color: UIColor, lineWidth: CGFloat) {
        drawPolyline([start, end], color: color, lineWidth: lineWidth, dashed: false)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length: CGFloat = 13
        let wing: CGFloat = .pi * 0.78
        let p1 = CGPoint(x: end.x + cos(angle + wing) * length, y: end.y + sin(angle + wing) * length)
        let p2 = CGPoint(x: end.x + cos(angle - wing) * length, y: end.y + sin(angle - wing) * length)
        drawPolyline([p1, end, p2], color: color, lineWidth: lineWidth, dashed: false)
    }

    private static func drawMarkerText(_ text: String, at point: CGPoint, color: UIColor) {
        let label = text.isEmpty ? "批注" : text
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: UIColor.label
        ]
        let size = (label as NSString).size(withAttributes: attributes)
        let rect = CGRect(x: point.x + 8, y: point.y - size.height / 2 - 5, width: min(size.width + 14, 180), height: size.height + 10)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
        color.withAlphaComponent(0.16).setFill()
        path.fill()
        color.setStroke()
        path.lineWidth = 1
        path.stroke()
        (label as NSString).draw(at: CGPoint(x: rect.minX + 7, y: rect.minY + 5), withAttributes: attributes)
    }

    private static func drawIssueMarker(_ marker: CADFallbackIssueMarker, at point: CGPoint) {
        let color = UIColor(hex: marker.colorHex ?? "E24A7A") ?? .systemPink
        color.setFill()
        UIBezierPath(ovalIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)).fill()
        UIColor.white.setStroke()
        let ring = UIBezierPath(ovalIn: CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14))
        ring.lineWidth = 2
        ring.stroke()
        let text = marker.photoFileName == nil ? marker.title : "\(marker.title) · 照片"
        drawMarkerText(text, at: CGPoint(x: point.x + 8, y: point.y), color: color)
    }
}

private extension UIColor {
    convenience init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") {
            raw.removeFirst()
        }
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else {
            return nil
        }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}
