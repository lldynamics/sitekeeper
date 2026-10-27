import Foundation
import Combine
import UIKit
import AVFoundation

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

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "watermark.camera.session")
    private var generationGate = WatermarkCameraCaptureGenerationGate()
    private var activeCapture: ActiveCapture?
    private var generationByPhotoSettingsID: [Int64: UUID] = [:]
    private var configurationErrorMessage: String?
    private var didAttemptConfiguration = false
    private var isConfigured = false

    func start(completion: @escaping @MainActor @Sendable (String?) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded()
            if self.isConfigured, !self.session.isRunning {
                self.session.startRunning()
            }
            let errorMessage = self.configurationErrorMessage
            Task { @MainActor in
                completion(errorMessage)
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
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
            guard self.activeCapture == nil else {
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
                targetCount: max(1, count),
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
    }

    private func captureOne(generation: UUID) {
        dispatchPrecondition(condition: .onQueue(sessionQueue))
        guard generationGate.accepts(generation),
              let activeCapture,
              activeCapture.generation == generation else { return }
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(activeCapture.flashMode) {
            settings.flashMode = activeCapture.flashMode
        }
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        generationByPhotoSettingsID[settings.uniqueID] = generation
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    private func bestSupportedPhotoDimensions(from format: AVCaptureDevice.Format) -> CMVideoDimensions? {
        var result: CMVideoDimensions?
        var maxPixelCount = 0
        for dimensions in format.supportedMaxPhotoDimensions {
            let pixelCount = Int(dimensions.width) * Int(dimensions.height)
            if pixelCount > maxPixelCount {
                maxPixelCount = pixelCount
                result = dimensions
            }
        }
        return result
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
        Task { @MainActor in
            completion(photoData.compactMap { UIImage(data: $0) }, capturedAt, error)
        }
    }
}
