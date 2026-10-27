import SwiftUI
import AVFoundation
import AVKit
import UIKit
import QuickLook

struct QuickNoteAttachmentStrip: View {
    let attachments: [QuickNoteAttachment]
    var showsRemoveButton = true
    let onPreview: (QuickNoteAttachment) -> Void
    let onRemove: (QuickNoteAttachment) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    ZStack(alignment: .topTrailing) {
                        Button { onPreview(attachment) } label: {
                            attachmentCard(attachment)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            attachment.attachmentKind == .audio
                            ? AppLocalization.string("quick_note_attachment_play_audio_accessibility_label")
                            : AppLocalization.string("quick_note_attachment_preview_accessibility_label")
                        )
                        .accessibilityValue("\(attachment.attachmentKind.title) \(label(for: attachment))")
                        .accessibilityHint(
                            attachment.attachmentKind == .audio
                            ? AppLocalization.string("quick_note_attachment_play_audio_accessibility_hint")
                            : AppLocalization.string("quick_note_attachment_preview_accessibility_hint")
                        )

                        if showsRemoveButton {
                            Button { onRemove(attachment) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.55))
                            }
                            .offset(x: 5, y: -5)
                            .accessibilityLabel(AppLocalization.string("quick_note_attachment_remove_accessibility_label"))
                            .accessibilityValue("\(attachment.attachmentKind.title) \(label(for: attachment))")
                            .accessibilityHint(AppLocalization.string("quick_note_attachment_remove_accessibility_hint"))
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func attachmentCard(_ attachment: QuickNoteAttachment) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemBackground))
                attachmentPreview(attachment)
                if attachment.attachmentKind == .video {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.45))
                }
            }
            .frame(width: 78, height: 78)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(label(for: attachment))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 82)
    }

    @ViewBuilder
    private func attachmentPreview(_ attachment: QuickNoteAttachment) -> some View {
        switch attachment.attachmentKind {
        case .photo, .drawing:
            AsyncQuickNoteAttachmentImageView(fileName: attachment.fileName) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image(systemName: attachment.attachmentKind.systemImage)
                    .font(.title2)
                    .foregroundStyle(.appWarning)
            }
        case .video:
            if let image = QuickNoteAttachmentStorage.videoThumbnail(for: attachment.fileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: attachment.attachmentKind.systemImage)
                    .font(.title2)
                    .foregroundStyle(.appWarning)
            }
        case .audio, .file:
            Image(systemName: attachment.attachmentKind.systemImage)
                .font(.title2)
                .foregroundStyle(.appWarning)
        }
    }

    private func label(for attachment: QuickNoteAttachment) -> String {
        if attachment.attachmentKind == .audio, let duration = attachment.durationSeconds, duration > 0 {
            return String(
                format: AppLocalization.string("quick_note_attachment_audio_duration_format"),
                Int(duration)
            )
        }
        if attachment.attachmentKind == .video,
           let size = QuickNoteAttachmentStorage.formattedFileSize(for: attachment.fileName) {
            return String(
                format: AppLocalization.string("quick_note_attachment_video_size_format"),
                size
            )
        }
        if attachment.attachmentKind == .file {
            return attachment.displayName
        }
        return attachment.attachmentKind.title
    }
}

struct QuickNoteAttachmentPreview: View {
    @Environment(\.dismiss) private var dismiss
    let attachment: QuickNoteAttachment
    @State private var previewImage: UIImage?
    @State private var attemptedImageLoad = false

    var body: some View {
        NavigationStack {
            Group {
                switch attachment.attachmentKind {
                case .photo, .drawing:
                    imagePreview
                case .video:
                    videoPreview
                case .audio:
                    audioPreview
                case .file:
                    filePreview
                }
            }
            .navigationTitle(pdfURL == nil ? attachment.attachmentKind.title : attachment.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLocalization.string("quick_note_attachment_close_button")) { dismiss() }
                        .accessibilityIdentifier("quick-note-attachment-close")
                }
                if let pdfURL {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: pdfURL) {
                            Label(AppLocalization.string("quick_note_attachment_open_or_share"), systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("quick-note-pdf-share")
                    }
                }
            }
        }
    }

    private var pdfURL: URL? {
        guard attachment.attachmentKind == .file else { return nil }
        let url = QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)
        return AppFilePreviewRoute.route(for: url) == .pdf ? url : nil
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let previewImage {
            QuickNoteImagePreviewController(image: previewImage)
                .ignoresSafeArea(edges: .bottom)
        } else if attemptedImageLoad {
            ContentUnavailableView(AppLocalization.string("quick_note_attachment_file_missing"), systemImage: "exclamationmark.triangle")
        } else {
            ProgressView(AppLocalization.string("quick_note_attachment_loading"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: attachment.fileName) {
                    await loadImagePreview()
                }
        }
    }

    private func loadImagePreview() async {
        attemptedImageLoad = false
        guard let data = await QuickNoteAttachmentStorage.dataAsync(for: attachment.fileName),
              let image = UIImage(data: data) else {
            previewImage = nil
            attemptedImageLoad = true
            return
        }
        previewImage = image
        attemptedImageLoad = true
    }

    @ViewBuilder
    private var videoPreview: some View {
        if QuickNoteAttachmentStorage.exists(fileName: attachment.fileName) {
            VideoPlayer(player: AVPlayer(url: QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)))
        } else {
            ContentUnavailableView(AppLocalization.string("quick_note_attachment_video_missing"), systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var audioPreview: some View {
        if QuickNoteAttachmentStorage.exists(fileName: attachment.fileName) {
            QuickNoteAudioPlayer(url: QuickNoteAttachmentStorage.fileURL(for: attachment.fileName))
                .padding()
        } else {
            ContentUnavailableView(AppLocalization.string("quick_note_attachment_audio_missing"), systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var filePreview: some View {
        if QuickNoteAttachmentStorage.exists(fileName: attachment.fileName) {
            let url = QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)
            VStack(spacing: 0) {
                QuickNoteFilePreviewController(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if pdfURL == nil {
                    fileDetails(url: url)
                }
            }
        } else {
            ContentUnavailableView(AppLocalization.string("quick_note_attachment_file_missing"), systemImage: "exclamationmark.triangle")
        }
    }

    private func fileDetails(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(attachment.displayName, systemImage: attachment.attachmentKind.systemImage)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
            if let size = QuickNoteAttachmentStorage.formattedFileSize(for: attachment.fileName) {
                Text(size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ShareLink(item: url) {
                Label(AppLocalization.string("quick_note_attachment_open_or_share"), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appProminent())
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
}

struct QuickNoteInlineAudioAttachmentPlayer: View {
    let attachment: QuickNoteAttachment
    var onClose: () -> Void = {}

    var body: some View {
        if QuickNoteAttachmentStorage.exists(fileName: attachment.fileName) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(title, systemImage: "waveform")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(AppLocalization.string("quick_note_attachment_collapse_audio_player_accessibility_label"))
                }

                QuickNoteAudioPlayer(
                    url: QuickNoteAttachmentStorage.fileURL(for: attachment.fileName),
                    style: .inline
                )
            }
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Label(AppLocalization.string("quick_note_attachment_audio_missing"), systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var title: String {
        guard let duration = attachment.durationSeconds, duration > 0 else {
            return AppLocalization.string("quick_note_attachment_audio_title")
        }
        return String(
            format: AppLocalization.string("quick_note_attachment_audio_duration_format"),
            Int(duration)
        )
    }
}
