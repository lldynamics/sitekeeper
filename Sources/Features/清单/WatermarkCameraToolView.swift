import SwiftUI
import UniformTypeIdentifiers
import UIKit

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
    @AppStorage("watermarkCameraTag") private var tag = String(localized: "wm_camera_default_tag")
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
    @State private var alertTitle = String(localized: "wm_camera_alert_cannot_continue_title")
    @State private var alertMessage = ""
    @State private var alertSettingsURL: URL?
    @State private var showAlert = false
    @State private var savingToAlbum = false
    @State private var didAutoOpenCamera = false
    @State private var showLogDraft = false
    @State private var showClearPhotosConfirm = false
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
            WatermarkTemplateSection(templateRaw: $templateRaw)
            WatermarkCaptureSection(openCamera: openCamera)
            WatermarkInfoSection(
                tag: $tag,
                photographer: $photographer,
                locationText: $locationText,
                locationStatusText: locationStatusText,
                requestLocation: locationManager.requestLocation
            )
            WatermarkCameraSettingsSection(
                exportQuality: exportQualityBinding,
                showGrid: $showGrid,
                flashEnabled: $flashEnabled,
                burstCount: $burstCount,
                boundedBurstCount: boundedBurstCount
            )
            WatermarkAutoSaveSection(
                autoSaveToAlbum: $autoSaveToAlbum,
                autoOpenLogDraft: $autoOpenLogDraft
            )
            WatermarkRecentCaptureSection(
                capturedPhoto: capturedPhoto,
                capturedPhotos: capturedPhotos,
                selectedCapturedPhotoID: $selectedCapturedPhotoID,
                hasMultipleCapturedPhotos: hasMultipleCapturedPhotos,
                selectedCapturedPhotoNumber: selectedCapturedPhotoNumber,
                projectAssociationText: projectAssociationText,
                capturedPhotoMetaText: capturedPhotoMetaText(capturedAt:),
                savingToAlbum: savingToAlbum,
                selectedProjectId: selectedProjectId,
                logSeedPhoto: logSeedPhoto,
                logDraftContent: logDraftContent,
                todoSeedData: todoSeedData,
                saveCurrentImageToAlbum: saveCurrentImageToAlbum,
                exportCurrentImage: exportCurrentImage,
                saveAllImagesToAlbum: saveAllImagesToAlbum,
                saveCurrentImageAsProjectDocument: saveCurrentImageAsProjectDocument,
                requestClearPhotos: { showClearPhotosConfirm = true }
            )
        }
        .navigationTitle(String(localized: "wm_camera_nav_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            WatermarkCameraToolbarContent(
                hasCapturedPhoto: capturedPhoto != nil,
                hasMultipleCapturedPhotos: hasMultipleCapturedPhotos,
                savingToAlbum: savingToAlbum,
                selectedProjectId: selectedProjectId,
                logSeedPhoto: logSeedPhoto,
                logDraftContent: logDraftContent,
                todoSeedData: todoSeedData,
                openCamera: openCamera,
                exportCurrentImage: exportCurrentImage,
                saveAllImagesToAlbum: saveAllImagesToAlbum,
                saveCurrentImageAsProjectDocument: saveCurrentImageAsProjectDocument,
                requestClearPhotos: { showClearPhotosConfirm = true }
            )
        }
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
                presentInfo(String(localized: "wm_camera_export_photo_success"))
            case .failure(let error):
                presentError(
                    String(
                        format: String(localized: "wm_camera_export_photo_failed_format"),
                        error.localizedDescription
                    )
                )
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            if let alertSettingsURL {
                Button(String(localized: "wm_camera_go_to_settings_button")) {
                    openURL(alertSettingsURL)
                }
            }
            Button(String(localized: "wm_camera_ack_button"), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert(String(localized: "wm_camera_clear_photos_confirm_title"), isPresented: $showClearPhotosConfirm) {
            Button(String(localized: "取消"), role: .cancel) {}
            Button(String(localized: "wm_camera_clear_photos_confirm_button"), role: .destructive) {
                clearCapturedPhotos()
            }
        } message: {
            Text(String(localized: "wm_camera_clear_photos_confirm_message"))
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
                ContentUnavailableView(
                    String(localized: "wm_camera_no_log_draft_title"),
                    systemImage: "book.pages",
                    description: Text(String(localized: "wm_camera_capture_photo_first_message"))
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
                title: String(localized: "wm_camera_current_project_title"),
                projects: store.projects,
                selectedProjectId: $selectedProjectId,
                emptyText: String(localized: "wm_camera_unlinked_project_text")
            )
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

    private var projectAssociationText: String {
        guard let name = effectiveProjectName else { return String(localized: "wm_camera_unlinked_project_text") }
        return String(format: String(localized: "wm_camera_project_association_format"), name)
    }

    private func capturedPhotoMetaText(capturedAt: Date) -> String {
        WatermarkCameraTextBuilder.capturedPhotoMetaText(
            capturedAt: capturedAt,
            template: template,
            tag: tag
        )
    }

    private var exportFileName: String {
        WatermarkCameraTextBuilder.exportFileName(
            projectName: effectiveProjectName,
            capturedAt: capturedPhoto?.capturedAt
        )
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
        WatermarkCameraTextBuilder.logDraftContent(tag: tag)
    }

    private func handleCapturedImages(_ images: [UIImage], capturedAt: Date) {
        let outputs = images.map {
            WatermarkCapturedPhoto(
                image: $0.applyingCameraWatermark(context: currentContext, capturedAt: capturedAt),
                capturedAt: capturedAt
            )
        }
        guard !outputs.isEmpty else {
            presentError(String(localized: "wm_camera_capture_empty_result_error"))
            return
        }
        capturedPhotos = outputs
        selectedCapturedPhotoID = outputs.first?.id
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        presentToast(
            String(format: String(localized: "wm_camera_capture_success_toast_format"), outputs.count),
            style: .success
        )
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
        guard WatermarkCameraAccess.hasBackCamera else {
            presentBlockingError(String(localized: "wm_camera_device_unavailable_error"))
            return
        }
        Task { @MainActor in
            let isGranted = await WatermarkCameraAccess.requestCameraAccessIfNeeded()
            guard isGranted else {
                presentBlockingError(
                    String(localized: "wm_camera_permission_denied_error"),
                    settingsURL: WatermarkCameraAccess.appSettingsURL
                )
                return
            }
            showCamera = true
        }
    }

    private func exportCurrentImage() {
        guard let image = capturedPhoto?.image,
              let data = image.jpegData(compressionQuality: exportQuality.compression) else {
            presentError(String(localized: "wm_camera_export_photo_failed"))
            return
        }
        exportData = data
        showExporter = true
    }

    private func saveCurrentImageToAlbum() {
        guard let image = capturedPhoto?.image else {
            presentError(String(localized: "wm_camera_capture_photo_first_message"))
            return
        }

        saveImagesToAlbum([image])
    }

    private func saveAllImagesToAlbum() {
        let images = capturedPhotos.map(\.image)
        guard !images.isEmpty else {
            presentError(String(localized: "wm_camera_capture_photo_first_message"))
            return
        }
        saveImagesToAlbum(images)
    }

    private func saveImagesToAlbum(_ images: [UIImage]) {
        Task { @MainActor in
            let access = await WatermarkCameraAccess.requestPhotoLibraryAddAccessIfNeeded()
            switch access {
            case .granted:
                break
            case .rejectedRequest:
                presentBlockingError(
                    String(localized: "wm_camera_album_permission_missing_error"),
                    settingsURL: WatermarkCameraAccess.appSettingsURL
                )
                return
            case .denied:
                presentBlockingError(
                    String(localized: "wm_camera_album_permission_settings_error"),
                    settingsURL: WatermarkCameraAccess.appSettingsURL
                )
                return
            case .unknown:
                presentError(String(localized: "wm_camera_album_permission_unknown_error"))
                return
            }

            savingToAlbum = true
            do {
                try await WatermarkPhotoAlbumWriter.write(images)
                savingToAlbum = false
                if images.count > 1 {
                    presentInfo(String(format: String(localized: "wm_camera_save_album_multi_success_format"), images.count))
                } else {
                    presentInfo(String(localized: "wm_camera_save_album_single_success"))
                }
            } catch {
                savingToAlbum = false
                presentError(
                    String(
                        format: String(localized: "wm_camera_save_album_failed_format"),
                        error.localizedDescription
                    )
                )
            }
        }
    }

    private func watermarkPhotoNote(capturedAt: Date) -> String {
        WatermarkCameraTextBuilder.photoNote(
            capturedAt: capturedAt,
            photographer: photographer,
            locationText: locationText,
            tag: tag
        )
    }

    @MainActor
    private func saveCurrentImageAsProjectDocument() {
        guard let selectedProjectId else {
            presentError(String(localized: "wm_camera_pick_project_first_error"))
            return
        }
        guard let capturedPhoto else {
            presentError(String(localized: "wm_camera_capture_photo_first_message"))
            return
        }
        let error = WatermarkCameraProjectDocumentWriter.attach(
            photo: capturedPhoto,
            projectId: selectedProjectId,
            note: watermarkPhotoNote(capturedAt: capturedPhoto.capturedAt),
            store: store
        )
        if let error {
            presentError(error)
        } else {
            presentInfo(String(localized: "wm_camera_attach_project_document_success"))
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
        alertTitle = String(localized: "wm_camera_alert_cannot_continue_title")
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
