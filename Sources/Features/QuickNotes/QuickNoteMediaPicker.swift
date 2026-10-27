import SwiftUI
import PhotosUI
import UIKit

struct QuickNoteAttachmentPickerBar: View {
    let projectName: String
    var mode: QuickNoteMediaPickerMode = .full
    var onDiscardDraftRequest: (() -> Void)? = nil
    var onActivityChange: (Bool) -> Void = { _ in }
    let onAppend: (QuickNoteAttachment) -> Void
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var showPhotoLibrary = false
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

    private var hasAttachmentActivity: Bool {
        audioRecorder.isRecording || isImportingMedia || !selectedMediaItems.isEmpty || showPhotoLibrary || showCamera
            || showDrawing || showFileImporter || isRequestingAudio
    }

    @State private var isRequestingAudio = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            toolRow
            if isImportingMedia {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(mediaImportMessage.isEmpty ? AppLocalization.string("quick_note_media_importing_default_text") : mediaImportMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if audioRecorder.isRecording {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.appRisk)
                    Text(AppLocalization.string("quick_note_media_recording_hint_text"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: selectedMediaItems) { _, newItems in
            mediaImportTask?.cancel()
            mediaImportTask = Task { await importMediaItems(newItems) }
        }
        .onChange(of: hasAttachmentActivity) { _, isActive in onActivityChange(isActive) }
        .photosPicker(
            isPresented: $showPhotoLibrary,
            selection: $selectedMediaItems,
            maxSelectionCount: 4,
            matching: .any(of: [.images, .videos])
        )
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
        .alert(AppLocalization.string("quick_note_media_alert_title"), isPresented: $showAlert) {
            Button(AppLocalization.string("quick_note_media_alert_ack_button"), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .onDisappear {
            mediaImportTask?.cancel()
            fileImportTask?.cancel()
            mediaImportTask = nil
            fileImportTask = nil
            audioRecorder.cancelRecording()
            onActivityChange(false)
        }
    }

    @ViewBuilder
    private var toolRow: some View {
        if mode == .compact {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    compactCameraButton
                    compactAudioButton
                    compactPhotoButton
                    compactDrawingButton
                    compactFileButton
                    if onDiscardDraftRequest != nil {
                        compactMoreMenu(includesAttachmentActions: false)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)

                HStack(alignment: .top, spacing: 12) {
                    compactCameraButton
                    compactAudioButton
                    compactMoreMenu(includesAttachmentActions: true)
                }
            }
            .buttonStyle(.plain)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $selectedMediaItems, maxSelectionCount: 9, matching: .any(of: [.images, .videos])) {
                        toolLabel(AppLocalization.string("quick_note_media_tool_photo"), systemImage: "photo.stack")
                    }
                    .disabled(isImportingMedia)
                    .accessibilityLabel(AppLocalization.string("quick_note_media_add_photo_accessibility_label"))
                    .accessibilityHint(AppLocalization.string("quick_note_media_add_photo_accessibility_hint"))
                    Button { openCamera() } label: {
                        toolLabel(AppLocalization.string("quick_note_media_tool_camera"), systemImage: "camera")
                    }
                    .accessibilityLabel(AppLocalization.string("quick_note_media_take_photo_accessibility_label"))
                    .accessibilityHint(AppLocalization.string("quick_note_media_take_photo_accessibility_hint"))
                    Button {
                        Task { await toggleAudioRecording() }
                    } label: {
                        toolLabel(
                            audioRecorder.isRecording
                            ? AppLocalization.string("quick_note_media_tool_stop_record")
                            : AppLocalization.string("quick_note_media_tool_record"),
                            systemImage: audioRecorder.isRecording ? "stop.fill" : "waveform"
                        )
                    }
                    .tint(audioRecorder.isRecording ? Color.appRisk : Color.appPrimaryAction)
                    .accessibilityLabel(
                        audioRecorder.isRecording
                        ? AppLocalization.string("quick_note_media_stop_recording_accessibility_label")
                        : AppLocalization.string("quick_note_media_start_recording_accessibility_label")
                    )
                    .accessibilityHint(
                        audioRecorder.isRecording
                        ? AppLocalization.string("quick_note_media_stop_recording_accessibility_hint")
                        : AppLocalization.string("quick_note_media_start_recording_accessibility_hint")
                    )
                    Button { showDrawing = true } label: {
                        toolLabel(AppLocalization.string("quick_note_media_tool_drawing"), systemImage: "pencil.and.outline")
                    }
                    .accessibilityLabel(AppLocalization.string("quick_note_media_add_drawing_accessibility_label"))
                    .accessibilityHint(AppLocalization.string("quick_note_media_add_drawing_accessibility_hint"))
                    Button { showFileImporter = true } label: {
                        toolLabel(AppLocalization.string("quick_note_media_tool_file"), systemImage: "paperclip")
                    }
                    .accessibilityLabel(AppLocalization.string("quick_note_media_import_file_accessibility_label"))
                    .accessibilityHint(AppLocalization.string("quick_note_media_import_file_accessibility_hint"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var compactCameraButton: some View {
        Button { openCamera() } label: {
            compactToolLabel(AppLocalization.string("quick_note_media_tool_camera"), systemImage: "camera")
        }
        .accessibilityIdentifier("quick-note-take-photo")
        .accessibilityLabel(AppLocalization.string("quick_note_media_take_photo_accessibility_label"))
        .accessibilityHint(AppLocalization.string("quick_note_media_take_photo_accessibility_hint"))
    }

    private var compactAudioButton: some View {
        Button {
            Task { await toggleAudioRecording() }
        } label: {
            compactToolLabel(
                AppLocalization.string(audioRecorder.isRecording ? "quick_note_media_tool_stop_record" : "quick_note_media_tool_voice"),
                systemImage: audioRecorder.isRecording ? "stop.fill" : "waveform",
                isActive: audioRecorder.isRecording
            )
        }
        .accessibilityIdentifier("quick-note-record-audio")
        .accessibilityLabel(
            audioRecorder.isRecording
            ? AppLocalization.string("quick_note_media_stop_recording_accessibility_label")
            : AppLocalization.string("quick_note_media_start_recording_accessibility_label")
        )
        .accessibilityHint(
            audioRecorder.isRecording
            ? AppLocalization.string("quick_note_media_stop_recording_accessibility_hint")
            : AppLocalization.string("quick_note_media_start_recording_accessibility_hint")
        )
    }

    private var compactPhotoButton: some View {
        Button { showPhotoLibrary = true } label: {
            compactToolLabel(AppLocalization.string("quick_note_media_tool_photo"), systemImage: "photo.stack")
        }
        .disabled(isImportingMedia)
        .accessibilityLabel(AppLocalization.string("quick_note_media_add_photo_accessibility_label"))
        .accessibilityHint(AppLocalization.string("quick_note_media_add_photo_accessibility_hint"))
    }

    private var compactDrawingButton: some View {
        Button { showDrawing = true } label: {
            compactToolLabel(AppLocalization.string("quick_note_media_tool_drawing"), systemImage: "pencil.and.outline")
        }
        .accessibilityIdentifier("quick-note-add-drawing")
        .accessibilityLabel(AppLocalization.string("quick_note_media_add_drawing_accessibility_label"))
        .accessibilityHint(AppLocalization.string("quick_note_media_add_drawing_accessibility_hint"))
    }

    private var compactFileButton: some View {
        Button { showFileImporter = true } label: {
            compactToolLabel(AppLocalization.string("quick_note_media_tool_file"), systemImage: "paperclip")
        }
        .accessibilityLabel(AppLocalization.string("quick_note_media_import_file_accessibility_label"))
        .accessibilityHint(AppLocalization.string("quick_note_media_import_file_accessibility_hint"))
    }

    private func compactMoreMenu(includesAttachmentActions: Bool) -> some View {
        Menu {
            if includesAttachmentActions {
                Button { showPhotoLibrary = true } label: {
                    Label(AppLocalization.string("quick_note_media_tool_photo"), systemImage: "photo.stack")
                }
                .disabled(isImportingMedia)
                .accessibilityLabel(AppLocalization.string("quick_note_media_add_photo_accessibility_label"))
                .accessibilityHint(AppLocalization.string("quick_note_media_add_photo_accessibility_hint"))

                Button { showDrawing = true } label: {
                    Label(AppLocalization.string("quick_note_media_tool_drawing"), systemImage: "pencil.and.outline")
                }
                .accessibilityIdentifier("quick-note-add-drawing")

                Button { showFileImporter = true } label: {
                    Label(AppLocalization.string("quick_note_media_tool_file"), systemImage: "paperclip")
                }
                .accessibilityLabel(AppLocalization.string("quick_note_media_import_file_accessibility_label"))
                .accessibilityHint(AppLocalization.string("quick_note_media_import_file_accessibility_hint"))
            }

            if let onDiscardDraftRequest {
                if includesAttachmentActions { Divider() }
                Button(role: .destructive, action: onDiscardDraftRequest) {
                    Label(AppLocalization.string("quick_note_composer_discard_draft_button"), systemImage: "trash")
                }
            }
        } label: {
            compactToolLabel(AppLocalization.string("quick_note_media_tool_more"), systemImage: "ellipsis")
        }
        .accessibilityLabel(AppLocalization.string("quick_note_media_more_accessibility_label"))
        .accessibilityIdentifier("quick-note-more-tools")
    }

    nonisolated private func compactToolLabel(_ title: String, systemImage: String, isActive: Bool = false) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title2.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? Color.appRisk : Color.appPrimaryAction)
            Text(title)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 44, minHeight: 52)
        .contentShape(Rectangle())
    }

    nonisolated private func toolLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
    }
}

extension QuickNoteAttachmentPickerBar {
    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showError(AppLocalization.string("quick_note_media_camera_unavailable_error"))
            return
        }
        showCamera = true
    }

