import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct WatermarkCameraToolView: View {
    @Environment(DataStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var preparedExport: WatermarkPreparedExport?
    @State private var exportCleanupURL: URL?
    @State private var batchTask: Task<Void, Never>?
    @State private var draftRefreshTask: Task<Void, Never>?
    @State private var operationID = UUID()
    @State private var workProgress = (done: 0, total: 0)
    @State private var recoveryToDelete: WatermarkRecoveredDraft?
    @State private var pendingLogPhotoIDs = Set<UUID>()
    @State private var albumAttemptPhoto: WatermarkCapturedPhoto?
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
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                WatermarkInfoSection(tag: binding(for: \.tag), photographer: binding(for: \.photographer),
                    locationText: Binding(get: { settings.locationText }, set: { locationManager.cancelRequest(); settings.setManualLocation($0) }),
                    locationStatusText: locationStatus(at: timeline.date), isRequesting: locationManager.isRequesting,
                    requestLocation: locationManager.requestLocation)
            }
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
                guard let id = await captures.addAnnotatedCopy(image: image, of: photo) else {
                    throw WatermarkDraftImageError.encodingFailed
                }
                selectedIDs = [id]
                if captures.photos.first(where: { $0.id == id })?.isPersisted == false {
                    presentInfo(AppLocalization.string("标注副本暂存在本次会话中，请勿关闭应用并重试保存草稿。"))
                }
            }
        }
        .sheet(item: $rectificationPhoto) { photo in
            WatermarkRectificationSheet(photo: photo, initialTodoId: rectificationInitialID) { _ in presentInfo(AppLocalization.string("整改照片已保存到原待办。")) }
        }
        .sheet(item: $preparedExport, onDismiss: cleanupExport) { file in
            WatermarkFileExportPicker(file: file) { saved in
                if saved { presentInfo(AppLocalization.string("wm_camera_export_photo_success")) }
                preparedExport = nil
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            if let alertSettingsURL { Button(AppLocalization.string("wm_camera_go_to_settings_button")) { openURL(alertSettingsURL) } }
            Button(AppLocalization.string("wm_camera_ack_button"), role: .cancel) {}
        } message: { Text(alertMessage) }
        .confirmationDialog(AppLocalization.string("删除未完成草稿？"), isPresented: Binding(get: { recoveryToDelete != nil }, set: { if !$0 { recoveryToDelete = nil } }), titleVisibility: .visible) {
            Button(AppLocalization.string("删除未完成草稿"), role: .destructive) {
                if let item = recoveryToDelete { Task { await captures.removeRecovery(id: item.id) } }
                recoveryToDelete = nil
            }
        } message: { Text(AppLocalization.string("这会删除保留的恢复文件，建议先导出留存。")) }
        .confirmationDialog(AppLocalization.string("核对相册保存结果"), isPresented: Binding(get: { albumAttemptPhoto != nil }, set: { if !$0 { albumAttemptPhoto = nil } }), titleVisibility: .visible) {
            Button(AppLocalization.string("已在相册中找到，标记完成")) {
                if let photo = albumAttemptPhoto { Task { await captures.resolveAlbumAttempt(id: photo.id, retryConfirmed: false) } }
                albumAttemptPhoto = nil
            }
            Button(AppLocalization.string("未找到，允许重新保存")) {
                if let photo = albumAttemptPhoto { Task { await captures.resolveAlbumAttempt(id: photo.id, retryConfirmed: true); await saveToAlbum([photo]) } }
                albumAttemptPhoto = nil
            }
        } message: { Text(AppLocalization.string("上次保存结果尚未确认。请先检查系统相册，重复保存可能产生重复照片。")) }
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
            if !didAutoOpenCamera, let initialProjectId { settings.selectedProjectId = initialProjectId }
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
            let shouldOpen = autoOpenCameraOnAppear && !didAutoOpenCamera
            didAutoOpenCamera = true
            await refreshLogDraftStatus()
            if shouldOpen { openCamera() }
        }
        .onReceive(NotificationCenter.default.publisher(for: WatermarkCameraDraftStorage.didChangeNotification).receive(on: RunLoop.main)) { notification in
            guard notification.userInfo?["directory"] as? String == captures.draftDirectory.standardizedFileURL.path else { return }
            draftRefreshTask?.cancel()
            draftRefreshTask = Task { @MainActor in
                guard await DebouncedTask.wait(for: .milliseconds(200)) else { return }
                await captures.restore()
            }
        }
        .onChange(of: showLogDraft) { _, shown in
            if !shown { Task { await refreshLogDraftStatus() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await captures.restore(); await refreshLogDraftStatus() } }
        }
        .onReceive(locationManager.$snapshot) { snapshot in
            if let snapshot { settings.acceptDeviceLocation(snapshot) }
        }
    }

    private func locationStatus(at now: Date) -> String {
        if locationManager.isRequesting { return locationManager.statusText }
        if let error = locationManager.requestError { return error + " " + settings.locationStatusText(at: now) }
        if !locationManager.statusText.isEmpty, locationManager.snapshot == nil { return locationManager.statusText }
        return settings.locationStatusText(at: now)
    }

    private var draftSection: some View {
        Section {
            if busy {
                if workProgress.total > 0 {
                    ProgressView(value: Double(workProgress.done), total: Double(workProgress.total)) {
                        Text(String(format: AppLocalization.string("正在处理 %lld / %lld 张"), workProgress.done, workProgress.total))
                    }
                    if batchTask != nil { Button(AppLocalization.string("取消处理")) { batchTask?.cancel() } }
                } else { ProgressView(AppLocalization.string("正在处理照片，请稍候…")) }
            }
            recoverySection
            if let error = captures.persistenceError {
                Text(error).font(.caption).foregroundStyle(.red)
                Button(AppLocalization.string("重试暂存")) { Task { await captures.retryPendingDrafts() } }.disabled(busy)
            }
            if captures.photos.isEmpty {
                Text(AppLocalization.string("拍摄后自动保留本地草稿，可继续拍摄并统一整理。")).foregroundStyle(.secondary)
            } else {
                WatermarkDraftGallery(photos: captures.photos, selectedPhotoID: Binding(get: { captures.selectedPhotoID }, set: { captures.selectedPhotoID = $0 }), selectedIDs: $selectedIDs, logStatuses: logStatuses)
                if let photo = selectedPhotos.first(where: { $0.albumAttemptID != nil && $0.albumStatus != .completed }) {
                    Button(AppLocalization.string("核对相册保存结果")) { albumAttemptPhoto = photo }.disabled(busy)
                }
                batchActions.disabled(busy || selectedPhotos.isEmpty)
            }
        } header: { Text(AppLocalization.string("照片草稿")) }
    }

    private var logStatuses: [UUID: String] {
        var statuses = Dictionary(uniqueKeysWithValues: pendingLogPhotoIDs.map { ($0, AppLocalization.string("已加入日志草稿")) })
        for log in store.dailyLogs {
            for attachment in log.photos {
                if let id = attachment.sourcePhotoID {
                    statuses[id] = String(format: AppLocalization.string("已保存到日志：%@"), log.date.storageText)
                }
            }
        }
        return statuses
    }

    private func refreshLogDraftStatus() async {
        let url = store.storeURL
        let projects = Set(captures.photos.map(\.projectId))
        do {
            pendingLogPhotoIDs = try await FileIOTaskRunner.run {
                let drafts = BusinessDraftStore.scoped(to: url)
                var ids = Set<UUID>()
                for project in projects { ids.formUnion(try drafts.dailyLogDraftSourcePhotoIDs(projectID: project)) }
                return ids
            }
        } catch { pendingLogPhotoIDs = [] }
    }

    @ViewBuilder private var recoverySection: some View {
        if !captures.recoveryItems.isEmpty {
            Text(AppLocalization.string("发现可恢复的照片文件")).font(.headline)
            ForEach(captures.recoveryItems) { item in
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.summary).font(.caption)
                    Text(item.availableFileNames.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                    HStack {
                        Button(AppLocalization.string("导出恢复文件")) {
                            isWorking = true
                            Task {
                                defer { isWorking = false }
                                do {
                                    let url = try await captures.exportRecovery(id: item.id)
                                    let cleanup = url.deletingLastPathComponent()
                                    exportCleanupURL = cleanup
                                    preparedExport = WatermarkPreparedExport(url: url, cleanupURL: cleanup)
                                } catch { presentBlockingError(error.localizedDescription) }
                            }
                        }
                        Button(AppLocalization.string("删除未完成草稿"), role: .destructive) { recoveryToDelete = item }
                    }.buttonStyle(.borderless).disabled(busy)
                }
            }
        }
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
                        tag: PhotoTag(rawValue: photo.context.tag) ?? .general, capturedAt: photo.capturedAt, sourcePhotoID: photo.id)
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
        guard !busy else { return }
        let photos = selectedPhotos
        let quality = settings.exportQuality.compression
        let format: WatermarkCameraBatchService.FileFormat = type == .pdf ? .pdf : (type == .zip ? .zip : .jpeg)
        let name = photos.count == 1 ? WatermarkCameraTextBuilder.exportFileName(projectName: photos.first?.context.projectName, capturedAt: photos.first?.capturedAt) : AppLocalization.string("现场照片")
        isWorking = true
        workProgress = (0, photos.count)
        let token = UUID()
        operationID = token
        batchTask = Task { @MainActor in
            defer { operationID = UUID(); isWorking = false; batchTask = nil; workProgress = (0, 0) }
            let worker = Task.detached(priority: .userInitiated) {
                try WatermarkCameraBatchService.exportFile(photos, format: format, compression: quality, name: name) { done, total in
                    Task { @MainActor in if operationID == token { workProgress = (done, total) } }
                }
            }
            do {
                let file = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled else { WatermarkCameraBatchService.cleanupExport(at: file.cleanupURL); return }
                exportCleanupURL = file.cleanupURL
                preparedExport = file
            } catch is CancellationError { presentInfo(AppLocalization.string("已取消处理，照片草稿已保留。")) }
            catch { presentBlockingError(error.localizedDescription) }
        }
    }

    private func cleanupExport() {
        if let url = exportCleanupURL { WatermarkCameraBatchService.cleanupExport(at: url) }
        exportCleanupURL = nil
    }

    private func archiveSelected() {
        guard !busy else { return }
        let photos = selectedPhotos
        isWorking = true
        workProgress = (0, photos.count)
        batchTask = Task { @MainActor in
            defer { isWorking = false; batchTask = nil; workProgress = (0, 0) }
            var failures = [String]()
            for (index, photo) in photos.enumerated() {
                if Task.isCancelled { break }
                do {
                    try await WatermarkCameraBatchService.archive(photo, in: store)
                    await captures.markArchived(id: photo.id)
                } catch {
                    failures.append(error.localizedDescription)
                    await captures.markArchiveFailed(id: photo.id, message: error.localizedDescription)
                }
                workProgress = (index + 1, photos.count)
            }
            if Task.isCancelled { presentInfo(AppLocalization.string("已取消处理，已完成的归档保留。")) }
            else if let failure = failures.first { presentBlockingError("\(AppLocalization.string("部分照片未归档，草稿已保留。"))\n\(failure)") }
            else { presentInfo(AppLocalization.string("所选照片已按拍摄项目归档。")) }
        }
    }

    private func saveToAlbum(_ photos: [WatermarkCapturedPhoto]) async {
        guard !savingAlbumBatch else { return }
        savingAlbumBatch = true
        defer { savingAlbumBatch = false }
        for candidate in photos {
            guard let photo = captures.photos.first(where: { $0.id == candidate.id }), photo.albumStatus != .completed else { continue }
            let result = await captures.saveToAlbum(photo: photo, quality: settings.exportQuality, coordinator: exportCoordinator)
            switch result {
            case .success: break
            case .blockingError(let message, let url): presentBlockingError(message, settingsURL: url); return
            case .error(let message): presentBlockingError(message); return
            }
        }
    }
}
