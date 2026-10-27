import SwiftUI
import UIKit
import CoreLocation
import AVFoundation

struct WatermarkCameraCaptureView: View {
    let watermarkContext: CameraWatermarkContext
    let showGrid: Bool
    let flashEnabled: Bool
    let burstCount: Int
    let onCapture: @MainActor @Sendable ([UIImage], Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = WatermarkCameraSession()
    @State private var isCapturing = false
    @State private var captureError = ""
    @State private var showError = false
    @State private var appearanceID = UUID()
    @State private var isVisible = false

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
                    Button(AppLocalization.string("wm_camera_close_button")) { dismiss() }
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
                    Text(String(format: AppLocalization.string("wm_camera_burst_count_indicator_format"), burstCount))
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
                        ? AppLocalization.string("wm_camera_flash_on_text")
                        : AppLocalization.string("wm_camera_flash_off_text")
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
        .alert(AppLocalization.string("wm_camera_unavailable_alert_title"), isPresented: $showError) {
            Button(AppLocalization.string("wm_camera_ack_button")) { dismiss() }
        } message: {
            Text(captureError)
        }
        .onAppear {
            isVisible = true
            let currentAppearance = appearanceID
            camera.start { message in
                guard isVisible, appearanceID == currentAppearance else { return }
                if let message {
                    captureError = message
                    showError = true
                }
            }
        }
        .onDisappear {
            isVisible = false
            appearanceID = UUID()
            camera.stop()
        }
    }

    private func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        let currentAppearance = appearanceID
        camera.capture(
            count: burstCount,
            flashMode: flashEnabled ? .on : .off
        ) { images, capturedAt, errorMessage in
            guard isVisible, appearanceID == currentAppearance else { return }
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
                captureError = AppLocalization.string("wm_camera_capture_empty_result_error")
                showError = true
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

@MainActor
final class WatermarkCameraLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var locationText = ""
    @Published var statusText = ""

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var geocodingGeneration = UUID()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocation() {
        geocodingGeneration = UUID()
        geocoder.cancelGeocode()
        guard CLLocationManager.locationServicesEnabled() else {
            statusText = AppLocalization.string("wm_camera_location_service_disabled")
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            statusText = AppLocalization.string("wm_camera_location_requesting_permission")
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            statusText = AppLocalization.string("wm_camera_location_fetching")
            manager.requestLocation()
        case .denied, .restricted:
            statusText = AppLocalization.string("wm_camera_location_permission_disabled")
        @unknown default:
            statusText = AppLocalization.string("wm_camera_location_unavailable")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorization = manager.authorizationStatus
        Task { @MainActor in
            if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
                self.manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latestLocation = locations.last else { return }
        let coordinate = latestLocation.coordinate
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        Task { @MainActor in
            self.resolveLocation(latitude: latitude, longitude: longitude)
        }
    }

    private func resolveLocation(latitude: Double, longitude: Double) {
        let generation = UUID()
        geocodingGeneration = generation
        geocoder.cancelGeocode()
        let latestLocation = CLLocation(latitude: latitude, longitude: longitude)
        let fallback = String(format: "%.5f, %.5f", latitude, longitude)
        geocoder.reverseGeocodeLocation(latestLocation) { [weak self] placemarks, _ in
            let readable = placemarks?.first.map { placemark in
                [placemark.administrativeArea, placemark.locality, placemark.subLocality,
                 placemark.thoroughfare, placemark.name]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }
            Task { @MainActor in
                guard let self, self.geocodingGeneration == generation else { return }
                if let readable {
                    if readable.isEmpty {
                        self.locationText = fallback
                    } else {
                        self.locationText = readable
                    }
                    self.statusText = AppLocalization.string("wm_camera_location_filled_current")
                } else {
                    self.locationText = fallback
                    self.statusText = AppLocalization.string("wm_camera_location_filled_coordinates")
                }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.statusText = AppLocalization.string("wm_camera_location_failed")
        }
    }
}