    private func importMediaItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        await MainActor.run {
            isImportingMedia = true
            mediaImportMessage = AppLocalization.string("quick_note_media_importing_default_text")
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
                await MainActor.run { showError(AppLocalization.string("quick_note_media_import_failed_single_item_error")) }
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
        await MainActor.run { mediaImportMessage = AppLocalization.string("quick_note_media_check_video_message") }
        do {
            guard let transfer = try await item.loadTransferable(type: QuickNoteVideoTransfer.self) else {
                await MainActor.run { showError(AppLocalization.string("quick_note_media_video_import_failed_error")) }
                return
            }
            _ = QuickNoteAttachmentStorage.videoThumbnail(for: transfer.fileName)
            await MainActor.run {
                onAppend(QuickNoteAttachment(kind: .video, fileName: transfer.fileName, originalName: transfer.originalName, durationSeconds: transfer.durationSeconds))
            }
        } catch let error as QuickNoteVideoTransferError {
            await MainActor.run { showError(error.userMessage) }
        } catch {
            await MainActor.run { showError(AppLocalization.string("quick_note_media_video_import_failed_error")) }
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
            showError(
                String(
                    format: AppLocalization.string("quick_note_media_image_save_failed_error_format"),
                    error.localizedDescription
                )
            )
            return
        }
        onAppend(QuickNoteAttachment(kind: kind, fileName: fileName))
    }

