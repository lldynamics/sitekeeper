import SwiftUI
import UIKit

enum WatermarkPhotoDeliveryStatus: String, Codable, Sendable {
    case pending
    case completed
    case failed
}

/// Metadata is frozen when the shutter fires. Only delivery status can change.
/// Successful drafts retain thumbnail pixels and file URLs, not full-resolution images.
struct WatermarkCapturedPhoto: Identifiable, Sendable {
    let id: UUID
    let capturedAt: Date
    let context: CameraWatermarkContext
    let projectId: UUID?
    let thumbnail: UIImage
    let originalURL: URL?
    let watermarkedURL: URL?
    var albumStatus: WatermarkPhotoDeliveryStatus = .pending
    var albumFailure: String?
    var archiveStatus: WatermarkPhotoDeliveryStatus = .pending
    var archiveFailure: String?
    // Only failed disk writes retain compressed payloads so retry cannot lose the capture.
    let pendingOriginalData: Data?
    let pendingWatermarkedData: Data?
    let fallbackOriginalImage: UIImage?
    let fallbackWatermarkedImage: UIImage?

    var isPersisted: Bool { originalURL != nil && watermarkedURL != nil }

    var image: UIImage {
        if let watermarkedURL, let image = UIImage(contentsOfFile: watermarkedURL.path) { return image }
        if let pendingWatermarkedData, let image = UIImage(data: pendingWatermarkedData) { return image }
        return fallbackWatermarkedImage ?? thumbnail
    }

    /// Delivery must never substitute a thumbnail for missing evidence.
    func imageForDelivery() throws -> UIImage {
        if let watermarkedURL {
            guard let image = UIImage(contentsOfFile: watermarkedURL.path) else { throw WatermarkDraftImageError.missingImage }
            return image
        }
        if let pendingWatermarkedData {
            guard let image = UIImage(data: pendingWatermarkedData) else { throw WatermarkDraftImageError.missingImage }
            return image
        }
        if let fallbackWatermarkedImage { return fallbackWatermarkedImage }
        // Legacy in-memory constructor stores its full image in this field.
        if originalURL == nil && pendingOriginalData == nil && fallbackOriginalImage == nil { return thumbnail }
        throw WatermarkDraftImageError.missingImage
    }

    func jpegDataForDelivery(compression: CGFloat) throws -> Data {
        guard let data = try imageForDelivery().jpegData(compressionQuality: compression) else {
            throw WatermarkDraftImageError.encodingFailed
        }
        return data
    }

    var originalImage: UIImage? {
        if let originalURL { return UIImage(contentsOfFile: originalURL.path) }
        return pendingOriginalData.flatMap { UIImage(data: $0) } ?? fallbackOriginalImage
    }

    init(
        id: UUID = UUID(), image: UIImage, capturedAt: Date,
        context: CameraWatermarkContext = CameraWatermarkContext(
            projectName: "", template: .constructionLog, tag: "", photographer: "", locationText: ""
        ), projectId: UUID? = nil,
        originalURL: URL? = nil, watermarkedURL: URL? = nil,
        pendingOriginalData: Data? = nil, pendingWatermarkedData: Data? = nil,
        fallbackOriginalImage: UIImage? = nil, fallbackWatermarkedImage: UIImage? = nil
    ) {
        self.id = id
        self.thumbnail = image
        self.capturedAt = capturedAt
        self.context = context
        self.projectId = projectId
        self.originalURL = originalURL
        self.watermarkedURL = watermarkedURL
        self.pendingOriginalData = pendingOriginalData
        self.pendingWatermarkedData = pendingWatermarkedData
        self.fallbackOriginalImage = fallbackOriginalImage
        self.fallbackWatermarkedImage = fallbackWatermarkedImage
    }
}

enum WatermarkDraftImageError: LocalizedError {
    case missingImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingImage: return "照片原文件丢失或已损坏，无法导出或归档。"
        case .encodingFailed: return "照片编码失败，请重试。"
        }
    }
}

enum WatermarkExportQuality: String, CaseIterable {
    case standard
    case high

    var displayName: String {
        switch self {
        case .standard:
            return AppLocalization.string("wm_camera_export_quality_standard")
        case .high:
            return AppLocalization.string("wm_camera_export_quality_high")
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

enum WatermarkToastStyle {
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

struct WatermarkToast: Identifiable {
    let id = UUID()
    let message: String
    let style: WatermarkToastStyle
}

struct WatermarkToastView: View {
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
