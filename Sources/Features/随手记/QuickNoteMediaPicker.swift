import SwiftUI
import PhotosUI
import UIKit

struct QuickNoteAttachmentPickerBar: View {
    let projectName: String
    var mode: QuickNoteMediaPickerMode = .full
    let onAppend: (QuickNoteAttachment) -> Void
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var showDrawing = false
    @State private var showFileImporter = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var isImportingMedia = false
    @State private var mediaImportMessage = ""
    @State private var mediaImportTask: Task<Void, Never>?
    @State private var fileImportTask: Task<Void, Never>?
    @State private var audioRecorder = QuickNoteAudioRecorder()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            toolRow
            if isImportingMedia {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(mediaImportMessage.isEmpty ? "正在导入媒体..." : mediaImportMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if audioRecorder.isRecording {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.appRisk)
                    Text("正在录音，点语音按钮结束")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: selectedMediaItems) { _, newItems in
            mediaImportTask?.cancel()
            mediaImportTask = Task { await importMediaItems(newItems) }
        }
        .sheet(isPresented: $showCamera) {
            ImagePickerView(
                sourceType: .camera,
                onPicked: appendCameraImage(_:)
            )
        }
        .sheet(isPresented: $showDrawing) {
            QuickNoteDrawingSheet { image in
                appendImage(image, kind: .drawing)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: QuickNoteFileAttachmentImport.allowedContentTypes,
            allowsMultipleSelection: true,
            onCompletion: handleFileImportResult(_:)
        )
        .alert("无法添加附件", isPresented: $showAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onDisappear {
            mediaImportTask?.cancel()
            fileImportTask?.cancel()
            mediaImportTask = nil
            fileImportTask = nil
            audioRecorder.cancelRecording()
        }
    }

    @ViewBuilder
    private var toolRow: some View {
        if mode == .compact {
            HStack(spacing: 7) {
                PhotosPicker(selection: $selectedMediaItems, maxSelectionCount: 4, matching: .any(of: [.images, .videos])) {
                    compactToolIcon("photo.stack")
                }
                .disabled(isImportingMedia)
                .accessibilityLabel("从相册添加媒体")
                .accessibilityHint("选择照片或视频附件")

                Button { openCamera() } label: {
                    compactToolIcon("camera")
                }
                .accessibilityLabel("拍照添加")
                .accessibilityHint("打开相机拍照并加入随手记")

                Button {
                    Task { await toggleAudioRecording() }
                } label: {
                    compactToolIcon(audioRecorder.isRecording ? "stop.fill" : "waveform", isActive: audioRecorder.isRecording)
                }
                .accessibilityLabel(audioRecorder.isRecording ? "停止录音" : "录制语音")
                .accessibilityHint(audioRecorder.isRecording ? "停止录音并加入随手记" : "开始录制现场语音")

                Button { showFileImporter = true } label: {
                    compactToolIcon("paperclip")
                }
                .accessibilityLabel("导入文件附件")
                .accessibilityHint("从文件中选择附件导入")
            }
            .buttonStyle(.plain)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $selectedMediaItems, maxSelectionCount: 9, matching: .any(of: [.images, .videos])) {
                        toolLabel("媒体", systemImage: "photo.stack")
                    }
                    .disabled(isImportingMedia)
                    .accessibilityLabel("从相册添加媒体")
                    .accessibilityHint("选择照片或视频附件")
                    Button { openCamera() } label: {
                        toolLabel("拍照", systemImage: "camera")
                    }
                    .accessibilityLabel("拍照添加")
                    .accessibilityHint("打开相机拍照并加入随手记")
                    Button {
                        Task { await toggleAudioRecording() }
                    } label: {
                        toolLabel(audioRecorder.isRecording ? "停止录音" : "语音", systemImage: audioRecorder.isRecording ? "stop.fill" : "waveform")
                    }
                    .tint(audioRecorder.isRecording ? Color.appRisk : Color.appPrimaryAction)
                    .accessibilityLabel(audioRecorder.isRecording ? "停止录音" : "录制语音")
                    .accessibilityHint(audioRecorder.isRecording ? "停止录音并加入随手记" : "开始录制现场语音")
                    Button { showDrawing = true } label: {
                        toolLabel("手绘/标注", systemImage: "pencil.and.outline")
                    }
                    .accessibilityLabel("添加手绘标注")
                    .accessibilityHint("打开手绘板创建标注附件")
                    Button { showFileImporter = true } label: {
                        toolLabel("附件", systemImage: "paperclip")
                    }
                    .accessibilityLabel("导入文件附件")
                    .accessibilityHint("从文件中选择附件导入")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func compactToolIcon(_ systemImage: String, isActive: Bool = false) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isActive ? Color.white : Color.appPrimaryAction)
            .frame(width: 32, height: 30)
            .background(isActive ? Color.appRisk : Color(.tertiarySystemGroupedBackground), in: Circle())
    }

    private func toolLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showError("当前设备不可用相机。")
            return
        }
        showCamera = true
    }

    private func importMediaItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        await MainActor.run {
            isImportingMedia = true
            mediaImportMessage = "正在导入媒体..."
        }
        for item in items {
            guard !Task.isCancelled else { break }
            if isVideoItem(item) {
                await importVideoItem(item)
                continue
            }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                guard !Task.isCancelled else { break }
                await MainActor.run { showError("有一项媒体导入失败。") }
                continue
            }
            guard !Task.isCancelled else { break }
            await MainActor.run { appendImage(image, kind: .photo) }
        }
        await MainActor.run {
            isImportingMedia = false
            mediaImportMessage = ""
            selectedMediaItems = []
        }
    }

    private func importVideoItem(_ item: PhotosPickerItem) async {
        await MainActor.run { mediaImportMessage = "检查视频大小和时长..." }
        do {
            guard let transfer = try await item.loadTransferable(type: QuickNoteVideoTransfer.self) else {
                await MainActor.run { showError("视频导入失败。") }
                return
            }
            _ = QuickNoteAttachmentStorage.videoThumbnail(for: transfer.fileName)
            await MainActor.run {
                onAppend(QuickNoteAttachment(kind: .video, fileName: transfer.fileName, originalName: transfer.originalName, durationSeconds: transfer.durationSeconds))
            }
        } catch let error as QuickNoteVideoTransferError {
            await MainActor.run { showError(error.userMessage) }
        } catch {
            await MainActor.run { showError("视频导入失败。") }
        }
    }

    private func isVideoItem(_ item: PhotosPickerItem) -> Bool {
        item.supportedContentTypes.contains { $0.conforms(to: .movie) || $0.conforms(to: .video) }
    }

    private func appendCameraImage(_ image: UIImage) {
        appendImage(image, kind: .photo)
    }

    private func appendImage(_ image: UIImage, kind: QuickNoteAttachmentKind) {
        let fileName: String
        do {
            fileName = try QuickNoteAttachmentStorage.saveImageOrThrow(image)
        } catch {
            showError("图片保存失败：\(error.localizedDescription)")
            return
        }
        onAppend(QuickNoteAttachment(kind: kind, fileName: fileName))
    }

    @MainActor
    private func toggleAudioRecording() async {
        do {
            if let attachment = try await audioRecorder.toggleRecording() {
                onAppend(attachment)
            }
        } catch let error as QuickNoteAudioRecorderError {
            showError(error.userMessage)
        } catch {
            showError("录音失败。")
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isImportingMedia = true
            mediaImportMessage = "正在导入附件..."
            fileImportTask?.cancel()
            fileImportTask = Task {
                for (index, url) in urls.enumerated() {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        mediaImportMessage = "正在导入附件 \(index + 1)/\(urls.count)"
                    }
                    do {
                        let attachment = try await Task.detached(priority: .utility) {
                            try QuickNoteFileAttachmentImport.copyFile(from: url)
                        }.value
                        await MainActor.run {
                            onAppend(attachment)
                        }
                    } catch let error as QuickNoteFileAttachmentImportError {
                        guard !Task.isCancelled else { break }
                        await MainActor.run { showError(error.userMessage) }
                    } catch {
                        guard !Task.isCancelled else { break }
                        await MainActor.run { showError("附件导入失败。") }
                    }
                }
                await MainActor.run {
                    isImportingMedia = false
                    mediaImportMessage = ""
                    fileImportTask = nil
                }
            }
        case .failure:
            showError("附件导入失败。")
        }
    }

    private func showError(_ message: String) {
        alertMessage = message
        showAlert = true
    }
}

enum QuickNoteMediaPickerMode {
    case full
    case compact
}
