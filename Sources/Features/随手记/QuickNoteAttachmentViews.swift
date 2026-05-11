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
                        .accessibilityLabel("预览附件")
                        .accessibilityValue("\(attachment.attachmentKind.title) \(label(for: attachment))")
                        .accessibilityHint("双击打开附件预览")

                        if showsRemoveButton {
                            Button { onRemove(attachment) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.55))
                            }
                            .offset(x: 5, y: -5)
                            .accessibilityLabel("删除附件")
                            .accessibilityValue("\(attachment.attachmentKind.title) \(label(for: attachment))")
                            .accessibilityHint("双击移除该附件")
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
                if let image = previewImage(for: attachment) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: attachment.attachmentKind.systemImage)
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
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

    private func previewImage(for attachment: QuickNoteAttachment) -> UIImage? {
        switch attachment.attachmentKind {
        case .photo, .drawing:
            guard let data = QuickNoteAttachmentStorage.data(for: attachment.fileName) else { return nil }
            return UIImage(data: data)
        case .video:
            return QuickNoteAttachmentStorage.videoThumbnail(for: attachment.fileName)
        case .audio, .file:
            return nil
        }
    }

    private func label(for attachment: QuickNoteAttachment) -> String {
        if attachment.attachmentKind == .audio, let duration = attachment.durationSeconds, duration > 0 {
            return "语音 \(Int(duration))s"
        }
        if attachment.attachmentKind == .video,
           let size = QuickNoteAttachmentStorage.formattedFileSize(for: attachment.fileName) {
            return "视频 \(size)"
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
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let data = QuickNoteAttachmentStorage.data(for: attachment.fileName),
           let image = UIImage(data: data) {
            QuickNoteImagePreviewController(image: image)
                .ignoresSafeArea(edges: .bottom)
        } else {
            ContentUnavailableView("文件不存在", systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var videoPreview: some View {
        if QuickNoteAttachmentStorage.data(for: attachment.fileName) != nil {
            VideoPlayer(player: AVPlayer(url: QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)))
        } else {
            ContentUnavailableView("视频文件不存在", systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var audioPreview: some View {
        if QuickNoteAttachmentStorage.data(for: attachment.fileName) != nil {
            QuickNoteAudioPlayer(url: QuickNoteAttachmentStorage.fileURL(for: attachment.fileName))
                .padding()
        } else {
            ContentUnavailableView("语音文件不存在", systemImage: "exclamationmark.triangle")
        }
    }

    @ViewBuilder
    private var filePreview: some View {
        let url = QuickNoteAttachmentStorage.fileURL(for: attachment.fileName)
        if FileManager.default.fileExists(atPath: url.path) {
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
                        Label("打开或分享附件", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(.systemGroupedBackground))
            }
        } else {
            ContentUnavailableView("附件文件不存在", systemImage: "exclamationmark.triangle")
        }
    }
}

struct QuickNoteAudioPlayer: View {
    let url: URL
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
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
                Label(isPlaying ? "暂停播放" : "播放语音", systemImage: isPlaying ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .onAppear(perform: preparePlayer)
        .onDisappear(perform: stopPlayback)
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
