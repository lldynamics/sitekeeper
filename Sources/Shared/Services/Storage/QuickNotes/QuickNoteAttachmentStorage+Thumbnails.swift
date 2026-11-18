import Foundation
import UIKit
import AVFoundation
import CryptoKit
import Darwin

extension QuickNoteAttachmentStorage {
    static func videoThumbnail(for fileName: String) -> UIImage? {
        videoThumbnail(for: fileName, cacheNamespace: nil)
    }

    // Namespaces keep regression fixtures isolated inside the same fixed cache boundary.
    static func videoThumbnail(for fileName: String, cacheNamespace: String?) -> UIImage? {
        guard let source = try? validatedFileURL(for: fileName),
              let sourceVersion = try? videoThumbnailSourceVersion(for: fileName) else { return nil }
        if let cachedURL = try? videoThumbnailCacheURL(sourceVersion: sourceVersion, cacheNamespace: cacheNamespace),
           let thumbnail = ThumbnailImageDecoder.decode(at: cachedURL, maxPixelSize: 512) {
            return UIImage(cgImage: thumbnail.image)
        }
        let asset = AVAsset(url: source)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        let cgImage: CGImage
        do {
            cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.video_thumbnail_failed", fileName: fileName, error: error)
            return nil
        }
        guard !Task.isCancelled else { return nil }
        let image = UIImage(cgImage: cgImage)
        if let data = image.jpegData(compressionQuality: 0.72) {
            do {
                // Do not cache a frame under an earlier version if an import/restore replaced
                // the source while AVFoundation was decoding it.
                guard try videoThumbnailSourceVersion(for: fileName) == sourceVersion else { return image }
                let directory = try videoThumbnailCacheDirectory(cacheNamespace: cacheNamespace)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let target = try videoThumbnailCacheURL(sourceVersion: sourceVersion, cacheNamespace: cacheNamespace)
                try data.write(to: target, options: .atomic)
            } catch {
                // A poisoned/unavailable cache must not prevent rendering the source video.
                DocumentStorageIssueLogger.record("quick_note_attachment.thumbnail_write_failed", fileName: fileName, error: error)
            }
        }
        return image
    }

    static func thumbnailCacheUsageBytes() -> Int {
        thumbnailCacheUsageBytes(cacheNamespace: nil)
    }

    static func thumbnailCacheUsageBytes(cacheNamespace: String?) -> Int {
        let files: [URL]
        do {
            let directory = try videoThumbnailCacheDirectory(cacheNamespace: cacheNamespace)
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return 0
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.thumbnail_directory_list_failed", error: error)
            return 0
        }
        return files.reduce(0) { total, url in
            do {
                try validateVideoThumbnailCacheFile(url, cacheNamespace: cacheNamespace)
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
                let size = max(0, values.fileSize ?? values.totalFileAllocatedSize ?? 0)
                return total > Int.max - size ? Int.max : total + size
            } catch {
                DocumentStorageIssueLogger.record("quick_note_attachment.thumbnail_file_size_failed", fileName: url.lastPathComponent, error: error)
                return total
            }
        }
    }

    static func clearThumbnailCache() {
        clearThumbnailCache(cacheNamespace: nil)
    }

    static func clearThumbnailCache(cacheNamespace: String?) {
        // Video previews are also cached in memory by their source attachment URL.
        // Invalidate them even when the disk cache directory is absent.
        StorageThumbnailCache.invalidate(directoryURL: attachmentDir)
        defer { StorageThumbnailCache.invalidate(directoryURL: attachmentDir) }
        let directory: URL
        let files: [URL]
        do {
            directory = try videoThumbnailCacheDirectory(cacheNamespace: cacheNamespace)
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.thumbnail_directory_list_failed", error: error)
            return
        }
        StorageThumbnailCache.invalidate(directoryURL: directory)
        defer { StorageThumbnailCache.invalidate(directoryURL: directory) }
        for url in files {
            do {
                try validateVideoThumbnailCacheFile(url, cacheNamespace: cacheNamespace)
                _ = try FileOps.removeIfExists(
                    at: url,
                    context: .init(
                        event: "quick_note_attachment.thumbnail_cache_clear",
                        category: .fileStorage,
                        source: "QuickNoteAttachmentStorage.clearThumbnailCache"
                    )
                )
            } catch {
                DocumentStorageIssueLogger.record("quick_note_attachment.thumbnail_cleanup_failed", fileName: url.lastPathComponent, error: error)
            }
        }
    }

    static func videoThumbnailCacheDirectory(cacheNamespace: String? = nil) throws -> URL {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw FileStorageError.directoryCreationFailed("QuickNoteVideoThumbnails-v1")
        }
        var directory = caches.appendingPathComponent("QuickNoteVideoThumbnails-v1", isDirectory: true)
        if let cacheNamespace {
            try AttachmentStoragePath.validateLeaf(cacheNamespace)
            directory.appendPathComponent(cacheNamespace, isDirectory: true)
        }
        try AttachmentStoragePath.validateDirectory(directory)
        return directory
    }

    static func validatedVideoThumbnailCacheURL(for fileName: String, cacheNamespace: String? = nil) throws -> URL {
        try videoThumbnailCacheURL(
            sourceVersion: videoThumbnailSourceVersion(for: fileName),
            cacheNamespace: cacheNamespace
        )
    }

    private static func videoThumbnailCacheURL(sourceVersion: String, cacheNamespace: String?) throws -> URL {
        try AttachmentStoragePath.fileURL(
            for: sourceVersion + ".jpg",
            in: videoThumbnailCacheDirectory(cacheNamespace: cacheNamespace)
        )
    }

    private static func videoThumbnailSourceVersion(for fileName: String) throws -> String {
        let source = try validatedFileURL(for: fileName)
        // Opening proves the source is currently readable without loading a large video.
        // fstat supplies the exact inode and nanosecond timestamps of that opened file;
        // atomic backup restores change the inode even if size/mtime are preserved.
        let descriptor = Darwin.open(source.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { Darwin.close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw FileStorageError.unsafeAttachmentPath(fileName)
        }
        let version = [
            String(metadata.st_dev), String(metadata.st_ino), String(metadata.st_size),
            String(metadata.st_mtimespec.tv_sec), String(metadata.st_mtimespec.tv_nsec),
            String(metadata.st_ctimespec.tv_sec), String(metadata.st_ctimespec.tv_nsec)
        ].joined(separator: ":")
        var key = Data(fileName.utf8)
        key.append(0)
        key.append(contentsOf: version.utf8)
        return SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
    }

    private static func validateVideoThumbnailCacheFile(_ url: URL, cacheNamespace: String?) throws {
        let directory = try videoThumbnailCacheDirectory(cacheNamespace: cacheNamespace)
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else {
            throw FileStorageError.unsafeAttachmentPath(url.lastPathComponent)
        }
        try AttachmentStoragePath.validateFile(url)
    }

    // Retain legacy references conservatively. Never read, migrate, overwrite or clear these
    // names in the attachment directory: a thumb-* file may be a genuine business attachment.
    static func videoThumbnailFileName(for fileName: String) -> String {
        "thumb-\(fileName).jpg"
    }
}
