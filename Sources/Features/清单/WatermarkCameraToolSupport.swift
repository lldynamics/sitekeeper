import AVFoundation
import Foundation
import Photos
import UIKit

enum WatermarkPhotoLibraryAccessResult {
    case granted
    case rejectedRequest
    case denied
    case unknown
}

enum WatermarkCameraAccess {
    static var appSettingsURL: URL? {
        URL(string: UIApplication.openSettingsURLString)
    }

    static var hasBackCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    static func requestCameraAccessIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await PermissionRequestTimeoutSupport.resolve(fallback: false) { resume in
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    resume(granted)
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    static func requestPhotoLibraryAddAccessIfNeeded() async -> WatermarkPhotoLibraryAccessResult {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited:
            return .granted
        case .notDetermined:
            return await PermissionRequestTimeoutSupport.resolve(fallback: .unknown) { resume in
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
                    switch newStatus {
                    case .authorized, .limited:
                        resume(.granted)
                    case .denied, .restricted:
                        resume(.rejectedRequest)
                    case .notDetermined:
                        resume(.unknown)
                    @unknown default:
                        resume(.unknown)
                    }
                }
            }
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .unknown
        }
    }
}

enum WatermarkPhotoAlbumWriter {
    struct WriteError: LocalizedError {
        var errorDescription: String? {
            String(localized: "wm_camera_unknown_error")
        }
    }

    static func write(_ images: [UIImage]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges {
                for image in images {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? WriteError())
                }
            }
        }
    }
}

enum WatermarkCameraTextBuilder {
    static func capturedPhotoMetaText(
        capturedAt: Date,
        template: CameraWatermarkTemplate,
        tag: String
    ) -> String {
        let time = Formatters.dateTime.string(from: capturedAt)
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTag.isEmpty {
            return String(format: String(localized: "wm_camera_capture_meta_without_tag_format"), time, template.displayName)
        }
        return String(format: String(localized: "wm_camera_capture_meta_with_tag_format"), time, template.displayName, trimmedTag)
    }

    static func exportFileName(projectName: String?, capturedAt: Date?) -> String {
        let base = projectName ?? String(localized: "wm_camera_export_default_name")
        let safe = base.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return "\(safe)_\(compactTimestamp(from: capturedAt ?? Date()))"
    }

    static func logDraftContent(tag: String) -> String {
        let trimmedTag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTag.isEmpty {
            return String(localized: "wm_camera_log_draft_default_content")
        }
        return String(format: String(localized: "wm_camera_log_draft_with_tag_format"), trimmedTag)
    }

    static func photoNote(
        capturedAt: Date,
        photographer: String,
        locationText: String,
        tag: String
    ) -> String {
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

    private static func compactTimestamp(from date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }
}

enum WatermarkCameraProjectDocumentWriter {
    @MainActor
    static func attach(
        photo: WatermarkCapturedPhoto,
        projectId: UUID,
        note: String,
        store: DataStore
    ) -> String? {
        ProjectDetailFinanceDocumentActions.importCapturedImage(
            photo.image,
            title: String(
                format: String(localized: "wm_camera_project_document_title_format"),
                Formatters.dateTime.string(from: photo.capturedAt)
            ),
            createdAt: Formatters.dateTime.string(from: photo.capturedAt),
            category: .constructionRecord,
            note: note,
            projectId: projectId,
            store: store
        )
    }
}
