import SwiftUI
import UIKit

struct WatermarkPhotoAnnotation: Identifiable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case arrow, circle, text
        var title: String {
            switch self { case .arrow: AppLocalization.string("箭头"); case .circle: AppLocalization.string("圆圈"); case .text: AppLocalization.string("文字") }
        }
    }
    let id: UUID
    var kind: Kind
    var start: CGPoint
    var end: CGPoint
    var text: String

    init(id: UUID = UUID(), kind: Kind, start: CGPoint, end: CGPoint, text: String = "") {
        self.id = id
        self.kind = kind
        self.start = Self.clamped(start)
        self.end = Self.clamped(end)
        self.text = text
    }

    var center: CGPoint { CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2) }

    func movingCenter(to point: CGPoint) -> Self {
        var copy = self
        let dx = min(1 - max(start.x, end.x), max(-min(start.x, end.x), point.x - center.x))
        let dy = min(1 - max(start.y, end.y), max(-min(start.y, end.y), point.y - center.y))
        copy.start = CGPoint(x: start.x + dx, y: start.y + dy)
        copy.end = CGPoint(x: end.x + dx, y: end.y + dy)
        return copy
    }

    private static func clamped(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(1, max(0, point.x.isFinite ? point.x : 0.5)),
                y: min(1, max(0, point.y.isFinite ? point.y : 0.5)))
    }
}

enum WatermarkPhotoAnnotationRenderer {
    static func render(image: UIImage, annotations: [WatermarkPhotoAnnotation]) -> UIImage {
        guard image.size.width > 0, image.size.height > 0 else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { context in
            image.draw(in: CGRect(origin: .zero, size: image.size))
            draw(annotations: annotations, in: image.size, context: context.cgContext)
        }
    }

    static func draw(annotations: [WatermarkPhotoAnnotation], in size: CGSize, context: CGContext) {
        let shortEdge = min(size.width, size.height)
        guard shortEdge > 0 else { return }
        let scale = shortEdge / 1_000
        context.saveGState()
        defer { context.restoreGState() }
        context.scaleBy(x: scale, y: scale)
        drawCanonical(annotations: annotations,
                      in: CGSize(width: size.width / scale, height: size.height / scale),
                      context: context)
    }

    private static func drawCanonical(annotations: [WatermarkPhotoAnnotation], in size: CGSize, context: CGContext) {
        UIGraphicsPushContext(context)
        defer { UIGraphicsPopContext() }
        let shortEdge: CGFloat = 1_000
        let stroke = shortEdge * 0.008
        for mark in annotations {
            let start = CGPoint(x: mark.start.x * size.width, y: mark.start.y * size.height)
            let end = CGPoint(x: mark.end.x * size.width, y: mark.end.y * size.height)
            context.saveGState()
            context.setStrokeColor(UIColor.systemRed.cgColor)
            context.setFillColor(UIColor.systemRed.cgColor)
            context.setLineWidth(stroke)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setShadow(offset: .zero, blur: stroke * 0.35, color: UIColor.black.cgColor)
            switch mark.kind {
            case .arrow:
                let angle = atan2(end.y - start.y, end.x - start.x)
                let head = shortEdge * 0.045
                context.move(to: start)
                context.addLine(to: end)
                context.move(to: CGPoint(x: end.x - head * cos(angle - .pi / 6), y: end.y - head * sin(angle - .pi / 6)))
                context.addLine(to: end)
                context.addLine(to: CGPoint(x: end.x - head * cos(angle + .pi / 6), y: end.y - head * sin(angle + .pi / 6)))
                context.strokePath()
            case .circle:
                context.strokeEllipse(in: CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                                 width: max(stroke, abs(end.x - start.x)), height: max(stroke, abs(end.y - start.y))))
            case .text:
                drawText(mark.text, at: start, size: size, shortEdge: shortEdge)
            }
            context.restoreGState()
        }
    }

    private static func drawText(_ text: String, at point: CGPoint, size: CGSize, shortEdge: CGFloat) {
        let text = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !text.isEmpty else { return }
        let font = UIFont.systemFont(ofSize: shortEdge * 0.04, weight: .bold)
        let padding = shortEdge * 0.012
        let maxWidth = size.width * 0.88 - padding * 2
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph]
        let width = min(maxWidth, (text as NSString).size(withAttributes: attributes).width)
        let rect = CGRect(x: min(max(padding, point.x), size.width - width - padding * 2),
                          y: min(max(padding, point.y), size.height - font.lineHeight - padding * 2),
                          width: width, height: font.lineHeight)
        UIColor.black.withAlphaComponent(0.7).setFill()
        UIBezierPath(roundedRect: rect.insetBy(dx: -padding, dy: -padding), cornerRadius: padding).fill()
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}

