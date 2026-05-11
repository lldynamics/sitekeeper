import SwiftUI
import UniformTypeIdentifiers
import UIKit
import CoreLocation
import Photos
import AVFoundation

struct WatermarkCameraToolView: View {
    @Environment(DataStore.self) private var store
    let initialProjectId: UUID?
    let autoOpenCameraOnAppear: Bool
    @State private var selectedProjectId: UUID?
    @AppStorage("watermarkCameraSelectedProjectId") private var selectedProjectIdRaw = ""
    @AppStorage("watermarkCameraProjectName") private var projectName = ""
    @AppStorage("watermarkCameraPhotographer") private var photographer = ""
    @AppStorage("watermarkCameraLocationText") private var locationText = ""
    @AppStorage("watermarkCameraTemplateRaw") private var templateRaw = CameraWatermarkTemplate.constructionLog.rawValue
    @AppStorage("watermarkCameraTag") private var tag = "现场记录"
    @AppStorage("watermarkCameraAutoSaveToAlbum") private var autoSaveToAlbum = false
    @AppStorage("watermarkCameraAutoOpenLogDraft") private var autoOpenLogDraft = false
    @AppStorage("watermarkCameraExportQualityRaw") private var exportQualityRaw = WatermarkExportQuality.standard.rawValue
    @AppStorage("watermarkCameraShowGrid") private var showGrid = true
    @AppStorage("watermarkCameraFlashEnabled") private var flashEnabled = false
    @AppStorage("watermarkCameraBurstCount") private var burstCount = 1
    @State private var showCamera = false
    @State private var capturedPhoto: WatermarkCapturedPhoto?
    @State private var exportData = Data()
    @State private var showExporter = false
    @State private var alertTitle = "无法继续"
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var savingToAlbum = false
    @State private var showWatermarkSettings = false
    @State private var didAutoOpenCamera = false
    @State private var showLogDraft = false
    @State private var toast: WatermarkToast?
    @StateObject private var locationManager = WatermarkCameraLocationManager()

    init(initialProjectId: UUID? = nil, autoOpenCameraOnAppear: Bool = false) {
        self.initialProjectId = initialProjectId
        self.autoOpenCameraOnAppear = autoOpenCameraOnAppear
        _selectedProjectId = State(initialValue: initialProjectId)
    }

    private var template: CameraWatermarkTemplate {
        get { StringEnumFallback.value(templateRaw, default: CameraWatermarkTemplate.constructionLog) }
        set { templateRaw = newValue.rawValue }
    }

    private var templateBinding: Binding<CameraWatermarkTemplate> {
        Binding(
            get: { template },
            set: { templateRaw = $0.rawValue }
        )
    }

    private var exportQuality: WatermarkExportQuality {
        get { StringEnumFallback.value(exportQualityRaw, default: WatermarkExportQuality.standard) }
        set { exportQualityRaw = newValue.rawValue }
    }

    private var exportQualityBinding: Binding<WatermarkExportQuality> {
        Binding(
            get: { exportQuality },
            set: { exportQualityRaw = $0.rawValue }
        )
    }

    private var boundedBurstCount: Int {
        min(5, max(1, burstCount))
    }

