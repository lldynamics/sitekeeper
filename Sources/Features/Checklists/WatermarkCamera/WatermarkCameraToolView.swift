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
    @State private var showCamera = false
    @State var alertTitle = AppLocalization.string("wm_camera_alert_cannot_continue_title")
    @State var alertMessage = ""
    @State var alertSettingsURL: URL?
    @State var showAlert = false
    @State private var didAutoOpenCamera = false
    @State private var showLogDraft = false
    @State private var showClearPhotosConfirm = false
    @State var toast: WatermarkToast?
    @StateObject private var locationManager = WatermarkCameraLocationManager()

    init(initialProjectId: UUID? = nil, autoOpenCameraOnAppear: Bool = false) {
        self.initialProjectId = initialProjectId
        self.autoOpenCameraOnAppear = autoOpenCameraOnAppear
    }

    var body: some View {
        Form {
            projectSection
            WatermarkTemplateSection(templateRaw: binding(for: \.templateRaw))
            WatermarkCaptureSection(openCamera: openCamera)
            WatermarkInfoSection(
                tag: binding(for: \.tag),
                photographer: binding(for: \.photographer),
                locationText: binding(for: \.locationText),
                locationStatusText: locationStatusText,
                requestLocation: locationManager.requestLocation
            )
            WatermarkCameraSettingsSection(
                exportQuality: exportQualityBinding,
                showGrid: binding(for: \.showGrid),
                flashEnabled: binding(for: \.flashEnabled),
                burstCount: binding(for: \.burstCount),
                boundedBurstCount: settings.boundedBurstCount
            )
            WatermarkAutoSaveSection(
                autoSaveToAlbum: binding(for: \.autoSaveToAlbum),
                autoOpenLogDraft: binding(for: \.autoOpenLogDraft)
            )
            WatermarkCapturePreviewSection(
                capturedPhoto: capturedPhoto,
                capturedPhotos: captures.photos,
                selectedCapturedPhotoID: selectedCapturedPhotoIDBinding,
                hasMultipleCapturedPhotos: captures.hasMultiplePhotos,
                selectedCapturedPhotoNumber: captures.selectedPhotoNumber,
                projectAssociationText: projectAssociationText,
                capturedPhotoMetaText: capturedPhotoMetaText(capturedAt:),
                savingToAlbum: exportCoordinator.savingToAlbum,
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
        .navigationTitle(AppLocalization.string("wm_camera_nav_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            WatermarkCameraToolbarContent(
                hasCapturedPhoto: capturedPhoto != nil,
                hasMultipleCapturedPhotos: captures.hasMultiplePhotos,
                savingToAlbum: exportCoordinator.savingToAlbum,
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
                showGrid: settings.showGrid,
                flashEnabled: settings.flashEnabled,
                burstCount: settings.boundedBurstCount
            ) { images, capturedAt in
                handleCapturedImages(images, capturedAt: capturedAt)
            }
        }
        .fileExporter(
            isPresented: showExporterBinding,
            document: ExportDocument(data: exportCoordinator.exportData),
            contentType: .jpeg,
            defaultFilename: exportFileName
        ) { result in
            switch result {
            case .success:
                presentInfo(AppLocalization.string("wm_camera_export_photo_success"))
            case .failure(let error):
                presentError(
                    String(
                        format: AppLocalization.string("wm_camera_export_photo_failed_format"),
                        error.localizedDescription
                    )
                )
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            if let alertSettingsURL {
                Button(AppLocalization.string("wm_camera_go_to_settings_button")) {
                    openURL(alertSettingsURL)
                }
            }
            Button(AppLocalization.string("wm_camera_ack_button"), role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert(AppLocalization.string("wm_camera_clear_photos_confirm_title"), isPresented: $showClearPhotosConfirm) {
            Button(AppLocalization.string("取消"), role: .cancel) {}
            Button(AppLocalization.string("wm_camera_clear_photos_confirm_button"), role: .destructive) {
                clearCapturedPhotos()
            }
        } message: {
            Text(AppLocalization.string("wm_camera_clear_photos_confirm_message"))
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
                    AppLocalization.string("wm_camera_no_log_draft_title"),
                    systemImage: "book.pages",
                    description: Text(AppLocalization.string("wm_camera_capture_photo_first_message"))
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
        .onChange(of: settings.burstCount) { _, _ in
            settings.normalizeBurstCount()
        }
        .onReceive(locationManager.$locationText) { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            settings.locationText = trimmed
        }
        .animation(.easeInOut(duration: 0.2), value: toast?.id)
        .onAppear {
            restoreInitialProjectIfNeeded()
            settings.normalizeBurstCount()
            guard autoOpenCameraOnAppear, !didAutoOpenCamera else { return }
            didAutoOpenCamera = true
            openCamera()
        }
    }

    private var projectSection: some View {
        Section {
            ProjectContextStrip(
                title: AppLocalization.string("wm_camera_current_project_title"),
                projects: store.projects,
                selectedProjectId: selectedProjectIdBinding,
                emptyText: AppLocalization.string("wm_camera_unlinked_project_text")
            )
        }
    }

    private var selectedProjectId: UUID? {
        settings.selectedProjectId
    }

    private var capturedPhoto: WatermarkCapturedPhoto? {
        captures.selectedPhoto
    }

    private var currentContext: CameraWatermarkContext {
        CameraWatermarkContext(
            projectName: effectiveProjectName,
            template: settings.template,
            tag: settings.tag,
            photographer: settings.photographer,
            locationText: settings.locationText
        )
    }

    private var effectiveProjectName: String? {
        if let selectedProjectId,
           let project = store.projects.first(where: { $0.id == selectedProjectId }) {
            return project.name
        }
        let trimmed = settings.projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var locationStatusText: String {
        locationManager.statusText
    }

    private var projectAssociationText: String {
        guard let name = effectiveProjectName else { return AppLocalization.string("wm_camera_unlinked_project_text") }
        return String(format: AppLocalization.string("wm_camera_project_association_format"), name)
    }

    private var exportFileName: String {
        WatermarkCameraTextBuilder.exportFileName(
            projectName: effectiveProjectName,
            capturedAt: capturedPhoto?.capturedAt
        )
    }

    private var logDraftCoordinator: WatermarkCameraLogDraftCoordinator {
        WatermarkCameraLogDraftCoordinator(
            tag: settings.tag,
            photographer: settings.photographer,
            locationText: settings.locationText,
            exportQuality: settings.exportQuality
        )
    }

    private var logSeedPhoto: DailyLogSeedPhoto? {
        logDraftCoordinator.logSeedPhoto(for: capturedPhoto)
    }

    private var todoSeedData: Data? {
        logDraftCoordinator.todoSeedData(for: capturedPhoto)
    }

    private var logDraftContent: String {
        logDraftCoordinator.logDraftContent
    }

    private var exportQualityBinding: Binding<WatermarkExportQuality> {
        Binding(
            get: { settings.exportQuality },
            set: { settings.exportQuality = $0 }
        )
    }

    private var selectedProjectIdBinding: Binding<UUID?> {
        Binding(
            get: { settings.selectedProjectId },
            set: { newValue in
                settings.selectedProjectId = newValue
                syncProjectName(with: newValue)
            }
        )
    }

    private var selectedCapturedPhotoIDBinding: Binding<UUID?> {
        Binding(
            get: { captures.selectedPhotoID },
            set: { captures.selectedPhotoID = $0 }
        )
    }

    private var showExporterBinding: Binding<Bool> {
        Binding(
            get: { exportCoordinator.showExporter },
            set: { exportCoordinator.showExporter = $0 }
        )
    }

    private func binding<Value>(
        for keyPath: ReferenceWritableKeyPath<WatermarkCameraSettingsStore, Value>
    ) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }

    private func capturedPhotoMetaText(capturedAt: Date) -> String {
        WatermarkCameraTextBuilder.capturedPhotoMetaText(
            capturedAt: capturedAt,
            template: settings.template,
            tag: settings.tag
        )
    }

    private func restoreInitialProjectIfNeeded() {
        if let initialProjectId {
            settings.selectedProjectId = initialProjectId
            syncProjectName(with: initialProjectId)
        } else {
            syncProjectName(with: settings.selectedProjectId)
        }
    }

    private func syncProjectName(with projectId: UUID?) {
        guard let project = projectId.flatMap({ id in store.projects.first { $0.id == id } }) else { return }
        settings.projectName = project.name
    }

    private func handleCapturedImages(_ images: [UIImage], capturedAt: Date) {
        let count = captures.replace(with: images, capturedAt: capturedAt, context: currentContext)
        guard count > 0 else {
            presentError(AppLocalization.string("wm_camera_capture_empty_result_error"))
            return
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        presentToast(
            String(format: AppLocalization.string("wm_camera_capture_success_toast_format"), count),
            style: .success
        )
        if settings.autoSaveToAlbum {
            if count > 1 {
                saveAllImagesToAlbum()
            } else {
                saveCurrentImageToAlbum()
            }
        }
        if settings.autoOpenLogDraft, selectedProjectId != nil, logSeedPhoto != nil {
            showLogDraft = true
        }
    }

    private func openCamera() {
        guard WatermarkCameraAccess.hasBackCamera else {
            presentBlockingError(AppLocalization.string("wm_camera_device_unavailable_error"))
            return
        }
        Task { @MainActor in
            let isGranted = await WatermarkCameraAccess.requestCameraAccessIfNeeded()
            guard isGranted else {
                presentBlockingError(
                    AppLocalization.string("wm_camera_permission_denied_error"),
                    settingsURL: WatermarkCameraAccess.appSettingsURL
                )
                return
            }
            showCamera = true
        }
    }

    private func exportCurrentImage() {
        guard exportCoordinator.prepareExport(photo: capturedPhoto, quality: settings.exportQuality) else {
            presentError(AppLocalization.string("wm_camera_export_photo_failed"))
            return
        }
    }

    private func saveCurrentImageToAlbum() {
        guard let image = capturedPhoto?.image else {
            presentError(AppLocalization.string("wm_camera_capture_photo_first_message"))
            return
        }

        saveImagesToAlbum([image])
    }

    private func saveAllImagesToAlbum() {
        let images = captures.photos.map(\.image)
        guard !images.isEmpty else {
            presentError(AppLocalization.string("wm_camera_capture_photo_first_message"))
            return
        }
        saveImagesToAlbum(images)
    }

    private func saveImagesToAlbum(_ images: [UIImage]) {
        Task { @MainActor in
            handleAlbumSaveResult(await exportCoordinator.saveImagesToAlbum(images))
        }
    }

    private func handleAlbumSaveResult(_ result: WatermarkCameraAlbumSaveResult) {
        switch result {
        case .success(let count):
            if count > 1 {
                presentInfo(String(format: AppLocalization.string("wm_camera_save_album_multi_success_format"), count))
            } else {
                presentInfo(AppLocalization.string("wm_camera_save_album_single_success"))
            }
        case .blockingError(let message, let settingsURL):
            presentBlockingError(message, settingsURL: settingsURL)
        case .error(let message):
            presentError(message)
        }
    }

    @MainActor
    private func saveCurrentImageAsProjectDocument() {
        guard let selectedProjectId else {
            presentError(AppLocalization.string("wm_camera_pick_project_first_error"))
            return
        }
        guard let capturedPhoto else {
            presentError(AppLocalization.string("wm_camera_capture_photo_first_message"))
            return
        }
        let error = WatermarkCameraProjectDocumentWriter.attach(
            photo: capturedPhoto,
            projectId: selectedProjectId,
            note: logDraftCoordinator.photoNote(capturedAt: capturedPhoto.capturedAt),
            store: store
        )
        if let error {
            presentError(error)
        } else {
            presentInfo(AppLocalization.string("wm_camera_attach_project_document_success"))
        }
    }

    private func clearCapturedPhotos() {
        captures.clear()
    }
}