struct WatermarkPhotoAnnotationView: View {
    let photo: WatermarkCapturedPhoto
    let onSave: @MainActor (UIImage) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var marks: [WatermarkPhotoAnnotation] = []
    @State private var tool: WatermarkPhotoAnnotation.Kind = .arrow
    @State private var note = ""
    @State private var dragMark: WatermarkPhotoAnnotation?
    @State private var isSaving = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Text(AppLocalization.string("在照片上拖动放置箭头或圆圈，轻点放置文字。也可用下方按钮和位置滑块添加标记。"))
                        .font(.caption).foregroundStyle(.secondary)
                    annotationPreview
                    Picker(AppLocalization.string("标记类型"), selection: $tool) {
                        ForEach(WatermarkPhotoAnnotation.Kind.allCases, id: \.self) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }.pickerStyle(.segmented)
                    if tool == .text {
                        TextField(AppLocalization.string("标注文字"), text: $note)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: note) { _, value in note = String(value.prefix(160)) }
                    }
                    HStack {
                        Button(String(format: AppLocalization.string("添加%@"), tool.title), systemImage: "plus") { addCenteredMark() }
                            .disabled(tool == .text && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                        Button(AppLocalization.string("撤销"), systemImage: "arrow.uturn.backward") { if !marks.isEmpty { marks.removeLast() } }
                            .disabled(marks.isEmpty)
                    }
                    if !marks.isEmpty {
                        VStack(alignment: .leading) {
                            Text(AppLocalization.string("最后一个标记的位置")).font(.caption).foregroundStyle(.secondary)
                            Slider(value: positionBinding(horizontal: true), in: 0...1) { Text(AppLocalization.string("标记横向位置")) }
                            Slider(value: positionBinding(horizontal: false), in: 0...1) { Text(AppLocalization.string("标记纵向位置")) }
                        }
                    }
                    Text(AppLocalization.string("保存后生成标注副本，保留原照片。"))
                        .font(.caption).foregroundStyle(.secondary)
                    if let errorText { Text(errorText).foregroundStyle(.red) }
                }
                .padding()
                .disabled(isSaving)
            }
            .navigationTitle(AppLocalization.string("照片标注"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("取消")) { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? AppLocalization.string("正在保存…") : AppLocalization.string("保存副本")) { saveCopy() }
                        .disabled(isSaving || marks.isEmpty)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private var annotationPreview: some View {
        let ratio = photo.imageAspectRatio
        return GeometryReader { proxy in
            ZStack {
                WatermarkDraftImageView(photo: photo, maxPixelSize: 1200)
                Canvas { context, size in
                    context.withCGContext { cg in
                        WatermarkPhotoAnnotationRenderer.draw(annotations: marks + (dragMark.map { [$0] } ?? []), in: size, context: cg)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in dragMark = makeMark(start: value.startLocation, end: value.location, size: proxy.size) }
                .onEnded { value in
                    let mark = makeMark(start: value.startLocation, end: value.location, size: proxy.size)
                    let distance = hypot(value.location.x - value.startLocation.x, value.location.y - value.startLocation.y)
                    if (mark.kind == .text && !mark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        || (mark.kind != .text && distance >= 8) {
                        marks.append(mark)
                    }
                    dragMark = nil
                })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(String(format: AppLocalization.string("照片标注预览，已有 %lld 个标记"), marks.count))
        }
        .aspectRatio(ratio, contentMode: .fit)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func makeMark(start: CGPoint, end: CGPoint, size: CGSize) -> WatermarkPhotoAnnotation {
        let first = CGPoint(x: start.x / max(1, size.width), y: start.y / max(1, size.height))
        let last = tool == .text ? first : CGPoint(x: end.x / max(1, size.width), y: end.y / max(1, size.height))
        return WatermarkPhotoAnnotation(kind: tool, start: first, end: last, text: note)
    }

    private func addCenteredMark() {
        marks.append(WatermarkPhotoAnnotation(kind: tool,
            start: tool == .text ? CGPoint(x: 0.5, y: 0.45) : CGPoint(x: 0.35, y: 0.35),
            end: tool == .text ? CGPoint(x: 0.5, y: 0.45) : CGPoint(x: 0.65, y: 0.55), text: note))
    }

    private func positionBinding(horizontal: Bool) -> Binding<Double> {
        Binding(get: {
            let point = marks.last?.center ?? CGPoint(x: 0.5, y: 0.5)
            return Double(horizontal ? point.x : point.y)
        }, set: { value in
            guard let last = marks.last else { return }
            let point = horizontal ? CGPoint(x: value, y: last.center.y) : CGPoint(x: last.center.x, y: value)
            marks[marks.count - 1] = last.movingCenter(to: point)
        })
    }

    private func saveCopy() {
        isSaving = true
        errorText = nil
        let annotations = marks
        let source = photo
        Task { @MainActor in
            do {
                let image = try await WatermarkCameraImageLoader.shared.imageForDelivery(source)
                let result = await Task.detached(priority: .userInitiated) {
                    WatermarkPhotoAnnotationRenderer.render(image: image, annotations: annotations)
                }.value
                try await onSave(result)
                dismiss()
            } catch {
                errorText = error.localizedDescription
                isSaving = false
            }
        }
    }
}
