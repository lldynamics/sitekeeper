import SwiftUI
import UIKit
import CoreLocation
import AVFoundation

struct WatermarkCameraCaptureView: View {
    let watermarkContext: CameraWatermarkContext
    let showGrid: Bool
    let flashEnabled: Bool
    let burstCount: Int
    let onCapture: ([UIImage], Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = WatermarkCameraSession()
    @State private var isCapturing = false
    @State private var captureError = ""
    @State private var showError = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            WatermarkCameraPreview(session: camera.session)
                .ignoresSafeArea()

            if showGrid {
                CameraGridOverlay()
                    .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                HStack {
                    Button(String(localized: "wm_camera_close_button")) { dismiss() }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.35), in: Capsule())
                    Spacer()
                }
                .padding(.top, 18)
                .padding(.horizontal, 14)

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(watermarkContext.lines(capturedAt: context.date), id: \.self) { line in
                            Text(line)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(10)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

                HStack(spacing: 16) {
                    Text(String(format: String(localized: "wm_camera_burst_count_indicator_format"), burstCount))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.35), in: Capsule())

                    Button {
                        capture()
                    } label: {
                        ZStack {
                            Circle().fill(.white).frame(width: 74, height: 74)
                            Circle().stroke(.appWarning, lineWidth: 4).frame(width: 62, height: 62)
                        }
                    }
                    .disabled(isCapturing)

                    Text(
                        flashEnabled
                        ? String(localized: "wm_camera_flash_on_text")
                        : String(localized: "wm_camera_flash_off_text")
                    )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.35), in: Capsule())
                }
                .padding(.bottom, 28)
            }
        }
        .alert(String(localized: "wm_camera_unavailable_alert_title"), isPresented: $showError) {
            Button(String(localized: "wm_camera_ack_button")) { dismiss() }
        } message: {
            Text(captureError)
        }
        .onAppear {
            camera.start()
            if let message = camera.lastErrorMessage {
                captureError = message
                showError = true
            }
        }
        .onDisappear {
            camera.stop()
        }
    }

    private func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        camera.capture(
            count: burstCount,
            flashMode: flashEnabled ? .on : .off
        ) { images, capturedAt, errorMessage in
            Task { @MainActor in
                isCapturing = false
                if let errorMessage {
                    captureError = errorMessage
                    showError = true
                    return
                }
                if !images.isEmpty {
                    onCapture(images, capturedAt)
                    dismiss()
                } else {
                    captureError = String(localized: "wm_camera_capture_empty_result_error")
                    showError = true
                }
            }
        }
    }
}

private struct WatermarkCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewContainerView, context: Context) {
        uiView.previewLayer.session = session
    }
}

private final class PreviewContainerView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
            assertionFailure("PreviewContainerView layer is not AVCaptureVideoPreviewLayer")
            return AVCaptureVideoPreviewLayer()
        }
        return previewLayer
    }
}

