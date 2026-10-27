import SwiftUI
import AVFoundation

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
                .font(.largeTitle)
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
                    ? AppLocalization.string("quick_note_attachment_pause_playback_button")
                    : AppLocalization.string("quick_note_attachment_play_audio_button"),
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
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.appWarning, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                isPlaying
                ? AppLocalization.string("quick_note_attachment_pause_playback_button")
                : AppLocalization.string("quick_note_attachment_play_audio_button")
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
            Task { @MainActor in
                guard timer != nil, let player else { return }
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
