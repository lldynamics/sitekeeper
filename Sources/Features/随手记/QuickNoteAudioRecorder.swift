import AVFoundation
import Combine
import Foundation

@MainActor
final class QuickNoteAudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var recorder: AVAudioRecorder?
    private var recordingFileName: String?

    func toggleRecording() async throws -> QuickNoteAttachment? {
        if isRecording {
            return stopRecording()
        }
        try await startRecording()
        return nil
    }

    private func startRecording() async throws {
        guard await requestPermission() else {
            throw QuickNoteAudioRecorderError.permissionDenied
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)

            let fileName = QuickNoteAttachmentStorage.makeFileName(extension: "m4a")
            let url = QuickNoteAttachmentStorage.fileURL(for: fileName)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            let audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder.record()
            recorder = audioRecorder
            recordingFileName = fileName
            isRecording = true
        } catch {
            throw QuickNoteAudioRecorderError.startFailed
        }
    }

    private func stopRecording() -> QuickNoteAttachment? {
        guard let recorder, let recordingFileName else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.recordingFileName = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return QuickNoteAttachment(kind: .audio, fileName: recordingFileName, durationSeconds: duration)
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }
}

enum QuickNoteAudioRecorderError: LocalizedError {
    case permissionDenied
    case startFailed

    var userMessage: String {
        switch self {
        case .permissionDenied:
            return "请在系统设置中允许麦克风权限。"
        case .startFailed:
            return "录音启动失败。"
        }
    }
}
