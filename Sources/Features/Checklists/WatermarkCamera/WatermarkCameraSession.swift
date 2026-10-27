import Foundation
import Combine
import UIKit
import AVFoundation
import ImageIO

struct WatermarkCameraCaptureGenerationGate {
    private(set) var activeGeneration: UUID?

    mutating func begin() -> UUID {
        let generation = UUID()
        activeGeneration = generation
        return generation
    }

    func accepts(_ generation: UUID) -> Bool {
        activeGeneration == generation
    }

    mutating func invalidate() {
        activeGeneration = nil
    }
}

struct WatermarkCameraControls: Sendable {
    var zoom: CGFloat = 1
    var maximumZoom: CGFloat = 1
    var supportsFlash = false
    var supportsTorch = false
    var torchEnabled = false
    var isReady = false
    var message: String?
}

/// `AVCaptureSession` and all mutable capture state are confined to `sessionQueue`.
/// AVFoundation's delegate only extracts immutable `Data` and error text before re-entering
/// that queue. The unchecked marker bridges the Objective-C delegate API; queue preconditions
/// enforce the actual isolation invariant.
final class WatermarkCameraSession: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    typealias Completion = @MainActor @Sendable ([UIImage], Date, String?) -> Void

    private struct ActiveCapture {
        let generation: UUID
        let targetCount: Int
        let capturedAt: Date
        let flashMode: AVCaptureDevice.FlashMode
        let completion: Completion
        var photoData: [Data] = []
    }

    @Published private(set) var controls = WatermarkCameraControls()
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "watermark.camera.session")
    private var generationGate = WatermarkCameraCaptureGenerationGate()
    private var activeCapture: ActiveCapture?
    private var generationByPhotoSettingsID: [Int64: UUID] = [:]
    private var configurationErrorMessage: String?
    private var didAttemptConfiguration = false
    private var isConfigured = false
    private var cameraDevice: AVCaptureDevice?
    private var wantsRunning = false
    private var rotationAngle: CGFloat = 90
    private var queueControls = WatermarkCameraControls()
    private var notificationTokens: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            self?.sessionQueue.async { [weak self] in self?.handleInterruption(message: AppLocalization.string("相机暂时被占用，恢复后可继续拍摄")) }
        })
        notificationTokens.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.sessionQueue.async { [weak self] in self?.resumeIfNeeded() }
        })
        notificationTokens.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] _ in
            self?.sessionQueue.async { [weak self] in
                self?.handleInterruption(message: AppLocalization.string("相机发生中断，正在尝试恢复"))
                self?.resumeIfNeeded()
            }
        })
    }

    deinit {
        for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
    }

    private func publishControls() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        let state = queueControls
        Task { @MainActor [weak self] in self?.controls = state }
    }

    private func handleInterruption(message: String) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        queueControls.isReady = false
        queueControls.message = message
        publishControls()
        if let capture = activeCapture {
            finish(generation: capture.generation, capture: capture, error: message)
        }
    }

    private func resumeIfNeeded() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard wantsRunning, isConfigured, !session.isInterrupted else { return }
        if !session.isRunning { session.startRunning() }
        queueControls.isReady = session.isRunning
        queueControls.message = session.isRunning ? nil : AppLocalization.string("相机未能恢复，请点重试")
        publishControls()
    }

    func setRotationAngle(_ angle: CGFloat) {
        sessionQueue.async { [weak self] in self?.rotationAngle = angle }
    }

    func setZoom(_ zoom: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.cameraDevice else { return }
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = min(max(zoom, device.minAvailableVideoZoomFactor), self.queueControls.maximumZoom)
                self.queueControls.zoom = device.videoZoomFactor
                device.unlockForConfiguration()
                self.publishControls()
            } catch { self.reportControlError(error) }
        }
    }

    func setTorch(_ enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.cameraDevice, device.hasTorch, device.isTorchAvailable else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = enabled ? .on : .off
                device.unlockForConfiguration()
                self.queueControls.torchEnabled = enabled
                self.publishControls()
            } catch { self.reportControlError(error) }
        }
    }

    func focus(at point: CGPoint, exposureBias: Float? = nil) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.cameraDevice else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported, device.isFocusModeSupported(.autoFocus) {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }
                if device.isExposurePointOfInterestSupported, device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .continuousAutoExposure
                }
                if let exposureBias {
                    device.setExposureTargetBias(min(max(exposureBias, device.minExposureTargetBias), device.maxExposureTargetBias))
                }
                device.unlockForConfiguration()
            } catch { self.reportControlError(error) }
        }
    }

    private func reportControlError(_ error: Error) {
        queueControls.message = String(format: AppLocalization.string("相机设置失败：%@"), error.localizedDescription)
        publishControls()
    }

    func start(completion: @escaping @MainActor @Sendable (String?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.wantsRunning = true
            if !self.isConfigured, self.didAttemptConfiguration {
                self.session.beginConfiguration()
                for input in self.session.inputs { self.session.removeInput(input) }
                for output in self.session.outputs { self.session.removeOutput(output) }
                self.session.commitConfiguration()
                self.didAttemptConfiguration = false
            }
            self.configureIfNeeded()
            if self.isConfigured, !self.session.isRunning {
                self.session.startRunning()
            }
            self.queueControls.isReady = self.session.isRunning && !self.session.isInterrupted
            self.queueControls.message = self.configurationErrorMessage
            self.publishControls()
            let errorMessage = self.configurationErrorMessage
            Task { @MainActor in
                completion(errorMessage)
            }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            self.wantsRunning = false
            if let device = self.cameraDevice, device.hasTorch {
                if (try? device.lockForConfiguration()) != nil {
                    device.torchMode = .off
                    device.unlockForConfiguration()
                }
            }
            self.queueControls.torchEnabled = false
            self.queueControls.isReady = false
            self.publishControls()
            self.generationGate.invalidate()
            self.activeCapture = nil
            self.generationByPhotoSettingsID.removeAll()
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func capture(
        count: Int,
        flashMode: AVCaptureDevice.FlashMode,
        completion: @escaping Completion
    ) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded()
            guard self.isConfigured else {
                self.deliver(
                    photoData: [],
                    capturedAt: Date(),
                    error: self.configurationErrorMessage ?? AppLocalization.string("wm_camera_init_failed_error"),
                    completion: completion
                )
                return
            }
            guard self.session.isRunning, !self.session.isInterrupted, self.activeCapture == nil else {
                self.deliver(
                    photoData: [],
                    capturedAt: Date(),
                    error: AppLocalization.string("wm_camera_init_failed_error"),
                    completion: completion
                )
                return
            }
            let generation = self.generationGate.begin()
            self.activeCapture = ActiveCapture(
                generation: generation,
                targetCount: min(5, max(1, count)),
                capturedAt: Date(),
                flashMode: flashMode,
                completion: completion
            )
            self.captureOne(generation: generation)
        }
    }

    private func configureIfNeeded() {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard !isConfigured, !didAttemptConfiguration else { return }
        didAttemptConfiguration = true
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus == .denied || authStatus == .restricted {
            configurationErrorMessage = AppLocalization.string("wm_camera_permission_not_enabled_settings_error")
            return
        }
        if authStatus == .notDetermined {
            configurationErrorMessage = AppLocalization.string("wm_camera_permission_request_first_error")
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            configurationErrorMessage = AppLocalization.string("wm_camera_device_unavailable_error")
            session.commitConfiguration()
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                configurationErrorMessage = AppLocalization.string("wm_camera_add_input_failed_error")
                session.commitConfiguration()
                return
            }
        } catch {
            configurationErrorMessage = String(
                format: AppLocalization.string("wm_camera_input_failed_format"),
                error.localizedDescription
            )
            session.commitConfiguration()
            return
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        } else {
            configurationErrorMessage = AppLocalization.string("wm_camera_add_output_failed_error")
            session.commitConfiguration()
            return
        }
        if let bestDimensions = bestSupportedPhotoDimensions(from: camera.activeFormat) {
            photoOutput.maxPhotoDimensions = bestDimensions
        }
        session.commitConfiguration()
        configurationErrorMessage = nil
        isConfigured = true
        cameraDevice = camera
        queueControls.maximumZoom = max(1, min(6, camera.maxAvailableVideoZoomFactor))
        queueControls.supportsFlash = camera.hasFlash
        queueControls.supportsTorch = camera.hasTorch && camera.isTorchAvailable
        publishControls()
    }

    private func captureOne(generation: UUID) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard generationGate.accepts(generation),
              let activeCapture,
              activeCapture.generation == generation else { return }
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(activeCapture.flashMode) {
            settings.flashMode = activeCapture.flashMode
        }
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        generationByPhotoSettingsID[settings.uniqueID] = generation
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func bestSupportedPhotoDimensions(from format: AVCaptureDevice.Format) -> CMVideoDimensions? {
        let dimensions = format.supportedMaxPhotoDimensions
        let bounded = dimensions.filter { Int64($0.width) * Int64($0.height) <= 12_500_000 }
        return (bounded.isEmpty ? dimensions : bounded).min {
            let left = Int64($0.width) * Int64($0.height)
            let right = Int64($1.width) * Int64($1.height)
            return bounded.isEmpty ? left < right : left > right
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let settingsID = photo.resolvedSettings.uniqueID
        let photoData = error == nil ? photo.fileDataRepresentation() : nil
        let errorMessage = error.map {
            String(
                format: AppLocalization.string("wm_camera_capture_failed_format"),
                $0.localizedDescription
            )
        }
        sessionQueue.async { [weak self] in
            self?.handlePhotoResult(settingsID: settingsID, photoData: photoData, errorMessage: errorMessage)
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard let error else { return }
        let settingsID = resolvedSettings.uniqueID
        let message = String(format: AppLocalization.string("wm_camera_capture_failed_format"), error.localizedDescription)
        sessionQueue.async { [weak self] in
            self?.handlePhotoResult(settingsID: settingsID, photoData: nil, errorMessage: message)
        }
    }

    private func handlePhotoResult(settingsID: Int64, photoData: Data?, errorMessage: String?) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard let generation = generationByPhotoSettingsID.removeValue(forKey: settingsID),
              generationGate.accepts(generation),
              var capture = activeCapture,
              capture.generation == generation else { return }

        if let errorMessage {
            finish(generation: generation, capture: capture, error: errorMessage)
            return
        }
        guard let photoData else {
            finish(
                generation: generation,
                capture: capture,
                error: AppLocalization.string("wm_camera_corrupted_photo_data_error")
            )
            return
        }

        capture.photoData.append(photoData)
        activeCapture = capture
        if capture.photoData.count < capture.targetCount {
            sessionQueue.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.captureOne(generation: generation)
            }
        } else {
            finish(generation: generation, capture: capture, error: nil)
        }
    }

    private func finish(generation: UUID, capture: ActiveCapture, error: String?) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard generationGate.accepts(generation) else { return }
        generationGate.invalidate()
        activeCapture = nil
        generationByPhotoSettingsID = generationByPhotoSettingsID.filter { $0.value != generation }
        deliver(
            photoData: capture.photoData,
            capturedAt: capture.capturedAt,
            error: error,
            completion: capture.completion
        )
    }

    private func deliver(
        photoData: [Data],
        capturedAt: Date,
        error: String?,
        completion: @escaping Completion
    ) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        // Decode away from the main thread and bound peak pixel memory for repeated batches.
        let images = photoData.compactMap { data -> UIImage? in
            autoreleasepool {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 4096
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: image)
            }
        }
        let resultError = images.count == photoData.count ? error : (error ?? AppLocalization.string("wm_camera_corrupted_photo_data_error"))
        Task { @MainActor in completion(images, capturedAt, resultError) }
    }
}
