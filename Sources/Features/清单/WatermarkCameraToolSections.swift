import SwiftUI
import UIKit

struct WatermarkTemplateSection: View {
    @Binding var templateRaw: String

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CameraWatermarkTemplate.allCases, id: \.rawValue) { template in
                        let isSelected = templateRaw == template.rawValue
                        Button {
                            templateRaw = template.rawValue
                        } label: {
                            WatermarkTemplateChip(
                                title: template.displayName,
                                systemImage: template.icon,
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
}

struct WatermarkCaptureSection: View {
    let openCamera: () -> Void

    var body: some View {
        Section {
            Button(action: openCamera) {
                Label(String(localized: "wm_camera_capture_button"), systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.appProminent())
        }
    }
}

struct WatermarkInfoSection: View {
    @Binding var tag: String
    @Binding var photographer: String
    @Binding var locationText: String
    let locationStatusText: String
    let requestLocation: () -> Void

    var body: some View {
        Section {
            TextField(String(localized: "wm_camera_tag_field"), text: $tag)
            TextField(String(localized: "wm_camera_photographer_field"), text: $photographer)
            HStack {
                TextField(String(localized: "wm_camera_location_field"), text: $locationText)
                Button(action: requestLocation) {
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
}

struct WatermarkCameraSettingsSection: View {
    @Binding var exportQuality: WatermarkExportQuality
    @Binding var showGrid: Bool
    @Binding var flashEnabled: Bool
    @Binding var burstCount: Int
    let boundedBurstCount: Int

    var body: some View {
        Section {
            DisclosureGroup {
                Picker(String(localized: "wm_camera_export_quality_picker"), selection: $exportQuality) {
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
}

struct WatermarkAutoSaveSection: View {
    @Binding var autoSaveToAlbum: Bool
    @Binding var autoOpenLogDraft: Bool

    var body: some View {
        Section {
            Toggle(String(localized: "wm_camera_auto_save_album_toggle"), isOn: $autoSaveToAlbum)
            Toggle(String(localized: "wm_camera_auto_open_log_draft_toggle"), isOn: $autoOpenLogDraft)
        }
    }
}

struct WatermarkCapturePreviewSection: View {
    let capturedPhoto: WatermarkCapturedPhoto?
    let capturedPhotos: [WatermarkCapturedPhoto]
    @Binding var selectedCapturedPhotoID: UUID?
    let hasMultipleCapturedPhotos: Bool
    let selectedCapturedPhotoNumber: Int
    let projectAssociationText: String
    let capturedPhotoMetaText: (Date) -> String
    let savingToAlbum: Bool
    let selectedProjectId: UUID?
    let logSeedPhoto: DailyLogSeedPhoto?
    let logDraftContent: String
    let todoSeedData: Data?
    let saveCurrentImageToAlbum: () -> Void
    let exportCurrentImage: () -> Void
    let saveAllImagesToAlbum: () -> Void
    let saveCurrentImageAsProjectDocument: () -> Void
    let requestClearPhotos: () -> Void

    var body: some View {
        if let capturedPhoto {
            Section(String(localized: "wm_camera_recent_capture_section_title")) {
                WatermarkCapturedPhotoPreview(photo: capturedPhoto)
                WatermarkCapturedPhotoList(
                    capturedPhotos: capturedPhotos,
                    selectedPhoto: capturedPhoto,
                    selectedCapturedPhotoID: $selectedCapturedPhotoID,
                    hasMultipleCapturedPhotos: hasMultipleCapturedPhotos
                )
                WatermarkCapturedPhotoMeta(
                    photo: capturedPhoto,
                    capturedPhotosCount: capturedPhotos.count,
                    hasMultipleCapturedPhotos: hasMultipleCapturedPhotos,
                    selectedCapturedPhotoNumber: selectedCapturedPhotoNumber,
                    projectAssociationText: projectAssociationText,
                    capturedPhotoMetaText: capturedPhotoMetaText
                )
                WatermarkRecentCaptureActions(
                    hasMultipleCapturedPhotos: hasMultipleCapturedPhotos,
                    savingToAlbum: savingToAlbum,
                    selectedProjectId: selectedProjectId,
                    logSeedPhoto: logSeedPhoto,
                    logDraftContent: logDraftContent,
                    todoSeedData: todoSeedData,
                    saveCurrentImageToAlbum: saveCurrentImageToAlbum,
                    exportCurrentImage: exportCurrentImage,
                    saveAllImagesToAlbum: saveAllImagesToAlbum,
                    saveCurrentImageAsProjectDocument: saveCurrentImageAsProjectDocument,
                    requestClearPhotos: requestClearPhotos
                )
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
}

struct WatermarkCapturedPhotoPreview: View {
    let photo: WatermarkCapturedPhoto

    var body: some View {
        Image(uiImage: photo.image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct WatermarkCapturedPhotoList: View {
    let capturedPhotos: [WatermarkCapturedPhoto]
    let selectedPhoto: WatermarkCapturedPhoto
    @Binding var selectedCapturedPhotoID: UUID?
    let hasMultipleCapturedPhotos: Bool

    @ViewBuilder
    var body: some View {
        if hasMultipleCapturedPhotos {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(capturedPhotos.enumerated()), id: \.element.id) { index, photo in
                        Button {
                            selectedCapturedPhotoID = photo.id
                        } label: {
                            WatermarkCaptureThumbnail(
                                photo: photo,
                                index: index,
                                isSelected: photo.id == selectedPhoto.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

struct WatermarkCapturedPhotoMeta: View {
    let photo: WatermarkCapturedPhoto
    let capturedPhotosCount: Int
    let hasMultipleCapturedPhotos: Bool
    let selectedCapturedPhotoNumber: Int
    let projectAssociationText: String
    let capturedPhotoMetaText: (Date) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(capturedPhotoMetaText(photo.capturedAt))
            Text(projectAssociationText)
            if hasMultipleCapturedPhotos {
                Text(
                    String(
                        format: String(localized: "wm_camera_burst_progress_text_format"),
                        capturedPhotosCount,
                        selectedCapturedPhotoNumber
                    )
                )
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

struct WatermarkRecentCaptureActions: View {
    let hasMultipleCapturedPhotos: Bool
    let savingToAlbum: Bool
    let selectedProjectId: UUID?
    let logSeedPhoto: DailyLogSeedPhoto?
    let logDraftContent: String
    let todoSeedData: Data?
    let saveCurrentImageToAlbum: () -> Void
    let exportCurrentImage: () -> Void
    let saveAllImagesToAlbum: () -> Void
    let saveCurrentImageAsProjectDocument: () -> Void
    let requestClearPhotos: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: saveCurrentImageToAlbum) {
                Label(String(localized: "wm_camera_save_album_button"), systemImage: "photo.on.rectangle.angled")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(savingToAlbum)

            WatermarkMoreMenu(
                isToolbar: false,
                hasMultipleCapturedPhotos: hasMultipleCapturedPhotos,
                savingToAlbum: savingToAlbum,
                selectedProjectId: selectedProjectId,
                logSeedPhoto: logSeedPhoto,
                logDraftContent: logDraftContent,
                todoSeedData: todoSeedData,
                exportCurrentImage: exportCurrentImage,
                saveAllImagesToAlbum: saveAllImagesToAlbum,
                saveCurrentImageAsProjectDocument: saveCurrentImageAsProjectDocument,
                requestClearPhotos: requestClearPhotos
            )
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

struct WatermarkCameraToolbarContent: ToolbarContent {
    let hasCapturedPhoto: Bool
    let hasMultipleCapturedPhotos: Bool
    let savingToAlbum: Bool
    let selectedProjectId: UUID?
    let logSeedPhoto: DailyLogSeedPhoto?
    let logDraftContent: String
    let todoSeedData: Data?
    let openCamera: () -> Void
    let exportCurrentImage: () -> Void
    let saveAllImagesToAlbum: () -> Void
    let saveCurrentImageAsProjectDocument: () -> Void
    let requestClearPhotos: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if hasCapturedPhoto {
                WatermarkMoreMenu(
                    isToolbar: true,
                    hasMultipleCapturedPhotos: hasMultipleCapturedPhotos,
                    savingToAlbum: savingToAlbum,
                    selectedProjectId: selectedProjectId,
                    logSeedPhoto: logSeedPhoto,
                    logDraftContent: logDraftContent,
                    todoSeedData: todoSeedData,
                    exportCurrentImage: exportCurrentImage,
                    saveAllImagesToAlbum: saveAllImagesToAlbum,
                    saveCurrentImageAsProjectDocument: saveCurrentImageAsProjectDocument,
                    requestClearPhotos: requestClearPhotos
                )
            }

            Button(action: openCamera) {
                Image(systemName: "plus").visibleIconStyle()
            }
            .accessibilityLabel(String(localized: "wm_camera_capture_button"))
        }
    }
}

struct WatermarkMoreMenu: View {
    let isToolbar: Bool
    let hasMultipleCapturedPhotos: Bool
    let savingToAlbum: Bool
    let selectedProjectId: UUID?
    let logSeedPhoto: DailyLogSeedPhoto?
    let logDraftContent: String
    let todoSeedData: Data?
    let exportCurrentImage: () -> Void
    let saveAllImagesToAlbum: () -> Void
    let saveCurrentImageAsProjectDocument: () -> Void
    let requestClearPhotos: () -> Void

    var body: some View {
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
                Button(role: .destructive, action: requestClearPhotos) {
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

private struct WatermarkCaptureThumbnail: View {
    let photo: WatermarkCapturedPhoto
    let index: Int
    let isSelected: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 54)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected ? Color.appPrimaryAction : Color.appStrokeSecondary,
                            lineWidth: isSelected ? 2 : 1
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
}