    var body: some View {
        Form {
            Section {
                ProjectContextStrip(
                    title: "当前工程",
                    projects: store.projects,
                    selectedProjectId: $selectedProjectId,
                    emptyText: "不关联项目"
                )
            }

            Section("拍摄") {
                Button {
                    openCamera()
                } label: {
                    Label("拍摄水印照片", systemImage: "camera.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)

                Text(effectiveProjectName.map { "当前水印工程：\($0)" } ?? "当前未指定工程，可在水印设置中选择或手填。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                DisclosureGroup(isExpanded: $showWatermarkSettings) {
                    Picker("关联工程", selection: $selectedProjectId) {
                        Text("不关联项目").tag(nil as UUID?)
                        ForEach(store.projects) { project in
                            Text(project.name).tag(project.id as UUID?)
                        }
                    }
                    TextField("工程名称（未选项目时填写）", text: $projectName)
                    Picker("水印模板", selection: templateBinding) {
                        ForEach(CameraWatermarkTemplate.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    TextField("标签", text: $tag)
                    TextField("拍摄人", text: $photographer)
                    HStack {
                        TextField("定位/位置", text: $locationText)
                        Button {
                            locationManager.requestLocation()
                        } label: {
                            Image(systemName: "location.fill").visibleIconStyle()
                        }
                        .buttonStyle(.appIcon())
                    }
                    Picker("导出画质", selection: exportQualityBinding) {
                        ForEach(WatermarkExportQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                    Toggle("拍完自动保存到相册", isOn: $autoSaveToAlbum)
                    Toggle("拍完自动进入施工日志草稿", isOn: $autoOpenLogDraft)
                    Toggle("相机显示网格线", isOn: $showGrid)
                    Toggle("默认开启闪光灯", isOn: $flashEnabled)
                    Stepper("连拍张数：\(boundedBurstCount)", value: $burstCount, in: 1...5)
                    if !locationManager.statusText.isEmpty {
                        Text(locationManager.statusText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Label("水印设置", systemImage: "slider.horizontal.3")
                }
            }

            if capturedPhoto != nil {
                Section("照片去向") {
                    Button {
                        saveCurrentImageToAlbum()
                    } label: {
                        Label(savingToAlbum ? "正在保存到相册" : "保存到相册", systemImage: "photo.on.rectangle.angled")
                    }
                    .disabled(savingToAlbum)

                    Button {
                        saveCurrentImageAsProjectDocument()
                    } label: {
                        Label("附到项目资料", systemImage: "folder.badge.plus")
                    }
                    .disabled(selectedProjectId == nil)

                    if let logSeedPhoto {
                        NavigationLink {
                            DailyLogView(
                                initialProjectId: selectedProjectId,
                                autoOpenComposer: true,
                                initialPhotoDrafts: [logSeedPhoto],
                                initialContent: logDraftContent
                            )
                        } label: {
                            Label("进入施工日志草稿", systemImage: "book.pages.fill")
                        }
                    }

                    if let todoSeedData {
                        NavigationLink {
                            SiteTodoView(
                                initialProjectId: selectedProjectId,
                                autoOpenComposer: true,
                                initialBeforePhotoData: todoSeedData
                            )
                        } label: {
                            Label("转为整改前待办", systemImage: "checklist")
                        }
                        .disabled(selectedProjectId == nil)

                        NavigationLink {
                            SiteTodoView(
                                initialProjectId: selectedProjectId,
                                autoOpenComposer: true,
                                initialAfterPhotoData: todoSeedData
                            )
                        } label: {
                            Label("转为整改后待办", systemImage: "checkmark.seal.fill")
                        }
                        .disabled(selectedProjectId == nil)
                    }

                    Button {
                        exportCurrentImage()
                    } label: {
                        Label("导出 JPEG（\(exportQuality.displayName)）", systemImage: "square.and.arrow.up")
                    }

                    Button("清空当前照片", role: .destructive) {
                        capturedPhoto = nil
                    }
                }
            }

            Section("预览") {
                if let capturedPhoto {
                    Image(uiImage: capturedPhoto.image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("拍摄时间：\(Formatters.dateTime.string(from: capturedPhoto.capturedAt))")
                            .fontWeight(.semibold)
                        Text(effectiveProjectName == nil ? "工程：未指定项目" : "工程：\(effectiveProjectName ?? "")")
                        Text("模板：\(template.displayName)")
                        Text("标签：\(tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : tag)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("还没有照片", systemImage: "camera.aperture", description: Text("拍摄后可直接导出带水印的 JPEG。"))
                }
            }
        }
        .navigationTitle("水印相机")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCamera) {
            WatermarkCameraCaptureView(
                watermarkContext: currentContext,
                showGrid: showGrid,
                flashEnabled: flashEnabled,
                burstCount: boundedBurstCount
            ) { image, capturedAt in
                handleCapturedImage(image, capturedAt: capturedAt)
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportData),
            contentType: .jpeg,
            defaultFilename: exportFileName
        ) { _ in }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .navigationDestination(isPresented: $showLogDraft) {
            if let logSeedPhoto {
                DailyLogView(
                    initialProjectId: selectedProjectId,
                    autoOpenComposer: true,
                    initialPhotoDrafts: [logSeedPhoto],
                    initialContent: logDraftContent
                )
            } else {
                ContentUnavailableView("暂无日志草稿", systemImage: "book.pages", description: Text("请先拍摄一张水印照片。"))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if capturedPhoto != nil {
                WatermarkQuickActionsBar(
                    canAttachToProject: selectedProjectId != nil,
                    onRetake: openCamera,
                    onSaveAlbum: saveCurrentImageToAlbum,
                    onAttachProject: saveCurrentImageAsProjectDocument,
                    onOpenLogDraft: {
                        if logSeedPhoto != nil {
                            showLogDraft = true
                        }
                    },
                    onExport: exportCurrentImage
                )
            }
        }
        .overlay(alignment: .top) {
            if let toast {
                WatermarkToastView(toast: toast)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: locationManager.locationText) { _, newValue in
            if !newValue.isEmpty {
                locationText = newValue
            }
        }
        .onChange(of: selectedProjectId) { _, newValue in
            selectedProjectIdRaw = newValue?.uuidString ?? ""
            guard let project = newValue.flatMap({ id in store.projects.first { $0.id == id } }) else { return }
            projectName = project.name
        }
        .onChange(of: burstCount) { _, newValue in
            burstCount = min(5, max(1, newValue))
        }
        .animation(.easeInOut(duration: 0.2), value: toast?.id)
        .onAppear {
            if let initialProjectId {
                selectedProjectId = initialProjectId
            } else if selectedProjectId == nil, let restored = UUID(uuidString: selectedProjectIdRaw) {
                selectedProjectId = restored
            }
            burstCount = min(5, max(1, burstCount))
            guard autoOpenCameraOnAppear, !didAutoOpenCamera else { return }
            didAutoOpenCamera = true
            openCamera()
        }
    }

    private var currentContext: CameraWatermarkContext {
        CameraWatermarkContext(
            projectName: effectiveProjectName,
            template: template.rawValue,
            tag: tag,
            photographer: photographer,
            locationText: locationText
        )
    }

    private var effectiveProjectName: String? {
        if let selectedProjectId,
           let project = store.projects.first(where: { $0.id == selectedProjectId }) {
            return project.name
        }
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var exportFileName: String {
        let base = effectiveProjectName ?? "水印照片"
        let safe = base.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return "\(safe)_\(Formatters.compactTimestamp(from: capturedPhoto?.capturedAt ?? Date()))"
    }

    private var logSeedPhoto: DailyLogSeedPhoto? {
        guard let capturedPhoto,
              let data = todoSeedData else { return nil }
        return DailyLogSeedPhoto(
            data: data,
            note: watermarkPhotoNote(capturedAt: capturedPhoto.capturedAt),
            tag: PhotoTag(rawValue: tag.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .general,
            capturedAt: capturedPhoto.capturedAt
        )
    }

    private var todoSeedData: Data? {
        capturedPhoto?.image.jpegData(compressionQuality: max(0.82, exportQuality.compression - 0.06))
    }

    private var logDraftContent: String {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTag.isEmpty {
            return "水印照片记录"
        }
        return "水印照片记录：\(trimmedTag)"
    }

    private func handleCapturedImage(_ image: UIImage, capturedAt: Date) {
        let output = image.applyingCameraWatermark(context: currentContext, capturedAt: capturedAt)
        capturedPhoto = WatermarkCapturedPhoto(image: output, capturedAt: capturedAt)
        presentToast("已拍摄 \(boundedBurstCount > 1 ? "连拍" : "照片")，可继续处理。", style: .success)
        if autoSaveToAlbum {
            saveCurrentImageToAlbum()
        }
        if autoOpenLogDraft, selectedProjectId != nil, logSeedPhoto != nil {
            showLogDraft = true
        }
    }

    private func openCamera() {
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            presentBlockingError("当前设备不可用相机。")
            return
        }
        Task { @MainActor in
            let isGranted = await requestCameraAccessIfNeeded()
            guard isGranted else {
                presentBlockingError("未获得相机权限，无法拍摄。")
                return
            }
            showCamera = true
        }
    }

    private func requestCameraAccessIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    continuation.resume(returning: granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func exportCurrentImage() {
        guard let image = capturedPhoto?.image,
              let data = image.jpegData(compressionQuality: exportQuality.compression) else {
            presentError("照片导出失败。")
            return
        }
        exportData = data
        showExporter = true
    }

    private func saveCurrentImageToAlbum() {
        guard let image = capturedPhoto?.image else {
            presentError("请先拍摄水印照片。")
            return
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            writeImageToAlbum(image)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                Task { @MainActor in
                    if newStatus == .authorized || newStatus == .limited {
                        writeImageToAlbum(image)
                    } else {
                        presentError("没有相册写入权限，无法保存。")
                    }
                }
            }
        case .denied, .restricted:
            presentError("没有相册写入权限，请到系统设置中开启。")
        @unknown default:
            presentError("无法确认相册权限。")
        }
    }

    private func writeImageToAlbum(_ image: UIImage) {
        savingToAlbum = true
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, error in
            Task { @MainActor in
                savingToAlbum = false
                if success {
                    presentInfo("已保存到相册。")
                } else {
                    presentError("保存到相册失败：\(error?.localizedDescription ?? "未知错误")")
                }
            }
        }
    }

    private func watermarkPhotoNote(capturedAt: Date) -> String {
        [
            "来源: 水印相机",
            "拍摄时间: \(Formatters.dateTime.string(from: capturedAt))",
            photographer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "拍摄人: \(photographer)",
            locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "位置: \(locationText)",
            tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "标签: \(tag)"
        ].compactMap { $0 }.joined(separator: "\n")
    }

    @MainActor
    private func saveCurrentImageAsProjectDocument() {
        guard let selectedProjectId else {
            presentError("请先选择要附加的工程。")
            return
        }
        guard let capturedPhoto else {
            presentError("请先拍摄水印照片。")
            return
        }
        let error = ProjectDetailFinanceDocumentActions.importCapturedImage(
            capturedPhoto.image,
            title: "水印照片-\(Formatters.dateTime.string(from: capturedPhoto.capturedAt))",
            createdAt: Formatters.dateTime.string(from: capturedPhoto.capturedAt),
            category: .construction,
            note: watermarkPhotoNote(capturedAt: capturedPhoto.capturedAt),
            projectId: selectedProjectId,
            store: store
        )
        if let error {
            presentError(error)
        } else {
            presentInfo("已附到项目资料。")
        }
    }

    private func presentInfo(_ message: String) {
        presentToast(message, style: .success)
    }

    private func presentError(_ message: String) {
        presentToast(message, style: .error)
    }

    private func presentBlockingError(_ message: String) {
        alertTitle = "无法继续"
        alertMessage = message
        showAlert = true
    }

    private func presentToast(_ message: String, style: WatermarkToastStyle) {
        let toast = WatermarkToast(message: message, style: style)
        withAnimation {
            self.toast = toast
        }
        Task { @MainActor in
            guard await DebouncedTask.wait(for: .seconds(2)) else { return }
            guard self.toast?.id == toast.id else { return }
            withAnimation {
                self.toast = nil
            }
        }
    }
}

private struct WatermarkCapturedPhoto {
    let image: UIImage
    let capturedAt: Date
}

private enum WatermarkExportQuality: String, CaseIterable {
    case standard
    case high

    var displayName: String {
        switch self {
        case .standard:
            return "标准"
        case .high:
            return "高清"
        }
    }

    var compression: CGFloat {
        switch self {
        case .standard:
            return 0.88
        case .high:
            return 0.96
        }
    }
}

private enum WatermarkToastStyle {
    case success
    case error

    var tint: Color {
        switch self {
        case .success:
            return .green
        case .error:
            return .red
        }
    }

    var icon: String {
        switch self {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

private struct WatermarkToast: Identifiable {
    let id = UUID()
    let message: String
    let style: WatermarkToastStyle
}

private struct WatermarkToastView: View {
    let toast: WatermarkToast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.style.icon)
                .font(.callout.weight(.semibold))
            Text(toast.message)
                .font(.callout)
                .lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(toast.style.tint.opacity(0.92))
        )
    }
}

private struct WatermarkQuickActionsBar: View {
    let canAttachToProject: Bool
    let onRetake: () -> Void
    let onSaveAlbum: () -> Void
    let onAttachProject: () -> Void
    let onOpenLogDraft: () -> Void
    let onExport: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                quickButton("再拍一张", icon: "camera.fill", action: onRetake)
                quickButton("保存相册", icon: "photo.on.rectangle.angled", action: onSaveAlbum)
                quickButton("附到项目", icon: "folder.badge.plus", disabled: !canAttachToProject, action: onAttachProject)
                quickButton("写日志", icon: "book.pages.fill", action: onOpenLogDraft)
                quickButton("导出", icon: "square.and.arrow.up", action: onExport)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    private func quickButton(
        _ title: String,
        icon: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(disabled)
    }
}

private struct WatermarkCameraCaptureView: View {
    let watermarkContext: CameraWatermarkContext
    let showGrid: Bool
    let flashEnabled: Bool
    let burstCount: Int
    let onCapture: (UIImage, Date) -> Void

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
                    Button("关闭") { dismiss() }
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
                    Text("连拍 x\(burstCount)")
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
                            Circle().stroke(.orange, lineWidth: 4).frame(width: 62, height: 62)
                        }
                    }
                    .disabled(isCapturing)

                    Text(flashEnabled ? "闪光: 开" : "闪光: 关")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.35), in: Capsule())
                }
                .padding(.bottom, 28)
            }
        }
        .alert("相机不可用", isPresented: $showError) {
            Button("知道了") { dismiss() }
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
                if let image = images.last {
                    onCapture(image, capturedAt)
                    dismiss()
                } else {
                    captureError = "未获取到照片，请重试。"
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
                completion([], Date(), self.lastErrorMessage ?? "相机初始化失败。")
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
            lastErrorMessage = "相机权限未开启，请到系统设置中允许访问相机。"
            return
        }
        if authStatus == .notDetermined {
            lastErrorMessage = "请先授权相机权限，再重新打开相机。"
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            lastErrorMessage = "当前设备不可用相机。"
            session.commitConfiguration()
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: camera)
            if session.canAddInput(input) {
                session.addInput(input)
            } else {
                lastErrorMessage = "无法添加相机输入。"
                session.commitConfiguration()
                return
            }
        } catch {
            lastErrorMessage = "相机输入失败：\(error.localizedDescription)"
            session.commitConfiguration()
            return
        }

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        } else {
            lastErrorMessage = "无法添加相机输出。"
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
            finish(error: "拍摄失败：\(error.localizedDescription)")
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            finish(error: "照片数据损坏，请重试。")
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

private final class WatermarkCameraLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
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
            statusText = "定位服务未开启"
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            statusText = "正在请求定位权限"
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            statusText = "正在获取当前位置"
            manager.requestLocation()
        case .denied, .restricted:
            statusText = "定位权限未开启，可手动填写位置"
        @unknown default:
            statusText = "无法获取定位，可手动填写位置"
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
                    self.statusText = "已填入当前位置"
                } else {
                    self.locationText = fallback
                    self.statusText = "已填入经纬度位置"
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        statusText = "定位失败，可手动填写位置"
    }
}

private extension Formatters {
    static func compactTimestamp(from date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }
}
