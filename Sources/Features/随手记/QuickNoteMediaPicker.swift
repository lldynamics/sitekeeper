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
                    Text(mediaImportMessage.isEmpty ? String(localized: "quick_note_media_importing_default_text") : mediaImportMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if audioRecorder.isRecording {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.appRisk)
                    Text(String(localized: "quick_note_media_recording_hint_text"))
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
        .alert(String(localized: "quick_note_media_alert_title"), isPresented: $showAlert) {
            Button(String(localized: "quick_note_media_alert_ack_button"), role: .cancel) {}
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
                .accessibilityLabel(String(localized: "quick_note_media_add_photo_accessibility_label"))
                .accessibilityHint(String(localized: "quick_note_media_add_photo_accessibility_hint"))

                Button { openCamera() } label: {
                    compactToolIcon("camera")
                }
                .accessibilityLabel(String(localized: "quick_note_media_take_photo_accessibility_label"))
                .accessibilityHint(String(localized: "quick_note_media_take_photo_accessibility_hint"))

                Button {
                    Task { await toggleAudioRecording() }
                } label: {
                    compactToolIcon(audioRecorder.isRecording ? "stop.fill" : "waveform", isActive: audioRecorder.isRecording)
                }
                .accessibilityLabel(
                    audioRecorder.isRecording
                    ? String(localized: "quick_note_media_stop_recording_accessibility_label")
                    : String(localized: "quick_note_media_start_recording_accessibility_label")
                )
                .accessibilityHint(
                    audioRecorder.isRecording
                    ? String(localized: "quick_note_media_stop_recording_accessibility_hint")
                    : String(localized: "quick_note_media_start_recording_accessibility_hint")
                )

                Button { showFileImporter = true } label: {
                    compactToolIcon("paperclip")
                }
                .accessibilityLabel(String(localized: "quick_note_media_import_file_accessibility_label"))
                .accessibilityHint(String(localized: "quick_note_media_import_file_accessibility_hint"))
            }
            .buttonStyle(.plain)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    PhotosPicker(selection: $selectedMediaItems, maxSelectionCount: 9, matching: .any(of: [.images, .videos])) {
                        toolLabel(String(localized: "quick_note_media_tool_photo"), systemImage: "photo.stack")
                    }
                    .disabled(isImportingMedia)
                    .accessibilityLabel(String(localized: "quick_note_media_add_photo_accessibility_label"))
                    .accessibilityHint(String(localized: "quick_note_media_add_photo_accessibility_hint"))
                    Button { openCamera() } label: {
                        toolLabel(String(localized: "quick_note_media_tool_camera"), systemImage: "camera")
                    }
                    .accessibilityLabel(String(localized: "quick_note_media_take_photo_accessibility_label"))
                    .accessibilityHint(String(localized: "quick_note_media_take_photo_accessibility_hint"))
                    Button {
                        Task { await toggleAudioRecording() }
                    } label: {
                        toolLabel(
                            audioRecorder.isRecording
                            ? String(localized: "quick_note_media_tool_stop_record")
                            : String(localized: "quick_note_media_tool_record"),
                            systemImage: audioRecorder.isRecording ? "stop.fill" : "waveform"
                        )
                    }
                    .tint(audioRecorder.isRecording ? Color.appRisk : Color.appPrimaryAction)
                    .accessibilityLabel(
                        audioRecorder.isRecording
                        ? String(localized: "quick_note_media_stop_recording_accessibility_label")
                        : String(localized: "quick_note_media_start_recording_accessibility_label")
                    )
                    .accessibilityHint(
                        audioRecorder.isRecording
                        ? String(localized: "quick_note_media_stop_recording_accessibility_hint")
                        : String(localized: "quick_note_media_start_recording_accessibility_hint")
                    )
                    Button { showDrawing = true } label: {
                        toolLabel(String(localized: "quick_note_media_tool_drawing"), systemImage: "pencil.and.outline")
                    }
                    .accessibilityLabel(String(localized: "quick_note_media_add_drawing_accessibility_label"))
                    .accessibilityHint(String(localized: "quick_note_media_add_drawing_accessibility_hint"))
                    Button { showFileImporter = true } label: {
                        toolLabel(String(localized: "quick_note_media_tool_file"), systemImage: "paperclip")
                    }
                    .accessibilityLabel(String(localized: "quick_note_media_import_file_accessibility_label"))
                    .accessibilityHint(String(localized: "quick_note_media_import_file_accessibility_hint"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func compactToolIcon(_ systemImage: String, isActive: Bool = false) -> some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
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
            showError(String(localized: "quick_note_media_camera_unavailable_error"))
            return
        }
        showCamera = true
    }

    private func importMediaItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        await MainActor.run {
            isImportingMedia = true
            mediaImportMessage = String(localized: "quick_note_media_importing_default_text")
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
                await MainActor.run { showError(String(localized: "quick_note_media_import_failed_single_item_error")) }
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
        await MainActor.run { mediaImportMessage = String(localized: "quick_note_media_check_video_message") }
        do {
            guard let transfer = try await item.loadTransferable(type: QuickNoteVideoTransfer.self) else {
                await MainActor.run { showError(String(localized: "quick_note_media_video_import_failed_error")) }
                return
            }
            _ = QuickNoteAttachmentStorage.videoThumbnail(for: transfer.fileName)
            await MainActor.run {
                onAppend(QuickNoteAttachment(kind: .video, fileName: transfer.fileName, originalName: transfer.originalName, durationSeconds: transfer.durationSeconds))
            }
        } catch let error as QuickNoteVideoTransferError {
            await MainActor.run { showError(error.userMessage) }
        } catch {
            await MainActor.run { showError(String(localized: "quick_note_media_video_import_failed_error")) }
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
                    format: String(localized: "quick_note_media_image_save_failed_error_format"),
                    error.localizedDescription
                )
            )
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
            showError(String(localized: "quick_note_media_recording_failed_error"))
        }
    }

    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isImportingMedia = true
            mediaImportMessage = String(localized: "quick_note_media_importing_files_message")
            fileImportTask?.cancel()
            fileImportTask = Task {
                for (index, url) in urls.enumerated() {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        mediaImportMessage = String(
                            format: String(localized: "quick_note_media_importing_files_progress_format"),
                            index + 1,
                            urls.count
                        )
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
                        await MainActor.run { showError(String(localized: "quick_note_media_file_import_failed_error")) }
                    }
                }
                await MainActor.run {
                    isImportingMedia = false
                    mediaImportMessage = ""
                    fileImportTask = nil
                }
            }
        case .failure:
            showError(String(localized: "quick_note_media_file_import_failed_error"))
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
