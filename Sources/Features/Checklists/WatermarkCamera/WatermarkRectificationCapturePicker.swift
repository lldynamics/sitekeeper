import SwiftUI
import UIKit

/// Freezes the issue and the watermark context before opening its alignment camera.
struct WatermarkRectificationCapturePicker: View {
    let projectId: UUID?
    let context: CameraWatermarkContext
    let showGrid: Bool
    let flashEnabled: Bool
    let burstCount: Int
    let onCapture: @MainActor ([UIImage], Date) -> Void
    let onFinished: @MainActor (UUID) -> Void

    @Environment(DataStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var cameraTarget: WatermarkRectificationCaptureTarget?
    @State private var loadingTodoID: UUID?
    @State private var capturedTodoID: UUID?
    @State private var preparationTask: Task<Void, Never>?
    @State private var errorMessage: String?

    private var eligibleTodos: [SiteTodo] {
        store.siteTodos.filter {
            WatermarkRectificationEligibility.accepts($0, projectID: projectId)
                && !($0.rectificationBeforePhotoFileName ?? "").isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(AppLocalization.string("选择已有问题，拍摄时将半透明显示整改前照片，便于保持相同角度。照片会先保留为草稿，完成拍摄后再核对关联。"))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section(AppLocalization.string("选择需要整改的问题")) {
                    if eligibleTodos.isEmpty {
                        ContentUnavailableView(
                            AppLocalization.string("暂无可对照的问题"), systemImage: "photo.on.rectangle",
                            description: Text(AppLocalization.string("仅显示同项目中已有整改前照片、尚无整改后证据的事项。"))
                        )
                    }
                    ForEach(eligibleTodos) { todo in
                        Button { prepareCamera(for: todo) } label: {
                            HStack(spacing: 12) {
                                AsyncPhotoThumbnailImageView(fileName: todo.rectificationBeforePhotoFileName) { image in
                                    image.resizable().scaledToFill().frame(width: 64, height: 64).clipped()
                                } placeholder: {
                                    Image(systemName: "photo").frame(width: 64, height: 64)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(todo.title).foregroundStyle(.primary)
                                    Text(AppLocalization.string("使用整改前照片辅助对齐")).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if loadingTodoID == todo.id { ProgressView() }
                                else { Image(systemName: "camera.fill") }
                            }
                        }
                        .disabled(loadingTodoID != nil)
                        .accessibilityLabel(String(format: AppLocalization.string("拍摄整改后照片：%@"), todo.title))
                    }
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
            }
            .navigationTitle(AppLocalization.string("拍摄整改后照片"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("取消")) {
                        preparationTask?.cancel()
                        dismiss()
                    }
                }
            }
            .sheet(item: $cameraTarget, onDismiss: finishCapture) { target in
                WatermarkCameraCaptureView(
                    watermarkContext: target.context,
                    showGrid: showGrid, flashEnabled: flashEnabled, burstCount: burstCount,
                    referenceImage: target.referenceImage
                ) { images, capturedAt in
                    guard !images.isEmpty else { return }
                    capturedTodoID = target.id
                    onCapture(images, capturedAt)
                }
            }
        }
        .onDisappear {
            preparationTask?.cancel()
            preparationTask = nil
        }
    }

    private func prepareCamera(for todo: SiteTodo) {
        guard loadingTodoID == nil,
              WatermarkRectificationEligibility.accepts(todo, projectID: projectId),
              let beforeName = todo.rectificationBeforePhotoFileName else { return }
        errorMessage = nil
        loadingTodoID = todo.id
        let frozenContext = context
        let frozenProjectID = projectId
        let beforeURL = PhotoStorage.fileURL(for: beforeName)
        preparationTask = Task { @MainActor in
            defer { loadingTodoID = nil; preparationTask = nil }
            // Read and decode only a bounded alignment image, never retain a full-resolution original.
            let reference = await ImageDownsampleService.downsampledImageAsync(
                at: beforeURL, maxPixelSize: 1400, source: "WatermarkRectificationCapturePicker"
            )
            guard !Task.isCancelled else { return }
            guard let reference else {
                errorMessage = AppLocalization.string("整改前照片已丢失或无法读取，请先到原事项中核对。")
                return
            }
            guard let current = store.siteTodos.first(where: { $0.id == todo.id }),
                  WatermarkRectificationEligibility.accepts(current, projectID: frozenProjectID),
                  current.rectificationBeforePhotoFileName == beforeName else {
                errorMessage = AppLocalization.string("事项归属或整改证据已变化，请重新选择。")
                return
            }
            capturedTodoID = nil
            cameraTarget = WatermarkRectificationCaptureTarget(id: current.id, context: frozenContext, referenceImage: reference)
        }
    }

    private func finishCapture() {
        guard let capturedTodoID else { return }
        self.capturedTodoID = nil
        // The caller queues association until this picker itself finishes dismissing.
        onFinished(capturedTodoID)
        dismiss()
    }
}

private struct WatermarkRectificationCaptureTarget: Identifiable {
    let id: UUID
    let context: CameraWatermarkContext
    let referenceImage: UIImage
}
