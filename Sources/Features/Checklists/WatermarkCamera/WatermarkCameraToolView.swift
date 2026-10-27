import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct WatermarkCameraToolView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.openURL) private var openURL
    let initialProjectId: UUID?
    let autoOpenCameraOnAppear: Bool
    @State private var settings = WatermarkCameraSettingsStore()
    @State private var captures = WatermarkCameraCaptureStore()
    @State private var exportCoordinator = WatermarkCameraExportCoordinator()
    @StateObject private var locationManager = WatermarkCameraLocationManager()
    @State private var selectedIDs = Set<UUID>()
    @State private var showCamera = false
    @State private var showRectificationCapture = false
    @State private var pendingRectificationID: UUID?
    @State private var rectificationInitialID: UUID?
    @State private var cameraContext = CameraWatermarkContext(projectName: nil)
    @State private var cameraProjectId: UUID?
    @State private var captureTask: Task<Void, Never>?
    @State private var sessionPhotoIDs = Set<UUID>()
    @State private var cameraSessionID = UUID()
    @State private var queuedCaptures = 0
    @State private var finishingSession = false
    @State private var savingAlbumBatch = false
    @State private var scopedDraftURL: URL?
    @State private var didAutoOpenCamera = false
    @State private var isWorking = false
    @State private var showClearPhotosConfirm = false
    @State private var annotationPhoto: WatermarkCapturedPhoto?
    @State private var rectificationPhoto: WatermarkCapturedPhoto?
    @State private var showLogDraft = false
    @State private var logPhotos: [DailyLogSeedPhoto] = []
    @State private var logProjectId: UUID?
    @State private var logContent = ""
    @State private var showTodo = false
    @State private var todoData: Data?
    @State private var todoProjectId: UUID?
    @State private var showExporter = false
    @State private var exportData = Data()
    @State private var exportType = UTType.jpeg
    @State private var exportName = "现场照片"
    @State var alertTitle = AppLocalization.string("wm_camera_alert_cannot_continue_title")
    @State var alertMessage = ""
    @State var alertSettingsURL: URL?
    @State var showAlert = false
    @State var toast: WatermarkToast?

    init(initialProjectId: UUID? = nil, autoOpenCameraOnAppear: Bool = false) {
        self.initialProjectId = initialProjectId
        self.autoOpenCameraOnAppear = autoOpenCameraOnAppear
    }

    private var selectedPhotos: [WatermarkCapturedPhoto] { captures.photos.filter { selectedIDs.contains($0.id) } }
    private var busy: Bool { isWorking || captures.busy || savingAlbumBatch || queuedCaptures > 0 || finishingSession || scopedDraftURL == nil }
    private var effectiveProjectName: String? {
        guard let id = settings.selectedProjectId else { return nil }
        return store.projects.first { $0.id == id }?.name
    }
    private var currentContext: CameraWatermarkContext {
        CameraWatermarkContext(
            projectName: effectiveProjectName, template: settings.template, tag: settings.tag,
            photographer: settings.photographer, locationText: settings.locationText,
            workSection: settings.workSection, floor: settings.floor, process: settings.process,
            issueNumber: settings.issueNumber, completedQuantity: settings.completedQuantity,
            receiptNote: settings.receiptNote, style: settings.style, locationSnapshot: settings.locationSnapshot
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
        Form {
            Section {
                ProjectContextStrip(title: AppLocalization.string("wm_camera_current_project_title"), projects: store.projects,
                    selectedProjectId: binding(for: \.selectedProjectId), emptyText: AppLocalization.string("wm_camera_unlinked_project_text"))
            }
            WatermarkCaptureSection(openCamera: openCamera).disabled(busy)
            Section {
                Button { requestCamera(rectification: true) } label: {
                    Label(AppLocalization.string("拍摄整改后照片"), systemImage: "square.on.square")
                }.disabled(busy || settings.selectedProjectId == nil)
            }
            draftSection.id("watermark-drafts")
            WatermarkTemplateSection(templateRaw: binding(for: \.templateRaw))
            WatermarkInfoSection(tag: binding(for: \.tag), photographer: binding(for: \.photographer),
                locationText: Binding(get: { settings.locationText }, set: { locationManager.cancelRequest(); settings.setManualLocation($0) }),
                locationStatusText: locationManager.isRequesting ? locationManager.statusText : locationStatus,
                requestLocation: locationManager.requestLocation)
            WatermarkEngineeringSection(template: settings.template,
                workSection: binding(for: \.workSection), floor: binding(for: \.floor), process: binding(for: \.process),
                issueNumber: binding(for: \.issueNumber), completedQuantity: binding(for: \.completedQuantity), receiptNote: binding(for: \.receiptNote))
            WatermarkStyleSection(style: binding(for: \.style))
            WatermarkCameraSettingsSection(exportQuality: binding(for: \.exportQuality), showGrid: binding(for: \.showGrid),
                flashEnabled: binding(for: \.flashEnabled), burstCount: binding(for: \.burstCount), boundedBurstCount: settings.boundedBurstCount)
            WatermarkAutoSaveSection(autoSaveToAlbum: binding(for: \.autoSaveToAlbum), autoOpenLogDraft: binding(for: \.autoOpenLogDraft))
        }
        .onChange(of: captures.selectedPhotoID) { _, _ in
            withAnimation { proxy.scrollTo("watermark-drafts", anchor: .top) }
        }
        }
        .navigationTitle(AppLocalization.string("wm_camera_nav_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: openCamera) { Image(systemName: "camera.fill") }
                    .accessibilityLabel(AppLocalization.string("wm_camera_capture_button")).disabled(busy)
            }
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: finishCameraSession) {
            WatermarkCameraCaptureView(watermarkContext: cameraContext, showGrid: settings.showGrid,
                flashEnabled: settings.flashEnabled, burstCount: settings.boundedBurstCount) { images, date in
                handleCapturedImages(images, capturedAt: date)
            }
        }
        .fullScreenCover(isPresented: $showRectificationCapture, onDismiss: finishRectificationCapture) {
            WatermarkRectificationCapturePicker(projectId: cameraProjectId, context: cameraContext,
                showGrid: settings.showGrid, flashEnabled: settings.flashEnabled, burstCount: settings.boundedBurstCount,
                onCapture: handleCapturedImages, onFinished: { pendingRectificationID = $0 })
        }
        .sheet(item: $annotationPhoto) { photo in
            WatermarkPhotoAnnotationView(photo: photo) { image in
                Task {
                    if let id = await captures.addAnnotatedCopy(image: image, of: photo) { selectedIDs = [id] }
                }
            }
        }
        .sheet(item: $rectificationPhoto) { photo in
            WatermarkRectificationSheet(photo: photo, initialTodoId: rectificationInitialID) { _ in presentInfo(AppLocalization.string("整改照片已保存到原待办。")) }
        }
        .fileExporter(isPresented: $showExporter, document: ExportDocument(data: exportData), contentType: exportType, defaultFilename: exportName) { result in
            switch result {
            case .success: presentInfo(AppLocalization.string("wm_camera_export_photo_success"))
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { presentBlockingError(error.localizedDescription) }
            }
            exportData = Data()
        }
        .alert(alertTitle, isPresented: $showAlert) {
            if let alertSettingsURL { Button(AppLocalization.string("wm_camera_go_to_settings_button")) { openURL(alertSettingsURL) } }
            Button(AppLocalization.string("wm_camera_ack_button"), role: .cancel) {}
        } message: { Text(alertMessage) }
        .confirmationDialog(AppLocalization.string("删除所选照片草稿？"), isPresented: $showClearPhotosConfirm, titleVisibility: .visible) {
            Button(AppLocalization.string("删除所选草稿"), role: .destructive) {
                let ids = selectedIDs
                Task {
                    for id in ids { await captures.remove(id: id) }
                    selectedIDs.formIntersection(Set(captures.photos.map(\.id)))
                }
            }
        } message: { Text(AppLocalization.string("将删除所选草稿的原片与标注副本文件；已存入相册或项目的照片保留。")) }
        .navigationDestination(isPresented: $showLogDraft) {
            DailyLogView(initialProjectId: logProjectId, autoOpenComposer: true, initialPhotoDrafts: logPhotos, initialContent: logContent)
        }
        .navigationDestination(isPresented: $showTodo) {
            SiteTodoView(initialProjectId: todoProjectId, autoOpenComposer: true, initialBeforePhotoData: todoData)
        }
        .overlay(alignment: .top) {
            if let toast { WatermarkToastView(toast: toast).padding(.top, 10) }
        }
        .task {
            let directory = WatermarkCameraDraftStorage.scopedDirectory(for: store.storeURL)
            if scopedDraftURL == nil {
                captures = WatermarkCameraCaptureStore(storage: WatermarkCameraDraftStorage(directory: directory))
                scopedDraftURL = directory
            }
            if let initialProjectId { settings.selectedProjectId = initialProjectId }
            await captures.restore()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uitest-watermark-fixture"),
               ProcessInfo.processInfo.arguments.contains("-uitest-skip-onboarding"), captures.photos.isEmpty {
                let project = store.projects.first
                settings.selectedProjectId = project?.id
                let context = CameraWatermarkContext(projectName: project?.name ?? "Camera Test Site", tag: "现场测试", photographer: "测试员", locationText: "测试工区", workSection: "1号楼", floor: "2层", process: "钢筋绑扎")
                let images = await Task.detached { WatermarkCameraTestFixture.images() }.value
                _ = await captures.append(images: images, capturedAt: Date(timeIntervalSince1970: 1_793_000_000), context: context, projectId: project?.id)
            }
            #endif
            if selectedIDs.isEmpty, let photo = captures.selectedPhoto { selectedIDs = [photo.id] }
            guard autoOpenCameraOnAppear, !didAutoOpenCamera else { return }
            didAutoOpenCamera = true
            openCamera()
        }
        .onReceive(locationManager.$snapshot) { snapshot in
            if let snapshot { settings.acceptDeviceLocation(snapshot) }
        }
    }

    private var locationStatus: String {
        if let error = locationManager.requestError { return error + " " + settings.locationStatusText() }
        if !locationManager.statusText.isEmpty, locationManager.snapshot == nil { return locationManager.statusText }
        return settings.locationStatusText()
    }

    private var draftSection: some View {
        Section {
            if busy { ProgressView(AppLocalization.string("正在处理照片，请稍候…")) }
            if let error = captures.persistenceError {
                Text(error).font(.caption).foregroundStyle(.red)
                Button(AppLocalization.string("重试暂存")) { Task { await captures.retryPendingDrafts() } }.disabled(busy)
            }
            if captures.photos.isEmpty {
                Text(AppLocalization.string("拍摄后自动保留本地草稿，可继续拍摄并统一整理。")).foregroundStyle(.secondary)
            } else {
                WatermarkDraftGallery(photos: captures.photos, selectedPhotoID: Binding(get: { captures.selectedPhotoID }, set: { captures.selectedPhotoID = $0 }), selectedIDs: $selectedIDs)
                batchActions.disabled(busy || selectedPhotos.isEmpty)
            }
        } header: { Text(AppLocalization.string("照片草稿")) }
    }

    private var batchActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { prepareLog(selectedPhotos) } label: { Label(AppLocalization.string("所选照片写入日志"), systemImage: "book.pages") }
                .accessibilityIdentifier("watermark-batch-log")
            Button { archiveSelected() } label: { Label(AppLocalization.string("按拍摄项目归档"), systemImage: "folder.badge.plus") }
                .accessibilityIdentifier("watermark-batch-archive")
            Menu {
                Button(AppLocalization.string("保存所选到相册")) { let photos = selectedPhotos; Task { await saveToAlbum(photos) } }
                Button(AppLocalization.string("导出照片包 ZIP")) { exportSelected(.zip) }
                Button(AppLocalization.string("导出照片册 PDF")) { exportSelected(.pdf) }
                if selectedPhotos.count == 1 {
                    Button(AppLocalization.string("导出照片 JPEG")) { exportSelected(.jpeg) }
                    Button(AppLocalization.string("标注副本")) { annotationPhoto = selectedPhotos.first }
                    Button(AppLocalization.string("关联已有整改")) { rectificationInitialID = nil; rectificationPhoto = selectedPhotos.first }
                    Button(AppLocalization.string("新建整改待办")) { prepareTodo() }
                }
                Button(AppLocalization.string("删除所选草稿"), role: .destructive) { showClearPhotosConfirm = true }
            } label: { Label(AppLocalization.string("导出与更多操作"), systemImage: "ellipsis.circle") }
        }
        .buttonStyle(.borderless)
    }

    private func binding<Value>(for keyPath: ReferenceWritableKeyPath<WatermarkCameraSettingsStore, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    private func openCamera() { requestCamera(rectification: false) }

    private func requestCamera(rectification: Bool) {
        guard !busy else { return }
        guard WatermarkCameraAccess.hasBackCamera else { presentBlockingError(AppLocalization.string("wm_camera_device_unavailable_error")); return }
        Task {
            guard await WatermarkCameraAccess.requestCameraAccessIfNeeded() else {
                presentBlockingError(AppLocalization.string("wm_camera_permission_denied_error"), settingsURL: WatermarkCameraAccess.appSettingsURL)
                return
            }
            cameraContext = currentContext
            if rectification {
                cameraContext.template = .rectification
                cameraContext.tag = PhotoTag.rectificationAfter.rawValue
            }
            cameraProjectId = settings.selectedProjectId
            sessionPhotoIDs = []
            cameraSessionID = UUID()
            if rectification { pendingRectificationID = nil; showRectificationCapture = true }
            else { showCamera = true }
        }
    }

    private func finishRectificationCapture() {
        let pending = captureTask
        let issueID = pendingRectificationID
        let session = cameraSessionID
        finishingSession = true
        Task { @MainActor in
            await pending?.value
            defer { finishingSession = false }
            guard session == cameraSessionID, let issueID,
                  let photo = captures.photos.last(where: { sessionPhotoIDs.contains($0.id) }) else { return }
            rectificationInitialID = issueID
            rectificationPhoto = photo
        }
    }

    private func handleCapturedImages(_ images: [UIImage], capturedAt: Date) {
        let previous = captureTask
        queuedCaptures += 1
        let context = cameraContext
        let projectId = cameraProjectId
        let autoSave = settings.autoSaveToAlbum
        captureTask = Task { @MainActor in
            await previous?.value
            defer { queuedCaptures -= 1 }
            let previousIDs = Set(captures.photos.map(\.id))
            _ = await captures.append(images: images, capturedAt: capturedAt, context: context, projectId: projectId)
            let newPhotos = captures.photos.filter { !previousIDs.contains($0.id) }
            sessionPhotoIDs.formUnion(newPhotos.map(\.id))
            selectedIDs = sessionPhotoIDs
            if autoSave { await saveToAlbum(newPhotos) }
        }
    }

    private func finishCameraSession() {
        let pending = captureTask
        let session = cameraSessionID
        finishingSession = true
        Task { @MainActor in
            await pending?.value
            defer { finishingSession = false }
            guard session == cameraSessionID else { return }
            if settings.autoOpenLogDraft, !sessionPhotoIDs.isEmpty {
                prepareLog(captures.photos.filter { sessionPhotoIDs.contains($0.id) })
            }
        }
    }

    private func prepareLog(_ photos: [WatermarkCapturedPhoto]) {
        guard !isWorking else { return }
        isWorking = true
        let quality = settings.exportQuality.compression
        Task {
            defer { isWorking = false }
            do {
                let projectId = try WatermarkCameraBatchService.logProject(for: photos)
                if let projectId, !store.projects.contains(where: { $0.id == projectId }) { throw WatermarkCameraBatchError.missingProject }
                let data = try await FileIOTaskRunner.run { try photos.map { try WatermarkCameraBatchService.jpeg($0, compression: quality) } }
                logProjectId = projectId
                logPhotos = zip(photos, data).map { photo, data in
                    DailyLogSeedPhoto(data: data, note: WatermarkCameraLogDraftCoordinator.photoNote(for: photo),
                        tag: PhotoTag(rawValue: photo.context.tag) ?? .general, capturedAt: photo.capturedAt)
                }
                logContent = photos.first.map { WatermarkCameraTextBuilder.logDraftContent(tag: $0.context.tag) } ?? ""
                showLogDraft = true
            } catch { presentBlockingError(error.localizedDescription) }
        }
    }

    private func prepareTodo() {
        guard let photo = selectedPhotos.first else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                todoData = try await FileIOTaskRunner.run { try WatermarkCameraBatchService.jpeg(photo, compression: 0.94) }
                todoProjectId = photo.projectId
                showTodo = true
            } catch { presentBlockingError(error.localizedDescription) }
        }
    }

    private func exportSelected(_ type: UTType) {
        let photos = selectedPhotos
        let quality = settings.exportQuality.compression
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                exportData = try await FileIOTaskRunner.run {
                    if type == .pdf { return try WatermarkCameraBatchService.pdf(photos) }
                    if type == .zip { return try WatermarkCameraBatchService.zip(photos, compression: quality) }
                    guard let first = photos.first else { throw WatermarkCameraBatchError.emptySelection }
                    return try WatermarkCameraBatchService.jpeg(first, compression: quality)
                }
                exportType = type
                exportName = photos.count == 1 ? WatermarkCameraTextBuilder.exportFileName(projectName: photos.first?.context.projectName, capturedAt: photos.first?.capturedAt) : AppLocalization.string("现场照片")
                showExporter = true
            } catch { presentBlockingError(error.localizedDescription) }
        }
    }

    private func archiveSelected() {
        let photos = selectedPhotos
        isWorking = true
        Task {
            defer { isWorking = false }
            var failures = [String]()
            for photo in photos {
                do {
                    try await WatermarkCameraBatchService.archive(photo, in: store)
                    await captures.markArchived(id: photo.id)
                } catch {
                    failures.append(error.localizedDescription)
                    await captures.markArchiveFailed(id: photo.id, message: error.localizedDescription)
                }
            }
            if let failure = failures.first { presentBlockingError("\(AppLocalization.string("部分照片未归档，草稿已保留。"))\n\(failure)") }
            else { presentInfo(AppLocalization.string("所选照片已按拍摄项目归档。")) }
        }
    }

    private func saveToAlbum(_ photos: [WatermarkCapturedPhoto]) async {
        guard !savingAlbumBatch else { return }
        savingAlbumBatch = true
        defer { savingAlbumBatch = false }
        // Hold the batch lock across loading, permission, every write and status persistence.
        for candidate in photos {
            guard let photo = captures.photos.first(where: { $0.id == candidate.id }), photo.albumStatus != .completed else { continue }
            do {
                let image = try await FileIOTaskRunner.run { try photo.imageForDelivery() }
                let result = await exportCoordinator.saveImagesToAlbum([image])
                switch result {
                case .success: await captures.markAlbumSaved(ids: [photo.id])
                case .blockingError(let message, let url):
                    await captures.markAlbumFailed(ids: [photo.id], message: message)
                    presentBlockingError(message, settingsURL: url)
                    return
                case .error(let message):
                    await captures.markAlbumFailed(ids: [photo.id], message: message)
                    presentBlockingError(message)
                    return
                }
            } catch {
                await captures.markAlbumFailed(ids: [photo.id], message: error.localizedDescription)
                presentBlockingError(error.localizedDescription)
                return
            }
        }
    }
}
