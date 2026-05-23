import UIKit
import Foundation

/// 照片独立文件存储，模型只存文件名
enum PhotoStorage {
    private static func logIssue(
        _ event: String,
        fileName: String? = nil,
        error: Error? = nil,
        details: [String: String] = [:]
    ) {
        var payload = details
        if let fileName, !fileName.isEmpty {
            payload["file"] = fileName
        }
        StorageIssueLog.recordEvent(
            "photo.\(event)",
            category: .fileStorage,
            details: payload,
            error: error
        )
    }

    private static var baseDirectory: URL {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return dir
        }
        logIssue(
            "base_directory_unavailable",
            details: ["fallback": "temporary-directory"]
        )
        return FileManager.default.temporaryDirectory
    }

    private static var photoDir: URL {
        baseDirectory.appendingPathComponent("Photos")
    }

    private static var thumbnailDir: URL {
        baseDirectory.appendingPathComponent("PhotoThumbnails")
    }

    /// 保存原图 + 缩略图，返回文件名
    static func save(original: Data, logId: UUID, index: Int = 0) -> String? {
        let suffix = index == 0 ? "" : "-\(index)"
        return save(original: original, fileName: "\(logId.uuidString)\(suffix).jpg")
    }

    /// 兼容旧调用：新写入流程应优先使用 `saveOrThrow`，让界面能提示失败原因。
    static func save(original: Data, fileName: String) -> String? {
        do {
            return try saveOrThrow(original: original, fileName: fileName)
        } catch {
            logIssue("save_failed", fileName: fileName, error: error)
            return nil
        }
    }

    static func saveOrThrow(original: Data, logId: UUID, index: Int = 0) throws -> String {
        let suffix = index == 0 ? "" : "-\(index)"
        return try saveOrThrow(original: original, fileName: "\(logId.uuidString)\(suffix).jpg")
    }

    static func saveOrThrow(original: Data, fileName: String) throws -> String {
        guard let image = UIImage(data: original) else { throw FileStorageError.invalidImageData }
        let thumb = resize(image, maxSide: 800)
        guard let thumbData = thumb.jpegData(compressionQuality: 0.7) else { throw FileStorageError.imageEncodingFailed }
        try ensureDirectoryExists()
        do {
            try original.write(to: fileURL(for: fileName), options: .atomic)
            try thumbData.write(to: thumbnailFileURL(for: fileName), options: .atomic)
        } catch {
            let fm = FileManager.default
            if fm.fileExists(atPath: fileURL(for: fileName).path) {
                do {
                    _ = try FileOps.removeIfExists(
                        at: fileURL(for: fileName),
                        context: .init(
                            event: "photo.save_rollback_cleanup",
                            category: .fileStorage,
                            source: "PhotoStorage.saveOrThrow.originalRollback"
                        )
                    )
                } catch {
                    logIssue("rollback_original_delete_failed", fileName: fileName, error: error)
                }
            }
            if fm.fileExists(atPath: thumbnailFileURL(for: fileName).path) {
                do {
                    _ = try FileOps.removeIfExists(
                        at: thumbnailFileURL(for: fileName),
                        context: .init(
                            event: "photo.save_rollback_cleanup",
                            category: .fileStorage,
                            source: "PhotoStorage.saveOrThrow.thumbnailRollback"
                        )
                    )
                } catch {
                    logIssue("rollback_thumbnail_delete_failed", fileName: fileName, error: error)
                }
            }
            throw FileStorageError.writeFailed(fileName)
        }

        return fileName
    }

    static func saveMany(originals: [Data], logId: UUID) -> [String] {
        originals.enumerated().compactMap { index, data in
            save(original: data, logId: logId, index: index)
        }
    }

    static func saveManyOrThrow(originals: [Data], logId: UUID) throws -> [String] {
        try originals.enumerated().map { index, data in
            try saveOrThrow(original: data, logId: logId, index: index)
        }
    }

    /// 读取缩略图
    static func thumbnail(for fileName: String?) -> UIImage? {
        guard let name = fileName else { return nil }
        return PhotoCache.shared.thumbnail(for: name)
    }

    static func thumbnailAsync(for fileName: String?) async -> UIImage? {
        guard let name = fileName else { return nil }
        return await PhotoCache.shared.thumbnailAsync(for: name)
    }

    /// 公开文件 URL（供缓存使用）
    static func thumbnailURL(for fileName: String) -> URL {
        let url = thumbnailFileURL(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return fileURL(for: fileName)
        }
        return url
    }

    /// 原始照片文件 URL（供备份、交付包和文件浏览使用）。
    static func fileURL(for fileName: String) -> URL {
        photoDir.appendingPathComponent(fileName)
    }

    /// 缩略图文件 URL（供清理回收站成对隔离/恢复）。
    static func thumbnailStorageURL(for fileName: String) -> URL {
        thumbnailFileURL(for: fileName)
    }

    /// 删除照片文件
    static func delete(fileName: String?) {
        guard let name = fileName else { return }
        do {
            try deleteOrThrow(fileName: name)
        } catch {
            logIssue("delete_failed", fileName: name, error: error)
        }
        PhotoCache.shared.invalidate(fileName: name)
    }

    static func deleteOrThrow(fileName: String) throws {
        let manager = FileManager.default
        let targets: [(url: URL, category: FileQuarantineCategory)] = [
            (fileURL(for: fileName), .photoOriginal),
            (thumbnailFileURL(for: fileName), .photoThumbnail)
        ]
        var quarantinedAnyFile = false
        for target in targets {
            guard manager.fileExists(atPath: target.url.path) else { continue }
            let quarantined = try FileQuarantineStore.quarantine(
                fileAt: target.url,
                category: target.category,
                originalFileName: fileName
            )
            quarantinedAnyFile = quarantinedAnyFile || quarantined
        }
        guard quarantinedAnyFile else { throw FileStorageError.deleteFailed(fileName) }
    }

    static func delete(fileNames: [String]) {
        for fileName in fileNames {
            delete(fileName: fileName)
        }
    }

    static func data(for fileName: String) -> Data? {
        do {
            return try Data(contentsOf: fileURL(for: fileName))
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return nil
        } catch {
            logIssue("read_failed", fileName: fileName, error: error)
            return nil
        }
    }

    static func dataAsync(for fileName: String) async -> Data? {
        let url = fileURL(for: fileName)
        do {
            return try await FileIOTaskRunner.run(
                priority: .utility,
                logContext: .init(
                    event: "photo.read",
                    source: "PhotoStorage.dataAsync",
                    category: .fileStorage,
                    details: ["file": fileName]
                )
            ) {
                do {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard !Task.isCancelled else { return nil }
                    return data
                } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
                    return nil
                }
            }
        } catch {
            return nil
        }
    }

    static func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: fileName).path)
    }

    static func fileSize(for fileName: String) -> Int {
        let url = fileURL(for: fileName)
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            return values.fileSize ?? values.totalFileAllocatedSize ?? 0
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return 0
        } catch {
            logIssue("file_size_failed", fileName: fileName, error: error)
            return 0
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
        PhotoCache.shared.clear()
    }

    static func referencedFileNames(logs: [DailyLog], todos: [SiteTodo]) -> Set<String> {
        var names = Set(logs.flatMap(\.allPhotoFileNames))
        names.formUnion(todos.compactMap(\.rectificationBeforePhotoFileName))
        names.formUnion(todos.compactMap(\.rectificationAfterPhotoFileName))
        return names
    }

    static func orphanFileNames(logs: [DailyLog], todos: [SiteTodo]) -> [String] {
        let referenced = referencedFileNames(logs: logs, todos: todos)
        return allStoredFileNames().filter { !referenced.contains($0) }
    }

    private static func resize(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        let ratio = min(maxSide / size.width, maxSide / size.height, 1.0)
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    private static func ensureDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(at: photoDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)
        } catch {
            throw FileStorageError.directoryCreationFailed("Photos")
        }
    }

    private static func thumbnailFileURL(for fileName: String) -> URL {
        thumbnailDir.appendingPathComponent(fileName)
    }
}

struct PhotoBackupFile: Identifiable, Codable, Sendable {
    var id: String { fileName }
    var fileName: String
    var data: Data
}

extension DailyLog {
    var photoAttachments: [LogPhoto] {
        var attachments = photos
        if let legacy = photoFileName, !attachments.contains(where: { $0.fileName == legacy }) {
            attachments.insert(LogPhoto(fileName: legacy), at: 0)
        }
        return attachments
    }

    var allPhotoFileNames: [String] {
        photoAttachments.map(\.fileName)
    }
}
