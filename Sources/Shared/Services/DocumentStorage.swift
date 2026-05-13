import AVFoundation
import Foundation
import UIKit
import AVFoundation
import UniformTypeIdentifiers

struct ProjectDocumentBackupFile: Identifiable, Codable {
    var id: String { fileName }
    var fileName: String
    var data: Data
}

enum ProjectDocumentStorage {
    private static var baseDirectory: URL {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return dir
        }
        StorageIssueLog.record("无法访问应用文档目录，项目资料目录已回退到临时目录")
        return FileManager.default.temporaryDirectory
    }

    private static var documentDir: URL {
        baseDirectory.appendingPathComponent("ProjectDocuments")
    }

    static func savePDF(data: Data, projectId: UUID) -> String? {
        // 兼容旧调用：新写入流程应优先使用 `savePDFOrThrow`。
        do {
            return try savePDFOrThrow(data: data, projectId: projectId)
        } catch {
            StorageIssueLog.record("项目资料保存失败：\(error.localizedDescription)")
            return nil
        }
    }

    static func savePDFOrThrow(data: Data, projectId: UUID) throws -> String {
        return try saveDataOrThrow(data: data, projectId: projectId, fileExtension: "pdf")
    }

    static func saveDataOrThrow(data: Data, projectId: UUID, fileExtension ext: String) throws -> String {
        let normalizedExt = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fileName = "\(projectId.uuidString)-\(UUID().uuidString).\(normalizedExt.isEmpty ? "dat" : normalizedExt)"
        try ensureDirectoryExists()
        do {
            try data.write(to: fileURL(for: fileName), options: .atomic)
        } catch {
            throw FileStorageError.writeFailed(fileName)
        }
        return fileName
    }

    static func saveImportedFileOrThrow(from sourceURL: URL, projectId: UUID, fileExtension ext: String) throws -> String {
        let normalizedExt = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let fileName = "\(projectId.uuidString)-\(UUID().uuidString).\(normalizedExt.isEmpty ? "dat" : normalizedExt)"
        try ensureDirectoryExists()
        do {
            try FileManager.default.copyItem(at: sourceURL, to: fileURL(for: fileName))
        } catch {
            throw FileStorageError.copyFailed(sourceURL.lastPathComponent)
        }
        return fileName
    }

    static func fileURL(for fileName: String) -> URL {
        documentDir.appendingPathComponent(fileName)
    }

    static func data(for fileName: String) -> Data? {
        do {
            return try Data(contentsOf: fileURL(for: fileName))
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return nil
        } catch {
            StorageIssueLog.record("项目资料读取失败：\(fileName)，\(error.localizedDescription)")
            return nil
        }
    }

    static func dataAsync(for fileName: String) async -> Data? {
        let url = fileURL(for: fileName)
        return await DocumentStorageBackgroundReader.data(
            from: url,
            missingFileCode: .fileReadNoSuchFile,
            missingLogPrefix: nil,
            failureLogPrefix: "项目资料读取失败",
            fileName: fileName
        )
    }

    static func delete(fileName: String) {
        do {
            try deleteOrThrow(fileName: fileName)
        } catch {
            StorageIssueLog.record("项目资料删除失败：\(fileName)")
        }
    }

    static func delete(fileNames: [String]) {
        for fileName in fileNames {
            delete(fileName: fileName)
        }
    }

    static func deleteOrThrow(fileName: String) throws {
        do {
            try FileManager.default.removeItem(at: fileURL(for: fileName))
        } catch {
            throw FileStorageError.deleteFailed(fileName)
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
            StorageIssueLog.record("项目资料文件体积读取失败：\(fileName)，\(error.localizedDescription)")
            return 0
        }
    }

    static func backupFiles(for documents: [ProjectDocument]) -> [ProjectDocumentBackupFile] {
        var seen = Set<String>()
        return documents.compactMap { document in
            guard !seen.contains(document.fileName), let data = data(for: document.fileName) else { return nil }
            seen.insert(document.fileName)
            return ProjectDocumentBackupFile(fileName: document.fileName, data: data)
        }
    }

    static func allStoredFileNames() -> [String] {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentDir, includingPropertiesForKeys: nil)
            return files.map(\.lastPathComponent).sorted()
        } catch {
            StorageIssueLog.record("项目资料目录读取失败：\(error.localizedDescription)")
            return []
        }
    }

    static func referencedFileNames(for documents: [ProjectDocument]) -> Set<String> {
        Set(documents.map(\.fileName))
    }

    static func orphanFileNames(for documents: [ProjectDocument]) -> [String] {
        let referenced = referencedFileNames(for: documents)
        return allStoredFileNames().filter { !referenced.contains($0) }
    }

    static func restore(_ files: [ProjectDocumentBackupFile]) {
        do {
            try restoreOrThrow(files)
        } catch {
            StorageIssueLog.record("项目资料恢复失败：\(error.localizedDescription)")
        }
    }

    static func restoreOrThrow(_ files: [ProjectDocumentBackupFile]) throws {
        try ensureDirectoryExists()
        for file in files {
            do {
                try file.data.write(to: fileURL(for: file.fileName), options: .atomic)
            } catch {
                throw FileStorageError.writeFailed(file.fileName)
            }
        }
    }

    private static func ensureDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(at: documentDir, withIntermediateDirectories: true)
        } catch {
            throw FileStorageError.directoryCreationFailed("ProjectDocuments")
        }
    }
}

