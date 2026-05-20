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
                            ? String(localized: "quick_note_attachment_play_audio_accessibility_label")
                            : String(localized: "quick_note_attachment_preview_accessibility_label")
                        )
                        .accessibilityValue("\(attachment.attachmentKind.title) \(label(for: attachment))")
                        .accessibilityHint(
                            attachment.attachmentKind == .audio
                            ? String(localized: "quick_note_attachment_play_audio_accessibility_hint")
                            : String(localized: "quick_note_attachment_preview_accessibility_hint")
                        )

                        if showsRemoveButton {
                            Button { onRemove(attachment) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.55))
                            }
                            .offset(x: 5, y: -5)
                            .accessibilityLabel(String(localized: "quick_note_attachment_remove_accessibility_label"))
                            .accessibilityValue("\(attachment.attachmentKind.title) \(label(for: attachment))")
                            .accessibilityHint(String(localized: "quick_note_attachment_remove_accessibility_hint"))
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
                format: String(localized: "quick_note_attachment_audio_duration_format"),
                Int(duration)
            )
        }
        if attachment.attachmentKind == .video,
           let size = QuickNoteAttachmentStorage.formattedFileSize(for: attachment.fileName) {
            return String(
                format: String(localized: "quick_note_attachment_video_size_format"),
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
            .navigationTitle(attachment.attachmentKind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "quick_note_attachment_close_button")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let previewImage {
            QuickNoteImagePreviewController(image: previewImage)
                .ignoresSafeArea(edges: .bottom)
        } else if attemptedImageLoad {
            ContentUnavailableView(String(localized: "quick_note_attachment_file_missing"), systemImage: "exclamationmark.triangle")
        } else {
            ProgressView(String(localized: "quick_note_attachment_loading"))
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
            ContentUnavailableView(String(localized: "quick_note_attachment_video_missing"), systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var audioPreview: some View {
        if QuickNoteAttachmentStorage.exists(fileName: attachment.fileName) {
            QuickNoteAudioPlayer(url: QuickNoteAttachmentStorage.fileURL(for: attachment.fileName))
                .padding()
        } else {
            ContentUnavailableView(String(localized: "quick_note_attachment_audio_missing"), systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var filePreview: some View {
        if QuickNoteAttachmentStorage.exists(fileName: attachment.fileName) {
            let url = QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)
            VStack(spacing: 0) {
                QuickNoteFilePreviewController(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        Label(String(localized: "quick_note_attachment_open_or_share"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appProminent())
                }
                .padding()
                .background(Color(.systemGroupedBackground))
            }
        } else {
            ContentUnavailableView(String(localized: "quick_note_attachment_file_missing"), systemImage: "exclamationmark.triangle")
        }
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
                    .accessibilityLabel(String(localized: "quick_note_attachment_collapse_audio_player_accessibility_label"))
                }

                QuickNoteAudioPlayer(
                    url: QuickNoteAttachmentStorage.fileURL(for: attachment.fileName),
                    style: .inline
                )
            }
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Label(String(localized: "quick_note_attachment_audio_missing"), systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var title: String {
        guard let duration = attachment.durationSeconds, duration > 0 else {
            return String(localized: "quick_note_attachment_audio_title")
        }
        return String(
            format: String(localized: "quick_note_attachment_audio_duration_format"),
            Int(duration)
        )
    }
}

enum QuickNoteAudioPlayerStyle {
    case full
    case inline
}

struct QuickNoteAudioPlayer: View {
    let url: URL
    var style: QuickNoteAudioPlayerStyle = .full
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timer: Timer?

    var body: some View {
        Group {
            switch style {
            case .full:
                fullPlayer
            case .inline:
                inlinePlayer
            }
        }
        .onAppear(perform: preparePlayer)
        .onDisappear(perform: stopPlayback)
    }

    private var fullPlayer: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.appWarning)
            Slider(value: Binding(
                get: { currentTime },
                set: { seek(to: $0) }
            ), in: 0...max(duration, 1))
            HStack {
                Text(formatTime(currentTime))
                Spacer()
                Text(formatTime(duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            Button { togglePlay() } label: {
                Label(
                    isPlaying
                    ? String(localized: "quick_note_attachment_pause_playback_button")
                    : String(localized: "quick_note_attachment_play_audio_button"),
                    systemImage: isPlaying ? "pause.fill" : "play.fill"
                )
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.appProminent())
        }
    }

    private var inlinePlayer: some View {
        HStack(spacing: 10) {
            Button { togglePlay() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.appWarning, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isPlaying
                ? String(localized: "quick_note_attachment_pause_playback_button")
                : String(localized: "quick_note_attachment_play_audio_button")
            )

            Slider(value: Binding(
                get: { currentTime },
                set: { seek(to: $0) }
            ), in: 0...max(duration, 1))
            .tint(.appWarning)

            Text("\(formatTime(currentTime))/\(formatTime(duration))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 82, alignment: .trailing)
        }
    }

    private func preparePlayer() {
        guard player == nil else { return }
        do {
            let audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer.prepareToPlay()
            player = audioPlayer
            duration = audioPlayer.duration
            currentTime = audioPlayer.currentTime
        } catch {
            player = nil
        }
    }

    private func togglePlay() {
        preparePlayer()
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            stopTimer()
            return
        }
        player.play()
        isPlaying = true
        startTimer()
    }

    private func seek(to value: Double) {
        player?.currentTime = value
        currentTime = value
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            guard let player else { return }
            currentTime = player.currentTime
            if !player.isPlaying || player.currentTime >= player.duration {
                isPlaying = false
                currentTime = min(player.currentTime, player.duration)
                stopTimer()
                if player.currentTime >= player.duration {
                    player.currentTime = 0
                    currentTime = 0
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
        stopTimer()
    }

    private func formatTime(_ seconds: Double) -> String {
        let value = max(Int(seconds), 0)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
