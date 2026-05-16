import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class QuickNoteAudioRecorder {
    private(set) var isRecording = false
    @ObservationIgnored
    private var recorder: AVAudioRecorder?
    @ObservationIgnored
    private var recordingFileName: String?
    private static let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
    ]

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

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            throw QuickNoteAudioRecorderError.sessionConfigurationFailed(error.localizedDescription)
        }

        guard session.isInputAvailable else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw QuickNoteAudioRecorderError.inputUnavailable
        }

        let fileName = QuickNoteAttachmentStorage.makeFileName(extension: "m4a")
        let url = QuickNoteAttachmentStorage.fileURL(for: fileName)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw QuickNoteAudioRecorderError.storageUnavailable
        }

        let audioRecorder: AVAudioRecorder
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: Self.recordingSettings)
        } catch {
            cleanupFailedRecording(fileName: fileName)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw QuickNoteAudioRecorderError.startFailed("录音文件创建失败：\(error.localizedDescription)")
        }

        audioRecorder.isMeteringEnabled = true
        guard audioRecorder.prepareToRecord() else {
            cleanupFailedRecording(fileName: fileName)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw QuickNoteAudioRecorderError.startFailed("无法准备录音文件。")
        }

        guard audioRecorder.record() else {
            cleanupFailedRecording(fileName: fileName)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw QuickNoteAudioRecorderError.startFailed("系统没有开始录音，请检查麦克风是否被占用。")
        }

        recorder = audioRecorder
        recordingFileName = fileName
        isRecording = true
    }

    func cancelRecording() {
        guard let recorder else {
            isRecording = false
            recordingFileName = nil
            return
        }

        let fileName = recordingFileName
        recorder.stop()
        self.recorder = nil
        recordingFileName = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        if let fileName {
            QuickNoteAttachmentStorage.delete(fileName: fileName)
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

    private func cleanupFailedRecording(fileName: String) {
        QuickNoteAttachmentStorage.delete(fileName: fileName)
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
    case inputUnavailable
    case sessionConfigurationFailed(String)
    case storageUnavailable
    case startFailed(String)

    var userMessage: String {
        switch self {
        case .permissionDenied:
            return "请在系统设置中允许麦克风权限。"
        case .inputUnavailable:
            return "当前设备没有可用麦克风。请检查模拟器或设备的音频输入。"
        case .sessionConfigurationFailed(let detail):
            return "录音会话启动失败：\(detail)"
        case .storageUnavailable:
            return "录音文件夹创建失败，请检查本机存储空间。"
        case .startFailed(let detail):
            return detail
        }
    }
}
