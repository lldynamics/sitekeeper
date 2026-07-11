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
    @State private var hasDrawing = false
    @State private var showClearConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var backgroundLoadTask: Task<Void, Never>?
    let onSave: (UIImage) -> Void

    private var hasContent: Bool {
        hasDrawing || backgroundImage != nil
    }

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
                    PencilCanvasView(canvasView: canvasView) { drawing in
                        hasDrawing = !drawing.bounds.isEmpty
                    }
                }
            }
            .navigationTitle(backgroundImage == nil ? String(localized: "quick_note_drawing_title") : String(localized: "quick_note_drawing_photo_markup_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "quick_note_drawing_cancel_button")) {
                        if hasContent {
                            showDiscardConfirmation = true
                        } else {
                            dismiss()
                        }
                    }
                    .accessibilityIdentifier("quick-note-drawing-cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "quick_note_drawing_undo_button")) { canvasView.undoManager?.undo() }
                        .accessibilityIdentifier("quick-note-drawing-undo")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "quick_note_drawing_save_button")) { saveDrawing() }
                        .disabled(!hasContent)
                        .accessibilityIdentifier("quick-note-drawing-save")
                }
            }
            .onChange(of: selectedColor) { _, _ in updateTool() }
            .onChange(of: lineWidth) { _, _ in updateTool() }
            .onChange(of: isEraser) { _, _ in updateTool() }
            .onChange(of: selectedBackgroundItem) { _, newItem in
                backgroundLoadTask?.cancel()
                guard let newItem else { return }
                backgroundLoadTask = Task { await loadBackgroundImage(newItem) }
            }
            .onAppear(perform: updateTool)
            .onDisappear {
                backgroundLoadTask?.cancel()
                backgroundLoadTask = nil
            }
            .confirmationDialog(
                String(localized: "quick_note_drawing_clear_confirmation_title"),
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "quick_note_drawing_clear_button"), role: .destructive) {
                    clearCanvas()
                }
                Button(String(localized: "quick_note_drawing_keep_editing_button"), role: .cancel) {}
            } message: {
                Text(String(localized: "quick_note_drawing_clear_confirmation_message"))
            }
            .confirmationDialog(
                String(localized: "quick_note_drawing_discard_confirmation_title"),
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "quick_note_drawing_discard_button"), role: .destructive) {
                    dismiss()
                }
                Button(String(localized: "quick_note_drawing_keep_editing_button"), role: .cancel) {}
            } message: {
                Text(String(localized: "quick_note_drawing_discard_confirmation_message"))
            }
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
                        if hasContent {
                            showClearConfirmation = true
                        }
                    } label: { Label(String(localized: "quick_note_drawing_clear_button"), systemImage: "trash") }
                        .disabled(!hasContent)
                        .accessibilityIdentifier("quick-note-drawing-clear")
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
              !Task.isCancelled,
              let image = UIImage(data: data) else { return }
        await MainActor.run { backgroundImage = image }
    }

    private func clearCanvas() {
        backgroundLoadTask?.cancel()
        backgroundLoadTask = nil
        canvasView.drawing = PKDrawing()
        hasDrawing = false
        backgroundImage = nil
        selectedBackgroundItem = nil
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
    let onDrawingChanged: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDrawingChanged: onDrawingChanged)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.drawingPolicy = .anyInput
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        canvasView.delegate = context.coordinator
        canvasView.accessibilityLabel = String(localized: "quick_note_drawing_canvas_accessibility_label")
        canvasView.accessibilityHint = String(localized: "quick_note_drawing_canvas_accessibility_hint")
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let onDrawingChanged: (PKDrawing) -> Void

        init(onDrawingChanged: @escaping (PKDrawing) -> Void) {
            self.onDrawingChanged = onDrawingChanged
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            onDrawingChanged(canvasView.drawing)
        }
    }
}
