import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class QuickNoteAudioRecorder {
    private(set) var isRecording = false
    @ObservationIgnored
    private let session: any QuickNoteAudioSessionControlling
    @ObservationIgnored
    private let recorderFactory: any QuickNoteAudioRecorderCreating
    @ObservationIgnored
    private let fileStore: any QuickNoteAudioRecordingFileStoring
    @ObservationIgnored
    private var recorder: (any QuickNoteAudioRecording)?
    @ObservationIgnored
    private var recordingFileName: String?
    private static let recordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44_100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
    ]

    init(
        session: any QuickNoteAudioSessionControlling = SystemQuickNoteAudioSessionController(),
        recorderFactory: any QuickNoteAudioRecorderCreating = SystemQuickNoteAudioRecorderFactory(),
        fileStore: any QuickNoteAudioRecordingFileStoring = QuickNoteAudioAttachmentFileStore()
    ) {
        self.session = session
        self.recorderFactory = recorderFactory
        self.fileStore = fileStore
    }

    func toggleRecording() async throws -> QuickNoteAttachment? {
        if isRecording {
            return stopRecording()
        }
        try await startRecording()
        return nil
    }

    private func startRecording() async throws {
        guard await session.requestRecordPermission() else {
            throw QuickNoteAudioRecorderError.permissionDenied
        }

        do {
            try session.configureForRecording()
        } catch {
            throw QuickNoteAudioRecorderError.sessionConfigurationFailed(error.localizedDescription)
        }

        guard session.isInputAvailable else {
            session.deactivateAfterRecording()
            throw QuickNoteAudioRecorderError.inputUnavailable
        }

        let fileName = fileStore.makeFileName(extension: "m4a")
        let url = fileStore.fileURL(for: fileName)
        do {
            try fileStore.prepareDirectory(for: url)
        } catch {
            session.deactivateAfterRecording()
            throw QuickNoteAudioRecorderError.storageUnavailable
        }

        let audioRecorder: any QuickNoteAudioRecording
        do {
            audioRecorder = try recorderFactory.makeRecorder(url: url, settings: Self.recordingSettings)
        } catch {
            cleanupFailedRecording(fileName: fileName)
            session.deactivateAfterRecording()
            throw QuickNoteAudioRecorderError.startFailed("录音文件创建失败：\(error.localizedDescription)")
        }

        audioRecorder.isMeteringEnabled = true
        guard audioRecorder.prepareToRecord() else {
            cleanupFailedRecording(fileName: fileName)
            session.deactivateAfterRecording()
            throw QuickNoteAudioRecorderError.startFailed("无法准备录音文件。")
        }

        guard audioRecorder.record() else {
            cleanupFailedRecording(fileName: fileName)
            session.deactivateAfterRecording()
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
        session.deactivateAfterRecording()

        if let fileName {
            cleanupCancelledRecording(fileName: fileName)
        }
    }

    private func stopRecording() -> QuickNoteAttachment? {
        guard let recorder, let recordingFileName else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        self.recordingFileName = nil
        isRecording = false
        session.deactivateAfterRecording()
        return QuickNoteAttachment(kind: .audio, fileName: recordingFileName, durationSeconds: duration)
    }

    private func cleanupFailedRecording(fileName: String) {
        fileStore.deleteRecording(fileName: fileName, summary: "quickNoteAudioRecorder.failedRecording")
    }

    private func cleanupCancelledRecording(fileName: String) {
        fileStore.deleteRecording(fileName: fileName, summary: "quickNoteAudioRecorder.cancelRecording")
    }
}

@MainActor
protocol QuickNoteAudioSessionControlling {
    var isInputAvailable: Bool { get }
    func requestRecordPermission() async -> Bool
    func configureForRecording() throws
    func deactivateAfterRecording()
}

protocol QuickNoteAudioRecording: AnyObject {
    var isMeteringEnabled: Bool { get set }
    var currentTime: TimeInterval { get }
    func prepareToRecord() -> Bool
    func record() -> Bool
    func stop()
}

protocol QuickNoteAudioRecorderCreating {
    func makeRecorder(url: URL, settings: [String: Any]) throws -> any QuickNoteAudioRecording
}

protocol QuickNoteAudioRecordingFileStoring {
    func makeFileName(extension ext: String) -> String
    func fileURL(for fileName: String) -> URL
    func prepareDirectory(for recordingURL: URL) throws
    func deleteRecording(fileName: String, summary: String)
}

private struct SystemQuickNoteAudioSessionController: QuickNoteAudioSessionControlling {
    var isInputAvailable: Bool {
        AVAudioSession.sharedInstance().isInputAvailable
    }

    func requestRecordPermission() async -> Bool {
        await PermissionRequestTimeoutSupport.resolve(fallback: false) { resume in
            AVAudioApplication.requestRecordPermission { allowed in
                resume(allowed)
            }
        }
    }

    func configureForRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
    }

    func deactivateAfterRecording() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

private struct SystemQuickNoteAudioRecorderFactory: QuickNoteAudioRecorderCreating {
    func makeRecorder(url: URL, settings: [String: Any]) throws -> any QuickNoteAudioRecording {
        try AVAudioRecorder(url: url, settings: settings)
    }
}

extension AVAudioRecorder: QuickNoteAudioRecording {}

private struct QuickNoteAudioAttachmentFileStore: QuickNoteAudioRecordingFileStoring {
    func makeFileName(extension ext: String) -> String {
        QuickNoteAttachmentStorage.makeFileName(extension: ext)
    }

    func fileURL(for fileName: String) -> URL {
        QuickNoteAttachmentStorage.fileURL(for: fileName)
    }

    func prepareDirectory(for recordingURL: URL) throws {
        try FileManager.default.createDirectory(
            at: recordingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func deleteRecording(fileName: String, summary: String) {
        DataStoreDeferredFileCleanup.quickNoteAttachmentFiles(
            [fileName],
            summary: summary
        )?.perform()
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
