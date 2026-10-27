import UIKit
import Foundation

/// 照片独立文件存储，模型只存文件名。
///
/// 存储边界约定：
/// - 原图 (`Photos/`) 是业务源文件，缩略图 (`PhotoThumbnails/`) 是可重建缓存。
/// - 写入采用“原图 + 缩略图”成对事务：任一环节失败都回滚，不留半成品。
/// - 删除采用“原图 + 缩略图”成对隔离：若中途失败，已隔离项会尽量恢复。
enum PhotoStorage {
    static func logIssue(
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

    static var photoDir: URL {
        baseDirectory.appendingPathComponent("Photos")
    }

    static var thumbnailDir: URL {
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
        try saveBatchOrThrow(originals: [original], fileNames: [fileName], directory: baseDirectory)
        return fileName
    }

    static func saveMany(originals: [Data], logId: UUID) -> [String] {
        do {
            return try saveManyOrThrow(originals: originals, logId: logId)
        } catch {
            logIssue("save_batch_failed", error: error)
            return []
        }
    }

    static func saveManyOrThrow(originals: [Data], logId: UUID) throws -> [String] {
        try saveManyOrThrow(originals: originals, logId: logId, directory: baseDirectory)
    }

    /// 图片解码、缩略图生成和磁盘事务均在后台执行。
    /// 提交前或提交中取消会回滚；最后一项提交完成后始终返回文件名，供调用方接管已保存文件。
    static func saveManyAsyncOrThrow(originals: [Data], logId: UUID) async throws -> [String] {
        try await FileIOTaskRunner.run(
            logContext: .init(event: "photo.save_batch", source: "PhotoStorage.saveManyAsyncOrThrow")
        ) {
            try saveManyOrThrow(originals: originals, logId: logId)
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
        var quarantinedEntries: [FileQuarantineEntry] = []

        do {
            for target in targets {
                guard manager.fileExists(atPath: target.url.path) else { continue }
                let quarantined = try FileQuarantineStore.quarantine(
                    fileAt: target.url,
                    category: target.category,
                    originalFileName: fileName
                )
                guard quarantined else { continue }
                quarantinedAnyFile = true
                if FileQuarantineStore.isQuarantineDeferred(for: target.url) { continue }
                if let entry = latestQuarantineEntry(
                    for: target.url,
                    category: target.category,
                    originalFileName: fileName
                ) {
                    quarantinedEntries.append(entry)
                } else {
                    logIssue(
                        "delete_rollback_entry_missing",
                        fileName: fileName,
                        details: [
                            "category": target.category.rawValue
                        ]
                    )
                }
            }
        } catch {
            rollbackQuarantinedPhotoPair(quarantinedEntries, fileName: fileName)
            throw FileStorageError.deleteFailed(fileName)
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

    static func ensureDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(at: photoDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: thumbnailDir, withIntermediateDirectories: true)
        } catch {
            throw FileStorageError.directoryCreationFailed("Photos")
        }
    }

    static func thumbnailFileURL(for fileName: String) -> URL {
        thumbnailDir.appendingPathComponent(fileName)
    }

    private static func latestQuarantineEntry(
        for originalURL: URL,
        category: FileQuarantineCategory,
        originalFileName: String
    ) -> FileQuarantineEntry? {
        FileQuarantineStore.loadEntries().first { entry in
            entry.category == category &&
                entry.originalPath == originalURL.path &&
                entry.originalFileName == originalFileName
        }
    }

    private static func rollbackQuarantinedPhotoPair(
        _ entries: [FileQuarantineEntry],
        fileName: String
    ) {
        for entry in entries.reversed() {
            do {
                try FileQuarantineStore.restore(entry)
            } catch {
                logIssue(
                    "delete_rollback_restore_failed",
                    fileName: fileName,
                    error: error,
                    details: [
                        "category": entry.category.rawValue
                    ]
                )
            }
        }
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