    @MainActor
    private func toggleAudioRecording() async {
        guard !isRequestingAudio else { return }
        isRequestingAudio = true
        defer { isRequestingAudio = false }
        do {
            if let attachment = try await audioRecorder.toggleRecording() {
                onAppend(attachment)
            }
        } catch let error as QuickNoteAudioRecorderError {
            showError(error.userMessage)
        } catch {
            showError(AppLocalization.string("quick_note_media_recording_failed_error"))
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isImportingMedia = true
            mediaImportMessage = AppLocalization.string("quick_note_media_importing_files_message")
            fileImportTask?.cancel()
            fileImportTask = Task {
                for (index, url) in urls.enumerated() {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        mediaImportMessage = String(
                            format: AppLocalization.string("quick_note_media_importing_files_progress_format"),
                            index + 1,
                            urls.count
                        )
                    }
                    do {
                        let attachment = try await FileIOTaskRunner.run(
                            priority: .utility,
                            logContext: .init(
                                event: "quick_note.file_import",
                                source: "QuickNoteMediaPicker.handleFileImportResult",
                                category: .fileStorage,
                                details: ["source_file": url.lastPathComponent]
                            )
                        ) {
                            try QuickNoteFileAttachmentImport.copyFile(from: url)
                        }
                        await MainActor.run {
                            onAppend(attachment)
                        }
                    } catch let error as QuickNoteFileAttachmentImportError {
                        guard !Task.isCancelled else { break }
                        await MainActor.run { showError(error.userMessage) }
                    } catch {
                        guard !Task.isCancelled else { break }
                        await MainActor.run { showError(AppLocalization.string("quick_note_media_file_import_failed_error")) }
                    }
                }
                await MainActor.run {
                    isImportingMedia = false
                    mediaImportMessage = ""
                    fileImportTask = nil
                }
            }
        case .failure:
            showError(AppLocalization.string("quick_note_media_file_import_failed_error"))
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
