import SwiftUI
import UniformTypeIdentifiers
import UIKit
import CoreLocation
import Photos
import AVFoundation

struct WatermarkCameraToolView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.openURL) private var openURL
    let initialProjectId: UUID?
    let autoOpenCameraOnAppear: Bool
    @State private var selectedProjectId: UUID?
    @AppStorage("watermarkCameraSelectedProjectId") private var selectedProjectIdRaw = ""
    @AppStorage("watermarkCameraProjectName") private var projectName = ""
    @AppStorage("watermarkCameraPhotographer") private var photographer = ""
    @AppStorage("watermarkCameraLocationText") private var locationText = ""
    @AppStorage("watermarkCameraTemplateRaw") private var templateRaw = CameraWatermarkTemplate.constructionLog.rawValue
    @AppStorage("watermarkCameraTag") private var tag = "现场记录"
    @AppStorage("watermarkCameraAutoSaveToAlbum") private var autoSaveToAlbum = true
    @AppStorage("watermarkCameraAutoOpenLogDraft") private var autoOpenLogDraft = false
    @AppStorage("watermarkCameraExportQualityRaw") private var exportQualityRaw = WatermarkExportQuality.standard.rawValue
    @AppStorage("watermarkCameraShowGrid") private var showGrid = true
    @AppStorage("watermarkCameraFlashEnabled") private var flashEnabled = false
    @AppStorage("watermarkCameraBurstCount") private var burstCount = 1
    @State private var showCamera = false
    @State private var capturedPhotos: [WatermarkCapturedPhoto] = []
    @State private var selectedCapturedPhotoID: UUID?
    @State private var exportData = Data()
    @State private var showExporter = false
    @State private var alertTitle = "无法继续"
    @State private var alertMessage = ""
    @State private var alertSettingsURL: URL?
    @State private var showAlert = false
    @State private var savingToAlbum = false
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

    private var capturedPhoto: WatermarkCapturedPhoto? {
        if let selectedCapturedPhotoID,
           let selected = capturedPhotos.first(where: { $0.id == selectedCapturedPhotoID }) {
            return selected
        }
        return capturedPhotos.first
    }

    private var hasMultipleCapturedPhotos: Bool {
        capturedPhotos.count > 1
    }

    private var selectedCapturedPhotoNumber: Int {
        guard let id = capturedPhoto?.id,
              let index = capturedPhotos.firstIndex(where: { $0.id == id }) else {
            return 1
        }
        return index + 1
    }

    var body: some View {
        Form {
            projectSection
            templateSection
            captureSection
            watermarkInfoSection
            cameraSettingsSection
            autoSaveSection
            recentCaptureSection
        }
        .navigationTitle("水印相机")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCamera) {
            WatermarkCameraCaptureView(
                watermarkContext: currentContext,
                showGrid: showGrid,
                flashEnabled: flashEnabled,
                burstCount: boundedBurstCount
            ) { images, capturedAt in
                handleCapturedImages(images, capturedAt: capturedAt)
            }
        }
        .fileExporter(
            isPresented: $showExporter,
            document: ExportDocument(data: exportData),
            contentType: .jpeg,
            defaultFilename: exportFileName
        ) { result in
            switch result {
            case .success:
                presentInfo("照片已导出。")
            case .failure(let error):
                presentError("照片导出失败：\(error.localizedDescription)")
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            if let alertSettingsURL {
                Button("前往设置") {
                    openURL(alertSettingsURL)
                }
            }
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
        .overlay(alignment: .top) {
            if let toast {
                WatermarkToastView(toast: toast)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
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
        .onReceive(locationManager.$locationText) { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            locationText = trimmed
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

    private var projectSection: some View {
        Section {
            ProjectContextStrip(
                title: "当前工程",
                projects: store.projects,
                selectedProjectId: $selectedProjectId,
                emptyText: "不关联项目"
            )
        }
    }

    private var templateSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CameraWatermarkTemplate.allCases, id: \.rawValue) { tmpl in
                        let isSelected = templateRaw == tmpl.rawValue
                        Button {
                            templateRaw = tmpl.rawValue
                        } label: {
                            WatermarkTemplateChip(
                                title: tmpl.displayName,
                                systemImage: tmpl.icon,
                                isSelected: isSelected
                            )
                        }
                    }
                }
            }
        } header: {
            Label("水印模板", systemImage: "rectangle.and.pencil.and.ellipsis")
        }
    }

    private var captureSection: some View {
        Section {
            Button {
                openCamera()
            } label: {
                Label("拍摄水印照片", systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.appProminent())
        }
    }

    private var watermarkInfoSection: some View {
        Section {
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
            if !locationStatusText.isEmpty {
                Text(locationStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Label("水印信息", systemImage: "info.circle")
        }
    }

    private var cameraSettingsSection: some View {
        Section {
            DisclosureGroup {
                Picker("导出画质", selection: exportQualityBinding) {
                    ForEach(WatermarkExportQuality.allCases, id: \.self) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                Toggle("相机网格线", isOn: $showGrid)
                Toggle("默认闪光灯", isOn: $flashEnabled)
                Stepper("连拍张数：\(boundedBurstCount)", value: $burstCount, in: 1...5)
            } label: {
                Label("相机设置", systemImage: "camera.fill")
            }
        }
    }

    private var autoSaveSection: some View {
        Section {
            Toggle("拍完自动保存到相册", isOn: $autoSaveToAlbum)
            Toggle("拍完自动进入施工日志草稿", isOn: $autoOpenLogDraft)
        }
    }

    @ViewBuilder
    private var recentCaptureSection: some View {
        if let capturedPhoto {
            Section("最近拍摄") {
                Image(uiImage: capturedPhoto.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if hasMultipleCapturedPhotos {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(capturedPhotos.enumerated()), id: \.element.id) { index, photo in
                                Button {
                                    selectedCapturedPhotoID = photo.id
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: photo.image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 72, height: 54)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(
                                                        photo.id == capturedPhoto.id ? Color.appPrimaryAction : Color.appStrokeSecondary,
                                                        lineWidth: photo.id == capturedPhoto.id ? 2 : 1
                                                    )
                                            }
                                        Text("\(index + 1)")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.black.opacity(0.55), in: Capsule())
                                            .padding(4)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(capturedPhotoMetaText(capturedAt: capturedPhoto.capturedAt))
                    Text(projectAssociationText)
                    if hasMultipleCapturedPhotos {
                        Text("连拍共 \(capturedPhotos.count) 张，当前处理第 \(selectedCapturedPhotoNumber) 张")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                recentCaptureActions
            }
        } else {
            Section("最近拍摄") {
                ContentUnavailableView("还没有照片", systemImage: "camera.aperture", description: Text("拍摄后可直接导出带水印的 JPEG。"))
            }
        }
    }

    private var recentCaptureActions: some View {
        HStack(spacing: 12) {
            Button {
                saveCurrentImageToAlbum()
            } label: {
                Label("保存相册", systemImage: "photo.on.rectangle.angled")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(savingToAlbum)

            if hasMultipleCapturedPhotos {
                Button {
                    saveAllImagesToAlbum()
                } label: {
                    Label("保存全部", systemImage: "photo.stack")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(savingToAlbum)
            }

            Button {
                saveCurrentImageAsProjectDocument()
            } label: {
                Label("附项目资料", systemImage: "folder.badge.plus")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedProjectId == nil)

            Button {
                exportCurrentImage()
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Menu {
                if let logSeedPhoto {
                    NavigationLink {
                        DailyLogView(
                            initialProjectId: selectedProjectId,
                            autoOpenComposer: true,
                            initialPhotoDrafts: [logSeedPhoto],
                            initialContent: logDraftContent
                        )
                    } label: {
                        Label("进入施工日志", systemImage: "book.pages.fill")
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
                    NavigationLink {
                        SiteTodoView(
                            initialProjectId: selectedProjectId,
                            autoOpenComposer: true,
                            initialAfterPhotoData: todoSeedData
                        )
                    } label: {
                        Label("转为整改后待办", systemImage: "checkmark.seal.fill")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    clearCapturedPhotos()
                } label: {
                    Label("清空照片", systemImage: "trash")
                }
            } label: {
                Label("更多", systemImage: "ellipsis.circle")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var currentContext: CameraWatermarkContext {
        CameraWatermarkContext(
            projectName: effectiveProjectName,
            template: template,
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

    private var locationStatusText: String {
        locationManager.statusText
    }

    private var appSettingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    private var projectAssociationText: String {
        guard let name = effectiveProjectName else { return "未关联项目" }
        return "工程：\(name)"
    }

    private func capturedPhotoMetaText(capturedAt: Date) -> String {
        let time = Formatters.dateTime.string(from: capturedAt)
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTag.isEmpty {
            return "\(time) · \(template.displayName)"
        }
        return "\(time) · \(template.displayName) · \(trimmedTag)"
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

    private func handleCapturedImages(_ images: [UIImage], capturedAt: Date) {
        let outputs = images.map {
            WatermarkCapturedPhoto(
                image: $0.applyingCameraWatermark(context: currentContext, capturedAt: capturedAt),
                capturedAt: capturedAt
            )
        }
        guard !outputs.isEmpty else {
            presentError("未获取到照片，请重试。")
            return
        }
        capturedPhotos = outputs
        selectedCapturedPhotoID = outputs.first?.id
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        presentToast("已拍摄 \(outputs.count) 张，可继续处理。", style: .success)
        if autoSaveToAlbum {
            if outputs.count > 1 {
                saveAllImagesToAlbum()
            } else {
                saveCurrentImageToAlbum()
            }
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
                presentBlockingError(
                    "未获得相机权限，无法拍摄。",
                    settingsURL: appSettingsURL
                )
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

        performWithPhotoLibraryAccess {
            writeImagesToAlbum([image])
        }
    }

    private func saveAllImagesToAlbum() {
        let images = capturedPhotos.map(\.image)
        guard !images.isEmpty else {
            presentError("请先拍摄水印照片。")
            return
        }
        performWithPhotoLibraryAccess {
            writeImagesToAlbum(images)
        }
    }

    private func performWithPhotoLibraryAccess(_ action: @escaping () -> Void) {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            action()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                Task { @MainActor in
                    if newStatus == .authorized || newStatus == .limited {
                        action()
                    } else {
                        presentBlockingError(
                            "没有相册写入权限，无法保存。",
                            settingsURL: appSettingsURL
                        )
                    }
                }
            }
        case .denied, .restricted:
            presentBlockingError(
                "没有相册写入权限，请到系统设置中开启。",
                settingsURL: appSettingsURL
            )
        @unknown default:
            presentError("无法确认相册权限。")
        }
    }

    private func writeImagesToAlbum(_ images: [UIImage]) {
        savingToAlbum = true
        PHPhotoLibrary.shared().performChanges {
            for image in images {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } completionHandler: { success, error in
            Task { @MainActor in
                savingToAlbum = false
                if success {
                    presentInfo(images.count > 1 ? "已保存 \(images.count) 张到相册。" : "已保存到相册。")
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

    private func clearCapturedPhotos() {
        capturedPhotos.removeAll()
        selectedCapturedPhotoID = nil
    }

    private func presentInfo(_ message: String) {
        presentToast(message, style: .success)
    }

    private func presentError(_ message: String) {
        presentToast(message, style: .error)
    }

    private func presentBlockingError(_ message: String, settingsURL: URL? = nil) {
        alertTitle = "无法继续"
        alertMessage = message
        alertSettingsURL = settingsURL
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

private struct WatermarkTemplateChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.appPrimaryAction : Color(uiColor: .secondarySystemBackground))
            .foregroundStyle(isSelected ? .white : .primary)
            .clipShape(Capsule())
    }
}

private struct WatermarkCapturedPhoto: Identifiable {
    let id = UUID()
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
            return .appSuccess
        case .error:
            return .appRisk
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

private struct WatermarkCameraCaptureView: View {
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
                            Circle().stroke(.appWarning, lineWidth: 4).frame(width: 62, height: 62)
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
                if !images.isEmpty {
                    onCapture(images, capturedAt)
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
