import SwiftUI
import UniformTypeIdentifiers
import UIKit
import CoreLocation
import Photos

struct WatermarkCameraToolView: View {
    @Environment(DataStore.self) private var store
    let initialProjectId: UUID?
    let autoOpenCameraOnAppear: Bool
    @State private var selectedProjectId: UUID?
    @State private var projectName = ""
    @State private var photographer = ""
    @State private var locationText = ""
    @State private var template: CameraWatermarkTemplate = .constructionLog
    @State private var tag = "现场记录"
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
    @StateObject private var locationManager = WatermarkCameraLocationManager()

    init(initialProjectId: UUID? = nil, autoOpenCameraOnAppear: Bool = false) {
        self.initialProjectId = initialProjectId
        self.autoOpenCameraOnAppear = autoOpenCameraOnAppear
        _selectedProjectId = State(initialValue: initialProjectId)
    }

    var body: some View {
        Form {
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
                    Picker("水印模板", selection: $template) {
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
                            Image(systemName: "location.fill")
                        }
                        .buttonStyle(.borderless)
                    }
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
                        Label("导出 JPEG", systemImage: "square.and.arrow.up")
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
            ImagePickerView(
                sourceType: .camera,
                watermarkContext: currentContext,
                onPickedWithTimestamp: { image, capturedAt in
                    capturedPhoto = WatermarkCapturedPhoto(image: image, capturedAt: capturedAt)
                },
                onPicked: { image in
                    capturedPhoto = WatermarkCapturedPhoto(image: image, capturedAt: Date())
                }
            )
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
        .onChange(of: locationManager.locationText) { _, newValue in
            if !newValue.isEmpty {
                locationText = newValue
            }
        }
        .onChange(of: selectedProjectId) { _, newValue in
            guard let project = newValue.flatMap({ id in store.projects.first { $0.id == id } }) else { return }
            projectName = project.name
        }
        .onAppear {
            if selectedProjectId == nil {
                selectedProjectId = initialProjectId
            }
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
        capturedPhoto?.image.jpegData(compressionQuality: 0.82)
    }

    private var logDraftContent: String {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTag.isEmpty {
            return "水印照片记录"
        }
        return "水印照片记录：\(trimmedTag)"
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presentError("当前设备不可用相机。")
            return
        }
        showCamera = true
    }

    private func exportCurrentImage() {
        guard let image = capturedPhoto?.image,
              let data = image.jpegData(compressionQuality: 0.9) else {
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
                DispatchQueue.main.async {
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
            DispatchQueue.main.async {
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
        alertTitle = "已完成"
        alertMessage = message
        showAlert = true
    }

    private func presentError(_ message: String) {
        alertTitle = "无法继续"
        alertMessage = message
        showAlert = true
    }
}

private struct WatermarkCapturedPhoto {
    let image: UIImage
    let capturedAt: Date
}

private final class WatermarkCameraLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var locationText = ""
    @Published var statusText = ""

    private let manager = CLLocationManager()

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
        guard let coordinate = locations.last?.coordinate else { return }
        locationText = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
        statusText = "已填入当前位置"
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
