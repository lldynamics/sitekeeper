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
    // Optional fields preserve decoding compatibility with version 1 drafts.
    var pixelSize: CGSize?
    var albumAssetIdentifier: String?
    var albumAttemptID: UUID?

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
        pixelSize = photo.pixelSize
        albumAssetIdentifier = photo.albumAssetIdentifier
        albumAttemptID = photo.albumAttemptID
    }
}

struct WatermarkRecoveredDraft: Identifiable, Sendable {
    let id: String
    let capturedAt: Date?
    let availableFileNames: [String]
    let summary: String
}

struct WatermarkDraftStorageResult: Sendable {
    var photos: [WatermarkCapturedPhoto]
    var errors: [String]
    var recoveryItems: [WatermarkRecoveredDraft] = []
    var scanSucceeded = true
}

struct WatermarkAlbumReceipt: Codable, Sendable {
    let photoID: UUID
    let attemptID: UUID
    let assetIdentifier: String
    let savedAt: Date
}

/// Metadata restore does not decode all image pixels. Complete staging directories are
/// verified separately, then published by atomic rename; incomplete evidence stays intact.
actor WatermarkCameraDraftStorage {
    typealias DataWriter = @Sendable (Data, URL) throws -> Void
    static let didChangeNotification = Notification.Name("WatermarkCameraDraftStorage.didChange")
    nonisolated let directory: URL
    private let writeData: DataWriter
    private let fileManager = FileManager.default
    // Shared by every window. This lock never spans an await or Photos operation.
    private static let metadataLock = NSLock()

    static func scopedDirectory(for storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent().appendingPathComponent("BusinessDrafts", isDirectory: true)
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
                    image: WatermarkCapturedPhoto.placeholderThumbnail, capturedAt: capturedAt,
                    context: context, projectId: projectId,
                    pendingOriginalData: original, pendingWatermarkedData: rendered,
                    fallbackOriginalImage: original == nil ? image : nil,
                    fallbackWatermarkedImage: rendered == nil ? output : nil,
                    pixelSize: CGSize(width: output.size.width * output.scale, height: output.size.height * output.scale)
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
            else if let data = source.fallbackOriginalImage?.jpegData(compressionQuality: 1) { original = data }
            else { throw WatermarkDraftImageError.missingImage }
            guard let rendered = image.jpegData(compressionQuality: 0.96) else { throw WatermarkDraftImageError.encodingFailed }
            let photo = WatermarkCapturedPhoto(
                image: WatermarkCapturedPhoto.placeholderThumbnail,
                capturedAt: source.capturedAt, context: source.context, projectId: source.projectId,
                pendingOriginalData: original, pendingWatermarkedData: rendered,
                pixelSize: CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
            )
            result.photos.append(persistOrRetain(photo, errors: &result.errors))
        } catch { result.errors.append(message("无法保留标注副本：%@", error)) }
        return result
    }

    func retry(_ photos: [WatermarkCapturedPhoto]) -> WatermarkDraftStorageResult {
        var result = WatermarkDraftStorageResult(photos: [], errors: [])
        for photo in photos { result.photos.append(persistOrRetain(photo, errors: &result.errors)) }
        return result
    }

    func restore() -> WatermarkDraftStorageResult {
        Self.metadataLock.withLock {
            var result = WatermarkDraftStorageResult(photos: [], errors: [])
            do {
                do { try requireRealDirectory(directory) }
                catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
                    return result
                }
                let entries = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    do {
                        try requireRealDirectory(entry)
                        let staging = entry.lastPathComponent.hasPrefix("incomplete-")
                        let expectedID = staging ? String(entry.lastPathComponent.dropFirst("incomplete-".count)) : entry.lastPathComponent
                        guard let id = UUID(uuidString: expectedID) else { throw CocoaError(.fileReadCorruptFile) }
                        var photo = try readPhoto(at: entry, expectedID: id, verifyPixels: staging)
                        if staging {
                            let destination = draftURL(id)
                            // Never replace another published copy, even if its contents are broken.
                            guard !fileManager.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
                            try fileManager.moveItem(at: entry, to: destination)
                            notifyChange()
                            photo = try readPhoto(at: destination, expectedID: id)
                        }
                        result.photos.append(photo)
                    } catch {
                        let item = recoveryItem(at: entry, error: error)
                        result.recoveryItems.append(item)
                        result.errors.append(item.summary)
                    }
                }
            } catch {
                result.scanSucceeded = false
                result.errors.append(message("无法读取照片草稿：%@", error))
            }
            result.photos.sort { $0.capturedAt < $1.capturedAt }
            return result
        }
    }

    func latest(_ photo: WatermarkCapturedPhoto) throws -> WatermarkCapturedPhoto {
        guard photo.isPersisted else { return photo }
        return try Self.metadataLock.withLock { try readPhoto(at: draftURL(photo.id), expectedID: photo.id) }
    }

    @discardableResult
    func updateStatus(_ photo: WatermarkCapturedPhoto) throws -> WatermarkCapturedPhoto {
        guard photo.isPersisted else { return photo }
        return try Self.metadataLock.withLock { try writeStatus(photo) }
    }

    func beginAlbumAttempt(_ photo: WatermarkCapturedPhoto, attemptID: UUID) throws -> WatermarkCapturedPhoto {
        try Self.metadataLock.withLock {
            var latest = try readPhoto(at: draftURL(photo.id), expectedID: photo.id)
            guard latest.albumStatus != .completed, latest.albumAttemptID == nil else { return latest }
            latest.albumAttemptID = attemptID
            try writeRecord(latest)
            return latest
        }
    }

    func completeAlbumAttempt(_ photo: WatermarkCapturedPhoto, receipt: WatermarkAlbumReceipt) throws -> WatermarkCapturedPhoto {
        try Self.metadataLock.withLock {
            var latest = try readPhoto(at: draftURL(photo.id), expectedID: photo.id)
            guard receipt.photoID == latest.id else { throw CocoaError(.fileReadCorruptFile) }
            // Independent receipt survives a subsequent metadata write failure.
            try writeData(try JSONEncoder().encode(receipt), draftURL(photo.id).appendingPathComponent("album-receipt.json"))
            notifyChange()
            latest.albumStatus = .completed
            latest.albumFailure = nil
            latest.albumAssetIdentifier = receipt.assetIdentifier
            latest.albumAttemptID = nil
            try writeRecord(latest)
            return latest
        }
    }

    /// Called only after a confirmed Photos failure, or explicit user resolution of an uncertain attempt.
    func resolveAlbumAttempt(_ photo: WatermarkCapturedPhoto, retryConfirmed: Bool) throws -> WatermarkCapturedPhoto {
        try Self.metadataLock.withLock {
            var latest = try readPhoto(at: draftURL(photo.id), expectedID: photo.id)
            guard latest.albumStatus != .completed else { return latest }
            latest.albumAttemptID = nil
            latest.albumStatus = retryConfirmed ? .pending : .completed
            latest.albumFailure = nil
            try writeRecord(latest)
            return latest
        }
    }

    func remove(_ photo: WatermarkCapturedPhoto) throws {
        try Self.metadataLock.withLock {
            let url = photo.isPersisted ? draftURL(photo.id) : directory.appendingPathComponent("incomplete-\(photo.id.uuidString)")
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
                notifyChange()
            }
        }
    }

    /// Copies retained bytes without decoding, re-encoding or changing the evidence directory.
    func exportRecovery(id: String) throws -> URL {
        try Self.metadataLock.withLock {
            let source = try recoveryURL(id)
            try requireNoSymlinks(in: source)
            let parent = fileManager.temporaryDirectory.appendingPathComponent("WatermarkRecovery-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
            let destination = parent.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            do {
                try fileManager.copyItem(at: source, to: destination)
                return destination
            } catch {
                // Only the temporary copy created by this export is disposable.
                try? fileManager.removeItem(at: parent)
                throw error
            }
        }
    }

    func removeRecovery(id: String) throws {
        try Self.metadataLock.withLock {
            try fileManager.removeItem(at: recoveryURL(id))
            notifyChange()
        }
    }

    private func persistOrRetain(_ photo: WatermarkCapturedPhoto, errors: inout [String]) -> WatermarkCapturedPhoto {
        guard !photo.isPersisted else { return photo }
        return Self.metadataLock.withLock {
            let staging = directory.appendingPathComponent("incomplete-\(photo.id.uuidString)", isDirectory: true)
            do {
                if fileManager.fileExists(atPath: draftURL(photo.id).path) {
                    return try readPhoto(at: draftURL(photo.id), expectedID: photo.id)
                }
                guard let original = photo.pendingOriginalData ?? photo.fallbackOriginalImage?.jpegData(compressionQuality: 1),
                      let rendered = photo.pendingWatermarkedData ?? photo.fallbackWatermarkedImage?.jpegData(compressionQuality: 0.96) else { throw WatermarkDraftImageError.encodingFailed }
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
                try requireRealDirectory(staging)
                // Only this pending identity may retry its own staging writes.
                try writeData(original, staging.appendingPathComponent("original.jpg"))
                try writeData(rendered, staging.appendingPathComponent("watermarked.jpg"))
                try writeData(try JSONEncoder().encode(WatermarkCameraDraftRecord(photo: photo)), staging.appendingPathComponent("metadata.json"))
                _ = try readPhoto(at: staging, expectedID: photo.id, verifyPixels: true)
                try fileManager.moveItem(at: staging, to: draftURL(photo.id))
                notifyChange()
                return try readPhoto(at: draftURL(photo.id), expectedID: photo.id)
            } catch {
                errors.append(message("照片尚未保存到草稿，请勿关闭应用并重试：%@", error))
                return photo
            }
        }
    }

    private func readPhoto(at folder: URL, expectedID: UUID, verifyPixels: Bool = false) throws -> WatermarkCapturedPhoto {
        try requireRealDirectory(folder)
        let metadataURL = folder.appendingPathComponent("metadata.json")
        try requireRegularFile(metadataURL)
        let record = try JSONDecoder().decode(WatermarkCameraDraftRecord.self, from: Data(contentsOf: metadataURL))
        guard record.version == 1, record.id == expectedID else { throw CocoaError(.fileReadCorruptFile) }
        let original = folder.appendingPathComponent("original.jpg")
        let rendered = folder.appendingPathComponent("watermarked.jpg")
        // Image properties are small headers. Pixel decoding is reserved for staging validation.
        _ = try imageSize(at: original, verifyPixels: verifyPixels)
        let renderedSize = try imageSize(at: rendered, verifyPixels: verifyPixels)
        var photo = WatermarkCapturedPhoto(
            id: record.id, image: WatermarkCapturedPhoto.placeholderThumbnail, capturedAt: record.capturedAt,
            context: record.context, projectId: record.projectId, originalURL: original, watermarkedURL: rendered,
            pixelSize: record.pixelSize ?? renderedSize
        )
        photo.albumStatus = record.albumStatus
        photo.albumFailure = record.albumFailure
        photo.archiveStatus = record.archiveStatus
        photo.archiveFailure = record.archiveFailure
        photo.albumAssetIdentifier = record.albumAssetIdentifier
        photo.albumAttemptID = record.albumAttemptID
        let receiptURL = folder.appendingPathComponent("album-receipt.json")
        if fileManager.fileExists(atPath: receiptURL.path) {
            try requireRegularFile(receiptURL)
            let receipt = try JSONDecoder().decode(WatermarkAlbumReceipt.self, from: Data(contentsOf: receiptURL))
            guard receipt.photoID == photo.id, !receipt.assetIdentifier.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
            photo.albumAssetIdentifier = receipt.assetIdentifier
            photo.albumStatus = .completed
            photo.albumFailure = nil
            photo.albumAttemptID = nil
        }
        return photo
    }

    private func writeStatus(_ photo: WatermarkCapturedPhoto) throws -> WatermarkCapturedPhoto {
        let latest = try readPhoto(at: draftURL(photo.id), expectedID: photo.id)
        guard latest.capturedAt == photo.capturedAt, latest.context == photo.context,
              latest.projectId == photo.projectId else { throw CocoaError(.fileReadCorruptFile) }
        var merged = photo
        if latest.albumStatus == .completed || photo.albumStatus == .pending {
            merged.albumStatus = latest.albumStatus
            merged.albumFailure = latest.albumFailure
        }
        if latest.archiveStatus == .completed || photo.archiveStatus == .pending {
            merged.archiveStatus = latest.archiveStatus
            merged.archiveFailure = latest.archiveFailure
        }
        merged.albumAssetIdentifier = latest.albumAssetIdentifier ?? photo.albumAssetIdentifier
        merged.albumAttemptID = merged.albumStatus == .completed ? nil : latest.albumAttemptID
        if merged.albumStatus == .completed { merged.albumFailure = nil }
        if merged.archiveStatus == .completed { merged.archiveFailure = nil }
        try writeRecord(merged)
        return merged
    }

    private func writeRecord(_ photo: WatermarkCapturedPhoto) throws {
        try writeData(try JSONEncoder().encode(WatermarkCameraDraftRecord(photo: photo)), draftURL(photo.id).appendingPathComponent("metadata.json"))
        notifyChange()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil, userInfo: ["directory": directory.standardizedFileURL.path])
    }

    private func imageSize(at url: URL, verifyPixels: Bool) throws -> CGSize {
        try requireRegularFile(url)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0 else { throw CocoaError(.fileReadCorruptFile) }
        if verifyPixels {
            guard CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) != nil else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5...8).contains(orientation)
            ? CGSize(width: height.doubleValue, height: width.doubleValue)
            : CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    private func recoveryItem(at url: URL, error: Error) -> WatermarkRecoveredDraft {
        let names = (try? fileManager.contentsOfDirectory(atPath: url.path))?.sorted() ?? []
        let metadata = url.appendingPathComponent("metadata.json")
        let record: WatermarkCameraDraftRecord?
        if (try? requireRegularFile(metadata)) != nil {
            record = try? JSONDecoder().decode(WatermarkCameraDraftRecord.self, from: Data(contentsOf: metadata))
        } else { record = nil }
        let summary = String(format: AppLocalization.string("草稿无法读取，原文件已保留（%@）：%@"), url.lastPathComponent, error.localizedDescription)
        return WatermarkRecoveredDraft(id: url.lastPathComponent, capturedAt: record?.capturedAt, availableFileNames: names, summary: summary)
    }

    private func recoveryURL(_ id: String) throws -> URL {
        guard !id.isEmpty, id != ".", id != "..", !id.contains("/"), !id.contains("\\") else { throw CocoaError(.fileReadInvalidFileName) }
        let url = directory.appendingPathComponent(id, isDirectory: true)
        try requireRealDirectory(url)
        // A healthy published draft is never removed through the recovery API.
        if let uuid = UUID(uuidString: id), (try? readPhoto(at: url, expectedID: uuid)) != nil { throw CocoaError(.fileWriteNoPermission) }
        return url
    }

    private func requireRealDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
    }

    private func requireRegularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw CocoaError(.fileReadCorruptFile) }
    }

    private func requireNoSymlinks(in url: URL) throws {
        try requireRealDirectory(url)
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey]) else { throw CocoaError(.fileReadNoPermission) }
        for case let child as URL in enumerator {
            if try child.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true { throw CocoaError(.fileReadNoPermission) }
        }
    }

    private func message(_ key: String, _ error: Error) -> String {
        String(format: AppLocalization.string(key), error.localizedDescription)
    }
    private func draftURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString, isDirectory: true) }
}
