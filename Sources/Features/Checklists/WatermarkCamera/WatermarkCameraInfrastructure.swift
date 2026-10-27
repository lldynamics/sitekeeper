import SwiftUI
import UIKit
import AVFoundation

struct WatermarkCameraCaptureView: View {
    let watermarkContext: CameraWatermarkContext
    let showGrid: Bool
    let flashEnabled: Bool
    let burstCount: Int
    var referenceImage: UIImage? = nil
    var onDone: (() -> Void)? = nil
    let onCapture: @MainActor @Sendable ([UIImage], Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = WatermarkCameraSession()
    @State private var isCapturing = false
    @State private var captureError = ""
    @State private var showError = false
    @State private var appearanceID = UUID()
    @State private var isVisible = false
    @State private var totalCaptured = 0
    @State private var recentThumbnail: UIImage?
    @State private var flashMode: AVCaptureDevice.FlashMode = .off
    @State private var referenceVisible = true
    @State private var focusPoint = CGPoint(x: 0.5, y: 0.5)
    @State private var exposureBias: Float = 0
    @State private var previewRotationAngle: CGFloat = 90

    var body: some View {
        GeometryReader { _ in
            let isLandscape = previewRotationAngle == 0 || previewRotationAngle == 180
            VStack(spacing: 12) {
                header
                GeometryReader { canvas in
                    let frame = WatermarkCameraFraming.fittedSize(in: canvas.size, landscape: isLandscape)
                    ZStack {
                        WatermarkCameraPreview(session: camera.session, onRotation: { angle in
                            camera.setRotationAngle(angle)
                            if previewRotationAngle != angle {
                                Task { @MainActor in previewRotationAngle = angle }
                            }
                        }) { point in
                            focusPoint = point
                            camera.focus(at: point, exposureBias: exposureBias)
                        }
                        if referenceVisible, let referenceImage {
                            Image(uiImage: referenceImage).resizable().scaledToFill()
                                .opacity(0.3).allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        if showGrid { CameraGridOverlay() }
                        TimelineView(.periodic(from: .now, by: 1)) { timeline in
                            WatermarkCameraLiveOverlay(context: watermarkContext, capturedAt: timeline.date)
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(width: frame.width, height: frame.height)
                    .clipped()
                    .position(x: canvas.size.width / 2, y: canvas.size.height / 2)
                }
                controls
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(.black)
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isCapturing)
        .alert(AppLocalization.string("wm_camera_unavailable_alert_title"), isPresented: $showError) {
            Button(AppLocalization.string("wm_camera_ack_button"), role: .cancel) { }
            Button(AppLocalization.string("重试相机")) { startCamera() }
        } message: { Text(captureError) }
        .onAppear {
            isVisible = true
            flashMode = flashEnabled ? .on : .off
            startCamera()
        }
        .onDisappear {
            isVisible = false
            appearanceID = UUID()
            camera.stop()
        }
    }

    private var header: some View {
        HStack {
            Button(totalCaptured > 0 ? AppLocalization.string("完成") : AppLocalization.string("wm_camera_close_button")) {
                onDone?()
                dismiss()
            }
            .disabled(isCapturing)
            .accessibilityIdentifier("watermark.camera.done")
            Spacer()
            if camera.controls.supportsFlash {
                Menu {
                    Button(AppLocalization.string("自动闪光")) { flashMode = .auto }
                    Button(AppLocalization.string("闪光灯开")) { flashMode = .on }
                    Button(AppLocalization.string("闪光灯关")) { flashMode = .off }
                } label: {
                    Label(flashTitle, systemImage: flashMode == .off ? "bolt.slash.fill" : "bolt.fill")
                }
                .accessibilityLabel(String(format: AppLocalization.string("闪光灯，%@"), flashTitle))
            }
            if camera.controls.supportsTorch {
                Button {
                    camera.setTorch(!camera.controls.torchEnabled)
                } label: {
                    Image(systemName: camera.controls.torchEnabled ? "flashlight.on.fill" : "flashlight.off.fill")
                }
                .accessibilityLabel(camera.controls.torchEnabled ? AppLocalization.string("关闭补光灯") : AppLocalization.string("打开补光灯"))
                .frame(minWidth: 44, minHeight: 44)
            }
            if referenceImage != nil {
                Button { referenceVisible.toggle() } label: {
                    Image(systemName: referenceVisible ? "square.on.square" : "square")
                }
                .accessibilityLabel(referenceVisible ? AppLocalization.string("隐藏对照底图") : AppLocalization.string("显示对照底图"))
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .font(.subheadline)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if let message = camera.controls.message {
                HStack {
                    Text(message).font(.caption)
                    if !camera.controls.isReady { Button(AppLocalization.string("重试")) { startCamera() } }
                }
                .accessibilityElement(children: .combine)
            }
            if camera.controls.maximumZoom > 1 {
                HStack {
                    Text(String(format: "%.1f×", camera.controls.zoom)).monospacedDigit().frame(width: 44)
                    Slider(value: Binding(get: { camera.controls.zoom }, set: { camera.setZoom($0) }), in: 1...camera.controls.maximumZoom)
                        .accessibilityLabel(AppLocalization.string("相机变焦"))
                }
                .font(.caption)
            }
            HStack(spacing: 8) {
                Image(systemName: "sun.max")
                Slider(value: $exposureBias, in: -2...2) { _ in
                    camera.focus(at: focusPoint, exposureBias: exposureBias)
                }
                .accessibilityLabel(AppLocalization.string("曝光补偿"))
                .accessibilityValue(String(format: "%+.1f", exposureBias))
            }
            HStack {
                HStack(spacing: 8) {
                    if let recentThumbnail {
                        Image(uiImage: recentThumbnail).resizable().scaledToFill()
                            .frame(width: 44, height: 52).clipped().clipShape(RoundedRectangle(cornerRadius: 6))
                            .accessibilityLabel(AppLocalization.string("最近拍摄的照片"))
                    }
                    Text(String(format: AppLocalization.string("已拍 %lld 张"), Int64(totalCaptured))).font(.caption).monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: capture) {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 70, height: 70)
                        if isCapturing {
                            ProgressView().tint(.white)
                        } else {
                            Circle().fill(.white).frame(width: 58, height: 58)
                        }
                    }
                }
                .disabled(isCapturing || !camera.controls.isReady)
                .accessibilityLabel(isCapturing ? AppLocalization.string("正在拍摄，请稍候") : AppLocalization.string("拍照"))
                .accessibilityValue(String(format: AppLocalization.string("每次拍摄 %lld 张，累计 %lld 张"), Int64(burstCount), Int64(totalCaptured)))
                .accessibilityIdentifier("watermark.camera.shutter")
                Text(isCapturing ? AppLocalization.string("拍摄中…") : String(format: AppLocalization.string("连拍 %lld 张"), Int64(burstCount)))
                    .font(.caption).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .foregroundStyle(.white)
        .disabled(isCapturing)
    }

    private var flashTitle: String {
        switch flashMode {
        case .auto: return AppLocalization.string("自动")
        case .on: return AppLocalization.string("开")
        default: return AppLocalization.string("关")
        }
    }

    private func startCamera() {
        let currentAppearance = appearanceID
        camera.start { message in
            guard isVisible, appearanceID == currentAppearance else { return }
            if let message {
                captureError = message
                showError = true
            }
        }
    }

    private func capture() {
        guard !isCapturing else { return }
        isCapturing = true
        let currentAppearance = appearanceID
        camera.capture(count: burstCount, flashMode: flashMode) { images, capturedAt, errorMessage in
            guard isVisible, appearanceID == currentAppearance else { return }
            isCapturing = false
            // A later burst member can fail; completed photos must still enter the draft immediately.
            if !images.isEmpty {
                totalCaptured += images.count
                recentThumbnail = images.last?.preparingThumbnail(of: CGSize(width: 120, height: 160))
                onCapture(images, capturedAt)
            }
            if let errorMessage {
                captureError = images.isEmpty ? errorMessage : String(format: AppLocalization.string("已保留 %lld 张照片。%@"), Int64(images.count), errorMessage)
                showError = true
            } else if images.isEmpty {
                captureError = AppLocalization.string("wm_camera_capture_empty_result_error")
                showError = true
            }
        }
    }
}

struct WatermarkCameraFraming {
    static func fittedSize(in available: CGSize, landscape: Bool) -> CGSize {
        let ratio: CGFloat = landscape ? 4 / 3 : 3 / 4
        let width = max(0, min(available.width, available.height * ratio))
        return CGSize(width: width, height: width / ratio)
    }

    static func rotationAngle(for orientation: UIInterfaceOrientation) -> CGFloat {
        switch orientation {
        case .landscapeLeft: return 180
        case .landscapeRight: return 0
        case .portraitUpsideDown: return 270
        default: return 90
        }
    }
}

private struct WatermarkCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let onRotation: (CGFloat) -> Void
    let onFocus: (CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewContainerView {
        let view = PreviewContainerView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onRotation = onRotation
        view.onFocus = onFocus
        return view
    }

    func updateUIView(_ view: PreviewContainerView, context: Context) {
        view.onRotation = onRotation
        view.onFocus = onFocus
        view.setNeedsLayout()
    }
}

private final class PreviewContainerView: UIView {
    var onRotation: ((CGFloat) -> Void)?
    var onFocus: ((CGPoint) -> Void)?
    private let focusRing = UIView()

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(focus(_:))))
        focusRing.layer.borderColor = UIColor.systemYellow.cgColor
        focusRing.layer.borderWidth = 2
        focusRing.isUserInteractionEnabled = false
        focusRing.alpha = 0
        addSubview(focusRing)
        isAccessibilityElement = true
        accessibilityLabel = AppLocalization.string("相机预览，轻点画面对焦；可在下方调整曝光")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let angle = WatermarkCameraFraming.rotationAngle(for: window?.windowScene?.interfaceOrientation ?? .portrait)
        if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
        onRotation?(angle)
    }

    @objc private func focus(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: self)
        onFocus?(previewLayer.captureDevicePointConverted(fromLayerPoint: location))
        focusRing.layer.removeAllAnimations()
        focusRing.frame = CGRect(x: location.x - 30, y: location.y - 30, width: 60, height: 60)
        focusRing.alpha = 1
        UIView.animate(withDuration: 0.8, delay: 0.5, options: [.beginFromCurrentState]) { self.focusRing.alpha = 0 }
    }
}

private struct CameraGridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
                    path.move(to: CGPoint(x: geo.size.width * fraction, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width * fraction, y: geo.size.height))
                    path.move(to: CGPoint(x: 0, y: geo.size.height * fraction))
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height * fraction))
                }
            }
            .stroke(.white.opacity(0.4), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
