import SwiftUI
import PhotosUI
import PencilKit
import UIKit

struct QuickNoteDrawingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var canvasView = PKCanvasView()
    @State private var selectedBackgroundItem: PhotosPickerItem?
    @State private var backgroundImage: UIImage?
    @State private var selectedColor: Color = .black
    @State private var lineWidth: Double = 4
    @State private var isEraser = false
    let onSave: (UIImage) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                toolStrip
                ZStack {
                    Color.white
                    if let backgroundImage {
                        Image(uiImage: backgroundImage)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    }
                    PencilCanvasView(canvasView: canvasView)
                }
            }
            .navigationTitle(backgroundImage == nil ? String(localized: "quick_note_drawing_title") : String(localized: "quick_note_drawing_photo_markup_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "quick_note_drawing_cancel_button")) { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "quick_note_drawing_undo_button")) { canvasView.undoManager?.undo() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "quick_note_drawing_save_button")) { saveDrawing() }
                        .disabled(canvasView.drawing.bounds.isEmpty && backgroundImage == nil)
                }
            }
            .onChange(of: selectedColor) { _, _ in updateTool() }
            .onChange(of: lineWidth) { _, _ in updateTool() }
            .onChange(of: isEraser) { _, _ in updateTool() }
            .onChange(of: selectedBackgroundItem) { _, newItem in
                Task { await loadBackgroundImage(newItem) }
            }
            .onAppear(perform: updateTool)
        }
    }

    private var toolStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $selectedBackgroundItem, matching: .images) {
                        Label(String(localized: "quick_note_drawing_photo_markup_title"), systemImage: "photo")
                    }
                    Button { isEraser = false } label: { Label(String(localized: "quick_note_drawing_pen_tool"), systemImage: "pencil") }
                        .tint(isEraser ? .appMuted : .appWarning)
                    Button { isEraser = true } label: { Label(String(localized: "quick_note_drawing_eraser_tool"), systemImage: "eraser") }
                        .tint(isEraser ? .appWarning : .appMuted)
                    Button(role: .destructive) {
                        canvasView.drawing = PKDrawing()
                        backgroundImage = nil
                    } label: { Label(String(localized: "quick_note_drawing_clear_button"), systemImage: "trash") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            HStack {
                ColorPicker(String(localized: "quick_note_drawing_color_picker_label"), selection: $selectedColor)
                    .labelsHidden()
                    .disabled(isEraser)
                Text(String(localized: "quick_note_drawing_line_width_label"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $lineWidth, in: 2...18)
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
    }

    private func updateTool() {
        if isEraser {
            canvasView.tool = PKEraserTool(.bitmap)
        } else {
            canvasView.tool = PKInkingTool(.pen, color: UIColor(selectedColor), width: lineWidth)
        }
    }

    private func loadBackgroundImage(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        await MainActor.run { backgroundImage = image }
    }

    private func saveDrawing() {
        let bounds = canvasView.bounds.width > 1 && canvasView.bounds.height > 1
            ? canvasView.bounds
            : CGRect(x: 0, y: 0, width: 900, height: 650)
        let drawingImage = canvasView.drawing.image(from: bounds, scale: UIScreen.main.scale)
        let output = renderComposite(bounds: bounds, drawingImage: drawingImage)
        onSave(output)
        dismiss()
    }

    private func renderComposite(bounds: CGRect, drawingImage: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(bounds)
            if let backgroundImage {
                let target = aspectFitRect(imageSize: backgroundImage.size, container: bounds.insetBy(dx: 8, dy: 8))
                backgroundImage.draw(in: target)
            }
            drawingImage.draw(in: bounds)
        }
    }

    private func aspectFitRect(imageSize: CGSize, container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return container }
        let ratio = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
        return CGRect(x: container.midX - size.width / 2, y: container.midY - size.height / 2, width: size.width, height: size.height)
    }
}

struct PencilCanvasView: UIViewRepresentable {
    let canvasView: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}
