import AVFoundation
import Foundation
import UIKit

struct QuickNoteAttachmentBackupFile: Identifiable, Codable {
    var id: String { fileName }
    var fileName: String
    var data: Data
}

enum QuickNoteAttachmentStorage {
    private static let fileFamily = DocumentStorageFileFamily(
        directoryName: "QuickNoteAttachments",
        eventPrefix: "quick_note_attachment"
    )

    private static var attachmentDir: URL {
        fileFamily.directoryURL
    }

    static func makeFileName(extension ext: String) -> String {
        "quick-note-\(UUID().uuidString).\(ext)"
    }

    static func saveImage(_ image: UIImage, compressionQuality: CGFloat = 0.78) -> String? {
        // 兼容旧调用：新写入流程应优先使用 `saveImageOrThrow`。
        do {
            return try saveImageOrThrow(image, compressionQuality: compressionQuality)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.image_save_failed", error: error)
            return nil
        }
    }

    static func saveImageOrThrow(_ image: UIImage, compressionQuality: CGFloat = 0.78) throws -> String {
        let resized = image.resizedForQuickNote(longEdge: 1800)
        guard let data = resized.jpegData(compressionQuality: compressionQuality) else {
            throw FileStorageError.imageEncodingFailed
        }
        return try saveDataOrThrow(data, fileName: makeFileName(extension: "jpg"))
    }

    static func saveData(_ data: Data, extension ext: String) -> String? {
        saveData(data, fileName: makeFileName(extension: ext))
    }

    static func saveData(_ data: Data, fileName: String) -> String? {
        // 兼容旧调用：新写入流程应优先使用 `saveDataOrThrow`。
        do {
            return try saveDataOrThrow(data, fileName: fileName)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.save_failed", fileName: fileName, error: error)
            return nil
        }
    }

    static func saveDataOrThrow(_ data: Data, fileName: String) throws -> String {
        try fileFamily.writeDataOrThrow(data, fileName: fileName)
        return fileName
    }

    static func importFileOrThrow(from source: URL) throws -> QuickNoteAttachment {
        let ext = source.pathExtension.isEmpty ? "bin" : source.pathExtension.lowercased()
        let fileName = makeFileName(extension: ext)
        let target = fileURL(for: fileName)
        try ensureDirectoryExists()
        try FileOps.replaceByCopyWithRollback(
            from: source,
            to: target,
            context: .init(
                event: "quick_note_attachment.import_file",
                category: .fileStorage,
                source: "QuickNoteAttachmentStorage.importFileOrThrow"
            )
        )
        return QuickNoteAttachment(kind: .file, fileName: fileName, originalName: source.lastPathComponent)
    }

