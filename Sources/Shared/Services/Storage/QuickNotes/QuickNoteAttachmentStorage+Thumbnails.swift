import Foundation
import UIKit
import AVFoundation

extension QuickNoteAttachmentStorage {
    static func videoThumbnail(for fileName: String) -> UIImage? {
        let thumbName = videoThumbnailFileName(for: fileName)
        if let thumbnail = ThumbnailImageDecoder.decode(at: fileURL(for: thumbName), maxPixelSize: 512) {
            return UIImage(cgImage: thumbnail.image)
        }
        let asset = AVAsset(url: fileURL(for: fileName))
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
            _ = saveData(data, fileName: thumbName)
        }
        return image
    }

    static func thumbnailCacheUsageBytes() -> Int {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: attachmentDir, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.thumbnail_directory_list_failed", error: error)
            return 0
        }
        return files.reduce(0) { total, url in
            guard url.lastPathComponent.hasPrefix("thumb-") else { return total }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
                return total + (values.fileSize ?? values.totalFileAllocatedSize ?? 0)
            } catch {
                DocumentStorageIssueLogger.record("quick_note_attachment.thumbnail_file_size_failed", fileName: url.lastPathComponent, error: error)
                return total
            }
        }
    }

    static func clearThumbnailCache() {
        StorageThumbnailCache.invalidate(directoryURL: attachmentDir)
        defer { StorageThumbnailCache.invalidate(directoryURL: attachmentDir) }
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: attachmentDir, includingPropertiesForKeys: nil)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.thumbnail_directory_list_failed", error: error)
            return
        }
        for url in files where url.lastPathComponent.hasPrefix("thumb-") {
            do {
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

    static func videoThumbnailFileName(for fileName: String) -> String {
        "thumb-\(fileName).jpg"
    }
}