struct DrawingBackupFile: Identifiable, Codable {
    var id: String { fileName }
    var fileName: String
    var data: Data
}

enum DrawingStorage {
    private static var baseDirectory: URL {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return dir
        }
        StorageIssueLog.record("无法访问应用文档目录，图纸目录已回退到临时目录")
        return FileManager.default.temporaryDirectory
    }

    private static var drawingDir: URL {
        baseDirectory.appendingPathComponent("Drawings")
    }

    static func saveImportedFile(from sourceURL: URL, projectId: UUID) -> ProjectDrawing? {
        // 兼容旧调用：新导入流程应优先使用 `saveImportedFileOrThrow`。
        do {
            return try saveImportedFileOrThrow(from: sourceURL, projectId: projectId)
        } catch {
            StorageIssueLog.record("图纸导入失败：\(sourceURL.lastPathComponent)")
            return nil
        }
    }

    static func saveImportedFileOrThrow(from sourceURL: URL, projectId: UUID) throws -> ProjectDrawing {
        guard let ext = drawingFileExtension(for: sourceURL) else {
            let rawType = sourceURL.pathExtension.lowercased()
            throw FileStorageError.unsupportedFileType(rawType.isEmpty ? "未知类型" : rawType)
        }
        guard ProjectDrawing.allowedFileExtensions.contains(ext) else {
            throw FileStorageError.unsupportedFileType(ext)
        }
        let baseName = sourceURL.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = baseName.isEmpty ? "图纸" : baseName
        let storedFileName = "\(UUID().uuidString).\(ext)"
        let targetURL = drawingDir.appendingPathComponent(storedFileName)
        try ensureDirectoryExists()

        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        } catch {
            throw FileStorageError.copyFailed(sourceURL.lastPathComponent)
        }

        return makeDrawing(
            projectId: projectId,
            displayName: displayName,
            storedFileName: storedFileName,
            fileType: ext
        )
    }

    static func saveImportedDataOrThrow(data: Data, sourceFileName: String, projectId: UUID) throws -> ProjectDrawing {
        let ext = (sourceFileName as NSString).pathExtension.lowercased()
        guard ProjectDrawing.allowedFileExtensions.contains(ext) else {
            throw FileStorageError.unsupportedFileType(ext.isEmpty ? "未知类型" : ext)
        }
        let rawBaseName = ((sourceFileName as NSString).lastPathComponent as NSString).deletingPathExtension
        let displayName = rawBaseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "图纸"
            : rawBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
        let storedFileName = "\(UUID().uuidString).\(ext)"
        let targetURL = drawingDir.appendingPathComponent(storedFileName)
        try ensureDirectoryExists()
        do {
            try data.write(to: targetURL, options: .atomic)
        } catch {
            throw FileStorageError.writeFailed(sourceFileName)
        }
        return makeDrawing(
            projectId: projectId,
            displayName: displayName,
            storedFileName: storedFileName,
            fileType: ext
        )
    }

    private static func drawingFileExtension(for sourceURL: URL) -> String? {
        let ext = sourceURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ProjectDrawing.allowedFileExtensions.contains(ext) {
            return ext
        }

        if let contentType = try? sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if contentType.conforms(to: .pdf) {
                return "pdf"
            }
            if let preferred = contentType.preferredFilenameExtension?.lowercased(),
               ProjectDrawing.allowedFileExtensions.contains(preferred) {
                return preferred
            }
        }

        // 某些文件提供器会返回无后缀 URL，fallback 到文件名推断。
        let lowerName = sourceURL.lastPathComponent.lowercased()
        if lowerName.hasSuffix(".dwg") { return "dwg" }
        if lowerName.hasSuffix(".dxf") { return "dxf" }
        if lowerName.hasSuffix(".pdf") { return "pdf" }
        return nil
    }

    private static func makeDrawing(
        projectId: UUID,
        displayName: String,
        storedFileName: String,
        fileType: String
    ) -> ProjectDrawing {
        ProjectDrawing(
            projectId: projectId,
            name: displayName,
            fileName: storedFileName,
            fileType: fileType,
            importedAt: Formatters.now()
        )
    }

    static func fileURL(for fileName: String) -> URL {
        drawingDir.appendingPathComponent(fileName)
    }

    static func delete(fileName: String) {
        do {
            try deleteOrThrow(fileName: fileName)
        } catch {
            StorageIssueLog.record("图纸删除失败：\(fileName)")
        }
    }

    static func delete(fileNames: [String]) {
        for fileName in fileNames {
            delete(fileName: fileName)
        }
    }

    static func deleteOrThrow(fileName: String) throws {
        do {
            try FileManager.default.removeItem(at: fileURL(for: fileName))
        } catch {
            throw FileStorageError.deleteFailed(fileName)
        }
    }

    static func data(for fileName: String) -> Data? {
        do {
            return try Data(contentsOf: fileURL(for: fileName))
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return nil
        } catch {
            StorageIssueLog.record("图纸读取失败：\(fileName)")
            return nil
        }
    }

    static func dataAsync(for fileName: String) async -> Data? {
        let url = fileURL(for: fileName)
        return await DocumentStorageBackgroundReader.data(
            from: url,
            missingFileCode: .fileReadNoSuchFile,
            missingLogPrefix: nil,
            failureLogPrefix: "图纸读取失败",
            fileName: fileName
        )
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
            StorageIssueLog.record("图纸文件体积读取失败：\(fileName)，\(error.localizedDescription)")
            return 0
        }
    }

    static func backupFiles(for drawings: [ProjectDrawing]) -> [DrawingBackupFile] {
        var seen = Set<String>()
        return drawings.compactMap { drawing in
            guard !seen.contains(drawing.fileName), let data = data(for: drawing.fileName) else { return nil }
            seen.insert(drawing.fileName)
            return DrawingBackupFile(fileName: drawing.fileName, data: data)
        }
    }

    static func allStoredFileNames() -> [String] {
        do {
            let files = try FileManager.default.contentsOfDirectory(at: drawingDir, includingPropertiesForKeys: nil)
            return files.map(\.lastPathComponent).sorted()
        } catch {
            StorageIssueLog.record("图纸目录读取失败：\(error.localizedDescription)")
            return []
        }
    }

    static func referencedFileNames(for drawings: [ProjectDrawing]) -> Set<String> {
        Set(drawings.map(\.fileName))
    }

    static func orphanFileNames(for drawings: [ProjectDrawing]) -> [String] {
        let referenced = referencedFileNames(for: drawings)
        return allStoredFileNames().filter { !referenced.contains($0) }
    }

    static func restore(_ files: [DrawingBackupFile]) {
        do {
            try restoreOrThrow(files)
        } catch {
            StorageIssueLog.record("图纸恢复失败：\(error.localizedDescription)")
        }
    }

    static func restoreOrThrow(_ files: [DrawingBackupFile]) throws {
        try ensureDirectoryExists()
        for file in files {
            do {
                try file.data.write(to: fileURL(for: file.fileName), options: .atomic)
            } catch {
                throw FileStorageError.writeFailed(file.fileName)
            }
        }
    }

    private static func ensureDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(at: drawingDir, withIntermediateDirectories: true)
        } catch {
            throw FileStorageError.directoryCreationFailed("Drawings")
        }
    }
}