    static func importVideoOrThrow(from source: URL) async throws -> (fileName: String, originalName: String, byteSize: Int, durationSeconds: Double?) {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        let fileName = makeFileName(extension: ext)
        let target = fileURL(for: fileName)
        try ensureDirectoryExists()
        try FileOps.replaceByCopyWithRollback(
            from: source,
            to: target,
            context: .init(
                event: "quick_note_attachment.import_video",
                category: .fileStorage,
                source: "QuickNoteAttachmentStorage.importVideoOrThrow"
            )
        )
        let byteSize = fileSize(for: fileName)
        let durationSeconds: Double? = await {
            let asset = AVURLAsset(url: target)
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                guard seconds.isFinite, seconds > 0 else { return nil }
                return seconds
            } catch {
                DocumentStorageIssueLogger.record("quick_note_attachment.video_duration_failed", fileName: source.lastPathComponent, error: error)
                return nil
            }
        }()
        return (fileName, source.lastPathComponent, byteSize, durationSeconds)
    }

    static func fileURL(for fileName: String) -> URL {
        fileFamily.fileURL(for: fileName)
    }

    static func data(for fileName: String) -> Data? {
        fileFamily.data(for: fileName, failureEvent: "quick_note_attachment.read_failed")
    }

    static func dataAsync(for fileName: String) async -> Data? {
        await fileFamily.dataAsync(for: fileName, failureEvent: "quick_note_attachment.read_failed")
    }

    static func exists(fileName: String) -> Bool {
        fileFamily.exists(fileName: fileName)
    }

    static func fileSize(for fileName: String) -> Int {
        fileSize(at: fileURL(for: fileName))
    }

    static func fileSize(at url: URL) -> Int {
        fileFamily.fileSize(at: url, failureEvent: "quick_note_attachment.file_size_failed")
    }

    static func formattedFileSize(for fileName: String) -> String? {
        let size = fileSize(for: fileName)
        guard size > 0 else { return nil }
        return formattedFileSize(size)
    }

    static func formattedFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }

    static func delete(fileName: String) {
        do {
            try deleteOrThrow(fileName: fileName)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.delete_failed", fileName: fileName, error: error)
        }
    }

    static func deleteOrThrow(fileName: String) throws {
        try fileFamily.deleteOrThrow(
            fileName: fileName,
            quarantineCategory: .quickNoteAttachment,
            event: "quick_note_attachment.delete",
            source: "QuickNoteAttachmentStorage.deleteOrThrow"
        )
    }

    static func delete(fileNames: [String]) {
        for fileName in fileNames {
            delete(fileName: fileName)
        }
    }

    static func delete(attachments: [QuickNoteAttachment]) {
        for attachment in attachments {
            delete(fileName: attachment.fileName)
        }
    }

    static func backupFiles(
        for notes: [QuickNote],
        extraAttachments: [QuickNoteAttachment] = []
    ) -> [QuickNoteAttachmentBackupFile] {
        var seen = Set<String>()
        let allAttachments = notes.flatMap(\.attachments) + extraAttachments
        return allAttachments.compactMap { attachment in
            guard !seen.contains(attachment.fileName),
                  let data = data(for: attachment.fileName) else { return nil }
            seen.insert(attachment.fileName)
            return QuickNoteAttachmentBackupFile(fileName: attachment.fileName, data: data)
        }
    }

    static func allStoredFileNames() -> [String] {
        fileFamily.allStoredFileNames(failureEvent: "quick_note_attachment.directory_list_failed")
    }

    static func referencedFileNames(
        for notes: [QuickNote],
        extraAttachments: [QuickNoteAttachment] = []
    ) -> Set<String> {
        var names = Set((notes.flatMap { $0.attachments.map(\.fileName) }) + extraAttachments.map(\.fileName))
        names.formUnion(draftReferencedFileNames())
        let videoAttachments = notes.flatMap(\.attachments).filter { $0.attachmentKind == .video }
            + extraAttachments.filter { $0.attachmentKind == .video }
        for attachment in videoAttachments {
            names.insert(videoThumbnailFileName(for: attachment.fileName))
        }
        return names
    }

    static func orphanFileNames(
        for notes: [QuickNote],
        extraAttachments: [QuickNoteAttachment] = []
    ) -> [String] {
        let referenced = referencedFileNames(for: notes, extraAttachments: extraAttachments)
        return allStoredFileNames().filter { !referenced.contains($0) }
    }

    static func restore(_ files: [QuickNoteAttachmentBackupFile]) {
        do {
            try restoreOrThrow(files)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.restore_failed", error: error)
        }
    }

    static func restoreOrThrow(_ files: [QuickNoteAttachmentBackupFile]) throws {
        try fileFamily.restoreOrThrow(files.map { ($0.fileName, $0.data) })
    }

    static func videoThumbnail(for fileName: String) -> UIImage? {
        let thumbName = videoThumbnailFileName(for: fileName)
        if let data = data(for: thumbName), let image = UIImage(data: data) {
            return image
        }
        let asset = AVAsset(url: fileURL(for: fileName))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let cgImage: CGImage
        do {
            cgImage = try generator.copyCGImage(at: .zero, actualTime: nil)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.video_thumbnail_failed", fileName: fileName, error: error)
            return nil
        }
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

    private static func videoThumbnailFileName(for fileName: String) -> String {
        "thumb-\(fileName).jpg"
    }

    private static func draftReferencedFileNames() -> Set<String> {
        guard let raw = UserDefaults.standard.string(forKey: "quickNoteDraftAttachments"),
              let data = raw.data(using: .utf8) else {
            return []
        }
        let attachments: [QuickNoteAttachment]
        do {
            attachments = try JSONDecoder().decode([QuickNoteAttachment].self, from: data)
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.draft_decode_failed", error: error)
            return []
        }
        var names = Set(attachments.map(\.fileName))
        for attachment in attachments where attachment.attachmentKind == .video {
            names.insert(videoThumbnailFileName(for: attachment.fileName))
        }
        return names
    }

    private static func ensureDirectoryExists() throws {
        try fileFamily.ensureDirectoryExists()
    }

    static func clearAttachmentsDirectory() {
        do {
            _ = try FileOps.removeIfExists(
                at: attachmentDir,
                context: .init(
                    event: "quick_note_attachment.directory_clear",
                    category: .fileStorage,
                    source: "QuickNoteAttachmentStorage.clearAttachmentsDirectory"
                )
            )
        } catch {
            DocumentStorageIssueLogger.record("quick_note_attachment.directory_cleanup_failed", fileName: attachmentDir.lastPathComponent, error: error)
        }
    }
}

private extension UIImage {
    func resizedForQuickNote(longEdge: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > longEdge, maxSide > 0 else { return self }
        let ratio = longEdge / maxSide
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
