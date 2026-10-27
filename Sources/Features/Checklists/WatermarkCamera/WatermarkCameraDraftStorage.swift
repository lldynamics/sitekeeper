import Foundation
import ImageIO
import UIKit

struct WatermarkCameraDraftRecord: Codable, Sendable {
    let version: Int
    let id: UUID
    let capturedAt: Date
    let context: CameraWatermarkContext
    let projectId: UUID?
    var albumStatus: WatermarkPhotoDeliveryStatus
    var albumFailure: String?
    var archiveStatus: WatermarkPhotoDeliveryStatus
    var archiveFailure: String?

    init(photo: WatermarkCapturedPhoto) {
        version = 1
        id = photo.id
        capturedAt = photo.capturedAt
        context = photo.context
        projectId = photo.projectId
        albumStatus = photo.albumStatus
        albumFailure = photo.albumFailure
        archiveStatus = photo.archiveStatus
        archiveFailure = photo.archiveFailure
    }
}

struct WatermarkDraftStorageResult: Sendable {
    var photos: [WatermarkCapturedPhoto]
    var errors: [String]
}

/// All rendering, encoding and disk access happen on this actor, away from the UI actor.
/// Each draft is a self-contained directory published by one atomic rename. A broken
/// directory is never replaced during recovery; healthy neighbours remain usable.
actor WatermarkCameraDraftStorage {
    typealias DataWriter = @Sendable (Data, URL) throws -> Void
    let directory: URL
    private let writeData: DataWriter
    private let fileManager = FileManager.default
    // Different windows own different actors. Serialize only the short metadata transaction
    // so stale snapshots cannot overwrite another window's confirmed delivery status.
    private static let metadataLock = NSLock()

    static func scopedDirectory(for storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent()
            .appendingPathComponent("BusinessDrafts", isDirectory: true)
            .appendingPathComponent("WatermarkCamera", isDirectory: true)
    }

    init(directory: URL? = nil, writeData: @escaping DataWriter = { data, url in
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatermarkCameraDrafts", isDirectory: true)
        self.writeData = writeData
    }

    func capture(images: [UIImage], capturedAt: Date, context: CameraWatermarkContext, projectId: UUID?) -> WatermarkDraftStorageResult {
        var result = WatermarkDraftStorageResult(photos: [], errors: [])
        for image in images {
            autoreleasepool {
                let output = image.applyingCameraWatermark(context: context, capturedAt: capturedAt)
                let original = image.jpegData(compressionQuality: 1)
                let rendered = output.jpegData(compressionQuality: 0.96)
                let photo = WatermarkCapturedPhoto(
                    image: rendered.flatMap { thumbnail(data: $0) } ?? output,
                    capturedAt: capturedAt, context: context, projectId: projectId,
                    pendingOriginalData: original, pendingWatermarkedData: rendered,
                    fallbackOriginalImage: original == nil ? image : nil,
                    fallbackWatermarkedImage: rendered == nil ? output : nil
                )
                result.photos.append(persistOrRetain(photo, errors: &result.errors))
            }
        }
        return result
    }

    func annotatedCopy(image: UIImage, source: WatermarkCapturedPhoto) -> WatermarkDraftStorageResult {
        var result = WatermarkDraftStorageResult(photos: [], errors: [])
        do {
            let original: Data
            if let url = source.originalURL { original = try Data(contentsOf: url) }
            else if let data = source.pendingOriginalData { original = data }
            else { throw CocoaError(.fileReadNoSuchFile) }
            guard let rendered = image.jpegData(compressionQuality: 0.96) else { throw CocoaError(.fileWriteUnknown) }
            let photo = WatermarkCapturedPhoto(
                image: thumbnail(data: rendered) ?? image,
                capturedAt: source.capturedAt, context: source.context, projectId: source.projectId,
                pendingOriginalData: original, pendingWatermarkedData: rendered
            )
            result.photos.append(persistOrRetain(photo, errors: &result.errors))
        } catch {
            result.errors.append("无法保留标注副本：\(error.localizedDescription)")
        }
        return result
    }

    func retry(_ photos: [WatermarkCapturedPhoto]) -> WatermarkDraftStorageResult {
        var result = WatermarkDraftStorageResult(photos: [], errors: [])
        for photo in photos { result.photos.append(persistOrRetain(photo, errors: &result.errors)) }
        return result
    }

    func restore() -> WatermarkDraftStorageResult {
        guard fileManager.fileExists(atPath: directory.path) else {
            return WatermarkDraftStorageResult(photos: [], errors: [])
        }
        var result = WatermarkDraftStorageResult(photos: [], errors: [])
        do {
            let entries = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            for entry in entries {
                do {
                    // Incomplete staging directories are preserved for recovery and surfaced.
                    guard UUID(uuidString: entry.lastPathComponent) != nil else {
                        result.errors.append("发现未完成的照片草稿，原文件已保留：\(entry.lastPathComponent)")
                        continue
                    }
                    let record = try JSONDecoder().decode(WatermarkCameraDraftRecord.self, from: Data(contentsOf: entry.appendingPathComponent("metadata.json")))
                    guard record.version == 1, record.id.uuidString == entry.lastPathComponent else { throw CocoaError(.fileReadCorruptFile) }
                    let originalURL = entry.appendingPathComponent("original.jpg")
                    let renderedURL = entry.appendingPathComponent("watermarked.jpg")
                    guard let preview = thumbnail(url: renderedURL), thumbnail(url: originalURL) != nil else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    var photo = WatermarkCapturedPhoto(
                        id: record.id, image: preview, capturedAt: record.capturedAt,
                        context: record.context, projectId: record.projectId,
                        originalURL: originalURL, watermarkedURL: renderedURL
                    )
                    photo.albumStatus = record.albumStatus
                    photo.albumFailure = record.albumFailure
                    photo.archiveStatus = record.archiveStatus
                    photo.archiveFailure = record.archiveFailure
                    result.photos.append(photo)
                } catch {
                    result.errors.append("草稿无法读取，原文件已保留（\(entry.lastPathComponent)）：\(error.localizedDescription)")
                }
            }
        } catch { result.errors.append("无法读取照片草稿：\(error.localizedDescription)") }
        result.photos.sort { $0.capturedAt < $1.capturedAt }
        return result
    }

    @discardableResult
    func updateStatus(_ photo: WatermarkCapturedPhoto) throws -> WatermarkCapturedPhoto {
        guard photo.isPersisted else { return photo }
        return try Self.metadataLock.withLock {
            let metadataURL = draftURL(photo.id).appendingPathComponent("metadata.json")
            let record = try JSONDecoder().decode(WatermarkCameraDraftRecord.self, from: Data(contentsOf: metadataURL))
            guard record.version == 1, record.id == photo.id,
                  record.capturedAt == photo.capturedAt, record.context == photo.context,
                  record.projectId == photo.projectId else { throw CocoaError(.fileReadCorruptFile) }
            var merged = photo
            // Completion is monotonic. A stale pending snapshot must also retain a
            // recorded failure in the other delivery channel rather than erase it.
            if record.albumStatus == .completed || photo.albumStatus == .pending {
                merged.albumStatus = record.albumStatus
                merged.albumFailure = record.albumFailure
            }
            if record.archiveStatus == .completed || photo.archiveStatus == .pending {
                merged.archiveStatus = record.archiveStatus
                merged.archiveFailure = record.archiveFailure
            }
            if merged.albumStatus == .completed { merged.albumFailure = nil }
            if merged.archiveStatus == .completed { merged.archiveFailure = nil }
            try writeData(try JSONEncoder().encode(WatermarkCameraDraftRecord(photo: merged)), metadataURL)
            return merged
        }
    }

    func remove(_ photo: WatermarkCapturedPhoto) throws {
        let url = photo.isPersisted ? draftURL(photo.id) : directory.appendingPathComponent("incomplete-\(photo.id.uuidString)")
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    private func persistOrRetain(_ photo: WatermarkCapturedPhoto, errors: inout [String]) -> WatermarkCapturedPhoto {
        guard !photo.isPersisted else { return photo }
        let staging = directory.appendingPathComponent("incomplete-\(photo.id.uuidString)", isDirectory: true)
        do {
            guard let original = photo.pendingOriginalData ?? photo.fallbackOriginalImage?.jpegData(compressionQuality: 1),
                  let rendered = photo.pendingWatermarkedData ?? photo.fallbackWatermarkedImage?.jpegData(compressionQuality: 0.96) else { throw CocoaError(.fileWriteUnknown) }
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            // Retry may reuse only this photo's own staging area. Existing completed drafts are never overwritten.
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            try writeData(original, staging.appendingPathComponent("original.jpg"))
            try writeData(rendered, staging.appendingPathComponent("watermarked.jpg"))
            try writeData(try JSONEncoder().encode(WatermarkCameraDraftRecord(photo: photo)), staging.appendingPathComponent("metadata.json"))
            let destination = draftURL(photo.id)
            try fileManager.moveItem(at: staging, to: destination)
            var persisted = WatermarkCapturedPhoto(
                id: photo.id, image: photo.thumbnail, capturedAt: photo.capturedAt,
                context: photo.context, projectId: photo.projectId,
                originalURL: destination.appendingPathComponent("original.jpg"),
                watermarkedURL: destination.appendingPathComponent("watermarked.jpg")
            )
            persisted.albumStatus = photo.albumStatus
            persisted.albumFailure = photo.albumFailure
            persisted.archiveStatus = photo.archiveStatus
            persisted.archiveFailure = photo.archiveFailure
            return persisted
        } catch {
            errors.append("照片尚未保存到草稿，请勿关闭应用并重试：\(error.localizedDescription)")
            return photo
        }
    }

    private func draftURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString, isDirectory: true) }

    private func thumbnail(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(source: source)
    }

    private func thumbnail(url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(source: source)
    }

    private func thumbnail(source: CGImageSource) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 720,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