private final class WatermarkCameraSession: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "watermark.camera.session")
    private var completion: (([UIImage], Date, String?) -> Void)?
    private var targetCount = 1
    private var capturedImages: [UIImage] = []
    private var capturedAt = Date()
    private var currentFlashMode: AVCaptureDevice.FlashMode = .off
    private(set) var lastErrorMessage: String?
    private var isConfigured = false

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded()
            guard self.isConfigured else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func capture(
        count: Int,
        flashMode: AVCaptureDevice.FlashMode,
        completion: @escaping ([UIImage], Date, String?) -> Void
    ) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureIfNeeded()
            guard self.isConfigured else {
                completion([], Date(), self.lastErrorMessage ?? String(localized: "wm_camera_init_failed_error"))
                return
            }
            self.completion = completion
            self.targetCount = max(1, count)
            self.capturedImages = []
            self.capturedAt = Date()
            self.currentFlashMode = flashMode
            self.captureOne()
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if authStatus == .denied || authStatus == .restricted {
            lastErrorMessage = String(localized: "wm_camera_permission_not_enabled_settings_error")
            return
        }
        if authStatus == .notDetermined {
            lastErrorMessage = String(localized: "wm_camera_permission_request_first_error")
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            lastErrorMessage = String(localized: "wm_camera_device_unavailable_error")
            session.commitConfiguration()
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                lastErrorMessage = String(localized: "wm_camera_add_input_failed_error")
                session.commitConfiguration()
                return
            }
        } catch {
            lastErrorMessage = String(
                format: String(localized: "wm_camera_input_failed_format"),
                error.localizedDescription
            )
            session.commitConfiguration()
            return
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        } else {
            lastErrorMessage = String(localized: "wm_camera_add_output_failed_error")
            session.commitConfiguration()
            return
        }
        if let bestDimensions = bestSupportedPhotoDimensions(from: camera.activeFormat) {
            photoOutput.maxPhotoDimensions = bestDimensions
        }
        session.commitConfiguration()
        isConfigured = true
    }

    private func captureOne() {
        let settings = AVCapturePhotoSettings()
        if photoOutput.supportedFlashModes.contains(currentFlashMode) {
            settings.flashMode = currentFlashMode
        }
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
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
        if let error {
            finish(
                error: String(
                    format: String(localized: "wm_camera_capture_failed_format"),
                    error.localizedDescription
                )
            )
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            finish(error: String(localized: "wm_camera_corrupted_photo_data_error"))
            return
        }
        capturedImages.append(image)
        if capturedImages.count < targetCount {
            sessionQueue.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.captureOne()
            }
        } else {
            finish(error: nil)
        }
    }

    private func finish(error: String?) {
        let completion = self.completion
        self.completion = nil
        completion?(capturedImages, capturedAt, error)
    }
}

private struct CameraGridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                let x1 = w / 3
                let x2 = w * 2 / 3
                let y1 = h / 3
                let y2 = h * 2 / 3
                path.move(to: CGPoint(x: x1, y: 0))
                path.addLine(to: CGPoint(x: x1, y: h))
                path.move(to: CGPoint(x: x2, y: 0))
                path.addLine(to: CGPoint(x: x2, y: h))
                path.move(to: CGPoint(x: 0, y: y1))
                path.addLine(to: CGPoint(x: w, y: y1))
                path.move(to: CGPoint(x: 0, y: y2))
                path.addLine(to: CGPoint(x: w, y: y2))
            }
            .stroke(Color.appStrokeLightOverlay, lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

final class WatermarkCameraLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var locationText = ""
    @Published var statusText = ""

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        guard CLLocationManager.locationServicesEnabled() else {
            statusText = String(localized: "wm_camera_location_service_disabled")
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            statusText = String(localized: "wm_camera_location_requesting_permission")
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            statusText = String(localized: "wm_camera_location_fetching")
            manager.requestLocation()
        case .denied, .restricted:
            statusText = String(localized: "wm_camera_location_permission_disabled")
        @unknown default:
            statusText = String(localized: "wm_camera_location_unavailable")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.last else { return }
        let coordinate = latestLocation.coordinate
        let fallback = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        geocoder.reverseGeocodeLocation(latestLocation) { [weak self] placemarks, _ in
            Task { @MainActor in
                guard let self else { return }
                if let placemark = placemarks?.first {
                    let readable = [
                        placemark.administrativeArea,
                        placemark.locality,
                        placemark.subLocality,
                        placemark.thoroughfare,
                        placemark.name
                    ]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                    if readable.isEmpty {
                        self.locationText = fallback
                    } else {
                        self.locationText = readable
                    }
                    self.statusText = String(localized: "wm_camera_location_filled_current")
                } else {
                    self.locationText = fallback
                    self.statusText = String(localized: "wm_camera_location_filled_coordinates")
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusText = String(localized: "wm_camera_location_failed")
    }
}
