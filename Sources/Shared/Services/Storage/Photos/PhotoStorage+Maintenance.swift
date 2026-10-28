import Foundation
import UIKit

extension PhotoStorage {
    static func regenerateThumbnails(for fileNames: [String]) {
        for fileName in fileNames {
            regenerateThumbnail(for: fileName)
        }
    }

    static func regenerateThumbnail(for fileName: String) {
        guard let data = data(for: fileName),
              let image = UIImage(data: data) else { return }
        let thumb = resize(image, maxSide: 800)
        guard let thumbData = thumb.jpegData(compressionQuality: 0.7) else { return }
        do {
            try ensureDirectoryExists()
            try thumbData.write(to: thumbnailFileURL(for: fileName), options: .atomic)
            PhotoCache.shared.invalidate(fileName: fileName)
        } catch {
            logIssue("thumbnail_generate_failed", fileName: fileName, error: error)
        }
    }

    static func allStoredFileNames() -> [String] {
        let manager = FileManager.default
        var names = Set<String>()
        do {
            let files = try manager.contentsOfDirectory(at: photoDir, includingPropertiesForKeys: nil)
            names.formUnion(files.map(\.lastPathComponent))
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            // ignore missing directory
        } catch {
            logIssue("directory_list_failed", fileName: photoDir.lastPathComponent, error: error)
        }
        do {
            let files = try manager.contentsOfDirectory(at: thumbnailDir, includingPropertiesForKeys: nil)
            names.formUnion(files.map(\.lastPathComponent))
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            // ignore missing directory
        } catch {
            logIssue("thumbnail_directory_list_failed", fileName: thumbnailDir.lastPathComponent, error: error)
        }
        return names.sorted()
    }

    static func thumbnailCacheUsageBytes() -> Int {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: thumbnailDir,
                includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]
            )
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return 0
        } catch {
            logIssue("thumbnail_cache_usage_failed", fileName: thumbnailDir.lastPathComponent, error: error)
            return 0
        }
        return files.reduce(0) { total, url in
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
                return total + (values.fileSize ?? values.totalFileAllocatedSize ?? 0)
            } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
                return total
            } catch {
                logIssue("thumbnail_file_size_failed", fileName: url.lastPathComponent, error: error)
                return total
            }
        }
    }

    static func clearThumbnailCache() {
        PhotoCache.shared.clear()
        defer { PhotoCache.shared.clear() }
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: thumbnailDir, includingPropertiesForKeys: nil)
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return
        } catch {
            logIssue("thumbnail_cache_directory_list_failed", fileName: thumbnailDir.lastPathComponent, error: error)
            return
        }
        for url in files {
            do {
                _ = try FileOps.removeIfExists(
                    at: url,
                    context: .init(
                        event: "photo.thumbnail_cache_cleanup",
                        category: .fileStorage,
                        source: "PhotoStorage.clearThumbnailCache"
                    )
                )
            } catch {
                // FileOps 已记录失败事件，继续清理其他缓存文件。
            }
        }
    }

    static func restore(_ files: [PhotoBackupFile]) {
        do {
            try restoreOrThrow(files)
        } catch {
            logIssue("restore_failed", error: error)
        }
    }

    static func restoreOrThrow(_ files: [PhotoBackupFile]) throws {
        try ensureDirectoryExists()
        for file in files {
            do {
                try file.data.write(to: fileURL(for: file.fileName), options: .atomic)
                regenerateThumbnail(for: file.fileName)
                PhotoCache.shared.invalidate(fileName: file.fileName)
            } catch {
                throw FileStorageError.writeFailed(file.fileName)
            }
        }
    }

    static func backupFiles(for logs: [DailyLog]) -> [PhotoBackupFile] {
        var seen = Set<String>()
        return logs.flatMap(\.allPhotoFileNames).compactMap { fileName in
            guard !seen.contains(fileName), let data = data(for: fileName) else { return nil }
            seen.insert(fileName)
            return PhotoBackupFile(fileName: fileName, data: data)
        }
    }

    static func backupFiles(for todos: [SiteTodo]) -> [PhotoBackupFile] {
        var seen = Set<String>()
        let names = todos.flatMap { [$0.rectificationBeforePhotoFileName, $0.rectificationAfterPhotoFileName] }.compactMap { $0 }
        return names.compactMap { fileName in
            guard !seen.contains(fileName), let data = data(for: fileName) else { return nil }
            seen.insert(fileName)
            return PhotoBackupFile(fileName: fileName, data: data)
        }
    }

    static func resize(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let ratio = min(maxSide / size.width, maxSide / size.height, 1.0)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