struct QuickNoteAttachmentBackupFile: Identifiable, Codable {
    var id: String { fileName }
    var fileName: String
    var data: Data
}

enum QuickNoteAttachmentStorage {
    private static var baseDirectory: URL {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            return dir
        }
        StorageIssueLog.record("无法访问应用文档目录，随手记附件目录已回退到临时目录")
        return FileManager.default.temporaryDirectory
    }

    private static var attachmentDir: URL {
        baseDirectory.appendingPathComponent("QuickNoteAttachments")
    }

    static func makeFileName(extension ext: String) -> String {
        "quick-note-\(UUID().uuidString).\(ext)"
    }

    static func saveImage(_ image: UIImage, compressionQuality: CGFloat = 0.78) -> String? {
        // 兼容旧调用：新写入流程应优先使用 `saveImageOrThrow`。
        do {
            return try saveImageOrThrow(image, compressionQuality: compressionQuality)
        } catch {
            StorageIssueLog.record("随手记图片附件保存失败：\(error.localizedDescription)")
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
            StorageIssueLog.record("随手记附件保存失败：\(fileName)")
            return nil
        }
    }

    static func saveDataOrThrow(_ data: Data, fileName: String) throws -> String {
        do {
            try ensureDirectoryExists()
            try data.write(to: fileURL(for: fileName), options: .atomic)
            return fileName
        } catch {
            throw FileStorageError.writeFailed(fileName)
        }
    }

    static func importFileOrThrow(from source: URL) throws -> QuickNoteAttachment {
        let ext = source.pathExtension.isEmpty ? "bin" : source.pathExtension.lowercased()
        let fileName = makeFileName(extension: ext)
        let target = fileURL(for: fileName)
        try ensureDirectoryExists()
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: source, to: target)
        return QuickNoteAttachment(kind: .file, fileName: fileName, originalName: source.lastPathComponent)
    }

    static func importVideoOrThrow(from source: URL) async throws -> (fileName: String, originalName: String, byteSize: Int, durationSeconds: Double?) {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension.lowercased()
        let fileName = makeFileName(extension: ext)
        let target = fileURL(for: fileName)
        try ensureDirectoryExists()
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.copyItem(at: source, to: target)
        let byteSize = fileSize(for: fileName)
        let durationSeconds: Double? = await {
            let asset = AVURLAsset(url: target)
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                guard seconds.isFinite, seconds > 0 else { return nil }
                return seconds
            } catch {
                StorageIssueLog.record("随手记视频时长读取失败：\(source.lastPathComponent)，\(error.localizedDescription)")
                return nil
            }
        }()
        return (fileName, source.lastPathComponent, byteSize, durationSeconds)
    }

    static func fileURL(for fileName: String) -> URL {
        attachmentDir.appendingPathComponent(fileName)
    }

    static func data(for fileName: String) -> Data? {
        do {
            return try Data(contentsOf: fileURL(for: fileName))
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return nil
        } catch {
            StorageIssueLog.record("随手记附件读取失败：\(fileName)")
            return nil
        }
    }

    static func dataAsync(for fileName: String) async -> Data? {
        let url = fileURL(for: fileName)
        return await DocumentStorageBackgroundReader.data(
            from: url,
            missingFileCode: .fileReadNoSuchFile,
            missingLogPrefix: nil,
            failureLogPrefix: "随手记附件读取失败",
            fileName: fileName
        )
    }

    static func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: fileName).path)
    }

    static func fileSize(for fileName: String) -> Int {
        fileSize(at: fileURL(for: fileName))
    }

    static func fileSize(at url: URL) -> Int {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
            return values.fileSize ?? values.totalFileAllocatedSize ?? 0
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return 0
        } catch {
            StorageIssueLog.record("随手记附件体积读取失败：\(url.lastPathComponent)，\(error.localizedDescription)")
            return 0
        }
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
            StorageIssueLog.record("随手记附件删除失败：\(fileName)")
        }
    }

    static func deleteOrThrow(fileName: String) throws {
        do {
            try FileManager.default.removeItem(at: fileURL(for: fileName))
        } catch {
            throw FileStorageError.deleteFailed(fileName)
        }
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
        do {
            let files = try FileManager.default.contentsOfDirectory(at: attachmentDir, includingPropertiesForKeys: nil)
            return files.map(\.lastPathComponent).sorted()
        } catch {
            StorageIssueLog.record("随手记附件目录读取失败：\(error.localizedDescription)")
            return []
        }
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
            StorageIssueLog.record("随手记附件恢复失败：\(error.localizedDescription)")
        }
    }

    static func restoreOrThrow(_ files: [QuickNoteAttachmentBackupFile]) throws {
        try ensureDirectoryExists()
        for file in files {
            do {
                try file.data.write(to: fileURL(for: file.fileName), options: .atomic)
            } catch {
                throw FileStorageError.writeFailed(file.fileName)
            }
        }
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
            StorageIssueLog.record("随手记视频缩略图生成失败：\(fileName)，\(error.localizedDescription)")
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
            StorageIssueLog.record("随手记缩略图目录读取失败：\(error.localizedDescription)")
            return 0
        }
        return files.reduce(0) { total, url in
            guard url.lastPathComponent.hasPrefix("thumb-") else { return total }
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
                return total + (values.fileSize ?? values.totalFileAllocatedSize ?? 0)
            } catch {
                StorageIssueLog.record("随手记缩略图体积读取失败：\(url.lastPathComponent)，\(error.localizedDescription)")
                return total
            }
        }
    }

    static func clearThumbnailCache() {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: attachmentDir, includingPropertiesForKeys: nil)
        } catch {
            StorageIssueLog.record("随手记缩略图目录读取失败：\(error.localizedDescription)")
            return
        }
        for url in files where url.lastPathComponent.hasPrefix("thumb-") {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                StorageIssueLog.record("随手记缩略图清理失败：\(url.lastPathComponent)，\(error.localizedDescription)")
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
            StorageIssueLog.record("随手记草稿附件解析失败：\(error.localizedDescription)")
            return []
        }
        var names = Set(attachments.map(\.fileName))
        for attachment in attachments where attachment.attachmentKind == .video {
            names.insert(videoThumbnailFileName(for: attachment.fileName))
        }
        return names
    }

    private static func ensureDirectoryExists() throws {
        do {
            try FileManager.default.createDirectory(at: attachmentDir, withIntermediateDirectories: true)
        } catch {
            throw FileStorageError.directoryCreationFailed("QuickNoteAttachments")
        }
    }

    static func clearAttachmentsDirectory() {
        do {
            try FileManager.default.removeItem(at: attachmentDir)
        } catch {
            StorageIssueLog.record("随手记附件目录清理失败：\(attachmentDir.lastPathComponent)，\(error.localizedDescription)")
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

private enum DocumentStorageBackgroundReader {
    static func data(
        from url: URL,
        missingFileCode: CocoaError.Code,
        missingLogPrefix: String?,
        failureLogPrefix: String,
        fileName: String
    ) async -> Data? {
        await Task.detached(priority: .utility) {
            do {
                return try Data(contentsOf: url, options: .mappedIfSafe)
            } catch let cocoaError as CocoaError where cocoaError.code == missingFileCode {
                if let missingLogPrefix {
                    StorageIssueLog.record("\(missingLogPrefix)：\(fileName)")
                }
                return nil
            } catch {
                StorageIssueLog.record("\(failureLogPrefix)：\(fileName)，\(error.localizedDescription)")
                return nil
            }
        }.value
    }
}
