import SwiftUI
import UniformTypeIdentifiers
import UIKit
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
            templateSection
            captureSection
            watermarkInfoSection
            cameraSettingsSection
            autoSaveSection
            recentCaptureSection
        }
        .navigationTitle(String(localized: "wm_camera_nav_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if capturedPhoto != nil {
                    watermarkMoreMenu(isToolbar: true)
                }

                Button {
                    openCamera()
                } label: {
                    Image(systemName: "plus").visibleIconStyle()
                }
                .accessibilityLabel(String(localized: "wm_camera_capture_button"))
            }
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
            Label(String(localized: "wm_camera_template_section_title"), systemImage: "rectangle.and.pencil.and.ellipsis")
        }
    }

    private var captureSection: some View {
        Section {
            Button {
                openCamera()
            } label: {
                Label(String(localized: "wm_camera_capture_button"), systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.appProminent())
        }
    }

    private var watermarkInfoSection: some View {
        Section {
            TextField(String(localized: "wm_camera_tag_field"), text: $tag)
            TextField(String(localized: "wm_camera_photographer_field"), text: $photographer)
            HStack {
                TextField(String(localized: "wm_camera_location_field"), text: $locationText)
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
            Label(String(localized: "wm_camera_info_section_title"), systemImage: "info.circle")
        }
    }

    private var cameraSettingsSection: some View {
        Section {
            DisclosureGroup {
                Picker(String(localized: "wm_camera_export_quality_picker"), selection: exportQualityBinding) {
                    ForEach(WatermarkExportQuality.allCases, id: \.self) { quality in
                        Text(quality.displayName).tag(quality)
                    }
                }
                Toggle(String(localized: "wm_camera_show_grid_toggle"), isOn: $showGrid)
                Toggle(String(localized: "wm_camera_flash_default_toggle"), isOn: $flashEnabled)
                Stepper(
                    String(
                        format: String(localized: "wm_camera_burst_count_stepper_format"),
                        boundedBurstCount
                    ),
                    value: $burstCount,
                    in: 1...5
                )
            } label: {
                Label(String(localized: "wm_camera_settings_section_title"), systemImage: "camera.fill")
            }
        }
    }

    private var autoSaveSection: some View {
        Section {
            Toggle(String(localized: "wm_camera_auto_save_album_toggle"), isOn: $autoSaveToAlbum)
            Toggle(String(localized: "wm_camera_auto_open_log_draft_toggle"), isOn: $autoOpenLogDraft)
        }
    }

    @ViewBuilder
    private var recentCaptureSection: some View {
        if let capturedPhoto {
            Section(String(localized: "wm_camera_recent_capture_section_title")) {
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
                        Text(
                            String(
                                format: String(localized: "wm_camera_burst_progress_text_format"),
                                capturedPhotos.count,
                                selectedCapturedPhotoNumber
                            )
                        )
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                recentCaptureActions
            }
        } else {
            Section(String(localized: "wm_camera_recent_capture_section_title")) {
                ContentUnavailableView(
                    String(localized: "wm_camera_no_photo_title"),
                    systemImage: "camera.aperture",
                    description: Text(String(localized: "wm_camera_no_photo_message"))
                )
            }
        }
    }

    private var recentCaptureActions: some View {
        HStack(spacing: 12) {
            Button {
                saveCurrentImageToAlbum()
            } label: {
                Label(String(localized: "wm_camera_save_album_button"), systemImage: "photo.on.rectangle.angled")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(savingToAlbum)

            watermarkMoreMenu(isToolbar: false)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func watermarkMoreMenu(isToolbar: Bool) -> some View {
        Menu {
            Section(String(localized: "导出")) {
                Button {
                    exportCurrentImage()
                } label: {
                    Label(String(localized: "wm_camera_export_button"), systemImage: "square.and.arrow.up")
                }
            }

            Section(String(localized: "wm_camera_save_section_title")) {
                if hasMultipleCapturedPhotos {
                    Button {
                        saveAllImagesToAlbum()
                    } label: {
                        Label(String(localized: "wm_camera_save_all_button"), systemImage: "photo.stack")
                    }
                    .disabled(savingToAlbum)
                }

                Button {
                    saveCurrentImageAsProjectDocument()
                } label: {
                    Label(String(localized: "wm_camera_attach_project_document_button"), systemImage: "folder.badge.plus")
                }
                .disabled(selectedProjectId == nil)
            }

            Section(String(localized: "wm_camera_convert_section_title")) {
                if let logSeedPhoto {
                    NavigationLink {
                        DailyLogView(
                            initialProjectId: selectedProjectId,
                            autoOpenComposer: true,
                            initialPhotoDrafts: [logSeedPhoto],
                            initialContent: logDraftContent
                        )
                    } label: {
                        Label(String(localized: "wm_camera_enter_daily_log_menu"), systemImage: "book.pages.fill")
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
                        Label(String(localized: "wm_camera_convert_to_before_fix_todo_menu"), systemImage: "checklist")
                    }
                    NavigationLink {
                        SiteTodoView(
                            initialProjectId: selectedProjectId,
                            autoOpenComposer: true,
                            initialAfterPhotoData: todoSeedData
                        )
                    } label: {
                        Label(String(localized: "wm_camera_convert_to_after_fix_todo_menu"), systemImage: "checkmark.seal.fill")
                    }
                }
            }

            Section(String(localized: "删除")) {
                Button(role: .destructive) {
                    showClearPhotosConfirm = true
                } label: {
                    Label(String(localized: "wm_camera_clear_photos_menu"), systemImage: "trash")
                }
            }
        } label: {
            if isToolbar {
                Image(systemName: "ellipsis.circle").visibleIconStyle()
            } else {
                Label(String(localized: "wm_camera_more_menu"), systemImage: "ellipsis.circle")
                    .font(.caption.weight(.semibold))
            }
        }
        .accessibilityLabel(String(localized: "更多操作"))
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
        guard let name = effectiveProjectName else { return String(localized: "wm_camera_unlinked_project_text") }
        return String(format: String(localized: "wm_camera_project_association_format"), name)
    }

    private func capturedPhotoMetaText(capturedAt: Date) -> String {
        let time = Formatters.dateTime.string(from: capturedAt)
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTag.isEmpty {
            return String(format: String(localized: "wm_camera_capture_meta_without_tag_format"), time, template.displayName)
        }
        return String(format: String(localized: "wm_camera_capture_meta_with_tag_format"), time, template.displayName, trimmedTag)
    }

    private var exportFileName: String {
        let base = effectiveProjectName ?? String(localized: "wm_camera_export_default_name")
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
            return String(localized: "wm_camera_log_draft_default_content")
        }
        return String(format: String(localized: "wm_camera_log_draft_with_tag_format"), trimmedTag)
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
        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            presentBlockingError(String(localized: "wm_camera_device_unavailable_error"))
            return
        }
        Task { @MainActor in
            let isGranted = await requestCameraAccessIfNeeded()
            guard isGranted else {
                presentBlockingError(
                    String(localized: "wm_camera_permission_denied_error"),
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

        performWithPhotoLibraryAccess {
            writeImagesToAlbum([image])
        }
    }

    private func saveAllImagesToAlbum() {
        let images = capturedPhotos.map(\.image)
        guard !images.isEmpty else {
            presentError(String(localized: "wm_camera_capture_photo_first_message"))
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
                            String(localized: "wm_camera_album_permission_missing_error"),
                            settingsURL: appSettingsURL
                        )
                    }
                }
            }
        case .denied, .restricted:
            presentBlockingError(
                String(localized: "wm_camera_album_permission_settings_error"),
                settingsURL: appSettingsURL
            )
        @unknown default:
            presentError(String(localized: "wm_camera_album_permission_unknown_error"))
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
                    if images.count > 1 {
                        presentInfo(String(format: String(localized: "wm_camera_save_album_multi_success_format"), images.count))
                    } else {
                        presentInfo(String(localized: "wm_camera_save_album_single_success"))
                    }
                } else {
                    presentError(
                        String(
                            format: String(localized: "wm_camera_save_album_failed_format"),
                            error?.localizedDescription ?? String(localized: "wm_camera_unknown_error")
                        )
                    )
                }
            }
        }
    }

    private func watermarkPhotoNote(capturedAt: Date) -> String {
        [
            String(localized: "wm_camera_photo_note_source"),
            String(
                format: String(localized: "wm_camera_photo_note_capture_time_format"),
                Formatters.dateTime.string(from: capturedAt)
            ),
            photographer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : String(format: String(localized: "wm_camera_photo_note_photographer_format"), photographer),
            locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : String(format: String(localized: "wm_camera_photo_note_location_format"), locationText),
            tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : String(format: String(localized: "wm_camera_photo_note_tag_format"), tag)
        ].compactMap { $0 }.joined(separator: "\n")
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
        let error = ProjectDetailFinanceDocumentActions.importCapturedImage(
            capturedPhoto.image,
            title: String(
                format: String(localized: "wm_camera_project_document_title_format"),
                Formatters.dateTime.string(from: capturedPhoto.capturedAt)
            ),
            createdAt: Formatters.dateTime.string(from: capturedPhoto.capturedAt),
            category: .constructionRecord,
            note: watermarkPhotoNote(capturedAt: capturedPhoto.capturedAt),
            projectId: selectedProjectId,
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
            return String(localized: "wm_camera_export_quality_standard")
        case .high:
            return String(localized: "wm_camera_export_quality_high")
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

private extension Formatters {
    static func compactTimestamp(from date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }
}
