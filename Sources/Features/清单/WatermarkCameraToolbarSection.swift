import SwiftUI

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
